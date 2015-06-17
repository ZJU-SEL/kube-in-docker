# build the hyperkube image.

VERSION=v0.18.2

all:
	curl -O https://storage.googleapis.com/kubernetes-release/release/${VERSION}/bin/linux/amd64/hyperkube
	sed -i "s/VERSION/${VERSION}/g" master-multi.json master.json
	docker build -t wizardcxy/hyperkube:${VERSION} .
	docker push wizardcxy/hyperkube:${VERSION}

.PHONY: all
