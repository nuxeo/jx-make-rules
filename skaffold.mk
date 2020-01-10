# (C) Copyright 2019 Nuxeo (http://nuxeo.com/) and others.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# workaround against kaniko insecure registries accesses, run a pod providing
# the patched skaffold version aligned to the jx provided one (v0.29.0)
# to be reworked in NXBT-2910

.PHONY: skaffold@up skaffold@down

export ORG=nuxeo
export SCM_REF=$(shell git show -s --pretty=format:'%h%d' 2>/dev/null |echo unknown)
export VERSION ?= 0.0.0-SNAPSHOT
export DOCKER_REGISTRY ?= jenkins-x-docker-registry
export SKAFFOLD_DEPLOY_NAMESPACE ?= jx
export SKAFFOLD_NAMESPACE ?= $(SKAFFOLD_DEPLOY_NAMESPACE)

skaffold-version-embed = $(shell skaffold version 2>/dev/null)
skaffold-version ?= v0.38.0
ifneq ($(skaffold-version-embed),$(shell echo $(skaffold-versio) $(skaffold-version-embed) | sort -r -V | head -n1))
skaffold-pod-name := $(shell hostname)-skaffold
define skaffold_pod_template =
apiVersion: v1
kind: Pod
metadata:
  name: $(skaffold-pod-name)
spec:
  serviceAccountName: jenkins
  containers:
  - name: skaffold
    image: gcr.io/k8s-skaffold/skaffold:$(skaffold-version)
    command: ["/usr/bin/tail"]
    args: [ "-f", "/dev/null" ]
    volumeMounts:
      - name: kaniko-secret
        mountPath: /secret
    env:
      - name: GOOGLE_APPLICATION_CREDENTIALS
        value: /secret/kaniko-secret.json
  volumes:
    - name: kaniko-secret
      secret:
        secretName: kaniko-secret
endef
export skaffold_pod_template

define SKAFFOLD =
	tar cf - . | kubectl exec -i $(skaffold-pod-name) -- sh -c "rm -fr /tmp/skaffold && mkdir -p /tmp/skaffold && tar xvfC - /tmp/skaffold"
	kubectl exec $(skaffold-pod-name) -- sh -c "cd /tmp/skaffold && env VERSION=$(VERSION) DOCKER_REGISTRY=$(DOCKER_REGISTRY) skaffold $(1)"
endef
export SKAFFOLD


skaffold@up:
	@echo "$$skaffold_pod_template" | kubectl apply -f -
	@kubectl wait --timeout=-1s --for=condition=Ready pod/$(skaffold-pod-name)

skaffold@down:
	kubectl delete pod/$(skaffold-pod-name)
else
define SKAFFOLD =
	skaffold $(1)
endef
endif

.phony: skaffold@up skaffold@down skaffold.yaml~gen

skaffold.yaml~gen: skaffold.yaml
	envsubst < skaffold.yaml > skaffold.yaml~gen
