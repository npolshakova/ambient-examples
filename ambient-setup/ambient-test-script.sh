
# setup kind cluster

reg_name='kind-registry'
reg_port='5000'
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

# set extraPortMappings for mac setup
cat << EOF > kind-cluster-1.yaml
  kind: Cluster
  apiVersion: kind.x-k8s.io/v1alpha4
  kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    nodeRegistration:
      kubeletExtraArgs:
        authorization-mode: "AlwaysAllow"
        feature-gates: "EphemeralContainers=true"
        # Populate nodes with region/zone info, which are used by VirtualDestination locality-based failover
        node-labels: "ingress-ready=true,topology.kubernetes.io/region=us-west,topology.kubernetes.io/zone=us-west-1b"
  - |
    kind: KubeletConfiguration
    featureGates:
      EphemeralContainers: true
  - |
    kind: KubeProxyConfiguration
    featureGates:
      EphemeralContainers: true
  - |
    kind: ClusterConfiguration
    metadata:
      name: config
    apiServer:
      extraArgs:
        "feature-gates": "EphemeralContainers=true"
    scheduler:
      extraArgs:
        "feature-gates": "EphemeralContainers=true"
    controllerManager:
      extraArgs:
        "feature-gates": "EphemeralContainers=true"
  networking:
    disableDefaultCNI: false
  nodes:
  - role: control-plane
    extraPortMappings:
    - containerPort: 32080
      hostPort: 32080
      protocol: TCP
    - containerPort: 32443
      hostPort: 32443
      protocol: TCP
    - containerPort: 32081
      hostPort: 32081
      protocol: TCP
    - containerPort: 32444
      hostPort: 32444
      protocol: TCP
    - containerPort: 32446
      hostPort: 32446
      protocol: TCP
  - role: worker
  - role: worker
  - role: worker

EOF

kind create cluster --name cluster-1 --config kind-cluster-1.yaml

# get gateways crds
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.6.1" | kubectl apply -f -; }


# install latest istio which has ambient profile
curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.0-alpha.0 sh -
export PATH=$PWD/bin:$PATH

istioctl install -y --set profile=ambient --set meshConfig.accessLogFile=/dev/stdout

# deploy the sample bookinfo example

 kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/bookinfo/platform/kube/bookinfo.yaml

# setup prometheus to get metrics 

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/addons/prometheus.yaml --context=kind-cluster-1

# setup kiali to view metrics

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/addons/kiali.yaml --context=kind-cluster-1

kubectl port-forward svc/kiali 20001:20001 -n istio-system --context=kind-cluster-1

# apply authorization policy 

# l4
kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: ratings-access
 namespace: default
spec:
 selector:
   matchLabels:
     app: ratings
 action: ALLOW
 rules:
 - from:
   - source:
       principals:
       - cluster.local/ns/bookinfo/sa/productpage
EOF

# l7

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
 name: ratings-access
 namespace: default
spec:
 selector:
   matchLabels:
     istio.io/gateway-name: bookinfo-ratings
 action: ALLOW
 rules:
 - from:
   - source:
       principals:
       - cluster.local/ns/bookinfo/sa/productpage
   to:
   - operation:
       methods: ["GET"]
EOF

# apply fault injection policy 

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: ratings-ew
  namespace: bookinfo
spec:
  gateways:
  - mesh
  hosts:
  - ratings
  http:
  - fault:
      abort:
        httpStatus: 418
        percentage:
          value: 100
    match:
    # note - source labels don't work in ambient ****
    # - sourceLabels:
    #     app: productpage
    - uri:
        prefix: /
    name: ratings-rt
    route:
    - destination:
        host: ratings.bookinfo.svc.cluster.local
        port:
          number: 9080
EOF

curl ratings:9080/ratings/1 # productpage -> 418

curl ratings:9080/ratings/1 # reviews -> still 418, not supported 

# apply subset routing 

cat <<EOF | kubectl apply --context=kind-cluster-1 -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: reviews
  namespace: bookinfo
  annotations:
    istio.io/for-service-account: bookinfo-reviews
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - allowedRoutes:
      namespaces:
        from: Same
    name: mesh
    port: 15008
    protocol: HBONE
EOF

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: reviews-ew
  namespace: bookinfo
spec:
  gateways:
  - mesh
  hosts:
  - reviews
  http:
  - match:
    - uri:
        prefix: /
    name: reviews-rt
    route:
    - destination:
        host: reviews.bookinfo.svc.cluster.local
        port:
          number: 9080
        subset: version-v1
      weight: 10
    - destination:
        host: reviews.bookinfo.svc.cluster.local
        port:
          number: 9080
        subset: version-v2
      weight: 90
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: reviews-subsets
  namespace: bookinfo
spec:
  host: reviews.bookinfo.svc.cluster.local
  subsets:
  - labels:
      version: v1
    name: version-v1
  - labels:
      version: v2
    name: version-v2
EOF

for i in $(seq 100); do kubectl exec -it deploy/productpage-v1 -n bookinfo --context kind-cluster-1 -c curl -- curl reviews:9080/reviews/1; echo "\n"; done

 kubectl exec -it deploy/productpage-v1 -n bookinfo --context kind-cluster-1 -c curl -- sh -c "for i in \$(seq 1 100); do curl reviews:9080/reviews/1 | grep reviews-v.-; done"

# might be easier to see with helloworld example
kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: helloworld-ew
  namespace: bookinfo
spec:
  gateways:
  - mesh
  hosts:
  - helloworld
  http:
  - match:
    - uri:
        prefix: /
    name: helloworld-rt
    route:
    - destination:
        host: helloworld.helloworld.svc.cluster.local
        port:
          number: 5000
        subset: version-v1
      weight: 10
    - destination:
        host: helloworld.helloworld.svc.cluster.local
        port:
          number: 5000
        subset: version-v2
      weight: 90
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: helloworld-subsets
  namespace: bookinfo
spec:
  host: helloworld.helloworld.svc.cluster.local
  subsets:
  - labels:
      version: v1
    name: version-v1
  - labels:
      version: v2
    name: version-v2
EOF

for i in $(seq 100); do kubectl exec -it deploy/productpage-v1 -n bookinfo --context kind-cluster-1 -c curl -- curl helloworld.helloworld.svc:5000/hello; echo "\n"; done

# apply lb policy consistent hashing example
# based on https://dev.to/peterj/what-are-sticky-sessions-and-how-to-configure-them-with-istio-1e1a example 

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: VirtualService
metadata:
  name: sticky-svc-ew
  namespace: default
spec:
  hosts:
    - 'sticky-svc.default.svc.cluster.local'
  gateways:
    - gateway
  http:
    - route:
      - destination:
          host: sticky-svc.default.svc.cluster.local
          port:
            number: 8080
EOF

# this should take 5s
curl -H "x-user: test" http://sticky-svc.default.svc.cluster.local:8080/ping

kubectl scale deploy sticky-svc --replicas=0 --context=kind-cluster-1
kubectl scale deploy sticky-svc --replicas=5 --context=kind-cluster-1

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
    name: sticky-svc
spec:
    host: sticky-service.default
    trafficPolicy:
      loadBalancer:
        simple: RANDOM
EOF

kubectl apply --context=kind-cluster-1 -f - <<EOF
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
    name: sticky-svc
spec:
    host: sticky-service.default.svc.cluster.local
    trafficPolicy:
      loadBalancer:
        simple: LEAST_CONN
EOF

cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1alpha3
kind: DestinationRule
metadata:
    name: sticky-svc
spec:
    host: sticky-svc.default.svc.cluster.local
    trafficPolicy:
      loadBalancer:
        consistentHash:
          httpHeaderName: x-user
EOF

# try it without the waypoint? Nothing happens :( 
curl -H "x-user: test" http://sticky-svc.default.svc.cluster.local:8080/ping

# apply waypoint to the default ns 
cat <<EOF | kubectl apply --context=kind-cluster-1 -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: namespace
  namespace: default
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - allowedRoutes:
      namespaces:
        from: Same
    name: mesh
    port: 15008
    protocol: HBONE
EOF

cat <<EOF | kubectl apply --context=kind-cluster-1 -f -
apiVersion: gateway.networking.k8s.io/v1beta1
kind: Gateway
metadata:
  name: ratings
  namespace: bookinfo
  annotations:
    istio.io/for-service-account: bookinfo-ratings
spec:
  gatewayClassName: istio-waypoint
  listeners:
  - allowedRoutes:
      namespaces:
        from: Same
    name: mesh
    port: 15008
    protocol: HBONE
EOF

# this should take 5s the first time
curl -H "x-user: test" http://sticky-svc.default.svc.cluster.local:8080/ping
curl -H "x-user: test" http://sticky-svc.default.svc.cluster.local:8080/ping
