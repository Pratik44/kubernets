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

# initialize kube master for flannel
#kubeadm init --pod-network-cidr 10.244.0.0/16

# initialize kube master for calico
kubeadm init --pod-network-cidr=192.168.0.0/16

#
mkdir -p $HOME/.kube
cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
export KUBECONFIG=/etc/kubernetes/admin.conf


#schedule pods on master node
kubectl taint nodes --all node-role.kubernetes.io/master-

#configure add flannel
#kubectl apply -f 

#configure calico
kubectl apply -f https://docs.projectcalico.org/v3.0/getting-started/kubernetes/installation/hosted/kubeadm/1.7/calico.yaml

#Verify dns pod is up and running
kubectl get pods --all-namespaces

yum install git -y
git clone https://github.com/kubernetes/heapster.git
kubectl create -f ./heapster/deploy/kube-config/influxdb/influxdb.yaml
kubectl create -f ./heapster/deploy/kube-config/influxdb/heapster.yaml
kubectl create -f https://raw.githubusercontent.com/kubernetes/dashboard/master/src/deploy/recommended/kubernetes-dashboard.yaml

echo " Please update to node port :
kubectl get services kubernetes-dashboard -n kube-system
kubectl get pods --all-namespaces
kubectl cluster-info
kubectl edit service kubernetes-dashboard -n kube-system
kubectl proxy --address <internal_ip> --port=30000 --accept-hosts='^*$' &
"
cat <<EOF > kube-access-dashboard.yaml
apiVersion: rbac.authorization.k8s.io/v1beta1
kind: ClusterRoleBinding
metadata:
  name: kubernetes-dashboard
  labels:
    k8s-app: kubernetes-dashboard
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: kubernetes-dashboard
  namespace: kube-system
EOF
kubectl create -f kube-access-dashboard.yaml

cat <<EOF > default-backend-deployment.yaml
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: default-http-backend
  labels:
    k8s-app: default-http-backend
  namespace: kube-system
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: default-http-backend
    spec:
      terminationGracePeriodSeconds: 60
      containers:
      - name: default-http-backend
        # Any image is permissable as long as:
        # 1. It serves a 404 page at /
        # 2. It serves 200 on a /healthz endpoint
        image: gcr.io/google_containers/defaultbackend:1.0
        livenessProbe:
          httpGet:
            path: /healthz
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 30
          timeoutSeconds: 5
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: 10m
            memory: 20Mi
          requests:
            cpu: 10m
            memory: 20Mi
EOF

cat <<EOF > default-backend-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: default-http-backend
  namespace: kube-system
  labels:
    k8s-app: default-http-backend
spec:
  ports:
  - port: 80
    targetPort: 8080
  selector:
    k8s-app: default-http-backend
  type: ClusterIP
EOF

cat <<EOF > nginx-ingress-controller-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: nginx-ingress-controller
  namespace: kube-system
spec:      
  # Because of the type of NodePort, arbitrary port in specific range will be opened.
  type: NodePort
  ports:
    - port: 80
      name: http
    - port: 443
      name: https
  selector:
    k8s-app: nginx-ingress-controller
EOF

cat <<EOF > tomcat8-jenkins-deployment.yaml
apiVersion: apps/v1beta1
kind: Deployment
metadata:
  labels:
    k8s-app: tomcat8-jenkins
  name: tomcat8-jenkins
  namespace: default
spec:
  replicas: 1
  template:
    metadata:
      labels:
        k8s-app: tomcat8-jenkins
      name: tomcat8-jenkins
    spec:
      containers:
        -
          args:
          - daemon
          # Fetch from Docker Hub
          image: "skcho4docker/tomcat8-jenkins-path:ver1.6.3"
          name: tomcat8-jenkins-path
          ports:
            -
              containerPort: 8080
              protocol: TCP
EOF

cat <<EOF > tomcat8-jenkins-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: tomcat8-jenkins
  namespace: default
  labels:
    k8s-app: tomcat8-jenkins
spec:
  ports:
  - port: 80
    targetPort: 8080
    protocol: TCP
  selector:
    k8s-app: tomcat8-jenkins
  type: ClusterIP
EOF
