# Plan: WSL Ubuntu + Windows Host Config (Public/Private Repos)

This plan guides initial repo creation today, minimal scaffolding, and migration from `my-windows-scripts`, while keeping options open for chezmoi/Dotbot.

---

## Objectives

- Stand up four repos with shared history pattern:
  - wsl-ubuntu-config (public) / wsl-ubuntu-config-private (private)
  - wsl-windows-host-config (public) / wsl-windows-host-config-private (private)
- Seed minimal, useful structure and docs for immediate iteration.
- Start migration of Windows PowerShell content from `my-windows-scripts`.
- Keep secrets private via templates and private repos.
- Use clean Git history with pull.rebase = true.

## Repositories

- wsl-ubuntu-config                 # WSL guest (public)
- wsl-ubuntu-config-private         # WSL guest (private)
- wsl-windows-host-config           # Windows host (public)
- wsl-windows-host-config-private   # Windows host (private)
- my-windows-scripts                # Source of Windows scripts (private)

---

## Day 0: Create Repos and First Commits

### 0. Preconditions

- Ensure global Git config is set (pull.rebase = true, push.autoSetupRemote = true).
- SSH auth to GitHub ready.
- Working directory example: `~/projects/systems`
- Decide hooks dir and enable it:
  - Set repo hooks path: `git config core.hooksPath .githooks`
  - Ensure hooks are executable and committed:
    - Linux/WSL: `chmod +x .githooks/pre-commit .githooks/pre-push && git add -A && git commit -m "chore: make hooks executable"`
    - Windows (if core.filemode=false): `git update-index --chmod=+x .githooks/pre-commit && git update-index --chmod=+x .githooks/pre-push && git commit -m "chore: make hooks executable"`

### 1. Create Public Repositories (empty on GitHub, then clone)

```bash
mkdir -p ~/projects/systems && cd ~/projects/systems

# WSL guest (public)
git clone git@github.com:yourusername/wsl-ubuntu-config.git
cd wsl-ubuntu-config
# Minimal scaffold
mkdir -p docs templates scripts
cat > README.md << 'EOF'
# wsl-ubuntu-config
Public WSL Ubuntu dotfiles and setup. Private credentials/config live in the -private repo.
EOF
cat > docs/WORKFLOW.md << 'EOF'
See workspace doc for shared-history flow. Use feature branches and PRs for public contributions.
EOF
cat > templates/.gitconfig.template << 'EOF'
# Template: fill in user.email, signing key, and any private settings in -private repo
[user]
    name = YOUR NAME
    email = YOUR EMAIL
EOF
cat > scripts/setup.sh << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "WSL Ubuntu setup placeholder. Installs will be added after tool decision (chezmoi/Dotbot)."
EOF
chmod +x scripts/setup.sh
git add .
git commit -m "chore: initial public scaffold (WSL Ubuntu)"
git push origin main
cd ..
````

```powershell
# Windows host (public) — PowerShell-safe here-strings and directory creation
git clone git@github.com:yourusername/wsl-windows-host-config.git
Set-Location wsl-windows-host-config

# Create directories
New-Item -ItemType Directory -Path docs,scripts,profiles,modules -Force | Out-Null

# Files
Set-Content -Path README.md -Encoding UTF8 -NoNewline -Value @'
# wsl-windows-host-config
Public Windows host configuration (PowerShell profiles, utilities). Private customizations live in -private repo.
'@

Set-Content -Path docs/CLAUDE.md -Encoding UTF8 -NoNewline -Value @'
High-level coding guide for this repository. Reference the original in my-windows-scripts for deeper context.
'@

Set-Content -Path scripts/Setup-WindowsHost.ps1 -Encoding UTF8 -NoNewline -Value @'
Set-StrictMode -Version Latest
Write-Host "Windows host setup placeholder. Will integrate profile system and package installs post-tool decision."
'@

git add .
git commit -m "chore: initial public scaffold (Windows host)"
git push origin main
Set-Location ..
```

### 2. Create Private Repositories With Shared History

```bash
# Create -private repos on GitHub (empty; no README)

# WSL guest -private from public shared history
git clone git@github.com:yourusername/wsl-ubuntu-config.git wsl-ubuntu-config-private
cd wsl-ubuntu-config-private
git remote rename origin upstream
git remote add origin git@github.com:yourusername/wsl-ubuntu-config-private.git
git push origin main
# Private-only placeholders
mkdir -p private
cat > private/.gitconfig << 'EOF'
# Real user/signing config goes here. Do not commit to public.
[user]
    name = Jonathan A. Kimball
    email = 14268609+JAKimball@users.noreply.github.com
    signingkey = DF1CB4D8A1236B66
EOF
git add private/.gitconfig
git commit -m "chore: add private .gitconfig (kept private only)"
git push origin main
cd ..
```

```powershell
# Windows host -private from public shared history — PowerShell-safe
git clone git@github.com:yourusername/wsl-windows-host-config.git wsl-windows-host-config-private
Set-Location wsl-windows-host-config-private
git remote rename origin upstream
git remote add origin git@github.com:yourusername/wsl-windows-host-config-private.git
git push origin main

# Private-only placeholders
New-Item -ItemType Directory -Path private -Force | Out-Null
Set-Content -Path private/Private-Settings.ps1 -Encoding UTF8 -NoNewline -Value @'
# Place machine-specific paths, credentials, and private aliases here
'@

git add private/Private-Settings.ps1
git commit -m "chore: add private settings placeholder (kept private only)"
git push origin main
Set-Location ..
```

### 3. Branch Protection (public repos)

- GitHub Settings → Branches → Add rule for main:
  - Require PR reviews, dismiss stale reviews
  - Require status checks
  - Include administrators

---

## Initial Structure (Minimal, Expand Later)

### wsl-ubuntu-config (public)

- README.md
- docs/WORKFLOW.md
- templates/.gitconfig.template
- scripts/setup.sh
- Optional later: docs/tooling/ (decision, usage), .editorconfig, .gitattributes, .gitignore

### wsl-ubuntu-config-private

- private/.gitconfig (real)
- Optional: encrypted files (when tool chosen), machine-specific scripts

### wsl-windows-host-config (public)

- README.md
- docs/CLAUDE.md (short, link back)
- scripts/Setup-WindowsHost.ps1
- profiles/ (to be populated)
- modules/ (to be populated)

### wsl-windows-host-config-private

- private/Private-Settings.ps1
- Private-only profiles/modules, credentials

---

## Migration Plan from my-windows-scripts

1. Inventory
   - Tag each file: Public vs Private, Stable vs Experimental
   - Key buckets:
     - profiles/: PowerShell profile chain and logging framework
     - scripts/: WSL, updates, utilities (Compact-WSL.ps1, Get-Updates.ps1, etc.)
     - modules/: reusable code
     - docs/: carry over CLAUDE.md and refine per repo

2. Mapping
   - Public:
     - Generic utilities, safe defaults, documentation
     - Profile system skeleton without personal aliases/paths
   - Private:
     - Personal aliases (JAK), machine-specific paths, credentials, org-specific logic
   - Destination:
     - Windows host content → wsl-windows-host-config / -private
     - Any WSL guest-side setup scripts → wsl-ubuntu-config / -private

3. Transformations
   - Rename and standardize directories: profiles/, modules/, scripts/, docs/
   - Split interactive vs non-interactive logic consistently
   - Keep commit granularity small (per script or per feature)

4. Execution (short loop)
   - Start with low-risk public scripts (utilities with no secrets)
   - Publish selected files “as-is” from private to public:
     ```bash
     git fetch upstream
     git switch -c feature/publish-safe upstream/main
     git restore -s main -- path/one path/two
     git add path/one path/two
     git commit -m "feat: publish selected files from private"
     git push upstream feature/publish-safe
     ```
   - Or cherry-pick existing public-only commits onto upstream/main:
     ```bash
     git switch -c feature/publish-safe upstream/main
     git cherry-pick <sha1> [<sha2>...]
     ```
   - Port profile system scaffolding public-first; wire private bits in -private
   - Move CLAUDE.md content into docs/ with repository-specific adjustments

---

## Tooling Decision: chezmoi vs Dotbot

- Defer final decision; today’s scaffolding remains tool-agnostic.
- Recommendation: prefer chezmoi for cross-OS templating, secrets integration, and Windows support.
- When choosing chezmoi:
  - Add: .chezmoi.toml.tmpl, .chezmoiignore, templates with placeholders
  - Use age/sops or 1Password for secrets; keep templates public, real values private
- When choosing Dotbot:
  - Add: install.conf.yaml, scripts to symlink/copy templates
  - Keep secrets only in -private repos

---

## Repo Organization: chezmoi vs GNU stow (WSL Ubuntu)

Same (either tool)

- Keep two repos with shared history: public templates/configs vs private real values.
- Public stays template-friendly; no secrets. Private overlays real config.
- Same contribution flow and branch protections.

Different (structure, secrets, bootstrap)

- Chezmoi (templating + encryption; files are materialized to $HOME)
  - Public (wsl-ubuntu-config):
    - dot_bashrc.tmpl, dot_gitconfig.tmpl
    - templates/ (partials, data)
    - run_once_setup.sh.tmpl (optional bootstrap)
    - .chezmoi.toml.tmpl, .chezmoiignore
  - Private (wsl-ubuntu-config-private):
    - dot_gitconfig (real), private/age/ keys (if using age/sops)
    - .chezmoi.toml (real), extra data files
  - Bootstrap:

    ```bash
    chezmoi init git@github.com:yourusername/wsl-ubuntu-config-private.git
    # (private has upstream=public shared history)
    chezmoi apply
    ```

- GNU stow (symlink manager; no templating/encryption)
  - Public (wsl-ubuntu-config):
    - packages by area: core/, shell/, git/, scripts/
    - Example: shell/.bashrc, git/.gitconfig.template
  - Private (wsl-ubuntu-config-private):
    - packages holding secrets/real files: private/, git-private/
    - Example: git-private/.gitconfig (real), private/.ssh/config
  - Bootstrap:

    ```bash
    git clone git@github.com:yourusername/wsl-ubuntu-config.git ~/dots/public
    git clone git@github.com:yourusername/wsl-ubuntu-config-private.git ~/dots/private
    stow -d ~/dots/public  -t ~ core shell git scripts
    stow -d ~/dots/private -t ~ private git-private
    ```

Notes

- Chezmoi: prefer templates (*.tmpl) in public; real values in private; use age/sops for encryption.
- Stow: symlinks into $HOME; ensure target files don’t pre-exist; no secrets in public because no templating.
- Chezmoi materializes files (can also manage symlinks if desired); Stow always symlinks.

---

## Git Workflow Notes

- Use pull.rebase = true for linear history
- Private repos: upstream = public, origin = private
- Contributions flow:
  - Make public-safe changes in feature branches locally
  - Push feature branches to upstream (public) or fork, open PR
  - After merge, sync private via: fetch upstream, rebase, push origin

Reference doc: wsl-ubuntu-config-repository-workflow.md (adapt for Windows host too).

---

## Security & Secrets

- Never push credentials/API keys to public
- Use templates (.gitconfig.template, etc.) in public
- Keep real configs in -private under private/ or encrypted with chosen tool
- Review diffs before pushing public branches

---

## Timeline Checklist

Today (Initial commits)

- [x] Create public repos and push minimal scaffolds (Ubuntu guest, Windows host)
- [x] Create private repos using shared history; configure remotes; push placeholders
- [x] Enable branch protections on public repos

Next 1–2 days

- [ ] Decide tool (chezmoi preferred) and add minimal config
- [ ] Port first batch of public-safe scripts from my-windows-scripts
- [ ] Add README sections describing public/private split and contribution workflow

Next 1 week

- [ ] Migrate profile system (public scaffolding + private extensions)
- [ ] Add CI checks (shellcheck/PowerShellScriptAnalyzer) in public repos
- [ ] Document bootstrap steps (scripts/setup.sh, Setup-WindowsHost.ps1)
- [ ] Audit for anything suitable to contribute from private → public

---

## Commit Message Suggestions

- chore: initial public scaffold (WSL Ubuntu)
- chore: initial public scaffold (Windows host)
- chore: add private .gitconfig (kept private only)
- chore: add private settings placeholder (kept private only)
- docs: workflow and contribution notes
- feat: port <script-name> from my-windows-scripts (public-safe)
