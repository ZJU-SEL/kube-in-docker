#!/bin/bash
# Relase.sh will make a new realse of k8s including hyperkube image and deployment scripts
# all in aio.tar.gz

set -ex

export VERSION=v0.18.2

cd image && make
cd ..
sudo docker save wizardcxy/hyperkube:${VERSION} > hyper.tar
sudo docker pull docker.io/kubernetes/pause
sudo docker save docker.io/kubernetes/pause > pause.tar
tar czvf aio.tar.gz master.sh minion.sh pause.tar hyper.tar gorouter.tar registry.tar etcd.tar flannel.tar