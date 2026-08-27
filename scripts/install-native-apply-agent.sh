#!/usr/bin/env bash
# One-time (idempotent) setup for the native `local`-backend Woodpecker
# agent that runs homelab-infra's `apply` workflow directly on this host
# -- no Docker sandbox, no SSH-forced-command hack. See
# homelab-infra/.woodpecker/apply.yaml, this repo's README, and the
# "merge homelab-edge into homelab-infra" plan for context.
#
# Authenticates to the server using the SAME system token the existing
# Docker-backed agent uses (AGENT_SECRET in this repo's .env) -- Woodpecker
# does not support inventing an arbitrary secret for a new agent; it's
# either this shared system token (any agent presenting it gets
# auto-registered with its own server-assigned ID) or a per-agent token
# issued manually through the Woodpecker web UI. The system token is
# simpler and matches what's already in place, so that's what this uses.
#
# Usage: sudo bash scripts/install-native-apply-agent.sh /path/to/woodpecker-agent.deb
set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DEB_PATH="${1:?Usage: $0 /path/to/woodpecker-agent.deb}"
LOCAL_TEMP_DIR="/var/lib/woodpecker-apply"
ENV_FILE="/etc/woodpecker/woodpecker-agent.env"
SUDOERS_FILE="/etc/sudoers.d/woodpecker-apply"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Must run as root (sudo bash $0 ...)" >&2
  exit 1
fi

if [[ ! -f "$REPO_ROOT/.env" ]]; then
  echo "Missing $REPO_ROOT/.env -- copy .env.example and fill it in first." >&2
  exit 1
fi

# shellcheck disable=SC1090
AGENT_SECRET="$(grep -E '^AGENT_SECRET=' "$REPO_ROOT/.env" | cut -d= -f2-)"
if [[ -z "$AGENT_SECRET" ]]; then
  echo "AGENT_SECRET not set in $REPO_ROOT/.env" >&2
  exit 1
fi

echo "== Install woodpecker-agent package =="
dpkg -i "$DEB_PATH"

echo "== Create dedicated 'woodpecker' system user =="
if ! id woodpecker >/dev/null 2>&1; then
  useradd --system --no-create-home --shell /usr/sbin/nologin woodpecker
  echo "Created user 'woodpecker'."
else
  echo "User 'woodpecker' already exists."
fi

echo "== Create local-backend temp-dir prefix =="
mkdir -p "$LOCAL_TEMP_DIR"
chown woodpecker:woodpecker "$LOCAL_TEMP_DIR"

echo "== Write agent env file (same system token as the Docker agent) =="
cat > "$ENV_FILE" <<EOF
WOODPECKER_SERVER=localhost:20036
WOODPECKER_AGENT_SECRET=$AGENT_SECRET
WOODPECKER_BACKEND=local
WOODPECKER_AGENT_LABELS=type=host-apply
WOODPECKER_BACKEND_LOCAL_TEMP_DIR=$LOCAL_TEMP_DIR
# Persist the agent's server-assigned identity in the state directory the
# systemd unit already owns (StateDirectory=woodpecker -> /var/lib/woodpecker,
# owned by the woodpecker user). Without this the agent is stateless and
# re-registers as a new agent entry on every restart (the default path,
# /etc/woodpecker/agent.conf, isn't writable by the woodpecker user).
WOODPECKER_AGENT_CONFIG_FILE=/var/lib/woodpecker/agent.conf
EOF
chmod 600 "$ENV_FILE"
chown root:root "$ENV_FILE"

echo "== Install sudoers rule scoping 'woodpecker' to only the apply script =="
# Confirmed via a real pipeline run's clone logs: the local backend
# clones into $LOCAL_TEMP_DIR/<random>/workspace/, not
# $LOCAL_TEMP_DIR/<random>/ directly -- the extra /workspace/ segment
# is required here, not a guess.
cat > "$SUDOERS_FILE" <<EOF
woodpecker ALL=(root) NOPASSWD: $LOCAL_TEMP_DIR/*/workspace/edge/scripts/apply.sh
EOF
chmod 440 "$SUDOERS_FILE"
visudo -c

echo "== Enable and start the agent =="
systemctl daemon-reload
systemctl enable --now woodpecker-agent

sleep 2
systemctl status woodpecker-agent --no-pager -l
