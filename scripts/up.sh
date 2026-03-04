#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

echo "START woodpecker compose up"

run_privileged() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi

  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  echo "This action requires root privileges, but sudo was not found." >&2
  exit 1
}

ensure_tailscale_installed() {
  if command -v tailscale >/dev/null 2>&1 && command -v tailscaled >/dev/null 2>&1; then
    return
  fi

  if ! command -v curl >/dev/null 2>&1; then
    echo "curl is required to install Tailscale automatically." >&2
    exit 1
  fi

  echo "Installing Tailscale on the host"
  run_privileged sh -c 'curl -fsSL https://tailscale.com/install.sh | sh'
}

ensure_tailscaled_running() {
  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl was not found; ensure tailscaled is running before using Tailscale Funnel." >&2
    return
  fi

  if ! systemctl is-enabled --quiet tailscaled 2>/dev/null; then
    run_privileged systemctl enable tailscaled
  fi

  if ! systemctl is-active --quiet tailscaled 2>/dev/null; then
    run_privileged systemctl start tailscaled
  fi
}

ensure_tailscale_connected() {
  if tailscale status --json >/dev/null 2>&1 && tailscale ip -4 >/dev/null 2>&1; then
    return
  fi

  cat >&2 <<'EOF'
Tailscale is installed but this host is not connected to your tailnet yet.
Run the following once, complete the browser auth, and then rerun ./scripts/up.sh:

  sudo tailscale up
EOF
  exit 1
}

ensure_tailscale_funnel() {
  local port=$1

  echo "Ensuring Tailscale Funnel is serving port ${port}"
  run_privileged tailscale funnel --bg "${port}"
}

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but was not found in PATH" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Missing .env. Copy .env.example to .env and fill in the required values." >&2
  exit 1
fi

set -a
. ./.env
set +a

WOODPECKER_PORT=${WOODPECKER_PORT:-20034}

ensure_tailscale_installed
ensure_tailscaled_running
ensure_tailscale_connected

docker compose up -d
status=$?

if [ "$status" -eq 0 ]; then
  ensure_tailscale_funnel "$WOODPECKER_PORT"
fi

echo "END woodpecker compose up"
echo "woodpecker available at ${WOODPECKER_HOST:-http://ci.stanley.arpa}"

exit "$status"
