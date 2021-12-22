: '
Copyright 2021 The Kubernetes Authors.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
'
set -e

# TODO Add these as command line options

echo "ARGS: $1 $2 $3 $4 $5"
if [[ "$1" == "" || "$2" == "" || "$3" == "" || "$4" == "" || "$5" == "" ]] ; then
  cat << EOF
    Missing args.
    You need to send overwrite_linux_bins, k8s_linux_registry, k8s_linux_kubelet_deb, k8s_linux_apiserver, k8s_kubelet_nodeip i.e. something like...
    ./controlplane.sh false gcr.io/k8s-staging-ci-images 1.21.0 v1.22.0-alpha.3.31+a3abd06ad53b2f"}
    Normally these are in your variables.yml, and piped in by Vagrant.
    So, check that you didn't break the Vagrantfile :)
    BTW the only reason this error message is fancy is because friedrich said we should be curteous to people who want to
    copy paste this code from the internet and reuse it.
EOF
  exit 1
fi

overwrite_linux_bins=${1}
k8s_linux_registry=${2}
k8s_linux_kubelet_deb=${3}
k8s_linux_apiserver=${4}
k8s_kubelet_node_ip=${5}

echo "Using $kubernetes_version as the Kubernetes version"
echo "Overwriting bins is set to '$overwrite_bins'"

# Add GDP keys and repository for Kubernetes
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | sudo apt-key add -
cat << EOF | sudo tee /etc/apt/sources.list.d/kubernetes.list
deb https://apt.kubernetes.io/ kubernetes-xenial main
EOF
sudo apt-get update


#disable swap
sudo swapoff -a
sudo sed -i '/swap/d' /etc/fstab

cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Setup required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

# Apply sysctl params without reboot
sudo sysctl --system

# Install containerd and Kubernetes binaries
sudo apt-get install -y containerd \
kubelet=${k8s_linux_kubelet_deb}-00 \
kubeadm=${k8s_linux_kubelet_deb}-00 \
kubectl=${k8s_linux_kubelet_deb}-00

sudo apt-mark hold kubelet kubeadm kubectl
if $overwrite_linux_bins ; then
  echo "overwriting binaries ..."
  for BIN in kubeadm kubectl kubelet
  do
      echo "=> $BIN" 
      sudo cp /var/sync/linux/bin/$BIN /bin/ -f
  done
fi

# #bridged traffic to iptables is enabled for kube-router:
# echo "net.bridge.bridge-nf-call-iptables=1" | sudo tee -a /etc/sysctl.conf
# echo "net.bridge.bridge-nf-call-ip6tables=1" | sudo tee -a /etc/sysctl.conf
# echo "net.bridge.bridge-nf-call-arptables=1" | sudo tee -a /etc/sysctl.conf
# sudo sysctl -p

# Configuring and starting containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sudo systemctl restart containerd
sudo crictl config --set runtime-endpoint=unix:///run/containerd/containerd.sock

# TODO HELP WANTED
#start cluster with Flannel:
# https://stackoverflow.com/questions/60391127/kubeadm-init-apiserver-advertise-address-flag-equivalent-in-config-file
# Someday consider
  #cat <<EOF | sudo tee kubeadm-config.yaml
  #kind: ClusterConfiguration
  #apiVersion: kubeadm.k8s.io/v1beta2
  #kubernetes_version: v$kubernetes_version
  #networking:
  #  podSubnet: "10.244.0.0/16"
  #---
  #kind: KubeletConfiguration
  #apiVersion: kubelet.config.k8s.io/v1beta1
  #cgroupDriver: systemd
  #EOF
# RIGHT NOW we NEED to use ApiSErverAdvertiseAddress... but not sure how to do that equivalent in kubeadm.

# k8s.gcr.io/pause:3.2
# k8s.gcr.io/etcd:3.4.13-0
# k8s.gcr.io/coredns:1.7.0
# sudo ctr images tag k8s.gcr.io/etcd:3.4.13-0 k8s.gcr.io/etcd:v1.22.0-alpha.3.31_a3abd06ad53b2f
# sudo kubeadm init --apiserver-advertise-address=10.20.30.10 --pod-network-cidr=10.244.0.0/16 --image-repository="k8s.gcr.io" --kubernetes-version="v1.22.0-alpha.3.31+a3abd06ad53b2f"

cat << EOF > /var/sync/shared/kubeadm.yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: InitConfiguration
localAPIEndpoint:
  advertiseAddress: $k8s_kubelet_node_ip
nodeRegistration:
  kubeletExtraArgs:
    node-ip: $k8s_kubelet_node_ip
    cgroup-driver: cgroupfs
    v: "3"
    feature-gates: "NodeLogs=true"
---
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: $k8s_linux_apiserver
networking:
  podSubnet: "100.244.0.0/16"
EOF

sudo kubeadm init --config=/var/sync/shared/kubeadm.yaml --v=6

#to start the cluster with the current user:
mkdir -p $HOME/.kube
sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
sudo chown $(id -u):$(id -g) $HOME/.kube/config

rm -f /var/sync/shared/config
cp $HOME/.kube/config /var/sync/shared/config

######## MAKE THE JOIN FILE FOR WINDOWS ##########
######## MAKE THE JOIN FILE FOR WINDOWS ##########
######## MAKE THE JOIN FILE FOR WINDOWS ##########
rm -f /var/sync/shared/kubejoin.ps1

cat << EOF > /var/sync/shared/kubejoin.ps1
cp C:\Users\vagrant\crictl.exe "C:\Program Files\containerd"
cp C:\sync\windows\bin\* c:\k
\$env:path += ";C:\Program Files\containerd"
[Environment]::SetEnvironmentVariable("Path", \$env:Path, [System.EnvironmentVariableTarget]::Machine)
EOF

kubeadm token create --print-join-command >> /var/sync/shared/kubejoin.ps1

sed -i 's#--token#--cri-socket "npipe:////./pipe/containerd-containerd" --token#g' /var/sync/shared/kubejoin.ps1

### NOW MAKE WINDOWS PROXY SECRETS...
#### TODO Put these in a single file or something...

cat << EOF > kube-proxy-and-antrea.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  labels:
    app: kube-proxy
  name: kube-proxy-windows
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node:kube-proxy
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:node-proxier
subjects:
- kind: Group
  name: system:node
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: kube-proxy-windows
  namespace: kube-system
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node:god2
  namespace: kube-system
subjects:
- kind: User
  name: system:node:winw1
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node:god3
  namespace: kube-system
subjects:
- kind: Group
  name: system:nodes
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: node:god4
  namespace: kube-system
subjects:
- kind: User
  name: system:serviceaccount:kube-system:kube-proxy-windows
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io
EOF

kubectl create -f kube-proxy-and-antrea.yaml

echo "testing that we didnt blow anything up "

kubectl get pods -A
