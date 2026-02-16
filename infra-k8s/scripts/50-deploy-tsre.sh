#!/usr/bin/env bash
set -euo pipefail

kubectl create ns tsre --dry-run=client -o yaml | kubectl apply -f -

values_args=(-f apps/tsre-microservices/values.yaml)
if [[ -f app-values/tsre-local.yaml ]]; then
  values_args+=(-f app-values/tsre-local.yaml)
fi

helm template tsre apps/tsre-microservices -n tsre "${values_args[@]}" >/dev/null
helm upgrade --install tsre apps/tsre-microservices -n tsre "${values_args[@]}" --wait

kubectl -n tsre get deploy,pods,svc
