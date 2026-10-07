SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.RECIPEPREFIX = >
.PHONY: key cloud-init apply configure rollout status destroy

key:
> test -f ~/.ssh/fleet_key || ssh-keygen -t ed25519 -f ~/.ssh/fleet_key -N "" -C "fleet"

cloud-init: key
> printf '#cloud-config\nssh_authorized_keys:\n  - %s\n' "$$(cat ~/.ssh/fleet_key.pub)" > terraform/cloud-init.yaml

apply: cloud-init check-state
> multipass list > /dev/null
> cd terraform && terraform init -input=false && terraform apply -auto-approve

configure:
> cd ansible && ansible-playbook site.yml

rollout:
> cd ansible && ansible-playbook rollout.yml

status:
> cd ansible && ansible llama -m ansible.builtin.command -a "curl -s http://127.0.0.1:8080/health"

destroy:
> cd terraform && terraform destroy -auto-approve

.PHONY: verify act-rollout

verify:
> curl -sf http://$$(cd terraform && terraform output -json ips | jq -r '.["node-a"]'):8000/v1/chat/completions -H "Content-Type: application/json" -d '{"messages":[{"role":"user","content":"Say ok"}],"max_tokens":5}' | jq -r '.choices[0].message.content'

act-rollout:
> mkdir -p logs
> act workflow_dispatch -W .github/workflows/deploy.yml -P self-hosted=-self-hosted -b 2>&1 | tee logs/act-rollout-$$(date +%Y%m%d-%H%M%S).log

.PHONY: setup plan act-plan lint act-ci test-tf test-molecule check-state build model secrets

setup: key secrets
> cd terraform && terraform init -input=false

plan: cloud-init check-state
> cd terraform && terraform plan -input=false

act-plan:
> mkdir -p logs
> act workflow_dispatch -W .github/workflows/plan.yml -P self-hosted=-self-hosted 2>&1 | tee logs/act-plan-$$(date +%Y%m%d-%H%M%S).log

lint:
> cd terraform && terraform fmt -check -recursive
> cd terraform && terraform validate
> cd terraform && tflint
> shellcheck ansible/roles/llama_server/files/measure-load.sh scripts/*.sh
> yamllint .
> cd ansible && ansible-lint
> actionlint

act-ci:
> mkdir -p logs
> act workflow_dispatch -W .github/workflows/ci.yml -P self-hosted=-self-hosted 2>&1 | tee logs/act-ci-$$(date +%Y%m%d-%H%M%S).log

test-tf:
> cd terraform && terraform test

test-molecule:
> cd ansible/roles/common && molecule test

check-state:
> ./scripts/check-state.sh

LLAMA_VERSION := $(shell awk '/^llama_version:/ {gsub(/"/,"",$$2); print $$2}' ansible/group_vars/all.yml)

build: model
> sudo apt-get install -y -qq build-essential cmake git
> ./scripts/build-llama.sh $(LLAMA_VERSION)

MODEL_FILE := qwen2.5-0.5b-instruct-q4_k_m.gguf
MODEL_URL  := https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/$(MODEL_FILE)

model:
> mkdir -p ~/work/models
> test -f ~/work/models/$(MODEL_FILE) || (wget -q -O ~/work/models/$(MODEL_FILE).tmp $(MODEL_URL) && mv ~/work/models/$(MODEL_FILE).tmp ~/work/models/$(MODEL_FILE))
> ls -lh ~/work/models/$(MODEL_FILE)

secrets:
> mkdir -p ~/.config/fleet && chmod 700 ~/.config/fleet
> test -f ~/.config/fleet/grafana_admin_password || (umask 077 && openssl rand -base64 18 > ~/.config/fleet/grafana_admin_password)
