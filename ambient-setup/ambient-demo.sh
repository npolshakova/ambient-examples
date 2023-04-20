#!/usr/bin/env bash

########################
# include the magic https://github.com/paxtonhare/demo-magic
########################
# export /Users/ninapolshakova/vm-demo/demo-magic.sh
. ${DEMO_MAGIC_PATH}

# make demo output look pretty
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

# run through examples

clear

export AMBIENT_CONTEXT=kind-ambient-cluster

# AuthorizationPolicy
pe "cat ../examples/authorizationpolicy/l4policy.yaml"
pe "kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l4policy.yaml"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1" # should suceed
pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1" # 403

# try same policy as sidecar
pe "cat ../examples/authorizationpolicy/l7policysidecar.yaml"
pe "kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l7policysidecar.yaml"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1" 
pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1" # no gateway yet!

pe "cat ../examples/authorizationpolicy/l7policyambient.yaml"
pe "kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l7policyambient.yaml"

pe "cat ../examples/authorizationpolicy/gateway.yaml"
pe "kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/gateway.yaml"

pe "kubectl get pods -n bookinfo --context=${AMBIENT_CONTEXT}"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # should suceed
pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: not-istio'" # 403
pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 403

# FaultInjection

pe "cat ../examples/faultinjection/virtualservice.yaml"

pe "kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/faultinjection/virtualservice.yaml"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 418

pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 403 -> still blocked by access policy

# Traffic Shift to subsets 
pe "cat ../examples/trafficshift/virtualservice.yaml"
pe "kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/virtualservice.yaml"

pe "cat ../examples/trafficshift/destinationrule.yaml"
pe "kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/destinationrule.yaml"

pe "cat ../examples/trafficshift/gateway.yaml"
pe "kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/gateway.yaml"
pe "kubectl get pods -n bookinfo --context=${AMBIENT_CONTEXT}"

# optional step to show hpa scaling works, this requires metrics server (see setup script)
# pe "kubectl autoscale deployment reviews-v1 --cpu-percent=50 --min=1 --max=10 -n bookinfo --context=${AMBIENT_CONTEXT}"
# pe "kubectl autoscale deployment reviews-v2 --cpu-percent=50 --min=1 --max=10 -n bookinfo --context=${AMBIENT_CONTEXT}"
# pe "kubectl get hpa -n bookinfo --context=${AMBIENT_CONTEXT}"

# check metrics sum(rate(istio_requests_total{destination_workload="reviews-v1"}[1m]))/sum(rate(istio_requests_total{destination_service_name="reviews"}[1m]))
pe "while true; do kubectl exec -it deploy/productpage-v1 --context=${AMBIENT_CONTEXT} -c curl -n bookinfo -- curl reviews:9080/reviews/1; done"