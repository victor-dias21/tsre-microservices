#!/usr/bin/env bash
set -euo pipefail

ARGO_NS="argocd"
REPO_URL="${GITOPS_REPO_URL:-$(git config --get remote.origin.url)}"

if [[ -z "$REPO_URL" ]]; then
  echo "[ERROR] unable to determine GitOps repo URL" >&2
  exit 1
fi

if [[ "$REPO_URL" == git@github.com:* ]]; then
  REPO_URL="https://github.com/${REPO_URL#git@github.com:}"
fi
REPO_URL="${REPO_URL%.git}"

helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
helm repo update >/dev/null

helm upgrade --install argocd argo/argo-cd \
  --namespace "$ARGO_NS" \
  --create-namespace \
  --wait

kubectl -n "$ARGO_NS" wait --for=condition=available deployment/argocd-server --timeout=300s
kubectl apply --dry-run=client -f platform/argocd/project.yaml >/dev/null
kubectl apply -f platform/argocd/project.yaml

rendered_appset="/tmp/tsre-applicationset.yaml"
sed "s|__REPO_URL__|$REPO_URL|g" platform/argocd/applicationset.yaml.tmpl > "$rendered_appset"
kubectl apply --dry-run=client -f "$rendered_appset" >/dev/null
kubectl apply -f "$rendered_appset"

echo "[INFO] Argo CD installed and ApplicationSet applied (repo: $REPO_URL)"
