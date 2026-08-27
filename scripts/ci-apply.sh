#!/usr/bin/env bash
# Deploys the latest merged homelab-infra + homelab-edge state.
#
# Intended to be invoked ONLY via the restricted `woodpecker_ci_apply` SSH
# key's forced command in ~/.ssh/authorized_keys — never interactively, and
# never against the interactively-managed clones under
# ~/git/github.com/jakestanley/, which may have uncommitted personal work.
#
# Uses its own dedicated checkout directory that only this script touches,
# so `git reset --hard` here can never discard anyone's in-progress changes.
set -euo pipefail

DEPLOY_ROOT="${HOMELAB_CI_DEPLOY_ROOT:-$HOME/.homelab-ci-deploy}"
INFRA_DIR="$DEPLOY_ROOT/homelab-infra"
EDGE_DIR="$DEPLOY_ROOT/homelab-edge"

mkdir -p "$DEPLOY_ROOT"

sync_repo() {
  local dir="$1" url="$2"
  if [[ ! -d "$dir/.git" ]]; then
    git clone --quiet "$url" "$dir"
  fi
  git -C "$dir" fetch --quiet origin main
  git -C "$dir" reset --hard --quiet origin/main
  git -C "$dir" clean -fdx --quiet
}

echo "== Sync homelab-infra =="
sync_repo "$INFRA_DIR" "git@github.com:jakestanley/homelab-infra.git"

echo "== Sync homelab-edge =="
sync_repo "$EDGE_DIR" "git@github.com:jakestanley/homelab-edge.git"

echo "== Apply =="
exec sudo "$EDGE_DIR/scripts/apply.sh" --registry "$INFRA_DIR/registry.yaml"
