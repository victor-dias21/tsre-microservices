#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="kind-tsre"
KIND_CONFIG="clusters/kind/kind-config.yaml"
BOOTSTRAP_NS="clusters/kind/bootstrap/namespaces.yaml"

if ! kind get clusters | grep -qx "$CLUSTER_NAME"; then
  kind create cluster --config "$KIND_CONFIG"
else
  echo "[INFO] cluster $CLUSTER_NAME already exists"
fi

kubectl cluster-info >/dev/null
kubectl apply --dry-run=client -f "$BOOTSTRAP_NS" >/dev/null
kubectl apply -f "$BOOTSTRAP_NS"

kubectl get nodes
kubectl get ns argocd istio-system istio-ingress gateway-system datadog tsre >/dev/null
