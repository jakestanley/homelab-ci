#!/usr/bin/env bash
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)

cd "$REPO_ROOT"

echo "START woodpecker add repo"

if ! command -v curl >/dev/null 2>&1; then
  echo "curl is required but was not found in PATH" >&2
  exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required but was not found in PATH" >&2
  exit 1
fi

if [ ! -f .env ]; then
  echo "Missing .env. Copy .env.example to .env and fill in the required values." >&2
  exit 1
fi

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 owner/repo" >&2
  exit 1
fi

set -a
. ./.env
set +a

: "${WOODPECKER_HOST:?Missing WOODPECKER_HOST in .env}"
: "${WOODPECKER_TOKEN:?Missing WOODPECKER_TOKEN in .env}"

REPO_FULL_NAME=$1
API_BASE="${WOODPECKER_HOST%/}/api"

user_repos_json="$(
  curl -fsS \
    -H "Authorization: Bearer $WOODPECKER_TOKEN" \
    "$API_BASE/user/repos?all=true"
)"

if ! repo_state="$(
  REPO_FULL_NAME="$REPO_FULL_NAME" USER_REPOS_JSON="$user_repos_json" python3 <<'PY'
import json
import os
import sys

target = os.environ["REPO_FULL_NAME"]
repos = json.loads(os.environ["USER_REPOS_JSON"])
for repo in repos:
    if repo.get("full_name") == target:
        active = "1" if repo.get("active") else "0"
        forge_remote_id = repo.get("forge_remote_id", "")
        repo_id = str(repo.get("id", ""))
        print(f"{active}\t{forge_remote_id}\t{repo_id}")
        break
else:
    sys.exit(2)
PY
)"; then
  echo "Repository $REPO_FULL_NAME was not found in the repositories visible to this Woodpecker user." >&2
  exit 1
fi

if [ -z "$repo_state" ]; then
  echo "Failed to resolve repository metadata for $REPO_FULL_NAME" >&2
  exit 1
fi

IFS=$'\t' read -r repo_active forge_remote_id repo_id <<EOF
$repo_state
EOF

if [ -z "$forge_remote_id" ]; then
  echo "Repository $REPO_FULL_NAME is visible, but no forge_remote_id was returned." >&2
  exit 1
fi

if [ "$repo_active" = "1" ]; then
  echo "Repository $REPO_FULL_NAME is already active in Woodpecker (id: $repo_id)."
  echo "END woodpecker add repo"
  exit 0
fi

activation_response="$(
  FORGE_REMOTE_ID="$forge_remote_id" API_BASE="$API_BASE" WOODPECKER_TOKEN="$WOODPECKER_TOKEN" python3 <<'PY'
import os
import subprocess
import sys
from urllib.parse import urlencode

query = urlencode({"forge_remote_id": os.environ["FORGE_REMOTE_ID"]})
url = f'{os.environ["API_BASE"]}/repos?{query}'
result = subprocess.run(
    [
        "curl",
        "-fsS",
        "-X",
        "POST",
        "-H",
        f'Authorization: Bearer {os.environ["WOODPECKER_TOKEN"]}',
        url,
    ],
    check=False,
    capture_output=True,
    text=True,
)
if result.returncode != 0:
    sys.stderr.write(result.stderr)
    sys.exit(result.returncode)
sys.stdout.write(result.stdout)
PY
)"

activated_summary="$(
  ACTIVATION_RESPONSE="$activation_response" python3 <<'PY'
import json
import os

repo = json.loads(os.environ["ACTIVATION_RESPONSE"])
print(f'{repo.get("full_name", "unknown")} {repo.get("id", "unknown")}')
PY
)"

activated_name=${activated_summary% *}
activated_id=${activated_summary##* }

echo "Activated repository $activated_name (id: $activated_id)."
echo "END woodpecker add repo"
