#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: scripts/bootstrap-private-fork.sh <private-origin-url>

Run this from inside a clone of the public repository after creating an empty
private repository. The script renames the current public origin remote to
upstream, adds the private repository as origin, pushes main, retargets local
main to origin/main, and applies repo-local Git settings.
EOF
}

if [[ $# -ne 1 ]]; then
  usage
  exit 1
fi

private_origin_url="$1"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: scripts/bootstrap-private-fork.sh must be run from within this repository." >&2
  exit 1
fi

if git remote get-url upstream >/dev/null 2>&1; then
  public_origin_url="$(git remote get-url upstream)"
else
  public_origin_url="$(git remote get-url origin 2>/dev/null || true)"
  if [[ -z "$public_origin_url" ]]; then
    echo "Error: expected origin to point at the public repository before bootstrap." >&2
    exit 1
  fi
  git remote rename origin upstream
fi

if git remote get-url origin >/dev/null 2>&1; then
  current_origin_url="$(git remote get-url origin)"
  if [[ "$current_origin_url" != "$private_origin_url" ]]; then
    git remote set-url origin "$private_origin_url"
  fi
else
  git remote add origin "$private_origin_url"
fi

git push -u origin main
"$repo_root/scripts/setup.sh"

cat <<EOF
Private fork bootstrap complete.
origin:   $(git remote get-url origin)
upstream: $(git remote get-url upstream)
public:   $public_origin_url
EOF