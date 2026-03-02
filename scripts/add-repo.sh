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
CRON_NAME="every-15-minutes"
CRON_SCHEDULE="@every 15m"

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
        default_branch = repo.get("default_branch", "")
        print(f"{active}\t{forge_remote_id}\t{repo_id}\t{default_branch}")
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

IFS=$'\t' read -r repo_active forge_remote_id repo_id default_branch <<EOF
$repo_state
EOF

if [ -z "$forge_remote_id" ]; then
  echo "Repository $REPO_FULL_NAME is visible, but no forge_remote_id was returned." >&2
  exit 1
fi

if [ "$repo_active" = "1" ]; then
  echo "Repository $REPO_FULL_NAME is already active in Woodpecker (id: $repo_id)."
else
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
print(
    f'{repo.get("full_name", "unknown")}\t'
    f'{repo.get("id", "unknown")}\t'
    f'{repo.get("default_branch", "")}'
)
PY
  )"

  IFS=$'\t' read -r activated_name activated_id activated_default_branch <<EOF
$activated_summary
EOF
  repo_id=$activated_id
  if [ -n "$activated_default_branch" ]; then
    default_branch=$activated_default_branch
  fi

  echo "Activated repository $activated_name (id: $activated_id)."
fi

if [ -z "$repo_id" ]; then
  echo "Repository $REPO_FULL_NAME does not have a Woodpecker repository id." >&2
  exit 1
fi

if [ -z "$default_branch" ]; then
  echo "Repository $REPO_FULL_NAME does not report a default_branch in Woodpecker." >&2
  exit 1
fi

cron_list_json="$(
  curl -fsS \
    -H "Authorization: Bearer $WOODPECKER_TOKEN" \
    "$API_BASE/repos/$repo_id/cron"
)"

cron_state="$(
  CRON_LIST_JSON="$cron_list_json" CRON_NAME="$CRON_NAME" python3 <<'PY'
import json
import os

target = os.environ["CRON_NAME"]
payload = json.loads(os.environ["CRON_LIST_JSON"])
if payload is None:
    payload = []
elif not isinstance(payload, list):
    raise SystemExit("Unexpected cron payload shape from Woodpecker API")

for cron in payload:
    if cron.get("name") == target:
        enabled = "1" if cron.get("enabled") else "0"
        cron_id = str(cron.get("id", ""))
        branch = cron.get("branch", "")
        schedule = cron.get("schedule", "")
        print(f"{cron_id}\t{enabled}\t{branch}\t{schedule}")
        break
PY
)"

desired_cron_payload="$(
  CRON_NAME="$CRON_NAME" CRON_SCHEDULE="$CRON_SCHEDULE" DEFAULT_BRANCH="$default_branch" python3 <<'PY'
import json
import os

payload = {
    "name": os.environ["CRON_NAME"],
    "branch": os.environ["DEFAULT_BRANCH"],
    "schedule": os.environ["CRON_SCHEDULE"],
    "enabled": True,
    "variables": {},
}
print(json.dumps(payload))
PY
)"

if [ -z "$cron_state" ]; then
  curl -fsS \
    -X POST \
    -H "Authorization: Bearer $WOODPECKER_TOKEN" \
    -H "Content-Type: application/json" \
    -d "$desired_cron_payload" \
    "$API_BASE/repos/$repo_id/cron" >/dev/null
  echo "Created cron $CRON_NAME for $REPO_FULL_NAME on branch $default_branch with schedule $CRON_SCHEDULE."
else
  IFS=$'\t' read -r cron_id cron_enabled cron_branch cron_schedule <<EOF
$cron_state
EOF

  if [ "$cron_enabled" = "1" ] && [ "$cron_branch" = "$default_branch" ] && [ "$cron_schedule" = "$CRON_SCHEDULE" ]; then
    echo "Cron $CRON_NAME already matches branch $default_branch and schedule $CRON_SCHEDULE."
  else
    curl -fsS \
      -X PATCH \
      -H "Authorization: Bearer $WOODPECKER_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$desired_cron_payload" \
      "$API_BASE/repos/$repo_id/cron/$cron_id" >/dev/null
    echo "Updated cron $CRON_NAME for $REPO_FULL_NAME to branch $default_branch and schedule $CRON_SCHEDULE."
  fi
fi

echo "END woodpecker add repo"
