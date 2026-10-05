.RECIPEPREFIX = >
.PHONY: key cloud-init apply configure rollout status destroy

key:
> test -f ~/.ssh/fleet_key || ssh-keygen -t ed25519 -f ~/.ssh/fleet_key -N "" -C "fleet"

cloud-init: key
> printf '#cloud-config\nssh_authorized_keys:\n  - %s\n' "$$(cat ~/.ssh/fleet_key.pub)" > terraform/cloud-init.yaml

apply: cloud-init
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
> act workflow_dispatch -W .github/workflows/deploy.yml -P self-hosted=-self-hosted -b
