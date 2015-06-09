#!/bin/bash

set -ex

# variables which user filled in 
# registry related
PRIVATE_IP="10.168.14.145"
PRIVATE_PORT="5000"
HOSTDIR="/mnt"

url='https://get.docker.com/'
# we support ubuntu, debian, mint, centos, fedora and gentoo dist
lsb_dist=""
DOCKER_CONF=""

if [ "$(id -u)" != "0" ]; then
  echo >&2 "Please run as root"
  exit 1
fi

command_exists() {
	command -v "$@" > /dev/null 2>&1
}

echo_docker_as_nonroot() {
	your_user=your-user
	[ "$user" != 'root' ] && your_user="$user"
	# intentionally mixed spaces and tabs here -- tabs are stripped by "<<-EOF", spaces are kept in the output
	cat <<-EOF

	If you would like to use Docker as a non-root user, you should now consider
	adding your user to the "docker" group with something like:

	  sudo usermod -aG docker $your_user

	Remember that you will have to log out and back in for this to take effect!

	EOF
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

install_docker() {
	if command_exists docker || command_exists lxc-docker; then
		cat >&2 <<-'EOF'
		Warning: "docker" or "lxc-docker" command appears to already exist.
		Please ensure that you do not already have docker installed.
		You may press Ctrl+C now to abort this process and rectify this situation.
		EOF
		( set -x; sleep 20 )
	fi

	user="$(id -un 2>/dev/null || true)"

	sh_c='sh -c'
	if [ "$user" != 'root' ]; then
		if command_exists sudo; then
			sh_c='sudo -E sh -c'
		elif command_exists su; then
			sh_c='su -c'
		else
			cat >&2 <<-'EOF'
			Error: this installer needs the ability to run commands as root.
			We are unable to find either "sudo" or "su" available to make this happen.
			EOF
			exit 1
		fi
	fi

	curl=''
	if command_exists curl; then
		curl='curl -sSL'
	elif command_exists wget; then
		curl='wget -qO-'
	elif command_exists busybox && busybox --list-modules | grep -q wget; then
		curl='busybox wget -qO-'
	fi

	case "$lsb_dist" in
		fedora|centos)
			if [ "$lsb_dist" = 'amzn' ]; then
				(
					set -x
					$sh_c 'sleep 3; yum -y -q install docker'
				)
			else
				(
					set -x
					$sh_c 'sleep 3; yum -y -q install docker-io'
				)
			fi
			if command_exists docker && [ -e /var/run/docker.sock ]; then
				(
					set -x
					$sh_c 'docker version'
				) || true
			fi
            DOCKER_CONF="/etc/sysconfig/docker"
			echo_docker_as_nonroot
			;;
		ubuntu|debian|linuxmint)
			export DEBIAN_FRONTEND=noninteractive

			did_apt_get_update=
			apt_get_update() {
				if [ -z "$did_apt_get_update" ]; then
					( set -x; $sh_c 'sleep 3; apt-get update' )
					did_apt_get_update=1
				fi
			}

			# aufs is preferred over devicemapper; try to ensure the driver is available.
			if ! grep -q aufs /proc/filesystems && ! $sh_c 'modprobe aufs'; then
				if uname -r | grep -q -- '-generic' && dpkg -l 'linux-image-*-generic' | grep -q '^ii' 2>/dev/null; then
					kern_extras="linux-image-extra-$(uname -r) linux-image-extra-virtual"

					apt_get_update
					( set -x; $sh_c 'sleep 3; apt-get install -y -q '"$kern_extras" ) || true

					if ! grep -q aufs /proc/filesystems && ! $sh_c 'modprobe aufs'; then
						echo >&2 'Warning: tried to install '"$kern_extras"' (for AUFS)'
						echo >&2 ' but we still have no AUFS.  Docker may not work. Proceeding anyways!'
						( set -x; sleep 10 )
					fi
				else
					echo >&2 'Warning: current kernel is not supported by the linux-image-extra-virtual'
					echo >&2 ' package.  We have no AUFS support.  Consider installing the packages'
					echo >&2 ' linux-image-virtual kernel and linux-image-extra-virtual for AUFS support.'
					( set -x; sleep 10 )
				fi
			fi

			# install apparmor utils if they're missing and apparmor is enabled in the kernel
			# otherwise Docker will fail to start
			if [ "$(cat /sys/module/apparmor/parameters/enabled 2>/dev/null)" = 'Y' ]; then
				if command -v apparmor_parser &> /dev/null; then
					echo 'apparmor is enabled in the kernel and apparmor utils were already installed'
				else
					echo 'apparmor is enabled in the kernel, but apparmor_parser missing'
					apt_get_update
					( set -x; $sh_c 'sleep 3; apt-get install -y -q apparmor' )
				fi
			fi

			if [ ! -e /usr/lib/apt/methods/https ]; then
				apt_get_update
				( set -x; $sh_c 'sleep 3; apt-get install -y -q apt-transport-https ca-certificates' )
			fi
			if [ -z "$curl" ]; then
				apt_get_update
				( set -x; $sh_c 'sleep 3; apt-get install -y -q curl ca-certificates' )
				curl='curl -sSL'
			fi
			(
				set -x
				if [ "https://get.docker.com/" = "$url" ]; then
					$sh_c "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 36A1D7869245C8950F966E92D8576A8BA88D21E9"
				elif [ "https://test.docker.com/" = "$url" ]; then
					$sh_c "apt-key adv --keyserver hkp://p80.pool.sks-keyservers.net:80 --recv-keys 740B314AE3941731B942C66ADF4FD13717AAD7D6"
				else
					$sh_c "$curl ${url}gpg | apt-key add -"
				fi
				$sh_c "echo deb ${url}ubuntu docker main > /etc/apt/sources.list.d/docker.list"
				$sh_c 'sleep 3; apt-get update; apt-get install -y -q lxc-docker'
			)
			if command_exists docker && [ -e /var/run/docker.sock ]; then
				(
					set -x
					$sh_c 'docker version'
				) || true
			fi
			DOCKER_CONF="/etc/default/docker"
			echo_docker_as_nonroot
			;;

		*)
            cat >&2 <<-'EOF'

			  Either your platform is not easily detectable, is not supported by this
			  installer script.

			  Sorry !

			EOF
			exit 1
	esac

	# prepare the docker bootstrap daemon
	sudo -b docker -d -H unix:///var/run/docker-bootstrap.sock -p /var/run/docker-bootstrap.pid --iptables=false --ip-masq=false --bridge=none --graph=/var/lib/docker-bootstrap 2> /var/log/docker-bootstrap.log 1> /dev/null

	sleep 5
}

start_k8s(){
	# Start etcd 
	docker -H unix:///var/run/docker-bootstrap.sock run --net=host -d wizardcxy/etcd:2.0.9 /usr/local/bin/etcd --addr=127.0.0.1:4001 --bind-addr=0.0.0.0:4001 --data-dir=/var/etcd/data

	sleep 5
	# Set flannel net config
	docker -H unix:///var/run/docker-bootstrap.sock run --net=host wizardcxy/etcd:2.0.9 etcdctl set /coreos.com/network/config '{ "Network": "10.1.0.0/16" }'
    
    # iface may change to a private network interface
    flannelCID=$(docker -H unix:///var/run/docker-bootstrap.sock run -d --net=host --privileged -v /dev/net:/dev/net quay.io/coreos/flannel:0.3.0 /opt/bin/flanneld -iface="eth0")
	
	sleep 8

	# configure docker net settings ans restart it
	docker -H unix:///var/run/docker-bootstrap.sock cp ${flannelCID}:/run/flannel/subnet.env .
	source subnet.env

	echo "DOCKER_OPTS=\"\$DOCKER_OPTS --mtu=${FLANNEL_MTU} --bip=${FLANNEL_SUBNET}\"" | sudo tee -a sudo tee -a ${DOCKER_CONF}

	ifconfig docker0 down
    apt-get install bridge-utils && sudo brctl delbr docker0

	case "$lsb_dist" in
		fedora|centos)
            systemctl stop docker
        ;;
        ubuntu|debian|linuxmint)
            service docker restart
        ;;
    esac

	# Start Master components
	docker run --net=host -d -v /var/run/docker.sock:/var/run/docker.sock  wizardcxy/hyperkube:v0.17.0 /hyperkube kubelet --api_servers=http://localhost:8080 --v=2 --address=0.0.0.0 --enable_server --hostname_override=127.0.0.1 --config=/etc/kubernetes/manifests-multi
    docker run -d --net=host --privileged wizardcxy/hyperkube:v0.17.0 /hyperkube proxy --master=http://127.0.0.1:8080 --v=2   
}

install_registry(){
	# install private registry then
    docker -H unix:///var/run/docker-bootstrap.sock run -itd -p ${PRIVATE_IP}:${PRIVATE_PORT}:5000 -v ${HOSTDIR}:/tmp/registry-dev wizardcxy/registry:2.0

    # use insecure docker registry 
    echo "DOCKER_OPTS=\"\$DOCKER_OPTS --insecure-registry=${PRIVATE_IP}:${PRIVATE_PORT}\"" | sudo tee -a ${DOCKER_CONF}
}

detect_lsb

install_docker

install_registry

start_k8s


