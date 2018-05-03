#!/bin/bash

#create repo
cat <<EOF > /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF

#unset selinux
setenforce 0

#enable ip forwarding
sysctl -w net.ipv4.ip_forward=1

#install docker
yum install -y docker
systemctl enable docker && systemctl start docker

#install k8s
yum install -y kubelet kubeadm kubectl
systemctl enable kubelet && systemctl start kubelet

#Configure route
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EOF
sysctl --system

#configure cgroup
echo "please verify if the cgroups are same for - docker and k8s"
echo "Docker - "
docker info | grep -i cgroup
echo "Kubernets - "
cat /etc/systemd/system/kubelet.service.d/10-kubeadm.conf | grep cgroup-driver

sysctl net.bridge.bridge-nf-call-iptables=1

#disable firewall
systemctl stop firewalld
systemctl disable firewalld

# initialize kube master
kubeadm init --pod-network-cidr 10.244.0.0/16

#
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf


#add flannel
kubectl apply -f kube-flannel.yml

#schedule pods on master node
kubectl taint nodes --all node-role.kubernetes.io/master-

#Verify dns pod is up and running
kubectl get pods --all-namespaces
