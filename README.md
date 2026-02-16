# TSRE Microservices com Kind + Argo CD + Istio + Gateway API + Datadog

Este repositório contém a aplicação TSRE Microservices e uma camada de infraestrutura Kubernetes local em `infra-k8s/`.

O objetivo é subir um ambiente completo com:
- Cluster local `kind` (`kind-tsre`)
- Argo CD (base GitOps)
- Istio (control plane + ingress gateway)
- Gateway API (GatewayClass, Gateway e HTTPRoute)
- Datadog (agents e cluster agent)
- Deploy da aplicação TSRE

## Estrutura do Projeto

- `infra-k8s/clusters/kind/`: configuração do cluster kind e bootstrap
- `infra-k8s/platform/argocd/`: AppProject e ApplicationSet
- `infra-k8s/platform/istio/`: values de instalação do Istio
- `infra-k8s/platform/gateway-api/`: manifests Gateway API
- `infra-k8s/platform/datadog/`: chart wrapper + values do Datadog
- `infra-k8s/apps/tsre-microservices/`: chart Helm da aplicação TSRE
- `infra-k8s/scripts/`: automações de setup e operação
- `infra-k8s/app-values/`: overrides locais de values

## Pré-requisitos

Ferramentas necessárias:
- `docker`
- `kind`
- `kubectl`
- `helm`
- `git`
- `make`
- `curl`

Observações:
- O script bootstrap tenta instalar automaticamente dependências ausentes.
- Em Linux, instalações podem pedir senha sudo.
- O Docker precisa estar em execução e acessível ao usuário atual.

## Variáveis Obrigatórias (Datadog)

Antes de subir o ambiente, exporte:

```bash
export DD_API_KEY="<sua_datadog_api_key>"
export DD_APP_KEY="<sua_datadog_app_key>"
```

Sem essas variáveis o bootstrap falha imediatamente.

## Subida Completa com 1 Comando (Recomendado)

Execute da raiz do repositório:

```bash
DD_API_KEY="<api_key>" DD_APP_KEY="<app_key>" ./infra-k8s/scripts/bootstrap-kind.sh
```

Comportamento do script:
1. Valida variáveis obrigatórias (`DD_API_KEY` e `DD_APP_KEY`)
2. Checa/instala dependências ausentes
3. Valida acesso ao Docker
4. Cria/atualiza o cluster `kind-tsre`
5. Cria namespace `datadog` e aplica `Secret` `datadog-secret`
6. Instala Argo CD e aplica objetos GitOps base
7. Instala Istio
8. Instala Gateway API e recursos de roteamento
9. Instala Datadog
10. Faz deploy da TSRE e roda smoke test

Saída esperada:
- Logs com `[STEP X/9]`
- Em caso de erro, mensagem com a etapa e comando que falhou

## Uso via Makefile

A execução por etapas também está disponível:

```bash
make -C infra-k8s check
make -C infra-k8s up
make -C infra-k8s status
make -C infra-k8s smoke
make -C infra-k8s down
```

## Verificações Pós-Deploy

### Kubernetes

```bash
kubectl get nodes
kubectl get ns
kubectl get pods -A
kubectl get gateway,httproute -A
```

### Aplicação TSRE

```bash
kubectl -n tsre get deploy,pods,svc
kubectl -n tsre port-forward svc/frontend 8088:80
```

Acesse:
- `http://127.0.0.1:8088`

### Datadog

Verifique no Datadog:
- Cluster `kind-tsre` visível
- Logs de pods do namespace `tsre`
- Métricas de Kubernetes
- Traces de pelo menos um serviço

## Configurações Locais (`app-values`)

- `infra-k8s/app-values/datadog-local.yaml`: tags e parâmetros locais do Datadog
- `infra-k8s/app-values/tsre-local.yaml`: overrides locais da aplicação

## Troubleshooting

### 1) Erro de permissão no Docker

Sintoma:
- `docker info` falha no bootstrap

Ação:
- habilitar daemon Docker
- adicionar usuário ao grupo `docker`
- relogar sessão

### 2) Porta 80/443 já em uso

Sintoma:
- falha ao criar kind cluster

Ação:
- liberar portas locais 80/443
- ou ajustar `infra-k8s/clusters/kind/kind-config.yaml`

### 3) `DD_API_KEY`/`DD_APP_KEY` ausentes

Sintoma:
- bootstrap interrompe no passo 1

Ação:
- exportar ambas variáveis e rodar novamente

### 4) Falha em chart/datadog

Ação:
```bash
helm dependency build infra-k8s/platform/datadog
helm template datadog-platform infra-k8s/platform/datadog -n datadog
```

### 5) Falha no smoke test

Ação:
```bash
kubectl -n tsre get pods
kubectl -n tsre describe pod <pod>
kubectl -n tsre logs <pod> --tail=200
```

## Segurança

- Não commitar chaves Datadog no Git
- Use variáveis de ambiente no runtime
- O secret Kubernetes `datadog-secret` é gerado em tempo de execução

## Limpeza do Ambiente

```bash
make -C infra-k8s down
```

Isso remove o cluster `kind-tsre`.
