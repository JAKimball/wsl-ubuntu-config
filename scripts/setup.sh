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

if ! command -v stow >/dev/null 2>&1; then
	echo "GNU Stow not found; skipping dotfile symlink step."
	echo "Install stow and rerun scripts/setup.sh to link packages into \$HOME."
	exit 0
fi

stow_packages=()
for package in core shell git; do
	if [[ -d "$repo_root/$package" ]]; then
		stow_packages+=("$package")
	fi
done

if [[ ${#stow_packages[@]} -eq 0 ]]; then
	echo "No Stow packages found under $repo_root."
	exit 0
fi

stow --restow --dir "$repo_root" --target "$HOME" "${stow_packages[@]}"
echo "Stowed packages to $HOME: ${stow_packages[*]}"
