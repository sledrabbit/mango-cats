#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
export AWS_PROFILE="${AWS_PROFILE:-default}"
action="${1:-apply}"
if [[ "$action" != "apply" && "$action" != "destroy" ]]; then
  echo "Usage: ./deployment/initial-deploy.sh [apply|destroy]" >&2
  exit 1
fi

key="$HOME/.ssh/mango-cats"
mkdir -p "$HOME/.ssh"
if [[ ! -f "$key" && ! -f "$key.pub" ]]; then
  ssh-keygen -q -t ed25519 -N '' -f "$key" -C mango-cats-deploy
fi
if [[ ! -f "$key" || ! -f "$key.pub" ]]; then
  echo "Expected both $key and $key.pub" >&2
  exit 1
fi

public_ip="$(curl --fail --silent --show-error -4 https://checkip.amazonaws.com | tr -d '[:space:]')"
terraform -chdir=terraform init
terraform -chdir=terraform "$action" -var "ssh_cidr=$public_ip/32" -var "ssh_public_key_path=$key.pub"
if [[ "$action" == "apply" ]]; then
  ./deployment/update-app.sh
fi
