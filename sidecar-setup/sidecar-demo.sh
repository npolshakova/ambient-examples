#!/usr/bin/env bash

########################
# include the magic https://github.com/paxtonhare/demo-magic
########################
# export DEMO_MAGIC_PATH=/Users/ninapolshakova/demo-magic/demo-magic.sh
. ${DEMO_MAGIC_PATH}

# make demo output look pretty
DEMO_PROMPT="${GREEN}➜ ${CYAN}\W "

SIDECAR_CONTEXT=kind-sidecar-cluster

clear 

# run through examples

# AuthorizationPolicy
pe "cat ../examples/authorizationpolicy/l4policy.yaml | yq"
pe "kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/authorizationpolicy/l4policy.yaml"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1" # should suceed
pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1" # 403

pe "cat ../examples/authorizationpolicy/l7policysidecar.yaml | yq"
pe "kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/authorizationpolicy/l7policysidecar.yaml"

pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # should suceed
pe "kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: not-istio'" # 403
pe "kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 403

# FaultInjection

pe "cat ../examples/faultinjection/virtualservice.yaml | yq"

pe "kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/faultinjection/virtualservice.yaml"

pe " kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 418
pe " kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'" # 418 -> client side

# Traffic shift

pe "cat ../examples/trafficshift/virtualservice.yaml | yq"
pe "kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/trafficshift/virtualservice.yaml"

pe "cat ../examples/trafficshift/destinationrule.yaml | yq"
pe "kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/trafficshift/destinationrule.yaml"

# optional step to show hpa scaling works, this requires metrics server (see setup script)
# pe "kubectl autoscale deployment reviews-v1 --cpu-percent=50 --min=1 --max=10 -n bookinfo --context=${SIDECAR_CONTEXT}"
# pe "kubectl autoscale deployment reviews-v2 --cpu-percent=50 --min=1 --max=10 -n bookinfo --context=${SIDECAR_CONTEXT}"
# pe "kubectl get hpa -n bookinfo --context=${SIDECAR_CONTEXT}"

# check metrics sum(rate(istio_requests_total{destination_workload="reviews-v1"}[1m]))/sum(rate(istio_requests_total{destination_service_name="reviews"}[1m]))
pe "while true; do kubectl exec -it deploy/productpage-v1 --context=${SIDECAR_CONTEXT} -c curl -n bookinfo -- curl reviews:9080/reviews/1; done"