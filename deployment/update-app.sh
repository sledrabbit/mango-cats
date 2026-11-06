#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/mango-cats}"
if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "SSH key not found at $SSH_KEY_PATH. Run ./deployment/initial-deploy.sh first." >&2
  exit 1
fi

public_ip="$(terraform -chdir=terraform output -raw public_ip)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

echo "Building Linux binary..."
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -o "$tmp_dir/mango-cats" .

ssh_options=(-i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new)
target="ec2-user@$public_ip"

echo "Waiting for SSH on $target..."
ready=false
for attempt in {1..12}; do
  if ssh "${ssh_options[@]}" -o ConnectTimeout=5 "$target" true 2>/dev/null; then
    ready=true
    break
  fi
  sleep 5
done
if [[ "$ready" != true ]]; then
  echo "SSH is not ready. Check the instance status and your current IP in the security group." >&2
  exit 1
fi

echo "Copying app and systemd service to $target..."
scp "${ssh_options[@]}" "$tmp_dir/mango-cats" "$target:/tmp/mango-cats.new"
scp "${ssh_options[@]}" deployment/mango-cats.service "$target:/tmp/mango-cats.service.new"

ssh "${ssh_options[@]}" "$target" '
  set -e
  if ! id mango-cats >/dev/null 2>&1; then
    sudo useradd --system --home-dir /var/lib/mango-cats --shell /sbin/nologin mango-cats
  fi
  sudo install -d -o mango-cats -g mango-cats -m 0750 /var/lib/mango-cats
  sudo install -o root -g root -m 0755 /tmp/mango-cats.new /usr/local/bin/mango-cats.next
  sudo mv -f /usr/local/bin/mango-cats.next /usr/local/bin/mango-cats
  sudo install -o root -g root -m 0644 /tmp/mango-cats.service.new /etc/systemd/system/mango-cats.service
  sudo systemctl daemon-reload
  sudo systemctl enable mango-cats.service
  sudo systemctl restart mango-cats.service
  sudo systemctl --no-pager --full status mango-cats.service
  rm /tmp/mango-cats.new /tmp/mango-cats.service.new
'

echo "App: http://$public_ip:8080"
echo "Health: http://$public_ip:8080/health"
echo "Checking health..."
for attempt in 1 2 3 4 5; do
  if curl --fail --silent --show-error --max-time 3 "http://$public_ip:8080/health"; then
    exit 0
  fi
  sleep 2
done
echo "Health check failed. Inspect logs with: ssh -i $SSH_KEY_PATH $target 'sudo journalctl -u mango-cats -n 50 --no-pager'" >&2
exit 1
