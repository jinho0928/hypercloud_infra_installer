# HyperCloud

## HyperCloud Infra
### Prerequisites
- CentOS 7

### Setup master node
Install Kubernetes, CRI-O, Calico, Kubevirt and HyperCloud
1. Download installer file in our repository
    ```
    git clone https://github.com/tmax-cloud/hypercloud_infra_installer.git
    ```
2. Modify `k8s.config` to suit your environment
    * `crioVersion` : cri-o runtime version
    * `k8sVersion` : kubeadm, kubelet, kubectl version
      * CRI-O major and minor versions must match Kubernetes major and minor versions.
      * ex : crioVersion=1.17 k8sVersion=1.17.6        
      * ex : crioVersion=1.18 k8sVersion=1.18.3
      * ex : crioVersion=1.19 k8sVersion=1.19.4      
    * `apiServer` : The IP address the API Server will advertise it's listening on.
      * ex : apiServer={Kubernetes master IP}
      * ex : apiServer=172.22.5.2
    * `podSubnet` : Pod IPs will be chosen from this range. This should fall within `--cluster-cidr`.
      * ex : podSubnet={POD_IP_POOL}/{CIDR}
      * ex : podSubnet=10.244.0.0/16
    * `calicoVersion` : calico network plugin version(OPTIONAL)
      * If nothing is specified, the default version(v3.13.4) is installed.
      * ex : calicoVersion=3.16
    * `kubevirtVersion` : kubevirt plugin version(OPTIONAL)
      * If nothing is specified, the default version(v0.27.0) is installed.
      * ex : kubevirtVersion=0.34.2
3. Execute installer script
    ```
    ./k8s_master_install.sh
    ```
4.  Get the join command for worker node
    ```
    kubeadm token create --print-join-command
    ```
    You can get the result in this format:
    ```
    kubeadm join 192.168.122.50:6443 --token mnp5b8.u7tl2cruk73gh0zh     --discovery-token-ca-cert-hash sha256:662a697f67ecbb8b376898dcd5bf4df806249175ea4a90c2d3014be399c6c18a
    ```
5. If you create a single node Kubernetes cluster, you have to untaint the master node
    ```
    kubectl taint nodes --all node-role.kubernetes.io/master-
    ```
6. If the installation process fails, execute uninstaller script then installer script again
    ```
    ./k8s_uninstall.sh
    ./k8s_master_install.sh
    ```
### Setup worker nodes
Install Kubernetes and CRI-O
1. Download installer file in our repository
    ```
    git clone https://github.com/tmax-cloud/hypercloud_infra_installer.git
    ```
2. Modify `k8s.config` to suit your environment
    * `crioVersion` : cri-o runtime version
    * `k8sVersion` : kubeadm, kubelet, kubectl version
      * CRI-O major and minor versions must match Kubernetes major and minor versions.
      * ex : crioVersion=1.17 k8sVersion=1.17.6        
      * ex : crioVersion=1.18 k8sVersion=1.18.3
      * ex : crioVersion=1.19 k8sVersion=1.19.4      
3. Execute installer script
    ```
    ./k8s_node_install.sh
    ```
4. Execute the join command
    ```
    kubeadm join 192.168.122.50:6443 --token mnp5b8.u7tl2cruk73gh0zh     --discovery-token-ca-cert-hash sha256:662a697f67ecbb8b376898dcd5bf4df806249175ea4a90c2d3014be399c6c18a
    ```
5. If the installation process fails, execute uninstaller script then installer script again
    ```
    ./k8s_uninstall.sh
    ./k8s_node_install.sh
    ```

## HyperCloud Storage(hcsctl)
`hcsctl` provides installation, removal and management of HyperCloud Storage.

### Prerequisite
- kubectl (>= 1.15)
- Fully-installed Kubernetes Cluster

### Getting Started
- Before installing hypercloud-storage with hcsctl, create yaml files is required for installation and change it to suit your environment.

   ``` shell
   $ hcsctl create-inventory {$inventory_name}
   # Ex) hcsctl create-inventory myInventory
   ```

- Two directories of rook and cdi are created in the created inventory. `./myInventory/rook/*.yaml` are yaml files used for Rook-Ceph installation, and `./myInventory/cdi/*.yaml` are yaml files used for KubeVirt-CDI installation.
- Since all the generated yaml files are for sample provision, you have to use the contents of each yaml file after **modifying to your environment**.<strong> Do not modify the folder and file name. </strong>
- Modify yaml contents created under `./myInventory/rook/` path to fit your environment. Refer to https://rook.github.io/docs/rook/v1.3/ceph-cluster-crd.html
- For yaml files created under the path `./myInventory/cdi/`, you need to change the version of `OPERATOR_VERSION` and container image in the `operator.yaml` file only if you need to change the KubeVirt-CDI version to install.


- After modifying the inventory files to suit the environment, install hypercloud-storage with hcsctl.
   ``` shell
   $ hcsctl install {$inventory_name}
   # Ex) hcsctl install myInventory
   ```

    - When installation is completed normally, you can use hypercloud-storage. After installation, you can use Block Storage and Shared Filesystem.


- Verify whether hypercloud-storage is properly installed with hcsctl.test.
    ``` shell
    $ hcsctl.test
    ```
    - To check whether hypercloud-storage can be used normally, various scenario tests are performed.

### Uninstall
- Remove hypercloud-storage by referring to inventory used when installing with hcsctl.
    ``` shell
    $ hcsctl uninstall {$inventory_name}
    # Ex) hcsctl uninstall myInventory
    ```
    - You need additional work by checking the message displayed after the removal is completed.

### Additional features
- In addition to basic installation and uninstallation, various additional functions are also provided for efficient use.

    You can run ceph with hcsctl.

    ``` shell
    $ hcsctl ceph status
    $ hcsctl ceph exec {$ceph_cmd}

    # Commands frequently used to check the status are as follows.
    $ hcsctl ceph status
    $ hcsctl ceph exec ceph osd status
    $ hcsctl ceph exec ceph df
    ```

### Compatibility
- This project has been verified in the following versions.
    - Kubernetes
        - `kubectl` version compatible with each kubernetes server version is required.
        - v1.19
        - v1.18        
        - v1.17
        - v1.16
        - v1.15
    - OS
        - Ubuntu 18.04
        - CentOS 8.1, 7.7
        - ProLinux 7.5
