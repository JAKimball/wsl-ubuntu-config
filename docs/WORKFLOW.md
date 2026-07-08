# WSL Ubuntu Configuration Repository Workflow

## Repository Structure Overview

This setup maintains two repositories with shared history to enable public contribution while keeping private configurations separate.

### Repository Roles

**`wsl-ubuntu-config` (Public)**

- Clean, shareable dotfiles and configurations
- Generic aliases and utility functions
- Documentation and setup instructions
- Community contributions welcome

**`wsl-ubuntu-config-private` (Private)**

- Complete personal setup including private configurations
- Personal aliases marked with `(JAK)` or similar
- Machine-specific settings and credentials
- Private API keys and sensitive data

---

## Initial Setup

### 1. Create Public Repository First

```bash
# Create public repo on GitHub: wsl-ubuntu-config
cd ~/projects/systems/
git clone git@github.com:yourusername/wsl-ubuntu-config.git
cd wsl-ubuntu-config

# Add initial shareable configs
# Commit and push to establish shared history
git add .
git commit -m "Initial public dotfiles"
git push origin main
```

### 2. Create Private Repository with Shared History

```bash
# Create private repo on GitHub: wsl-ubuntu-config-private
# DO NOT initialize with README/gitignore

# Clone public repo as foundation for private
cd ~/projects/systems/
git clone git@github.com:yourusername/wsl-ubuntu-config.git wsl-ubuntu-config-private
cd wsl-ubuntu-config-private

# Reconfigure remotes
git remote rename origin upstream
git remote add origin git@github.com:yourusername/wsl-ubuntu-config-private.git

# Push shared history to private repo and set main to track origin/main
git push -u origin main

# Add private customizations
# Commit and push private changes
git add .
git commit -m "Add private customizations"
git push origin main
```

### 3. Verify Remote Configuration

**In private repo:**

```bash
git remote -v
# origin    git@github.com:yourusername/wsl-ubuntu-config-private.git (private)
# upstream  git@github.com:yourusername/wsl-ubuntu-config.git (public)
```

---

## Daily Workflow

### Working in Private Repository

Your day-to-day work happens in the private repository:

```bash
cd ~/projects/systems/wsl-ubuntu-config-private/

# Pull updates from public upstream
git fetch upstream
git rebase upstream/main

# Make your changes (public and private)
# Commit and push to private repo
git add .
git commit -m "Update configurations"
git push origin main
```

### Contributing Back to Public Repository

Use feature branches for public contributions, but branch from `upstream/main` for work that is intended to merge back cleanly:

```bash
# In private repo, start from public main
cd ~/projects/systems/wsl-ubuntu-config-private/
git fetch upstream
git switch -c feature/new-utility upstream/main

# Make changes to PUBLIC-APPROPRIATE files only
# Examples: generic aliases, utility functions, documentation

# Push feature branch to public upstream
git push upstream feature/new-utility

# Create Pull Request on GitHub: feature/new-utility → main
```

### After PR Merges

```bash
# Sync merged changes back to private repo
git fetch upstream
git checkout main
git rebase upstream/main  # Clean due to pull.rebase = true
git push origin main
```

---

## File Organization Guidelines

### Public Repository Contents

**Include:**

- Generic bash aliases (`ll`, `la`, `curltime`)
- Utility functions (`get-path`, `srihash`, `embiggen`)
- Terminal enhancements (tab colors, prompt functions)
- Basic dotfiles (`.bashrc`, `.vimrc`, `.gitconfig.template`)
- Documentation and setup instructions

**Template approach for sensitive configs:**

```
.gitconfig.template     # Generic version with placeholders
.bashrc.template        # Template with common settings
setup.sh               # Installation script
```

### Private Repository Contents

**Additional private files:**

- Personal aliases marked `(JAK)` or similar
- Machine-specific paths and settings
- Actual `.gitconfig` with real email/signing key
- Credential helpers and API keys
- Company/client-specific configurations

---

## Branch Protection Setup

Configure branch protection on public repository:

1. **GitHub Settings** → **Branches** → **Add rule** for `main`
2. Enable:
   - ✅ Require pull request reviews
   - ✅ Dismiss stale reviews when new commits are pushed
   - ✅ Require status checks to pass before merging
   - ✅ Include administrators (prevents direct pushes)

---

## Git Configuration Benefits

Your existing git config enhances this workflow:

```ini
[pull]
    rebase = true                 # Clean linear history
[push]
    autoSetupRemote = true        # Auto-setup tracking branches
[remote]
    pushDefault = origin          # Plain `git push` defaults to the private remote
[fetch]
    prune = true                  # Clean remote refs
```

These settings ensure:

- Clean rebasing when pulling from upstream
- Automatic remote tracking for feature branches
- Private `origin` remains the default push target in split public/private clones
- Pruned remote references

---

## Git Hooks and Executable Bit

- Git tracks and preserves only the executable bit on files (100755 vs 100644). Other permission bits aren’t versioned.
- If you see: "The '.githooks/\<hook>' hook was ignored because it's not set as executable", make the hook executable and commit the change.

Recommended setup:

```bash
# Tell Git to use the repo's hooks directory
git config core.hooksPath .githooks

# Mark hooks executable (Linux/WSL)
chmod +x .githooks/pre-*

# Commit the mode changes so the exec bit is preserved
git add .githooks/pre-*
git commit -m "chore: make hooks executable"

# On Windows (if core.filemode=false), set the bit via index:
git update-index --chmod=+x .githooks/pre-commit
git update-index --chmod=+x .githooks/pre-push
```

Notes

- The exec bit is stored in Git even if the underlying filesystem doesn’t support it; Windows may require update-index as shown.
- The pre-commit hook can block commits on `main` when `origin` still points at the public repo.

---

## For Other Users

### Using the Public Repository

```bash
# Fork the original public repository to your own GitHub account first.
# Then clone your fork.
git clone git@github.com:yourusername/wsl-ubuntu-config.git
cd wsl-ubuntu-config

# Apply repo-local Git settings
./scripts/setup.sh
```

### Creating Your Own Private Fork

Follow the same pattern:

1. Create an empty private repository.
2. Clone your own public fork and enter it.
3. Run `./scripts/bootstrap-private-fork.sh git@github.com:yourusername/wsl-ubuntu-config-private.git`.
4. Verify remotes with `git remote -v`.
5. Confirm `origin` points at your private repo and `upstream` points at your public fork (`yourusername/wsl-ubuntu-config`, not the original repo).
6. Add your private customizations.

Note: In the resulting private clone, `upstream` points to your own public fork (`yourusername/wsl-ubuntu-config`), not the original repository, so it remains a writable target for contribution branches.

### Contributing Back

1. Create feature branch in your private repo
2. Make changes to public-appropriate files only
3. Push feature branch to your public fork: `git push upstream <branch-name>`
4. Create Pull Request from your fork to the original public repository

---

### Publish selected files “as-is” to upstream

Goal: send specific public-safe files from your private repo to the public upstream without editing them and without merging private history.

```bash
# Start clean from public main
git fetch upstream
git switch -c feature/publish-safe upstream/main

# Bring specific paths exactly as they are on your private main
# (Git 2.23+)
git restore -s main -- path/to/file1 path/to/dir2
# Older Git:
# git checkout main -- path/to/file1 path/to/dir2

# Stage and commit only those paths
git add path/to/file1 path/to/dir2
git commit -m "feat: publish selected files from private (no private data)"

# Push branch to public upstream and open PR
git push upstream feature/publish-safe
```

Notes

- If a path is identical to upstream, there will be nothing to commit (no diff).
- Prefer this file-based flow when the same public-safe changes already exist on your private `main`. It avoids cherry-picking commits and publishes the file state directly, which can make later syncing simpler.
- If you start the public branch from `upstream/main` and do the public-safe work there first, any GitHub merge strategy can work. If the same change already exists as a different commit on private `main`, squash merge makes the later sync more conflict-prone because Git only sees two unrelated commits with similar content.
- Only cherry-pick onto a branch from `upstream/main` when the commit does not also need to remain on private `main`, or when you are prepared to drop or rebuild the private-side copy after the PR merges.
- If you do cherry-pick an existing public-safe commit, treat `upstream/main` as the canonical copy after merge and sync private by rebasing onto `upstream/main`. If the same change also exists as an older private commit, drop that duplicate commit during an interactive rebase of your private `main` (this rewrites history and may require a force-push to `origin/main`; avoid doing this on branches other people depend on).
- To move existing public-safe commits instead, cherry-pick them onto a branch from upstream/main:

  ```bash
  git switch -c feature/publish-safe upstream/main
  git cherry-pick <sha1> [<sha2>...]
  ```

- A safer default is: commit private-only work on private `main`; commit public-intended work on a branch created from `upstream/main`.

---

## Maintenance Checklist

### Weekly

- [ ] Pull latest changes from public upstream
- [ ] Review private customizations for anything suitable for public contribution

### Before Contributing

- [ ] Ensure feature branch contains only public-appropriate changes
- [ ] Remove personal information, credentials, or machine-specific paths
- [ ] Test functionality in clean environment
- [ ] Update documentation if needed

### After Major Changes

- [ ] Update this workflow documentation
- [ ] Review file organization guidelines
- [ ] Consider if new templates are needed for sensitive configs

---

## Security Notes

- Never commit credentials, API keys, or personal information to public repo
- Use templates with placeholders for sensitive configuration files
- Review diffs carefully before pushing to public branches
- Consider using environment variables for sensitive values
- Regularly audit what's in public vs private repositories

---

## Benefits of This Approach

- **Clean public contributions** while maintaining private customizations
- **Shared history** makes merging straightforward
- **Community engagement** through public repository
- **Personal backup** through private repository
- **Scalable pattern** others can adopt for their own dotfiles

## Appendix: Using chezmoi vs GNU stow

Same

- Public/private split with shared history and upstream=public in the private repo.
- Public contains safe defaults/templates; private contains real values.

Chezmoi layout (examples)

```
wsl-ubuntu-config/
├─ dot_bashrc.tmpl
├─ dot_gitconfig.tmpl
├─ templates/
│  └─ user.tmpl
├─ .chezmoi.toml.tmpl
└─ .chezmoiignore
wsl-ubuntu-config-private/
├─ dot_gitconfig
├─ private/age/keys.txt      # if using age/sops
└─ .chezmoi.toml
```

Stow layout (examples)

```
wsl-ubuntu-config/
├─ core/.editorconfig
├─ shell/.bashrc
├─ git/.gitconfig.template
└─ scripts/setup.sh
wsl-ubuntu-config-private/
├─ git-private/.gitconfig
└─ private/.ssh/config
```

Bootstrap

- Chezmoi:

  ```bash
  chezmoi init git@github.com:yourusername/wsl-ubuntu-config-private.git
  chezmoi apply
  ```

- Stow:

  ```bash
  stow -d ~/dots/public  -t ~ core shell git scripts
  stow -d ~/dots/private -t ~ private git-private
  ```

Trade-offs

- Chezmoi: templating, per-host data, encryption; safer for public templates.
- Stow: simple, fast symlinks; best when everything can be public or split manually without templates.
