#!/bin/bash

install_dir=$(dirname "$0")
. ${install_dir}/k8s.config

yaml_dir="${install_dir}/yaml"

sudo yum update -y

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
  targetDir=${yaml_dir}
else
  hypercloudOperatorCRDVersion=${hypercloudOperatorCRDVersion}
  targetDir=https://raw.githubusercontent.com/tmax-cloud/hypercloud-operator/master
fi

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
export nodeName=`kubectl get pod -n proauth-system -o wide -o=jsonpath='{.items[0].spec.nodeName}'`
echo "proauth server pod nodeName : $nodeName"
wget https://raw.githubusercontent.com/tmax-cloud/hypercloud-operator/master/_yaml_Install/5.proauth-server.yaml
sed -i "s/master-1/${nodeName}/g" 5.proauth-server.yaml
kubectl apply -f 5.proauth-server.yaml
rm 5.proauth-server.yaml

kubectl apply -f ${targetDir}/_yaml_Install/6.hypercloud4-operator.yaml
kubectl apply -f ${targetDir}/_yaml_Install/7.secret-watcher.yaml
kubectl apply -f ${targetDir}/_yaml_Install/8.default-auth-object-init.yaml

