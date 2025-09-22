#!/usr/bin/env bash
set -euo pipefail

# Set up git hooks and config specific to this repo
# The path is considered to be relative to the configuration file in which the include directive was found
git config --local include.path ../scripts/.gitconfig.local

echo "WSL Ubuntu setup placeholder. Installs will be added after tool decision (chezmoi/Dotbot)."
