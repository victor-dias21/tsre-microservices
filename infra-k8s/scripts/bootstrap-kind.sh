#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CURRENT_STEP="init"

log() {
  printf '[INFO] %s\n' "$*"
}

warn() {
  printf '[WARN] %s\n' "$*" >&2
}

err() {
  printf '[ERROR] %s\n' "$*" >&2
}

on_error() {
  local exit_code=$?
  err "Step '${CURRENT_STEP}' failed (exit=${exit_code}) while executing: ${BASH_COMMAND}"
  exit "$exit_code"
}

trap on_error ERR

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

with_sudo() {
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
    "$@"
  elif need_cmd sudo; then
    sudo "$@"
  else
    err "sudo is required to install missing dependencies."
    exit 1
  fi
}

detect_pkg_manager() {
  if need_cmd apt-get; then
    echo apt
    return
  fi
  if need_cmd dnf; then
    echo dnf
    return
  fi
  if need_cmd yum; then
    echo yum
    return
  fi
  if need_cmd brew; then
    echo brew
    return
  fi
  echo none
}

PKG_MANAGER="$(detect_pkg_manager)"

install_pkg() {
  case "$PKG_MANAGER" in
    apt)
      with_sudo apt-get update -y
      with_sudo apt-get install -y "$@"
      ;;
    dnf)
      with_sudo dnf install -y "$@"
      ;;
    yum)
      with_sudo yum install -y "$@"
      ;;
    brew)
      brew install "$@"
      ;;
    *)
      err "No supported package manager found. Install manually: $*"
      exit 1
      ;;
  esac
}

install_docker() {
  if need_cmd docker; then
    return
  fi
  log "Installing docker..."
  case "$PKG_MANAGER" in
    apt|dnf|yum)
      curl -fsSL https://get.docker.com | with_sudo sh
      if need_cmd systemctl; then
        with_sudo systemctl enable --now docker
      fi
      ;;
    brew)
      brew install --cask docker
      warn "Start Docker Desktop before continuing."
      ;;
    *)
      err "Unsupported OS/package manager for docker auto-install."
      exit 1
      ;;
  esac
}

install_kind() {
  if need_cmd kind; then
    return
  fi
  log "Installing kind..."
  local os arch url
  os="$(uname | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      err "Unsupported architecture for kind: $arch"
      exit 1
      ;;
  esac
  url="https://kind.sigs.k8s.io/dl/v0.23.0/kind-${os}-${arch}"
  curl -fsSL "$url" -o /tmp/kind
  with_sudo install -m 0755 /tmp/kind /usr/local/bin/kind
  rm -f /tmp/kind
}

install_kubectl() {
  if need_cmd kubectl; then
    return
  fi
  log "Installing kubectl..."
  local os arch version url
  os="$(uname | tr '[:upper:]' '[:lower:]')"
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *)
      err "Unsupported architecture for kubectl: $arch"
      exit 1
      ;;
  esac
  version="$(curl -fsSL https://dl.k8s.io/release/stable.txt)"
  url="https://dl.k8s.io/release/${version}/bin/${os}/${arch}/kubectl"
  curl -fsSL "$url" -o /tmp/kubectl
  with_sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl
  rm -f /tmp/kubectl
}

install_helm() {
  if need_cmd helm; then
    return
  fi
  log "Installing helm..."
  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 -o /tmp/get-helm-3.sh
  chmod +x /tmp/get-helm-3.sh
  with_sudo /tmp/get-helm-3.sh
  rm -f /tmp/get-helm-3.sh
}

install_git() {
  if need_cmd git; then
    return
  fi
  log "Installing git..."
  install_pkg git
}

install_make() {
  if need_cmd make; then
    return
  fi
  log "Installing make..."
  case "$PKG_MANAGER" in
    apt|dnf|yum|brew) install_pkg make ;;
    *)
      err "Unsupported package manager for make installation."
      exit 1
      ;;
  esac
}

install_curl() {
  if need_cmd curl; then
    return
  fi
  log "Installing curl..."
  install_pkg curl
}

ensure_docker_ready() {
  if docker info >/dev/null 2>&1; then
    return
  fi
  if need_cmd systemctl; then
    log "Starting docker daemon..."
    with_sudo systemctl enable --now docker || true
  fi
  if ! docker info >/dev/null 2>&1; then
    err "Docker daemon is not accessible for current user."
    err "If just installed, relogin to apply docker group permissions and rerun."
    exit 1
  fi
}

require_datadog_keys() {
  # For CI/local runs where Datadog isn't needed.
  if [[ "${SKIP_DATADOG:-0}" == "1" ]]; then
    warn "SKIP_DATADOG=1: skipping Datadog secret/key validation"
    return
  fi
  if [[ -z "${DD_API_KEY:-}" ]]; then
    err "DD_API_KEY is required. Export it before running."
    err "Example: DD_API_KEY=xxx DD_APP_KEY=yyy ./infra-k8s/scripts/bootstrap-kind.sh"
    exit 1
  fi
  if [[ -z "${DD_APP_KEY:-}" ]]; then
    err "DD_APP_KEY is required. Export it before running."
    err "Example: DD_API_KEY=xxx DD_APP_KEY=yyy ./infra-k8s/scripts/bootstrap-kind.sh"
    exit 1
  fi
}

create_datadog_secret() {
  if [[ "${SKIP_DATADOG:-0}" == "1" ]]; then
    warn "SKIP_DATADOG=1: not creating datadog-secret"
    return
  fi
  kubectl create ns datadog --dry-run=client -o yaml | kubectl apply -f -
  kubectl -n datadog create secret generic datadog-secret \
    --from-literal=api-key="$DD_API_KEY" \
    --from-literal=app-key="$DD_APP_KEY" \
    --dry-run=client -o yaml | kubectl apply -f -
}

run_check_prereqs() {
  local required optional bin
  required=(docker kind kubectl helm git)
  optional=(argocd istioctl)

  for bin in "${required[@]}"; do
    if ! need_cmd "$bin"; then
      err "missing required binary after install attempt: $bin"
      exit 1
    fi
    log "[OK] $bin"
  done

  for bin in "${optional[@]}"; do
    if need_cmd "$bin"; then
      log "[OK] optional $bin"
    else
      warn "optional binary not found: $bin"
    fi
  done

  docker info >/dev/null
  helm version >/dev/null
}

run_create_kind_cluster() {
  local cluster_name kind_config bootstrap_ns
  cluster_name="kind-tsre"
  kind_config="$ROOT_DIR/clusters/kind/kind-config.yaml"
  bootstrap_ns="$ROOT_DIR/clusters/kind/bootstrap/namespaces.yaml"

  if ! kind get clusters | grep -qx "$cluster_name"; then
    kind create cluster --config "$kind_config"
  else
    log "cluster $cluster_name already exists"
  fi

  kubectl cluster-info >/dev/null
  kubectl apply --dry-run=client -f "$bootstrap_ns" >/dev/null
  kubectl apply -f "$bootstrap_ns"
  kubectl get nodes
  kubectl get ns argocd istio-system istio-ingress gateway-system datadog tsre >/dev/null
}

run_install_argocd() {
  local argo_ns repo_url rendered_appset
  argo_ns="argocd"

  repo_url="${GITOPS_REPO_URL:-$(git -C "$ROOT_DIR/.." config --get remote.origin.url || true)}"
  if [[ -z "$repo_url" ]]; then
    err "unable to determine GitOps repo URL"
    exit 1
  fi
  if [[ "$repo_url" == git@github.com:* ]]; then
    repo_url="https://github.com/${repo_url#git@github.com:}"
  fi
  repo_url="${repo_url%.git}"

  helm repo add argo https://argoproj.github.io/argo-helm >/dev/null
  helm repo update >/dev/null

  helm upgrade --install argocd argo/argo-cd \
    --namespace "$argo_ns" \
    --create-namespace \
    --wait

  kubectl -n "$argo_ns" wait --for=condition=available deployment/argocd-server --timeout=300s
  kubectl apply --dry-run=client -f "$ROOT_DIR/platform/argocd/project.yaml" >/dev/null
  kubectl apply -f "$ROOT_DIR/platform/argocd/project.yaml"

  rendered_appset="/tmp/tsre-applicationset.yaml"
  sed "s|__REPO_URL__|$repo_url|g" "$ROOT_DIR/platform/argocd/applicationset.yaml.tmpl" > "$rendered_appset"
  kubectl apply --dry-run=client -f "$rendered_appset" >/dev/null
  kubectl apply -f "$rendered_appset"

  log "Argo CD installed and ApplicationSet applied (repo: $repo_url)"
}

run_install_istio() {
  kubectl create ns istio-system --dry-run=client -o yaml | kubectl apply -f -
  kubectl create ns istio-ingress --dry-run=client -o yaml | kubectl apply -f -

  helm repo add istio https://istio-release.storage.googleapis.com/charts >/dev/null
  helm repo update >/dev/null

  helm upgrade --install istio-base istio/base -n istio-system --wait
  helm upgrade --install istiod istio/istiod -n istio-system -f "$ROOT_DIR/platform/istio/values-istiod.yaml" --wait
  helm upgrade --install istio-ingress istio/gateway -n istio-ingress -f "$ROOT_DIR/platform/istio/values-gateway.yaml" --wait

  kubectl label namespace tsre istio-injection=enabled --overwrite
  kubectl -n istio-system get pods
}

run_install_gateway_api() {
  local gateway_api_version crd attempt
  gateway_api_version="v1.2.1"

  kubectl apply -f "https://github.com/kubernetes-sigs/gateway-api/releases/download/${gateway_api_version}/standard-install.yaml"

  for crd in \
    gatewayclasses.gateway.networking.k8s.io \
    gateways.gateway.networking.k8s.io \
    grpcroutes.gateway.networking.k8s.io \
    httproutes.gateway.networking.k8s.io \
    referencegrants.gateway.networking.k8s.io; do
    kubectl wait --for=condition=Established --timeout=180s "crd/${crd}" >/dev/null
  done

  # Give API discovery a short window to pick up newly established CRDs.
  for attempt in {1..12}; do
    if kubectl api-resources --api-group=gateway.networking.k8s.io | grep -q "HTTPRoute"; then
      break
    fi
    sleep 2
  done

  # Retry client-side validation to avoid transient "no matches for kind HTTPRoute".
  for attempt in {1..10}; do
    if kubectl apply --dry-run=client -k "$ROOT_DIR/platform/gateway-api" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" -eq 10 ]]; then
      err "Gateway API resources validation failed after retries."
      exit 1
    fi
    warn "Gateway API CRDs not fully ready yet (attempt ${attempt}/10), retrying..."
    sleep 3
  done

  kubectl apply -k "$ROOT_DIR/platform/gateway-api"
  kubectl get gatewayclass
  kubectl get gateway -n gateway-system
}

run_install_datadog() {
  local values_args
  create_datadog_secret

  helm repo add datadog https://helm.datadoghq.com >/dev/null
  helm repo update >/dev/null

  helm dependency build "$ROOT_DIR/platform/datadog" >/dev/null
  values_args=(-f "$ROOT_DIR/platform/datadog/values.yaml")
  if [[ -f "$ROOT_DIR/app-values/datadog-local.yaml" ]]; then
    values_args+=(-f "$ROOT_DIR/app-values/datadog-local.yaml")
  fi

  helm template datadog-platform "$ROOT_DIR/platform/datadog" -n datadog "${values_args[@]}" >/dev/null
  helm upgrade --install datadog-platform "$ROOT_DIR/platform/datadog" -n datadog "${values_args[@]}" --wait
  kubectl -n datadog get pods
}

run_deploy_tsre() {
  local values_args
  kubectl create ns tsre --dry-run=client -o yaml | kubectl apply -f -

  log "Building local paymentservice image for kind (tsre/paymentservice:kind)"
  docker build -t tsre/paymentservice:kind -f "$ROOT_DIR/../src/paymentservice/Dockerfile.kind" "$ROOT_DIR/../src/paymentservice"
  kind load docker-image tsre/paymentservice:kind --name kind-tsre

  values_args=(-f "$ROOT_DIR/apps/tsre-microservices/values.yaml")
  if [[ -f "$ROOT_DIR/app-values/tsre-local.yaml" ]]; then
    values_args+=(-f "$ROOT_DIR/app-values/tsre-local.yaml")
  fi

  helm template tsre "$ROOT_DIR/apps/tsre-microservices" -n tsre "${values_args[@]}" >/dev/null
  helm upgrade --install tsre "$ROOT_DIR/apps/tsre-microservices" -n tsre "${values_args[@]}" --wait
  kubectl -n tsre get deploy,pods,svc
}

run_smoke_test() {
  local status_code
  PF_PID=""
  kubectl -n tsre get deploy,pods,svc
  if kubectl -n tsre get pods --no-headers | grep -q "CrashLoopBackOff"; then
    err "CrashLoopBackOff detected in tsre namespace"
    exit 1
  fi

  kubectl get gateway,httproute -A
  kubectl -n tsre port-forward svc/frontend 8088:80 >/tmp/tsre-port-forward.log 2>&1 &
  PF_PID=$!
  trap 'if [[ -n "${PF_PID:-}" ]]; then kill "${PF_PID}" >/dev/null 2>&1 || true; fi' EXIT
  sleep 3

  status_code="$(curl -s -o /tmp/tsre-homepage.html -w "%{http_code}" http://127.0.0.1:8088/)"
  if [[ "$status_code" != "200" ]]; then
    err "frontend returned HTTP $status_code"
    exit 1
  fi
  log "[OK] frontend responded with HTTP 200"
  if [[ "${SKIP_DATADOG:-0}" != "1" ]]; then
    log "Datadog cluster-side check"
    kubectl -n datadog get pods
    log "Manual Datadog UI checks required: cluster metrics, tsre logs and traces"
  else
    log "SKIP_DATADOG=1: skipping Datadog checks"
  fi
  if [[ -n "${PF_PID:-}" ]]; then
    kill "${PF_PID}" >/dev/null 2>&1 || true
    PF_PID=""
  fi
  trap - EXIT
}

main() {
  CURRENT_STEP="validate-env-vars"
  log "[STEP 1/10] Validating required environment variables"
  require_datadog_keys

  CURRENT_STEP="install-dependencies"
  log "[STEP 2/10] Checking and installing dependencies if needed"
  install_curl
  install_git
  install_make
  install_docker
  install_kind
  install_kubectl
  install_helm
  ensure_docker_ready

  CURRENT_STEP="validate-tools"
  log "[STEP 3/10] Validating tools and runtime access"
  run_check_prereqs

  CURRENT_STEP="create-kind-cluster"
  log "[STEP 4/10] Creating/updating kind cluster"
  run_create_kind_cluster

  CURRENT_STEP="install-argocd"
  log "[STEP 5/10] Installing Argo CD and applying GitOps project/application set"
  run_install_argocd

  CURRENT_STEP="install-istio"
  log "[STEP 6/10] Installing Istio control plane and ingress gateway"
  run_install_istio

  CURRENT_STEP="install-gateway-api"
  log "[STEP 7/10] Installing Gateway API CRDs and gateway resources"
  run_install_gateway_api

  CURRENT_STEP="install-datadog"
  log "[STEP 8/10] Installing Datadog agents/components"
  if [[ "${SKIP_DATADOG:-0}" != "1" ]]; then
    run_install_datadog
  else
    warn "SKIP_DATADOG=1: skipping Datadog install"
  fi

  CURRENT_STEP="deploy-tsre"
  log "[STEP 9/10] Deploying TSRE application"
  run_deploy_tsre

  CURRENT_STEP="smoke-test"
  log "[STEP 10/10] Running smoke test"
  run_smoke_test

  log "Environment is up."
}

main "$@"
