SHELL := /usr/bin/env bash

.PHONY: up down status smoke check

check:
	./scripts/00-check-prereqs.sh

up: check
	./scripts/bootstrap-kind.sh

down:
	kind delete cluster --name kind-tsre

status:
	kubectl get nodes
	kubectl get ns
	kubectl get pods -A
	kubectl get gateway,httproute -A

smoke:
	./scripts/99-smoke-test.sh
