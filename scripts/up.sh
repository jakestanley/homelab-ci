#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

echo "START woodpecker compose up"

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is required but was not found in PATH" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Missing .env. Copy .env.example to .env and fill in the required values." >&2
  exit 1
fi

docker compose up -d
status=$?

echo "END woodpecker compose up"
echo "woodpecker available at ${WOODPECKER_HOST:-http://ci.stanley.arpa}"

exit "$status"
