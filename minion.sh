#!/bin/bash

set -e
# we only deploy one etcd instance among minions
if [ "$(id -u)" != "0" ]; then
  echo >&2 "Please run as root"
  exit 1
fi

# install docker first
wget -qO- https://get.docker.com/ | sh

MASTER_IP=""
HOSTNAME=""
flannelCID=""
if [ -z "${MASTER_IP}" ]; then
	echo "must set MASTER_IP and HOSTNAME variable"
	exit
fi

# Start a bootstrap docker daemon for running
sudo -b docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null

# Wait a little bit
sleep 5

# Start flannel
flannelCID=$(sudo docker -H unix:///var/run/docker-bootstrap.sock run -d --net=host --privileged -v /dev/net:/dev/net wizardcxy/flannel:0.3.0 /opt/bin/flanneld --etcd-endpoints=http://${MASTER_IP}:4001 -iface="eth0")

sleep 5
sudo docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
source subnet.env
# configure docker net settins ans restart it

echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a /etc/default/docker

sudo ifconfig docker0 down
sudo apt-get install bridge-utils && sudo brctl delbr docker0
sudo service docker restart

# sleep a little bit
sleep 5

# Start minion
sudo docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  wizardcxy/hyperkube:v0.17.0 /hyperkube kubelet --api_servers=http://${MASTER_IP}:8080 --v=2 --address=0.0.0.0 --enable_server --hostname_override=${HOSTNAME}
sudo docker run -d --net=host --privileged wizardcxy/hyperkube:v0.17.0 /hyperkube proxy --master=http://${MASTER_IP}:8080 --v=2
