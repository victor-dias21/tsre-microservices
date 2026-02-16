#!/usr/bin/env bash
set -euo pipefail

: "${DD_API_KEY:?DD_API_KEY must be set}"
DD_APP_KEY="${DD_APP_KEY:-$DD_API_KEY}"

kubectl create ns datadog --dry-run=client -o yaml | kubectl apply -f -
kubectl -n datadog create secret generic datadog-secret \
  --from-literal=api-key="$DD_API_KEY" \
  --from-literal=app-key="$DD_APP_KEY" \
  --dry-run=client -o yaml | kubectl apply -f -

helm dependency build platform/datadog >/dev/null
values_args=(-f platform/datadog/values.yaml)
if [[ -f app-values/datadog-local.yaml ]]; then
  values_args+=(-f app-values/datadog-local.yaml)
fi

helm template datadog-platform platform/datadog -n datadog "${values_args[@]}" >/dev/null
helm upgrade --install datadog-platform platform/datadog -n datadog "${values_args[@]}" --wait

kubectl -n datadog get pods
