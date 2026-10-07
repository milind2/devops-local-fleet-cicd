#!/bin/bash
# Refuse to run Terraform if state could leave this machine.
set -euo pipefail
cd "$(dirname "$0")/../terraform"

if grep -hoE 'backend "[a-z0-9_]+"' ./*.tf | grep -vq 'backend "local"'; then
  echo "ERROR: a non-local Terraform backend is configured. State must stay local." >&2
  exit 1
fi

if git ls-files --error-unmatch terraform.tfstate > /dev/null 2>&1; then
  echo "ERROR: terraform.tfstate is tracked by git." >&2
  exit 1
fi

if [ -f terraform.tfstate ]; then
  chmod 600 terraform.tfstate terraform.tfstate.backup 2>/dev/null || true
fi

echo "state check OK: local backend, not in git, mode 600"
