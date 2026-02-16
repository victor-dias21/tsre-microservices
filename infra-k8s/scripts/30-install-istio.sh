#!/usr/bin/env bash
set -euo pipefail

kubectl create ns istio-system --dry-run=client -o yaml | kubectl apply -f -
kubectl create ns istio-ingress --dry-run=client -o yaml | kubectl apply -f -

helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
helm repo update >/dev/null

helm upgrade --install istio-base istio/base -n istio-system --wait
helm upgrade --install istiod istio/istiod -n istio-system -f platform/istio/values-istiod.yaml --wait
helm upgrade --install istio-ingress istio/gateway -n istio-ingress -f platform/istio/values-gateway.yaml --wait

kubectl label namespace tsre istio-injection=enabled --overwrite
kubectl -n istio-system get pods
