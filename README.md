# wsl-ubuntu-config

Public WSL Ubuntu dotfiles managed with GNU Stow. Private credentials/config live in the `-private` repo.

## Layout

Stow package directories live at repository root:

- `git/` for public-safe git templates and defaults
- `core/` for shared core dotfiles
- `shell/` for shell dotfiles

Current files:

- `git/.gitconfig.template`

## Apply Dotfiles

Run setup from this repository:

```bash
./scripts/setup.sh
```

`scripts/setup.sh` applies repo-local git settings and runs Stow against all package directories that exist.

Manual Stow command (equivalent):

```bash
stow --dir "$PWD" --target "$HOME" core shell git
```
