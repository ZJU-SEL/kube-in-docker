# kube-in-docker
**Run Kubernetes in Docker and anywhere**

We now support ubuntu, debian, mint, centos, fedora distribution

**On going**:

1. make this work on centos (done!)
2. merge two scripts into one (pending)
3. merge into kubernetes/master (doing)

**TODO**:

move bootstrap-docker into auto start


**Requirement**

At least one node have access to Internet, no PublicIP required.

**Usage**

On the node which have Internet access, set these ENV:

```
# variables which requires user filled in 
# registry related
PRIVATE_IP="10.168.14.145"
PRIVATE_PORT="5000"
# extra volume for registry
HOSTDIR="/mnt"
USER="cxy"
```

run `master.sh`. This node will act as both master & minion.

On every other worker node, set these ENV: 

```
MASTER_IP="10.168.14.145"
# just use minion's ip instead
HOSTNAME="10.168.10.5"
USER="cxy"
```

run `minion.sh`. They will act as minion.

Done!

**Notice**

If there're some of your minions have no access to Internet, you cannot start container on it because Docker cannot download image. Tha't why we installed a private registry on master. Please use it. 

**For Chinese users**

Google's `pause` image is blocked by GFW. We recommend you to pull from docker.io mannually and re-tag it like what `fix-pause` did. **You need to do this on every node!**

If your node have no access to Internet, you need to pull it from docker.io, export it, scp it to nodes. Then import & re-tag it on every node.
