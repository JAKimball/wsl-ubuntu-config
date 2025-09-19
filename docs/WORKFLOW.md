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

# Push shared history to private repo
git push origin main

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
git pull upstream main

# Make your changes (public and private)
# Commit and push to private repo
git add .
git commit -m "Update configurations"
git push origin main
```

### Contributing Back to Public Repository

Use feature branches for public contributions:

```bash
# In private repo, create feature branch
cd ~/projects/systems/wsl-ubuntu-config-private/
git checkout -b feature/new-utility

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
[fetch]
    prune = true                  # Clean remote refs
```

These settings ensure:

- Clean rebasing when pulling from upstream
- Automatic remote tracking for feature branches
- Pruned remote references

---

## For Other Users

### Using the Public Repository

```bash
# Clone the public repository
git clone git@github.com:yourusername/wsl-ubuntu-config.git
cd wsl-ubuntu-config

# Review and customize template files
cp .gitconfig.template .gitconfig
# Edit .gitconfig with your details

# Run setup script (if provided)
./setup.sh
```

### Creating Your Own Private Fork

Follow the same pattern:

1. Fork the public `wsl-ubuntu-config` repository
2. Clone your fork as foundation for private repo
3. Create separate private repository with shared history
4. Configure remotes (upstream = original public, origin = your private)
5. Add your private customizations

### Contributing Back

1. Create feature branch in your private repo
2. Make changes to public-appropriate files only
3. Push feature branch to your public fork
4. Create Pull Request to original public repository

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
