#!/bin/bash

set -e


K8S_VERSION=0.18.2

# we support ubuntu, debian, mint, centos, fedora dist
lsb_dist=""
DOCKER_CONF=""

if [ "$(id -u)" != "0" ]; then
  echo >&2 "Please run as root"
  exit 1
fi

if [ -z "${MASTER_IP}" ]; then
        echo "Please export MASTER_IP in yout env"
        exit
fi

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

detect_lsb() {
	case "$(uname -m)" in
	*64)
		;;
	*)
		cat >&2 <<-'EOF'
		Error: you are not using a 64bit platform.
		We currently only supports 64bit platforms.
		EOF
		exit 1
		;;
	esac

	if command_exists lsb_release; then
		lsb_dist="$(lsb_release -si)"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/lsb-release ]; then
		lsb_dist="$(. /etc/lsb-release && echo "$DISTRIB_ID")"
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/debian_version ]; then
		lsb_dist='debian'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/fedora-release ]; then
		lsb_dist='fedora'
	fi
	if [ -z "$lsb_dist" ] && [ -r /etc/os-release ]; then
		lsb_dist="$(. /etc/os-release && echo "$ID")"
	fi

	lsb_dist="$(echo "$lsb_dist" | tr '[:upper:]' '[:lower:]')"
}


bootstrap_daemon() {
	# setup the docker bootstrap daemon too
	sudo -b docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null

	sleep 5
}

start_k8s() {
	# Start flannel
	flannelCID=$(sudo docker -H unix:///var/run/docker-bootstrap.sock run -d --restart=always --net=host --privileged -v /dev/net:/dev/net wizardcxy/flannel:0.3.0 /opt/bin/flanneld --etcd-endpoints=http://${MASTER_IP}:4001 -iface="eth0")

	sleep 8
	sudo docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
	source subnet.env

	case "$lsb_dist" in
		fedora|centos|amzn)
            DOCKER_CONF="/etc/sysconfig/docker"
        ;;
        ubuntu|debian|linuxmint)
            DOCKER_CONF="/etc/default/docker"
        ;;
    esac

	# configure docker net settings, then restart it
	echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a ${DOCKER_CONF}

	ifconfig docker0 down

    case "$lsb_dist" in
		fedora|centos)
            yum install bridge-utils && brctl delbr docker0 && systemctl restart docker
        ;;
        ubuntu|debian|linuxmint)
            apt-get install bridge-utils && brctl delbr docker0 && service docker restart
        ;;
    esac

	# sleep a little bit
	sleep 5

	# Start minion
	sudo docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  wizardcxy/hyperkube:v${K8S_VERSION} /hyperkube kubelet --api_servers=http://${MASTER_IP}:8080 --v=2 --address=0.0.0.0 --enable_server --hostname_override=$(hostname -i)
	sudo docker run -d --net=host --privileged wizardcxy/hyperkube:v${K8S_VERSION} /hyperkube proxy --master=http://${MASTER_IP}:8080 --v=2

}

echo "Detecting your OS distro ..."
detect_lsb

echo "Starting bootstrap docker ..."
bootstrap_daemon

echo "Starting k8s ..."
start_k8s

echo "Done!"