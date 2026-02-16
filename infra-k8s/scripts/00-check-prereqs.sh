#!/usr/bin/env bash
set -euo pipefail

required=(docker kind kubectl helm git)
optional=(argocd istioctl)

for bin in "${required[@]}"; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "[ERROR] missing required binary: $bin" >&2
    exit 1
  fi
  echo "[OK] $bin"
done

for bin in "${optional[@]}"; do
  if command -v "$bin" >/dev/null 2>&1; then
    echo "[OK] optional $bin"
  else
    echo "[WARN] optional binary not found: $bin"
  fi
done

echo "[INFO] validating docker"
docker info >/dev/null

echo "[INFO] validating helm"
helm version >/dev/null

echo "[INFO] prerequisite check complete"
