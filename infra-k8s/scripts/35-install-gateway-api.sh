#!/usr/bin/env bash
set -euo pipefail

GATEWAY_API_VERSION="v1.2.1"

kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${GATEWAY_API_VERSION}/standard-install.yaml"

kubectl apply --dry-run=client -k platform/gateway-api >/dev/null
kubectl apply -k platform/gateway-api

kubectl get gatewayclass
kubectl get gateway -n gateway-system
