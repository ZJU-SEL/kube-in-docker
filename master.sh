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

#TODO check is docker is running

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

start_k8s(){
	# Start etcd 
	docker -H unix:///var/run/docker-bootstrap.sock run --restart=always --net=host -d wizardcxy/etcd:2.0.9 /usr/local/bin/etcd --addr=127.0.0.1:4001 --bind-addr=0.0.0.0:4001 --data-dir=/var/etcd/data

	sleep 5
	# Set flannel net config
	docker -H unix:///var/run/docker-bootstrap.sock run --net=host wizardcxy/etcd:2.0.9 etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'
    
    # iface may change to a private network interface, eth0 is for ali ecs
    flannelCID=$(docker -H unix:///var/run/docker-bootstrap.sock run --restart=always -d --net=host --privileged -v /dev/net:/dev/net quay.io/coreos/flannel:0.3.0 /opt/bin/flanneld -iface="eth0")
	
	sleep 8

	# Configure docker net settings and registry setting and restart it
	docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
	source subnet.env

	case "$lsb_dist" in
		fedora|centos|amzn)
            DOCKER_CONF="/etc/sysconfig/docker"
        ;;
        ubuntu|debian|linuxmint)
            DOCKER_CONF="/etc/default/docker"
        ;;
    esac

    # use insecure docker registry
	echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a ${DOCKER_CONF}


	ifconfig docker0 down

    case "$lsb_dist" in
		fedora|centos|amzn)
            yum install bridge-utils && brctl delbr docker0 && systemctl restart docker
        ;;
        ubuntu|debian|linuxmint)
            apt-get install bridge-utils && brctl delbr docker0 && service docker restart
        ;;
    esac

    # sleep a little bit
	sleep 5

	# Start Master components
	docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  wizardcxy/hyperkube:v${K8S_VERSION} /hyperkube kubelet --api_servers=http://localhost:8080 --v=2 --address=0.0.0.0 --enable_server --hostname_override=127.0.0.1 --config=/etc/kubernetes/manifests-multi
    docker run -d --net=host --privileged wizardcxy/hyperkube:v${K8S_VERSION} /hyperkube proxy --master=http://127.0.0.1:8080 --v=2   
}

echo "Detecting your OS distro ..."
detect_lsb

echo "Starting bootstrap docker ..."
bootstrap_daemon

echo "Starting k8s ..."
start_k8s

echo "Done!"