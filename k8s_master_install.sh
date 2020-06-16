#!/bin/bash

install_dir=$(dirname "$0")
. ${install_dir}/k8s.config

yaml_dir="${install_dir}/yaml"

sudo yum update -y
sudo yum install wget -y

#crio repo

if [[ -z ${crioVersion} ]]; then
  VERSION=1.17
else
  echo crio version
  VERSION=${crioVersion}
fi

sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable/CentOS_7/devel:kubic:libcontainers:stable.repo
sudo curl -L -o /etc/yum.repos.d/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo https://download.opensuse.org/repositories/devel:kubic:libcontainers:stable:cri-o:${VERSION}/CentOS_7/devel:kubic:libcontainers:stable:cri-o:${VERSION}.repo

#install crio
echo install crio
sudo yum -y install cri-o
systemctl enable crio
systemctl start crio

#remove cni0
rm -rf /etc/cni/net.d/*
sed -i 's/\"\/usr\/libexec\/cni\"/\"\/usr\/libexec\/cni\"\,\"\/opt\/cni\/bin\"/g' /etc/crio/crio.conf
systemctl restart crio

#disable firewall
systemctl stop firewalld
systemctl disable firewalld

#swapoff
swapoff -a
sed s/\\/dev\\/mapper\\/centos-swap/#\ \\/dev\\/mapper\\/centos-swap/g -i /etc/fstab

#selinux mode
setenforce 0
sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config

#kubernetes repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

#install kubernetes
if [[ -z ${k8sVersion} ]]; then
  k8sVersion=1.17.6
else
  echo k8s version
  k8sVersion=${k8sVersion}
fi

echo install kubernetes
yum install -y kubeadm-${k8sVersion}-0 kubelet-${k8sVersion}-0 kubectl-${k8sVersion}-0
systemctl enable --now kubelet

#crio-kube set
modprobe overlay
modprobe br_netfilter

cat > /etc/sysctl.d/99-kubernetes-cri.conf <<EOF
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

echo '1' > /proc/sys/net/ipv4/ip_forward
echo '1' > /proc/sys/net/bridge/bridge-nf-call-iptables

if [[ -z ${apiServer} ]]; then
  apiServer=127.0.0.1
else
  apiServer=${apiServer}
fi
if [[ -z ${podSubnet} ]]; then
  podSubnet=10.244.0.0/16
else
  podSubnet=${podSubnet}
fi

sed -i "s|{k8sVersion}|v${k8sVersion}|g" ${yaml_dir}/kubeadm-config.yaml
sed -i "s|{apiServer}|${apiServer}|g" ${yaml_dir}/kubeadm-config.yaml
sed -i "s|{podSubnet}|\"${podSubnet}\"|g" ${yaml_dir}/kubeadm-config.yaml

echo kube init
kubeadm init --config=${yaml_dir}/kubeadm-config.yaml

mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

kubectl taint nodes --all node-role.kubernetes.io/master-

#install calico
if [[ -z ${calicoVersion} ]]; then
  calicoVersion=3.13
  echo calicoVersion=3.13
  kubectl apply -f ${yaml_dir}/calico.yaml
else
  calicoVersion=${calicoVersion}
  kubectl apply -f https://docs.projectcalico.org/${calicoVersion}/manifests/calico.yaml
fi

#install kubevirt-operator
if [[ -z ${kubevirtVersion} ]]; then
  echo kubevirtVersion=0.27.0
  kubevirtVersion=0.27.0
  kubectl apply -f ${yaml_dir}/kubevirt-operator.yaml
  kubectl apply -f ${yaml_dir}/kubevirt-cr.yaml
else
  kubevirtVersion=${kubevirtVersion}
  kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${kubevirtVersion}/kubevirt-operator.yaml
  kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/${kubevirtVersion}/kubevirt-cr.yaml  
fi

#install hypercloud-operator
if [[ -z ${hypercloudOperatorCRDVersion} ]]; then
  echo hypercloudOperatorCRDVersion=4.1.0.33
  hypercloudOperatorCRDVersion=4.1.0.33
else
  hypercloudOperatorCRDVersion=${hypercloudOperatorCRDVersion}
fi
  
targetDir=https://raw.githubusercontent.com/tmax-cloud/hypercloud_infra_installer/master/yaml/hypercloud-operator
kubectl apply -f ${targetDir}/_yaml_Install/1.initialization.yaml

kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Auth/UserCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Auth/UsergroupCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Auth/TokenCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Auth/ClientCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Auth/UserSecurityPolicyCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Claim/NamespaceClaimCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Claim/ResourceQuotaClaimCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Claim/RoleBindingClaimCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Registry/RegistryCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Registry/ImageCRD.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Template/TemplateCRD_v1beta1.yaml
kubectl apply -f ${targetDir}/_yaml_CRD/${hypercloudOperatorCRDVersion}/Template/TemplateInstanceCRD_v1beta1.yaml

kubectl apply -f ${targetDir}/_yaml_Install/2.mysql-settings.yaml
kubectl apply -f ${targetDir}/_yaml_Install/3.mysql-create.yaml
kubectl apply -f ${targetDir}/_yaml_Install/4.proauth-db.yaml
#export nodeName=`kubectl get pod -n proauth-system -o wide -o=jsonpath='{.items[0].spec.nodeName}'`
#echo "proauth server pod nodeName : $nodeName"
#wget https://raw.githubusercontent.com/tmax-cloud/hypercloud-operator/master/_yaml_Install/5.proauth-server.yaml
#sed -i "s/master-1/${nodeName}/g" 5.proauth-server.yaml
#kubectl apply -f 5.proauth-server.yaml
#rm 5.proauth-server.yaml

kubectl apply -f ${targetDir}/_yaml_Install/6.hypercloud4-operator.yaml
kubectl apply -f ${targetDir}/_yaml_Install/7.secret-watcher.yaml
kubectl apply -f ${targetDir}/_yaml_Install/8.default-auth-object-init.yaml


### script to install hypercloud-console

CONSOLE_GIT_DIR="https://raw.githubusercontent.com/tmax-cloud/hypercloud-console/hc-release/"
CONSOLE_GIT_YAML_DIR=$CONSOLE_GIT_DIR"install-yaml/"
CONSOLE_GIT_TLS_DIR=$CONSOLE_GIT_DIR"tls/"

console_file_initialization="1.initialization.yaml"
console_file_initialization_temp="1.initialization-temp.yaml"
console_file_svc_lb="2.svc-lb.yaml"
console_file_svc_lb_temp="2.svc-lb-temp.yaml"
console_file_deployment_pod="3.deployment-pod.yaml"
console_file_deployment_pod_temp="3.deployment-pod-temp.yaml"

mkdir hypercloud-console
cd hypercloud-console

if [ -z $CONSOLE_VERSION ]; then
    CONSOLE_VERSION="1.1.26.0"
fi
echo "CONSOLE_VERSION = ${CONSOLE_VERSION}"

HC4_IP=$(kubectl get svc -A | grep hypercloud4-operator-service | awk '{print $4}')
HC4_PORT=$(kubectl get svc -A | grep hypercloud4-operator-service | awk '{print $6}' | awk 'match($0, ":"){print substr($0,1,RSTART-1)}')
if [ -z $HC4_IP ]; then 
    echo "Cannot find HC4_IP in hypercloud4-operator-service. Is hypercloud4 operator installed?"
    HC4_IP="0.0.0.0"
    HC4_PORT="28677"
    echo "HC4_IP dummy value temporarily set to $HC4_IP:$HC4_PORT."
fi 
HC4=${HC4_IP}:${HC4_PORT}
echo "Hypercloud Addr = ${HC4}"

PROM_IP=$(kubectl get svc -A | grep prometheus-k8s | awk '{print $4}')
PROM_PORT=$(kubectl get svc -A | grep prometheus-k8s | awk '{print $6}' | awk 'match($0, ":"){print substr($0,1,RSTART-1)}')
if [ -z $PROM_IP ]; then 
    echo "Cannot find PROMETHEUS_IP in prometheus-k8s. Is prometheus installed?"
    PROM_IP="0.0.0.0"
    PROM_PORT="9090"
    echo "PROMETHEUS_IP dummy value temporarily set to $PROM_IP:$PROM_PORT."
fi 
PROM=${PROM_IP}:${PROM_PORT}
echo "Prometheus Addr = ${PROM}"

wget $CONSOLE_GIT_YAML_DIR$console_file_initialization
wget $CONSOLE_GIT_YAML_DIR$console_file_svc_lb
wget $CONSOLE_GIT_YAML_DIR$console_file_deployment_pod

cp $console_file_initialization $console_file_initialization_temp
cp $console_file_svc_lb $console_file_svc_lb_temp
cp $console_file_deployment_pod $console_file_deployment_pod_temp

mkdir tls
cd tls
wget $CONSOLE_GIT_TLS_DIR"tls.crt"
wget $CONSOLE_GIT_TLS_DIR"tls.key"
cd ..

sed -i "s%@@NAME_NS@@%console-system%g" ${console_file_initialization_temp}
sed -i "s%@@NAME_NS@@%console-system%g" ${console_file_svc_lb_temp}
sed -i "s%@@NAME_NS@@%console-system%g" ${console_file_deployment_pod_temp}
sed -i "s%@@HC4@@%${HC4}%g" ${console_file_deployment_pod_temp}
sed -i "s%@@PROM@@%${PROM}%g" ${console_file_deployment_pod_temp}
sed -i "s%@@VER@@%${CONSOLE_VERSION}%g" ${console_file_deployment_pod_temp}
sed -i '/--hdc-mode=/d' ${console_file_deployment_pod_temp}
sed -i '/--tmaxcloud-portal=/d' ${console_file_deployment_pod_temp}

kubectl create -f ${console_file_initialization_temp}
kubectl create secret tls console-https-secret --cert=tls/tls.crt --key=tls/tls.key -n console-system
kubectl create -f ${console_file_svc_lb_temp}
kubectl create -f ${console_file_deployment_pod_temp}

count=0
stop=60 
while :
do
    sleep 1
    count=$(($count+1))
    echo "Waiting for $count sec(s)..."
    kubectl get po -n console-system
    RUNNING_FLAG=$(kubectl get po -n console-system | grep console | awk '{print $3}')
    if [ ${RUNNING_FLAG} == "Running" ]; then
        echo "Console has been successfully deployed."
        break 
    fi
    if [ $count -eq $stop ]; then 
        echo "It seems that something went wrong! Check the log."
        kubectl logs -n console-system $(kubectl get po -n console-system | grep console | awk '{print $1}') 
        break
    fi
done

cd ..

### end of installing hypercloud-console


