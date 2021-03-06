#!/bin/bash

FEATURE_GATES=""

disable_selinux() {
 setenforce 0
 sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/sysconfig/selinux
}

disable_swap() {
 swapoff -a
 sed -i '/swap/s/^/#/g' /etc/fstab
}

enable_netfilter() {
 modprobe br_netfilter
 cat >> /etc/sysctl.conf <<EOF
net.bridge.bridge-nf-call-ip6tables=1
net.bridge.bridge-nf-call-iptables=1
EOF
 sysctl -p
}

prepare_yum() {
 yum install -y yum-utils
 cat > /etc/yum.repos.d/kubernetes.repo <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg
       https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg
EOF
}

install_docker() {
 yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
 yum install -y docker-ce device-mapper-persistent-data lvm2
 systemctl enable --now docker
 usermod -a -G docker vagrant
}

setup_kubectl_in_master() {
 USER="$1"

 if [ "$USER" = "root" ]; then
   USER_HOME="/root"
 else
   USER_HOME="/home/$1"
 fi

 while [ ! -f /etc/kubernetes/admin.conf ]
 do
   echo "Waiting for kubernetes for 5 seconds"
   sleep 5
 done

 mkdir -p "$USER_HOME"/.kube

 cp -i /etc/kubernetes/admin.conf "$USER_HOME"/.kube/config
 chown -R "$USER":"$USER" "$USER_HOME"/.kube/config
}

setup_kubectl_in_node() {
 USER="$1"

 if [ "$USER" = "root" ]; then
   USER_HOME="/root"
 else
   USER_HOME="/home/$1"
 fi

 while [ ! -f /etc/kubernetes/kubelet.conf ]
 do
   echo "Waiting for kubernetes for 5 seconds"
   sleep 5
 done

 mkdir -p "$USER_HOME"/.kube

 cp -i /etc/kubernetes/kubelet.conf "$USER_HOME"/.kube/config

 chown -R "$USER":"$USER" "$USER_HOME"/.kube/config
 chown -R "$USER":"$USER" /var/lib/kubelet/
}

setup_node_ip() {
  echo "KUBELET_EXTRA_ARGS=--node-ip=$1" > /etc/sysconfig/kubelet

  systemctl daemon-reload
  systemctl restart kubelet
}

install_kubernetes() {
 yum install tc
 yum install -y kubelet kubeadm kubectl

 if [ -z "$2" ]; then
   /vagrant/script/kubernetes-join.sh

   setup_kubectl_in_node "vagrant"
   setup_node_ip "$1"
 else
   kubeadm init --apiserver-advertise-address="$1" --pod-network-cidr="$2" --feature-gates="$FEATURE_GATES"
   setup_node_ip "$1"

   kubeadm token create --print-join-command > /vagrant/script/kubernetes-join.sh
   chmod +x /vagrant/script/kubernetes-join.sh

   setup_kubectl_in_master "vagrant"
   setup_kubectl_in_master "root"

   kubectl apply -f /home/vagrant/flannel/config.yml
 fi
}

main() {
 disable_selinux
 disable_swap

 enable_netfilter
 prepare_yum

 install_docker
 install_kubernetes "$@"
}

main "$@"
