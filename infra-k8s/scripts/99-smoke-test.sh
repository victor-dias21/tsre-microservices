#!/usr/bin/env bash
set -euo pipefail

kubectl -n tsre get deploy,pods,svc

if kubectl -n tsre get pods --no-headers | grep -q "CrashLoopBackOff"; then
  echo "[ERROR] CrashLoopBackOff detected in tsre namespace" >&2
  exit 1
fi

kubectl get gateway,httproute -A

kubectl -n tsre port-forward svc/frontend 8088:80 >/tmp/tsre-port-forward.log 2>&1 &
PF_PID=$!
trap 'kill $PF_PID >/dev/null 2>&1 || true' EXIT
sleep 3

status_code=$(curl -s -o /tmp/tsre-homepage.html -w "%{http_code}" http://127.0.0.1:8088/)
if [[ "$status_code" != "200" ]]; then
  echo "[ERROR] frontend returned HTTP $status_code" >&2
  exit 1
fi

echo "[OK] frontend responded with HTTP 200"

echo "[INFO] Datadog cluster-side check"
kubectl -n datadog get pods

echo "[INFO] Manual Datadog UI checks required: cluster metrics, tsre logs and traces"
