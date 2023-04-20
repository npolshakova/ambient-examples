#!/usr/bin/env bash

########################
# include the magic https://github.com/paxtonhare/demo-magic
########################

# apt update
# apt install pv

export DEMO_MAGIC_PATH="demo-magic/demo-magic.sh"

# https://github.com/paxtonhare/demo-magic.git
. ${DEMO_MAGIC_PATH}

# make demo output look pretty
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

# multicluster 

# kubectl apply --context ${MGMT} -f - <<EOF
# apiVersion: admin.gloo.solo.io/v2
# kind: Workspace
# metadata:
#   name: gateways
#   namespace: gloo-mesh
# spec:
#   workloadClusters:
#   - name: cluster1
#     namespaces:
#     - name: istio-gateways
#     - name: gloo-mesh-addons
#   - name: cluster2
#     namespaces:
#     - name: istio-gateways
#     - name: gloo-mesh-addons
# EOF

# kubectl apply --context ${CLUSTER1} -f - <<EOF
# apiVersion: admin.gloo.solo.io/v2
# kind: WorkspaceSettings
# metadata:
#   name: gateways
#   namespace: istio-gateways
# spec:
#   importFrom:
#   - workspaces:
#     - selector:
#         allow_ingress: "true"
#     resources:
#     - kind: SERVICE
#     - kind: ALL
#       labels:
#         expose: "true"
#   exportTo:
#   - workspaces:
#     - selector:
#         allow_ingress: "true"
#     resources:
#     - kind: SERVICE
# EOF

# kubectl apply --context ${MGMT} -f - <<EOF
# apiVersion: admin.gloo.solo.io/v2
# kind: Workspace
# metadata:
#   name: bookinfo
#   namespace: gloo-mesh
#   labels:
#     allow_ingress: "true"
# spec:
#   workloadClusters:
#   - name: cluster1
#     namespaces:
#     - name: bookinfo-frontends
#     - name: bookinfo-backends
#   - name: cluster2
#     namespaces:
#     - name: bookinfo-frontends
#     - name: bookinfo-backends
# EOF

# kubectl apply --context ${CLUSTER1} -f - <<EOF
# apiVersion: admin.gloo.solo.io/v2
# kind: WorkspaceSettings
# metadata:
#   name: bookinfo
#   namespace: bookinfo-frontends
# spec:
#   importFrom:
#   - workspaces:
#     - name: gateways
#     resources:
#     - kind: SERVICE
#   exportTo:
#   - workspaces:
#     - name: gateways
#     resources:
#     - kind: SERVICE
#       labels:
#         app: productpage
#     - kind: SERVICE
#       labels:
#         app: reviews
#     - kind: ALL
#       labels:
#         expose: "true"
# EOF

# echo "apiVersion: admin.gloo.solo.io/v2
# kind: RootTrustPolicy
# metadata:
#   name: root-trust-policy
#   namespace: gloo-mesh
# spec:
#   config:
#     mgmtServerCa:
#       generated: {}
#     autoRestartPods: true # Restarting pods automatically is NOT RECOMMENDED in Production
# " > roottrust.yaml  

# echo "apiVersion: networking.gloo.solo.io/v2
# kind: VirtualDestination
# metadata:
#   name: reviews
#   namespace: bookinfo-frontends
# spec:
#   hosts:
#   - reviews.global
#   services:
#   - namespace: bookinfo-backends
#     labels:
#       app: reviews
#   ports:
#     - number: 9080
#       protocol: HTTP
# " > virtualdestination.yaml  

# hide setup
clear

# enters interactive mode and allows newly typed command to be executed
# cmd

# p "ew_pod_cluster1=\$(kubectl --context cluster1 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')"
ew_pod_cluster1=$(kubectl --context cluster1 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')
p "istioctl --context cluster1 proxy-config secret -n istio-gateways \${ew_pod_cluster1}"
istioctl --context cluster1 proxy-config secret -n istio-gateways ${ew_pod_cluster1}

# p "ew_pod_cluster2=\$(kubectl --context cluster2 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')"
ew_pod_cluster2=$(kubectl --context cluster2 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')
p "istioctl --context cluster2 proxy-config secret -n istio-gateways \${ew_pod_cluster2}"
istioctl --context cluster2 proxy-config secret -n istio-gateways ${ew_pod_cluster2}

# pe "cat roottrust.yaml"
# pe "kubectl apply -f roottrust.yaml --context mgmt"  
pe "kubectl get roottrustpolicy root-trust-policy -n gloo-mesh --context mgmt -oyaml"

# give root trust some time
pe "cat virtualdestination.yaml"
pe "kubectl apply -f virtualdestination.yaml --context cluster1"  

pe "kubectl get gateways.networking.istio.io -n istio-gateways --context cluster2 -oyaml"

# ew_pod_cluster1=$(kubectl --context cluster1 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')
# p "istioctl --context cluster1 proxy-config secret -n istio-gateways \${ew_pod_cluster1}"
# istioctl --context cluster1 proxy-config secret -n istio-gateways ${ew_pod_cluster1}

# ew_pod_cluster2=$(kubectl --context cluster2 -n istio-gateways get pods -l istio=eastwestgateway -o jsonpath='{.items[0].metadata.name}')
# p "istioctl --context cluster2 proxy-config secret -n istio-gateways \${ew_pod_cluster2}"
# istioctl --context cluster2 proxy-config secret -n istio-gateways ${ew_pod_cluster2}

p "productpage_pod=\$(kubectl --context cluster1 -n bookinfo-frontends get pods -l app=productpage -o jsonpath='{.items[0].metadata.name}')"
productpage_pod=$(kubectl --context cluster1 -n bookinfo-frontends get pods -l app=productpage -o jsonpath='{.items[0].metadata.name}')
p "kubectl --context cluster1 -n bookinfo-frontends debug -i -q \${productpage_pod} --image=curlimages/curl -- curl -s http://reviews.global:9080/reviews/0 | jq"
kubectl --context cluster1 -n bookinfo-frontends debug -i -q ${productpage_pod} --image=curlimages/curl -- curl -s http://reviews.global:9080/reviews/0 | jq

# show graph
p "for i in \$(seq 25); do kubectl --context cluster1 -n bookinfo-frontends debug -i -q ${productpage_pod} --image=curlimages/curl -- curl -s http://reviews.global:9080/reviews/0; done"
for i in $(seq 25); do kubectl --context cluster1 -n bookinfo-frontends debug -i -q ${productpage_pod} --image=curlimages/curl -- curl -H -s http://reviews.global:9080/reviews/0; done

# show cluster2 
pe "kubectl scale deployment/reviews-v1 -n bookinfo-backends --replicas=0 --context cluster1"
pe "kubectl scale deployment/reviews-v2 -n bookinfo-backends --replicas=0 --context cluster1"
p "kubectl --context cluster1 -n bookinfo-frontends debug -i -q \${productpage_pod} --image=curlimages/curl -- curl -s http://reviews.global:9080/reviews/0 | jq"
kubectl --context cluster1 -n bookinfo-frontends debug -i -q ${productpage_pod} --image=curlimages/curl -- curl -s http://reviews.global:9080/reviews/0 | jq

# k1 delete vd reviews -n bookinfo-frontends
# k delete roottrustpolicy root-trust-policy -n gloo-mesh --context mgmt

# k1 scale deployment/reviews-v1 -n bookinfo-backends --replicas=0 
# k1 scale deployment/reviews-v2 -n bookinfo-backends --replicas=0

# k1 scale deployment/reviews-v1 -n bookinfo-backends --replicas=1 
# k1 scale deployment/reviews-v2 -n bookinfo-backends --replicas=1

# k1 delete pod -n istio-system --all
# k2 delete pod -n istio-system --all