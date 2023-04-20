# Table of Contents
* [Introduction](#introduction)
* [Sidecar Setup](#sidecar)
* [Ambient Setup](#ambient)
* [AuthorizationPolicy](#auth)
* [Fault Injection](#fault)
* [Traffic Shift](#traffic)
* [References](#refs)

# Introduction <a name="introduction"></a>

This guide compares Istio's API when working across two interacting sidecars vs a sidecarless Ambient mesh. While Istio Ambient Mesh supports the same Istio API primitives, when and where policies are implemented under the hood are different. The setup creates a [kind](https://kind.sigs.k8s.io/) cluster locally and install Istio in sidecar mode in one cluster and Istio in ambient mode in another.

# Sidecar Setup <a name="sidecar"></a>

Setup the cluster, install istio and bookinfo with: 

```
./sidecar-setup/sidecar-setup.sh
```

Validate that istio is installed:

```
✔ Istio core installed
✔ Istiod installed
✔ Installation complete
```

Remember to label the namespace you want as part of the mesh with `istio-injection=enabled`.

Then install the bookinfo example app:

```
kubectl apply --namespace bookinfo -f examples/bookinfo.yaml
```

# Ambient Setup <a name="ambient"></a>

Setup the cluster, install istio and bookinfo with: 

```
./ambient-setup/ambient-setup.sh
```

Validate that istio is installed:

```
✔ Istio core installed
✔ Istiod installed
✔ Ztunnel installed
✔ CNI installed
✔ Installation complete
```

Then install the bookinfo example app:

```
kubectl apply --namespace bookinfo -f examples/bookinfo.yaml
```

Remember to label the namespace you want as part of the mesh with `istio.io/dataplane-mode=ambient`.

## Helpful tips

Bad wifi? The setup script sets up the kind registry along with the kind cluster registry mirror. You can pull and load images into the kind cluster like this:

```
docker pull docker.io/istio/pilot:1.18.0-alpha.0
kind load docker-image docker.io/istio/pilot:1.18.0-alpha.0 --name sidecar-cluster
```

# Authorization Policy <a name="auth"></a>

## Sidecar 

First apply an L4 only AuthorizationPolicy to explictly allow only productpage to call ratings.

```
cat ../examples/authorizationpolicy/l4policy.yaml
kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l4policy.yaml
```

What will happen after each request?

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1
kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1
```

Now apply a L7 policy:

```
cat ../examples/authorizationpolicy/l7policysidecar.yaml
kubectl apply --namespace=bookinfo --context=${SIDECAR_CONTEXT} -f ../examples/authorizationpolicy/l7policysidecar.yaml
```

What happens if we apply an L7 policy before we get a Gateway? 

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```

Apply the Gateway resource to create a waypoint for the service account:

```
cat ../examples/authorizationpolicy/gateway.yaml
kubectl apply --namespace=bookinfo --context=${SIDECAR_CONTEXT} -f ../examples/authorizationpolicy/gateway.yaml
```

See the waypoint is created:
```
kubectl get pods -n bookinfo --context=${SIDECAR_CONTEXT}
```

Let's try again:

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: not-istio'
kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```


## Ambient 

The ambient example is almost identical in the policies we are applying except the L7 authorization policy. 

First apply an L4 only AuthorizationPolicy to explictly allow only productpage to call ratings.

```
cat ../examples/authorizationpolicy/l4policy.yaml
kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l4policy.yaml
```

What will happen after each request?

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1
kubectl exec -it deploy/reviews-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1
```

Now apply a L7 policy:

```
cat ../examples/authorizationpolicy/l7policyambient.yaml
kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/l7policyambient.yaml
```

What happens if we apply an L7 policy before we get a Gateway? 

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```

Apply the Gateway resource to create a waypoint for the service account:

```
cat ../examples/authorizationpolicy/gateway.yaml
kubectl apply --namespace=bookinfo --context=${AMBIENT_CONTEXT} -f ../examples/authorizationpolicy/gateway.yaml
```

See the waypoint is created:
```
kubectl get pods -n bookinfo --context=${AMBIENT_CONTEXT}
```

Let's try again:

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
kubectl exec -it deploy/productpage-v1 -n bookinfo --context ${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: not-istio'
kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```

# Fault injection <a name="fault"></a>

## Sidecar

Leave the L7 authorization policy from before, now apply a fault injection policy with the virtual service: 

```
cat ../examples/faultinjection/virtualservice.yaml

kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/faultinjection/virtualservice.yaml
```

What is the expected response in these two cases? 

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'

kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${SIDECAR_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```

Where is the policy being applied in this case?

## Ambient

Leave the L7 authorization policy from before, now apply a fault injection policy with the virtual service: 

```
cat ../examples/faultinjection/virtualservice.yaml

kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/faultinjection/virtualservice.yaml
```

What is the expected response in these two cases? 

```
kubectl exec -it deploy/productpage-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'

kubectl exec -it deploy/reviews-v1 -n bookinfo --context=${AMBIENT_CONTEXT} -c curl -- curl ratings:9080/ratings/1 -H 'X-Test: istio-is-cool'
```

Where is the policy being applied in this case?

# Traffic shift <a name="traffic"></a>

## Sidecar

Apply the virtual service to define the traffic weights:

```
cat ../examples/trafficshift/virtualservice.yaml
kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/trafficshift/virtualservice.yaml
```

Apply the destination rule to select the subsets on the reviews service:
```
cat ../examples/trafficshift/destinationrule.yaml
kubectl apply --context=${SIDECAR_CONTEXT} -f ../examples/trafficshift/destinationrule.yaml
```

Send some traffic from product page to reviews:
```
while true; do kubectl exec -it deploy/productpage-v1 --context=${SIDECAR_CONTEXT} -c curl -n bookinfo -- curl reviews:9080/reviews/1; done
```

Port forward prometheus:

```
kubectl port-forward svc/prometheus 9090:9090 -n istio-system --context=${SIDECAR_CONTEXT}
```

Now let's check metrics in prometheus to see what percentage is hitting v1 vs. v2:

```
sum(rate(istio_requests_total{destination_workload="reviews-v1"}[5m]))/sum(rate(istio_requests_total{destination_service_name="reviews"}[5m]))
```

## Ambient

Apply the virtual service to define the traffic weights:

```
cat ../examples/trafficshift/virtualservice.yaml
kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/virtualservice.yaml
```

Apply the destination rule to select the subsets on the reviews service:
```
cat ../examples/trafficshift/destinationrule.yaml
kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/destinationrule.yaml
```

For ambient, we need to create a waypoint proxy for the reviews service account: 

```
cat ../examples/trafficshift/gateway.yaml
kubectl apply --context=${AMBIENT_CONTEXT} -f ../examples/trafficshift/gateway.yaml
kubectl get pods -n bookinfo --context=${AMBIENT_CONTEXT}
```

Send some traffic from product page to reviews:
```
while true; do kubectl exec -it deploy/productpage-v1 --context=${AMBIENT_CONTEXT} -c curl -n bookinfo -- curl reviews:9080/reviews/1; done
```

Port forward prometheus:

```
kubectl port-forward svc/prometheus 9090:9090 -n istio-system --context=${AMBIENT_CONTEXT}
```

Now let's check metrics in prometheus to see what percentage is hitting v1 vs. v2:

```
sum(rate(istio_requests_total{destination_workload="reviews-v1"}[5m]))/sum(rate(istio_requests_total{destination_service_name="reviews"}[5m]))
```

## References <a name="refs"></a>

- https://preliminary.istio.io/latest/docs/ops/ambient/getting-started/
