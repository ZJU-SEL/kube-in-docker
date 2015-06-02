#!/bin/bash

set -e

if [ "$(id -u)" != "0" ]; then
  echo >&2 "Please run as root"
  exit 1
fi

# install docker first
wget -qO- https://get.docker.com/ | sh

# Start a bootstrap docker daemon for running
sudo -b docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null

# Wait a little bit
sleep 5

# Start etcd 
sudo docker -H unix:///var/run/docker-bootstrap.sock run --net=host -d wizardcxy/etcd:2.0.9 /usr/local/bin/etcd --addr=127.0.0.1:4001 --bind-addr=0.0.0.0:4001 --data-dir=/var/etcd/data

sleep 5
# Set flannel net config
sudo docker -H unix:///var/run/docker-bootstrap.sock run --net=host wizardcxy/etcd:2.0.9 etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'

# Start Master
sudo docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  wizardcxy/hyperkube:v0.17.0 /hyperkube kubelet --api_servers=http://localhost:8080 --v=2 --address=0.0.0.0 --enable_server --hostname_override=127.0.0.1 --config=/etc/kubernetes/manifests-multi
