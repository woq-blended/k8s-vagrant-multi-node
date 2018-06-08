MFILECWD = $(shell pwd)

# === BEGIN USER OPTIONS ===
# Box setup
BOX_IMAGE ?= centos/7
# Disk setup
DISK_COUNT ?= 1
DISK_SIZE_GB ?= 10

NODE_COUNT ?= 2
# Network
MASTER_IP ?= 192.168.26.10
NODE_IP_NW ?= 192.168.26.
POD_NW_CIDR ?= 10.244.0.0/16

# Addons
K8S_DASHBOARD ?= false

CLUSTER_NAME ?= $(shell basename $(MFILECWD))
# === END USER OPTIONS ===

preflight: token
	$(eval KUBETOKEN := $(shell cat $(MFILECWD)/.vagrant/KUBETOKEN))

token:
	@# [a-z0-9]{6}.[a-z0-9]{16}
	@if [ ! -f $(MFILECWD)/.vagrant/KUBETOKEN ]; then \
		if [ -z "$(KUBETOKEN)" ]; then \
			echo "$(shell cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 6 | head -n 1).$(shell cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 16 | head -n 1)" > $(MFILECWD)/.vagrant/KUBETOKEN; \
		else \
			echo "$(KUBETOKEN)" > $(MFILECWD)/.vagrant/KUBETOKEN; \
		fi; \
	fi;

up: preflight master nodes

master:
	vagrant up

	$(eval CLUSTERCERTSDIR := $(shell mktemp -d))

	vagrant ssh master -c 'sudo cat /etc/kubernetes/pki/ca.crt' \
		> $(CLUSTERCERTSDIR)/ca.crt
	vagrant ssh master -c 'sudo cat /root/.kube/config' \
		> $(CLUSTERCERTSDIR)/config
	@grep -P 'client-certificate-data:' $(CLUSTERCERTSDIR)/config | \
		sed -e 's/^[ \t]*//' | \
		cut -d' ' -f2 | \
		base64 -d -i \
		> $(CLUSTERCERTSDIR)/client-certificate.crt
	@grep -P 'client-key-data:' $(CLUSTERCERTSDIR)/config | \
		sed -e 's/^[ \t]*//' | \
		cut -d' ' -f2 | \
		base64 -d -i \
		> $(CLUSTERCERTSDIR)/client-key.key

	# kubeclt create cluster
	kubectl \
		config set-cluster \
			$(CLUSTER_NAME) \
			--embed-certs=true \
			--server=$(MASTER_IP):6443 \
			--certificate-authority=$(CLUSTERCERTSDIR)/ca.crt
	kubectl \
		config set-credentials \
			$(CLUSTER_NAME)-kubernetes-admin \
			--embed-certs=true \
			--username=kubernetes-admin \
			--client-certificate=$(CLUSTERCERTSDIR)/client-certificate.crt \
			--client-key=$(CLUSTERCERTSDIR)/client-key.key
	@rm -rf $(CLUSTERCERTSDIR)

	# kubeclt create context
	kubectl \
		config set-context \
			$(CLUSTER_NAME) \
			--cluster=$(CLUSTER_NAME) \
			--user=$(CLUSTER_NAME)-kubernetes-admin

	# kubectl switch to created context
	kubectl config use-context $(CLUSTER_NAME)
	@echo
	@echo "kubeclt has been configured to use started k8s-vagrant-multi-node Kubernetes cluster"
	@echo "kubectl context name: $(CLUSTER_NAME)"
	@echo

nodes: $(shell for i in $(shell seq 1 $(NODE_COUNT)); do echo "node-$$i"; done)

node-%:
	VAGRANT_VAGRANTFILE=Vagrantfile_nodes NODE=$* vagrant up

stop:
	vagrant halt -f
	VAGRANT_VAGRANTFILE=Vagrantfile_nodes vagrant halt -f

clean: clean-master $(shell for i in $(shell seq 1 $(NODE_COUNT)); do echo "clean-node-$$i"; done)

clean-master:
	-vagrant destroy -f

clean-node-%:
	-VAGRANT_VAGRANTFILE=Vagrantfile_nodes NODE=$* vagrant destroy -f node$*

clean-data:
	rm -rf "$(PWD)/data/*"
	rm -rf "$(PWD)/.vagrant/*.vdi"

load-image: load-image-master $(shell for i in $(shell seq 1 $(NODE_COUNT)); do echo "load-image-node-$$i"; done)

load-image-master:
	docker save $(IMG) | vagrant ssh "master" -t -c 'sudo docker load'

load-image-node-%:
	docker save $(IMG) | VAGRANT_VAGRANTFILE=Vagrantfile_nodes NODE=$* vagrant ssh "node$*" -t -c 'sudo docker load'

status: status-master $(shell for i in $(shell seq 1 $(NODE_COUNT)); do echo "status-node-$$i"; done)

status-master:
	@vagrant status | tail -n+3 | head -n-5

status-node-%:
	@VAGRANT_VAGRANTFILE=Vagrantfile_nodes NODE=$* vagrant status | tail -n+3 | head -n-5

.PHONY: preflight up master nodes stop clean clean-master clean-data load-image status
.EXPORT_ALL_VARIABLES:
