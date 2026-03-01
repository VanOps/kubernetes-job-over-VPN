## ══════════════════════════════════════════════════════════════════════
## GitOps – Ansible Jobs over WireGuard VPN
## Usage: make <target>   |   make help
## ══════════════════════════════════════════════════════════════════════

.DEFAULT_GOAL := help
SHELL         := /usr/bin/env bash

# ── Registry & Images ──────────────────────────────────────────────────
REGISTRY      ?= ghcr.io
REPO_OWNER    ?= $(shell git config --get remote.origin.url 2>/dev/null \
                   | sed -E 's|.*[:/]([^/]+)/.*|\1|' | tr '[:upper:]' '[:lower:]' \
                   || echo "OWNER")
VPN_IMAGE     := $(REGISTRY)/$(REPO_OWNER)/k8s-vpn-sidecar
ANSIBLE_IMAGE := $(REGISTRY)/$(REPO_OWNER)/k8s-ansible-executor
IMAGE_TAG     ?= $(shell git rev-parse --short HEAD 2>/dev/null || echo "dev")

# ── ArgoCD ─────────────────────────────────────────────────────────────
ARGOCD_SERVER ?= argocd.example.com
ARGOCD_TOKEN  ?= $(shell cat ~/.argocd-token 2>/dev/null || echo "SET_ARGOCD_TOKEN")

# ── Local testing ──────────────────────────────────────────────────────
ANSIBLE_PLAYBOOK  ?= playbooks/test-connectivity.yml
ANSIBLE_INVENTORY ?= inventories/dev
ANSIBLE_VERBOSITY ?= 2
ANSIBLE_TAGS      ?= test

# ── Colours ────────────────────────────────────────────────────────────
CYAN  := \033[0;36m
RESET := \033[0m
BOLD  := \033[1m

.PHONY: help
help: ## Show this help
	@echo ""
	@echo "$(BOLD)GitOps – Ansible Jobs over WireGuard VPN$(RESET)"
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*?##/ \
	  { printf "  $(CYAN)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo ""

## ── Docker ─────────────────────────────────────────────────────────────

.PHONY: build-vpn
build-vpn: ## Build WireGuard VPN sidecar image (local tag)
	docker build \
	  -t $(VPN_IMAGE):$(IMAGE_TAG) \
	  -t $(VPN_IMAGE):latest \
	  -t k8s-vpn-sidecar:local \
	  ./docker/vpn

.PHONY: build-ansible
build-ansible: ## Build Ansible executor image (local tag)
	docker build \
	  -t $(ANSIBLE_IMAGE):$(IMAGE_TAG) \
	  -t $(ANSIBLE_IMAGE):latest \
	  -t k8s-ansible-executor:local \
	  -f docker/ansible/Dockerfile \
	  .

.PHONY: build
build: build-vpn build-ansible ## Build all Docker images

.PHONY: push
push: ## Push images to GHCR (requires docker login)
	docker push $(VPN_IMAGE):$(IMAGE_TAG)
	docker push $(VPN_IMAGE):latest
	docker push $(ANSIBLE_IMAGE):$(IMAGE_TAG)
	docker push $(ANSIBLE_IMAGE):latest

.PHONY: build-push
build-push: build push ## Build and push all images

## ── Local Development ──────────────────────────────────────────────────

.PHONY: dev-setup
dev-setup: ## First-time setup: generate VPN lab keys + copy example secrets
	@echo "Setting up local dev environment..."
	@echo ""
	@echo "── Secrets ──────────────────────────────────"
	@[ -f test/secrets/vault-password ] || \
	  (cp test/secrets/vault-password.example test/secrets/vault-password && \
	   echo "  ✓ Created test/secrets/vault-password — set your vault password")
	@echo ""
	@echo "── VPN Lab keys (WireGuard + SSH) ───────────"
	bash test/vpn-lab/setup.sh
	@echo ""
	@echo "Ready. Common next steps:"
	@echo "  make lab-up             → start VPN lab only (standalone)"
	@echo "  make dev-up             → full local stack (VPN + Ansible executor)"

.PHONY: dev-up
dev-up: build ## Build images and run test playbook locally (VPN + Ansible)
	@echo "Starting VPN sidecar..."
	docker compose --profile dev up -d vpn
	@echo "Waiting for VPN container to become healthy (max 60s)..."
	@elapsed=0; \
	while true; do \
	  status=$$(docker inspect vpn-sidecar --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing"); \
	  state=$$(docker inspect vpn-sidecar --format '{{.State.Status}}' 2>/dev/null || echo "missing"); \
	  if [ "$$status" = "healthy" ]; then \
	    echo "VPN sidecar is healthy."; break; \
	  fi; \
	  if [ "$$state" = "exited" ] || [ "$$state" = "dead" ]; then \
	    echo ""; \
	    echo "ERROR: VPN container crashed (state=$$state). Logs:"; \
	    docker compose --profile dev logs vpn; \
	    echo ""; \
	    echo "Tip: set SKIP_VPN=true in docker-compose.yml or check test/vpn/wg0.conf"; \
	    exit 1; \
	  fi; \
	  if [ $$elapsed -ge 60 ]; then \
	    echo "TIMEOUT: VPN not healthy after 60s (status=$$status)."; \
	    docker compose --profile dev logs vpn; \
	    exit 1; \
	  fi; \
	  printf "."; sleep 2; elapsed=$$((elapsed + 2)); \
	done
	@echo "Running Ansible playbook: $(ANSIBLE_PLAYBOOK)"
	docker compose --profile dev run --rm \
	  -e ANSIBLE_PLAYBOOK=$(ANSIBLE_PLAYBOOK) \
	  -e ANSIBLE_INVENTORY=$(ANSIBLE_INVENTORY) \
	  -e ANSIBLE_VERBOSITY=$(ANSIBLE_VERBOSITY) \
	  ansible
	@echo "Done. Run 'make dev-down' to stop."

.PHONY: dev-down
dev-down: ## Stop and remove local dev containers
	docker compose --profile dev --profile run down

.PHONY: dev-logs
dev-logs: ## Follow logs from local dev environment
	docker compose --profile dev logs -f

.PHONY: dev-shell
dev-shell: ## Open shell in Ansible container (VPN must be running)
	docker compose --profile dev run --rm --entrypoint bash ansible

.PHONY: dev-vpn-status
dev-vpn-status: ## Show WireGuard status in local VPN container
	docker compose --profile dev exec vpn wg show wg0

## ── VPN Lab (Docker simulation) ────────────────────────────────────────
# Simulates a real WireGuard VPN server + remote Debian host using Docker.
# Use this to test the full VPN tunnel flow locally or from a K8s dev cluster
# without needing a real VPN server.
# Prerequisite: Docker with WireGuard kernel module (modprobe wireguard).

LAB_COMPOSE := docker-compose.vpn-lab.yml

.PHONY: lab-setup
lab-setup: ## Generate WireGuard + SSH keys for the VPN lab (run once)
	@echo "Generating VPN lab keys and configs..."
	bash test/vpn-lab/setup.sh

.PHONY: lab-build
lab-build: ## Build VPN lab Docker images (vpn-server + remote-host)
	docker compose -f $(LAB_COMPOSE) build

.PHONY: lab-up
lab-up: ## Start VPN lab (vpn-server + remote-host). Runs lab-setup if keys missing.
	@[ -f test/vpn-lab/wg0-server.conf ] || $(MAKE) lab-setup
	docker compose -f $(LAB_COMPOSE) up -d --build
	@echo "Waiting for vpn-server to become healthy (max 30s)..."
	@elapsed=0; \
	while true; do \
	  status=$$(docker inspect vpn-server --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing"); \
	  state=$$(docker inspect vpn-server --format '{{.State.Status}}' 2>/dev/null || echo "missing"); \
	  if [ "$$status" = "healthy" ]; then \
	    echo "vpn-server is healthy."; break; \
	  fi; \
	  if [ "$$state" = "exited" ] || [ "$$state" = "dead" ]; then \
	    echo ""; echo "ERROR: vpn-server crashed. Logs:"; \
	    docker compose -f $(LAB_COMPOSE) logs vpn-server; exit 1; \
	  fi; \
	  if [ $$elapsed -ge 30 ]; then \
	    echo "TIMEOUT: vpn-server not healthy after 30s."; \
	    docker compose -f $(LAB_COMPOSE) logs vpn-server; exit 1; \
	  fi; \
	  printf "."; sleep 2; elapsed=$$((elapsed + 2)); \
	done
	@echo ""
	@echo "VPN Lab is up."
	@echo "  WireGuard server : UDP $$(hostname -I | awk '{print $$1}'):51820"
	@echo "  Remote host (VPN): 10.10.20.10  (reachable only via tunnel)"
	@echo ""
	@echo "To use with the full local stack:"
	@echo "  SKIP_VPN=false docker compose --profile vpn-lab up"

.PHONY: lab-down
lab-down: ## Stop and remove VPN lab containers
	docker compose -f $(LAB_COMPOSE) down

.PHONY: lab-logs
lab-logs: ## Follow VPN lab logs (vpn-server + remote-host)
	docker compose -f $(LAB_COMPOSE) logs -f

.PHONY: lab-vpn-status
lab-vpn-status: ## Show WireGuard status on the VPN server
	docker exec vpn-server wg show wg0

.PHONY: lab-test
lab-test: ## Test VPN connectivity: ping remote-host through the WireGuard tunnel
	@echo "=== VPN Lab Connectivity Test ==="
	@echo ""
	@echo "1. WireGuard server status:"
	@docker exec vpn-server wg show wg0
	@echo ""
	@echo "2. Ping remote-host (10.10.20.10) from vpn-sidecar:"
	@docker exec vpn-sidecar ping -c 3 10.10.20.10 && \
	  echo "  ✓ remote-host reachable via VPN" || \
	  echo "  ✗ FAILED — ensure SKIP_VPN=false and vpn-sidecar is connected"

.PHONY: lab-shell
lab-shell: ## Open a shell inside the remote-host container
	docker exec -it remote-host bash

.PHONY: lab-clean
lab-clean: lab-down ## Stop VPN lab and remove all generated keys/configs
	@echo "Removing generated VPN lab files..."
	rm -f test/vpn-lab/server.key test/vpn-lab/server.pub \
	      test/vpn-lab/client.key test/vpn-lab/client.pub \
	      test/vpn-lab/wg0-server.conf \
	      test/vpn/wg0.conf \
	      test/secrets/ssh-public-key test/secrets/ssh-private-key
	@echo "Done. Run 'make lab-setup' to regenerate."

## ── Ansible Vault ──────────────────────────────────────────────────────

.PHONY: vault-create
vault-create: ## Create new ansible-vault secrets file
	ansible-vault create ansible/vault/secrets.yml

.PHONY: vault-edit
vault-edit: ## Edit ansible-vault secrets file
	ansible-vault edit ansible/vault/secrets.yml

.PHONY: vault-encrypt
vault-encrypt: ## Encrypt plaintext secrets.yml with ansible-vault
	ansible-vault encrypt ansible/vault/secrets.yml

.PHONY: vault-view
vault-view: ## View (but don't decrypt to disk) ansible-vault contents
	ansible-vault view ansible/vault/secrets.yml

## ── Helm ───────────────────────────────────────────────────────────────

.PHONY: helm-lint
helm-lint: ## Lint Helm chart for all environments
	@echo "Linting base chart..."
	helm lint helm/ansible-job/
	@echo "Linting dev..."
	helm lint helm/ansible-job/ -f helm/ansible-job/values-dev.yaml
	@echo "Linting staging..."
	helm lint helm/ansible-job/ -f helm/ansible-job/values-staging.yaml
	@echo "Linting prod..."
	helm lint helm/ansible-job/ -f helm/ansible-job/values-prod.yaml
	@echo "All lints passed ✓"

.PHONY: helm-template-dev
helm-template-dev: ## Render Helm templates for dev
	helm template ansible-job-dev helm/ansible-job/ \
	  -f helm/ansible-job/values.yaml \
	  -f helm/ansible-job/values-dev.yaml \
	  --namespace ansible-jobs-dev

.PHONY: helm-template-staging
helm-template-staging: ## Render Helm templates for staging
	helm template ansible-job-staging helm/ansible-job/ \
	  -f helm/ansible-job/values.yaml \
	  -f helm/ansible-job/values-staging.yaml \
	  --namespace ansible-jobs-staging

.PHONY: helm-template-prod
helm-template-prod: ## Render Helm templates for prod
	helm template ansible-job-prod helm/ansible-job/ \
	  -f helm/ansible-job/values.yaml \
	  -f helm/ansible-job/values-prod.yaml \
	  --namespace ansible-jobs-prod

## ── Kubernetes – Manual Secret Bootstrap (Initial Testing) ─────────────

.PHONY: k8s-secrets-dev
k8s-secrets-dev: ## Create K8s secrets in dev namespace (initial testing, no ExternalSecrets)
	@echo "Creating secrets in ansible-jobs-dev..."
	kubectl create namespace ansible-jobs-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic vpn-wireguard-config \
	  --from-file=wg0.conf=./test/vpn/wg0.conf \
	  -n ansible-jobs-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic ansible-vault-password \
	  --from-file=vault-password=./test/secrets/vault-password \
	  -n ansible-jobs-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic ansible-ssh-key \
	  --from-file=ssh-private-key=./test/secrets/ssh-private-key \
	  -n ansible-jobs-dev --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret docker-registry ghcr-pull-secret \
		--docker-server=ghcr.io \
		--docker-username=${GITHUB_USER} \
		--docker-password=${GITHUB_PAT} \
		-n ansible-jobs-dev
	echo ${GITHUB_PAT} | docker login ghcr.io -u ${GITHUB_USER} --password-stdin
	@echo "Secrets created in ansible-jobs-dev ✓"

.PHONY: k8s-secrets-vault-token
k8s-secrets-vault-token: ## Crear secret vault-token en ns external-secrets (auth ESO→Vault para staging)
	@test -n "$(VAULT_TOKEN)" || (echo "ERROR: usa: make k8s-secrets-vault-token VAULT_TOKEN=hvs.XXXX"; exit 1)
	kubectl create namespace external-secrets --dry-run=client -o yaml | kubectl apply -f -
	kubectl create secret generic vault-token \
	  --from-literal=token=$(VAULT_TOKEN) \
	  -n external-secrets --dry-run=client -o yaml | kubectl apply -f -
	@echo "vault-token creado en external-secrets ✓"

.PHONY: k8s-apply-external-secrets-staging
k8s-apply-external-secrets-staging: ## Aplicar Vault ClusterSecretStore + ExternalSecrets de staging (requiere vault-token)
	kubectl apply -f k8s/external-secrets/secret-store-vault.yaml
	kubectl apply -f k8s/external-secrets/staging-external-secret.yaml

.PHONY: k8s-apply-external-secrets-prod
k8s-apply-external-secrets-prod: ## Aplicar AWS ClusterSecretStore + ExternalSecrets de prod (requiere IRSA)
	kubectl apply -f k8s/external-secrets/secret-store-aws.yaml
	kubectl apply -f k8s/external-secrets/prod-external-secret.yaml

.PHONY: k8s-apply-external-secrets
k8s-apply-external-secrets: k8s-apply-external-secrets-staging k8s-apply-external-secrets-prod ## Aplicar todos los recursos ESO (staging + prod)

.PHONY: k8s-watch-dev
k8s-watch-dev: ## Watch Jobs in dev namespace
	kubectl get jobs -n ansible-jobs-dev -w

.PHONY: k8s-watch-staging
k8s-watch-staging: ## Watch Jobs in staging namespace
	kubectl get jobs -n ansible-jobs-staging -w

.PHONY: k8s-logs-dev
k8s-logs-dev: ## Get logs from latest ansible-executor in dev
	kubectl logs -n ansible-jobs-dev \
	  -l app.kubernetes.io/name=ansible-job \
	  -c ansible-executor --tail=200 --follow

.PHONY: k8s-logs-vpn-dev
k8s-logs-vpn-dev: ## Get VPN sidecar logs in dev
	kubectl logs -n ansible-jobs-dev \
	  -l app.kubernetes.io/name=ansible-job \
	  -c vpn-sidecar --tail=100

## ── ArgoCD ─────────────────────────────────────────────────────────────

.PHONY: argocd-login
argocd-login: ## Login to ArgoCD with token
	argocd login $(ARGOCD_SERVER) \
	  --auth-token $(ARGOCD_TOKEN) \
	  --grpc-web --insecure

.PHONY: argocd-install
argocd-install: ## Bootstrap ArgoCD app-of-apps (one-time setup)
	kubectl apply -f argocd/app-of-apps.yaml

.PHONY: dev-sync
dev-sync: ## Sync ArgoCD dev application
	argocd app sync ansible-job-dev --grpc-web
	argocd app wait ansible-job-dev --health --timeout 300 --grpc-web

.PHONY: staging-sync
staging-sync: ## Sync ArgoCD staging application (requires approval in CI)
	argocd app sync ansible-job-staging --grpc-web
	argocd app wait ansible-job-staging --health --timeout 600 --grpc-web

.PHONY: prod-approve
prod-approve: ## Interactively approve and sync ArgoCD prod (irreversible!)
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@echo "  ⚠  PRODUCTION SYNC – Review diff first:"
	argocd app diff ansible-job-prod --grpc-web || true
	@echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
	@read -rp "Type 'yes' to proceed with PROD sync: " confirm && \
	  [ "$$confirm" = "yes" ] || (echo "Aborted."; exit 1)
	argocd app sync ansible-job-prod --grpc-web
	argocd app wait ansible-job-prod --health --timeout 900 --grpc-web
	@echo "Production sync complete ✓"
	argocd app history ansible-job-prod --grpc-web | head -6

.PHONY: argocd-status
argocd-status: ## Show status of all ArgoCD applications
	argocd app list -l app.kubernetes.io/part-of=ansible-gitops --grpc-web

.PHONY: argocd-diff-dev
argocd-diff-dev: ## Show ArgoCD diff for dev
	argocd app diff ansible-job-dev --grpc-web

.PHONY: argocd-diff-staging
argocd-diff-staging: ## Show ArgoCD diff for staging
	argocd app diff ansible-job-staging --grpc-web

.PHONY: argocd-diff-prod
argocd-diff-prod: ## Show ArgoCD diff for prod
	argocd app diff ansible-job-prod --grpc-web

## ── CI / Quality ───────────────────────────────────────────────────────

.PHONY: ci
ci: helm-lint ## Run all local CI checks
	@echo "Running YAML lint..."
	@command -v yamllint &>/dev/null && \
	  yamllint -d '{extends: relaxed, rules: {line-length: {max: 160}}}' \
	  ansible/ helm/ argocd/ k8s/ || \
	  echo "yamllint not installed – skipping"
	@echo "CI checks passed ✓"

.PHONY: update-image-tags
update-image-tags: ## Update image tags in Helm values to current git SHA
	@echo "Updating image tags to: $(IMAGE_TAG)"
	@command -v yq &>/dev/null || (echo "ERROR: yq required. brew install yq"; exit 1)
	@read -rp "Update which env? (dev/staging/prod/all): " env; \
	  case "$$env" in \
	    dev)     yq eval ".vpn.image.tag = \"$(IMAGE_TAG)\" | .ansible.image.tag = \"$(IMAGE_TAG)\"" \
	               -i helm/ansible-job/values-dev.yaml ;; \
	    staging) yq eval ".vpn.image.tag = \"$(IMAGE_TAG)\" | .ansible.image.tag = \"$(IMAGE_TAG)\"" \
	               -i helm/ansible-job/values-staging.yaml ;; \
	    prod)    yq eval ".vpn.image.tag = \"$(IMAGE_TAG)\" | .ansible.image.tag = \"$(IMAGE_TAG)\"" \
	               -i helm/ansible-job/values-prod.yaml ;; \
	    all) for f in dev staging prod; do \
	           yq eval ".vpn.image.tag = \"$(IMAGE_TAG)\" | .ansible.image.tag = \"$(IMAGE_TAG)\"" \
	             -i helm/ansible-job/values-$$f.yaml; done ;; \
	  esac
	@echo "Done ✓"

## ── SSH Testing Labs ───────────────────────────────────────────────────

.PHONY: ssh-lab-up
ssh-lab-up: ## Start SSH testing lab (server + client with automated tests)
	@echo "$(CYAN)Starting SSH testing lab...$(RESET)"
	docker compose -f docker-compose.ssh-lab.yml up --build -d
	@echo "$(CYAN)Waiting for services to be ready...$(RESET)"
	@sleep 3
	docker compose -f docker-compose.ssh-lab.yml logs -f ssh-client

.PHONY: ssh-lab-logs
ssh-lab-logs: ## View SSH lab logs (both server and client)
	docker compose -f docker-compose.ssh-lab.yml logs -f

.PHONY: ssh-lab-down
ssh-lab-down: ## Stop and remove SSH testing lab
	@echo "$(CYAN)Stopping SSH lab...$(RESET)"
	docker compose -f docker-compose.ssh-lab.yml down

.PHONY: ssh-lab-reset
ssh-lab-reset: ssh-lab-down ssh-lab-up ## Reset SSH lab (down + up)

.PHONY: ssh-lab-shell
ssh-lab-shell: ## Open interactive shell in SSH client container
	docker exec -it ssh-test-client sh

.PHONY: ssh-test-connection
ssh-test-connection: ## Test SSH connection manually from client to server
	@echo "$(CYAN)Testing SSH connection...$(RESET)"
	docker exec -it ssh-test-client \
	  ssh -o StrictHostKeyChecking=accept-new ansible@ssh-server whoami

.PHONY: ssh-test-ansible
ssh-test-ansible: ## Test Ansible ping against SSH server
	@echo "$(CYAN)Testing Ansible ping module...$(RESET)"
	docker exec ssh-test-client \
	  ansible all -i ssh-server, -u ansible --private-key=/root/.ssh/id_rsa -m ping

.PHONY: build-ssh-server
build-ssh-server: ## Build SSH test server image
	@echo "$(CYAN)Building SSH test server...$(RESET)"
	docker build -t ssh-test-server:latest -f docker/ssh-test-server/Dockerfile .
	@echo "$(CYAN)Done ✓$(RESET)"
