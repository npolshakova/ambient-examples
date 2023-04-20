reg_name='kind-registry'
reg_port='5000'
running="$(docker inspect -f '{{.State.Running}}' "${reg_name}" 2>/dev/null || true)"
if [ "${running}" != 'true' ]; then
  docker run \
    -d --restart=always -p "127.0.0.1:${reg_port}:5000" --name "${reg_name}" \
    registry:2
fi

export AMBIENT_CLUSTER=ambient-cluster

kind create cluster --name ${AMBIENT_CLUSTER} --config ambient-cluster.yaml

if [ "$(docker inspect -f='{{json .NetworkSettings.Networks.kind}}' "${reg_name}")" = 'null' ]; then
  docker network connect "kind" "${reg_name}"
fi

# get gateways crds
kubectl get crd gateways.gateway.networking.k8s.io &> /dev/null || \
  { kubectl kustomize "github.com/kubernetes-sigs/gateway-api/config/crd?ref=v0.6.1" | kubectl apply -f -; }


# make sure you have installed latest istio which has ambient profile
# curl -L https://istio.io/downloadIstio | ISTIO_VERSION=1.18.0-alpha.0 sh -
# export PATH=$PWD/bin:$PATH

istioctl install -y --context kind-${AMBIENT_CLUSTER} -f install_ambient.yaml

# load the docker image nonsense that takes forever 
kind load docker-image docker.io/istio/pilot:1.18.0-alpha.0 --name ${AMBIENT_CLUSTER}

kind load docker-image docker.io/istio/examples-bookinfo-productpage-v1:1.17.0 --name ${AMBIENT_CLUSTER}
kind load docker-image docker.io/istio/examples-bookinfo-ratings-v1:1.17.0 --name ${AMBIENT_CLUSTER}
kind load docker-image docker.io/istio/examples-bookinfo-reviews-v1:1.17.0 --name ${AMBIENT_CLUSTER}
kind load docker-image docker.io/istio/examples-bookinfo-details-v1:1.17.0 --name ${AMBIENT_CLUSTER}

# deploy the sample bookinfo example
kubectl create ns bookinfo
kubectl apply --namespace bookinfo -f ../examples/bookinfo.yaml --context kind-${AMBIENT_CLUSTER}

# label bookinfo namespace -> don't need pod restart :) 
kubectl label namespace bookinfo istio.io/dataplane-mode=ambient --context kind-${AMBIENT_CLUSTER}

# setup prometheus to get metrics 

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/addons/prometheus.yaml --context=kind-${AMBIENT_CLUSTER}

# setup kiali to view metrics

kubectl apply -f https://raw.githubusercontent.com/istio/istio/release-1.17/samples/addons/kiali.yaml --context=kind-${AMBIENT_CLUSTER}

# kubectl port-forward svc/kiali 20001:20001 -n istio-system --context=kind-${AMBIENT_CLUSTER}

# apply metrics server to use hpa (https://github.com/kubernetes-sigs/kind/issues/398)
# kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/download/v0.5.0/components.yaml  --context=kind-${AMBIENT_CLUSTER}
# kubectl patch deployment metrics-server -n kube-system --patch "$(cat ../examples/metric-server-patch.yaml)" --context=kind-${AMBIENT_CLUSTER}