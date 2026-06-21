#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

include_path="../scripts/.gitconfig.local"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
	echo "Error: scripts/setup.sh must be run from within this repository." >&2
	exit 1
fi

if ! git config --local --get-all include.path | grep -Fxq "$include_path"; then
	git config --local --add include.path "$include_path"
fi

# In private clones, retarget local main to origin/main after the private origin exists.
if git show-ref --verify --quiet refs/heads/main \
	&& git remote get-url origin >/dev/null 2>&1 \
	&& git show-ref --verify --quiet refs/remotes/origin/main \
	&& git remote get-url upstream >/dev/null 2>&1; then
	git branch --set-upstream-to=origin/main main >/dev/null
fi

echo "Configured repo-local Git settings from scripts/.gitconfig.local."
echo "WSL Ubuntu setup placeholder. Installs will be added after tool decision (chezmoi/Dotbot)."
