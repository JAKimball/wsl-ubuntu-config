# Lessons Learned — Addendum 2

> Scratchpad for brainstorming and streamlining the public/private split-repo Git workflow.
> Extracted from a single chat session's history. To be merged with other addenda and distilled into `WORKFLOW.md` and agent instructions.

---

## Pain Points

### 1. Branch tracking defaults to the wrong remote after `git remote rename`

**What happened:** Following the bootstrap script, `git remote rename origin upstream` silently retargeted `branch.main.remote` from `origin` to `upstream`. The subsequent `git remote add origin <private>` did not retarget `main` back. Plain `git push` on `main` pushed to the public repo.

**Root cause:** `git remote rename` updates all refs that pointed at the old remote name, including branch tracking config. `git remote add` does not retarget any branches. The original bootstrap script used `git push origin main` without `-u`, so it did not change tracking either.

**Impact:** A private-only commit (`private/.gitconfig`) was pushed to the public repo.

**Current mitigation:** `scripts/setup.sh` now runs `git branch --set-upstream-to=origin/main main` when both `origin` and `upstream` remotes exist. `scripts/bootstrap-private-fork.sh` does the same. Docs updated to include this step explicitly.

**Still fragile:** If a user skips `setup.sh` or bootstraps manually, the foot-gun remains. The `pre-commit` hook guards against committing on `main` when `origin` equals `upstream`, but it cannot guard against the more subtle case where `origin` is private but `branch.main.remote` is still `upstream`.

**Ideas:**

- Add a `pre-push` hook check: if pushing `main` and `branch.main.remote != origin`, warn or block.
- Add a setup verification step that prints `branch.main.remote` and warns if it is not `origin`.
- Consider a `post-remote-add` or `post-checkout` hook (non-standard; would need a wrapper script).
- Document the `git remote rename` side effect prominently in WORKFLOW.md.

---

### 2. `git push` with no explicit remote is ambiguous in a split-remote repo

**What happened:** On a branch created from `upstream/main` (e.g., `public/updates`), plain `git push` went to `upstream` because `branch.<name>.remote = upstream`. On `main`, before the tracking fix, plain `git push` also went to `upstream`. In another case, a branch intended for upstream was pushed to `origin` because `remote.pushDefault = origin` was set and the branch had no explicit `branch.<name>.remote`.

**Root cause:** Git's push remote resolution has multiple layers (`branch.<name>.pushRemote` > `remote.pushDefault` > `branch.<name>.remote` > `push.default`). In a split-remote repo, the "default" is context-dependent and easy to get wrong.

**Impact:** Docs changes were pushed to the private repo instead of the public repo, then merged via a PR on the wrong repo. Required history rewrite to undo.

**Current mitigation:** `remote.pushDefault = origin` is set in `scripts/.gitconfig.local`, making plain `git push` default to private. The `pre-push` hook blocks pushes of `main` to `upstream`.

**Still fragile:** Public contribution branches (e.g., `public/updates`, `public/docs-sync`) are configured with `branch.<name>.remote = upstream`, which overrides `remote.pushDefault`. This is correct for those branches, but the user must be aware that plain `git push` on those branches goes to `upstream`. If a branch is created with `git switch -c <name> upstream/main`, `push.autoSetupRemote = true` sets tracking to `upstream/main`, which may or may not be what the user wants.

**Ideas:**

- Always use explicit remote in push commands: `git push upstream <branch>` or `git push origin <branch>`.
- Add a pre-push warning (not block) when the remote being pushed to does not match the user's likely intent. This is hard to determine automatically.
- Create wrapper scripts: `push-public` and `push-private` that explicitly target the correct remote.
- Document the push resolution hierarchy in WORKFLOW.md with a decision tree.
- Consider a shell prompt or pre-commit status check that shows the current branch's push target.

---

### 3. Cherry-picking from private `main` to a public branch creates duplicate history

**What happened:** Public-safe changes were committed to private `main` first. Then a public branch was created from `upstream/main` and the commit was cherry-picked onto it. The PR was squash-merged on GitHub. When syncing back to private `main`, everything conflicted because Git saw two unrelated commits with similar content.

**Root cause:** Cherry-pick creates a new commit with a different SHA but the same content. Squash merge creates yet another new commit. Git cannot recognize these as "the same change" during rebase, so it reports conflicts on every overlapping line.

**Impact:** Full conflict resolution required across all changed files. Required rebuilding private `main` from `upstream/main` and reapplying only the private-only commit.

**Current mitigation:** WORKFLOW.md and plan.md now explicitly recommend:

- Public-intended work should start on a branch from `upstream/main`, not on private `main`.
- If public-safe content already exists on private `main`, use `git restore -s main -- <paths>` to copy file contents onto a public branch, rather than cherry-picking commits.
- Cherry-pick only when the commit will not also remain on private `main`.

**Still fragile:** The docs describe the correct flow, but there is no automated guard against cherry-picking a commit that also exists on private `main` into a public branch.

**Ideas:**

- Add a pre-push hook that checks if any commit being pushed to `upstream` also exists on `origin/main` (by patch ID, not SHA). If so, warn that sync-back may conflict.
- Create a `publish-files` script that automates the `git restore -s main` flow and opens the PR.
- Document a "decision tree" for publishing: Is the change already on private `main`? → Use file restore. Is it new? → Work on a public branch from `upstream/main`.
- Consider maintaining a separate public-only clone/worktree to eliminate the mental overhead entirely.

---

### 4. Squash merge destroys commit correspondence

**What happened:** A PR was squash-merged on GitHub. The squashed commit on `upstream/main` had no ancestry relationship to the original commits on the feature branch or on private `main`.

**Root cause:** Squash merge creates a single new commit that collapses all branch commits into one. It does not preserve any commit SHAs or ancestry from the source branch.

**Impact:** Syncing private `main` onto the new `upstream/main` caused conflicts because the same content changes existed as different commits on both sides.

**Current mitigation:** WORKFLOW.md now warns that squash merge makes sync-back more conflict-prone when the same change exists on private `main`.

**Still fragile:** GitHub's default merge button is often "Squash and merge". Users may not notice which strategy is selected.

**Ideas:**

- For this workflow, prefer "Create a merge commit" or "Rebase and merge" on public PRs.
- Configure GitHub repo settings to disable squash merge on the public repo (or at least document the preference).
- If squash merge is used, treat `upstream/main` as canonical and rebuild private `main` from it, rather than trying to reconcile.
- Add a post-merge sync checklist: after PR merge, `git fetch upstream && git rebase upstream/main` and resolve by taking `upstream/main` versions of public files.

---

### 5. `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` environment variables leak across repos

**What happened:** Environment variables `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE` were set in a PowerShell session to fix timestamps in an unrelated repo. Subsequent `git commit` commands in this repo inherited those variables, producing incorrect timestamps.

**Root cause:** These environment variables override Git's default timestamp behavior globally for the current shell session. They are not scoped to a specific repo.

**Impact:** Commit history showed dates that did not match actual commit times, making the timeline confusing and harder to reason about.

**Current mitigation:** `pre-commit` hook blocks commits when `GIT_COMMITTER_DATE` is set. (It does not block `GIT_AUTHOR_DATE` because Git itself can set that variable during certain operations.)

**Still fragile:** The hook only checks `GIT_COMMITTER_DATE`, not `GIT_AUTHOR_DATE`. If a user sets only `GIT_AUTHOR_DATE`, the hook will not catch it. Also, hooks can be bypassed with `--no-verify`.

**Ideas:**

- Document the risk of setting these variables in shell profiles or session scripts.
- Consider a shell function or alias for `git commit` that unsets these variables unless explicitly requested.
- Add a `pre-commit` hook check for `GIT_AUTHOR_DATE` as well, with a warning (not block) if it is set and appears to be a manual override. This is tricky because Git may set it internally.
- Use `git commit --date=now` explicitly when you want the current time, rather than relying on environment variable absence.

---

### 6. Accidental PR on the wrong repo (origin instead of upstream)

**What happened:** A branch intended for the public repo was pushed to the private repo (`origin`) because `remote.pushDefault = origin` was set and the branch's tracking was configured to `origin`. The GitHub PR link in the push output was followed without noticing it pointed at the private repo. The PR was merged on the private repo before the mistake was noticed.

**Root cause:** Multiple factors:

1. `remote.pushDefault = origin` correctly defaults to private, but public branches need explicit `git push upstream <branch>`.
2. The branch was created with `git switch -c <name> upstream/main`, which set tracking to `upstream/main` via `push.autoSetupRemote`. But after stash pop and commit, the user ran plain `git push`, which may have used `remote.pushDefault` instead of the branch tracking, depending on Git version and config.
3. The GitHub PR link in push output says `github.com:JAKimball/wsl-ubuntu-config-private.git` for origin and `github.com:JAKimball/wsl-ubuntu-config.git` for upstream, but the user did not notice the difference.

**Impact:** Docs changes were merged into the private repo via a PR, creating a merge commit on `origin/main` that diverged from `upstream/main`. Required force-push to reset `origin/main` and re-creation of the docs changes on a clean public branch.

**Current mitigation:** No automated guard exists for this specific mistake.

**Ideas:**

- Always read the push output carefully, especially the remote URL in the "Create a pull request" line.
- Add a pre-push hook that prints a warning when pushing to `origin` on a branch whose name starts with `public/` or `feature/pub`, since those are likely intended for upstream.
- Create wrapper scripts: `publish` (pushes to upstream and opens PR) and `save` (pushes to origin).
- Use `gh pr create` with explicit `--repo` flag to avoid creating PRs on the wrong repo.
- Add a visual cue in the shell prompt showing which remote the current branch will push to.
- Document a pre-push checklist: "Which remote am I pushing to? Which repo will the PR be created on?"

---

### 7. Branch clutter from recovery operations

**What happened:** Multiple backup, rewrite, and recovery branches accumulated: `backup/main-before-resync`, `backup/origin-main`, `backup/upstream-main`, `backup/upstream-main-2026-06-20`, `backup/origin-main-doc-pr-2026-06-21`, `rewrite/origin-main`, `rewrite/upstream-main`, `template`, `hooks`, `public/updates`, `feature/pub-safe`, `public/docs-sync`, `public/stow-layout`, `docs/public`.

**Root cause:** Each recovery operation created new branches for safety, but there was no cleanup routine.

**Impact:** `git branch -vv` output became noisy and hard to parse. Risk of confusing backup branches with active branches.

**Current mitigation:** None automated.

**Ideas:**

- Create a `scripts/cleanup-branches.sh` that lists branches matching `backup/*`, `rewrite/*`, and `template`, and offers to delete them after confirmation.
- Use tags instead of branches for backups: `git tag backup/<description>` is more clearly a point-in-time marker.
- Document a cleanup cadence: after each successful sync, delete backup branches older than the last sync.
- Add a `scripts/branch-status.sh` that shows which branches are merged into `main` or `upstream/main` and can be safely deleted.

---

### 8. `git fetch origin upstream` is not `git fetch origin && git fetch upstream`

**What happened:** Running `git fetch origin upstream` produced `fatal: couldn't find remote ref upstream` because Git interpreted it as "fetch ref `upstream` from remote `origin`", not "fetch from both `origin` and `upstream`".

**Root cause:** `git fetch <remote> <refspec>` syntax. The second argument is a refspec, not a remote name.

**Impact:** Minor; the error was immediately recognizable. But it highlighted that Git CLI syntax is not always intuitive.

**Current mitigation:** None needed; this is a knowledge gap, not a workflow flaw.

**Ideas:**

- Document common fetch patterns in WORKFLOW.md.
- Consider a shell alias: `git fetch-all` = `git fetch --all` or `git fetch --multiple origin upstream`.

---

## Recovery Strategies (Reference)

### Removing an unwanted commit from public history (no collaborators)

```bash
# Save backup refs
git branch backup/upstream-main upstream/main
git tag backup/upstream-main-<date> upstream/main

# Rebuild public main without the unwanted commit
git switch --detach upstream/main
git switch -c rewrite/upstream-main
git rebase --onto <parent-of-unwanted> <unwanted>

# Verify
git log --reverse --oneline --max-count=10
git ls-tree -r --name-only HEAD | grep '^private/' || true

# Force-push
git push --force-with-lease upstream HEAD:main
```

### Rebuilding private main from cleaned public main

```bash
git switch main
git branch backup/main-before-resync
git reset --hard upstream/main
git cherry-pick <private-only-commit-sha>
git push --force-with-lease origin main
```

### Undoing an accidental PR merge on the wrong repo

```bash
# Save backup
git branch backup/origin-main-<date> origin/main

# Reset private main to the pre-merge state
git switch main
git reset --hard <pre-merge-sha>
git push --force-with-lease origin main

# Delete the mistaken remote branch
git push origin --delete <branch-name>

# Re-create the changes on a clean public branch
git switch -c public/<name> upstream/main
git restore -s <backup-branch> -- <paths>
git add <paths>
git commit -m "..."
git push -u upstream public/<name>
```

### Syncing private main after a public PR merge

```bash
git switch main
git fetch upstream
git rebase upstream/main
git push origin main
```

If conflicts arise because the same changes existed on private `main`:

- Drop the duplicate private-side commit during interactive rebase.
- Or reset private `main` to `upstream/main` and reapply only private-only commits.

---

## Proposed Automation and Safeguards

### Wrapper scripts

| Script | Purpose |
|--------|---------|
| `scripts/publish.sh <branch>` | Pushes a branch to `upstream` and creates a PR via `gh pr create --repo JAKimball/wsl-ubuntu-config`. |
| `scripts/save.sh` | Pushes current branch to `origin` (private). |
| `scripts/sync-from-upstream.sh` | Fetches `upstream`, rebases `main` onto `upstream/main`, pushes to `origin`. |
| `scripts/cleanup-branches.sh` | Lists and optionally deletes backup/rewrite/template branches. |
| `scripts/branch-status.sh` | Shows each branch's tracking remote, ahead/behind, and whether it is merged. |

### Hook enhancements

| Hook | Check | Action |
|------|-------|--------|
| `pre-commit` | `GIT_COMMITTER_DATE` set | Block (existing) |
| `pre-commit` | Committing on `main` when `origin == upstream` | Block (existing) |
| `pre-commit` | `GIT_AUTHOR_DATE` set | Warn (new; hard to distinguish from Git-internal sets) |
| `pre-push` | Pushing `main` to `upstream` | Block (existing) |
| `pre-push` | Pushing to `upstream` when commit range contains `private/` paths | Block (new; proposed) |
| `pre-push` | Pushing to `upstream` when commit range contains `scripts/.gitconfig.local` | Block (new; proposed) |
| `pre-push` | Pushing branch named `public/*` or `feature/pub*` to `origin` | Warn (new; proposed) |
| `pre-push` | Pushing to `upstream` when any commit also exists on `origin/main` by patch ID | Warn (new; proposed) |
| `pre-push` | Non-fast-forward push to `upstream` | Warn unless `ALLOW_UPSTREAM_REWRITE=1` (new; proposed) |

### Config enhancements

| Setting | Value | Purpose |
|---------|-------|---------|
| `remote.pushDefault` | `origin` | Default plain `git push` to private (existing) |
| `branch.main.remote` | `origin` | Track private main (existing, enforced by `setup.sh`) |
| `branch.main.pushRemote` | `origin` | Explicitly set push target for `main` (proposed; redundant but explicit) |
| `push.default` | `current` | Push current branch name (existing) |

### Branch naming conventions (proposed)

| Prefix | Meaning | Push target |
|--------|---------|-------------|
| `main` | Private main (public history + private-only commits) | `origin` |
| `public/*` | Public contribution branches | `upstream` |
| `feature/*` | Private feature branches | `origin` |
| `backup/*` | Point-in-time recovery refs | (not pushed) |
| `rewrite/*` | History rewrite working branches | (not pushed) |

### GitHub repo settings (proposed)

- Disable "Squash and merge" on the public repo, or at minimum document that "Create a merge commit" is preferred.
- Enable branch protection on `upstream/main` with "Include administrators".
- Consider auto-deleting head branches after merge on both repos.

---

## Key Mental Model

The single most important principle:

> **`upstream/main` is the canonical public history. Private `main` is always a superset of `upstream/main` plus private-only commits.**

If this relationship breaks (e.g., private `main` diverges with its own version of public-safe changes), recovery is painful. The way to keep it intact:

1. **Public-intended work:** Start from `upstream/main` on a `public/*` branch. Never commit it to private `main` first.
2. **Private-only work:** Commit on private `main`. It will never go upstream.
3. **After a public PR merges:** Rebase private `main` onto the new `upstream/main`. This replays private-only commits on top of the updated public history.
4. **If the same change exists on both sides:** Treat `upstream/main` as canonical. Drop the private-side duplicate. Do not try to "merge" them.

---

## Open Questions

- Should we maintain a separate public-only clone/worktree to eliminate split-remote mental overhead entirely?
- Should `setup.sh` verify and warn if `branch.main.remote != origin` after setup?
- Is it worth implementing patch-ID-based duplicate detection in `pre-push`?
- Should we use `git config --local branch.main.pushRemote origin` as an explicit redundant safeguard?
- Would a shell prompt integration (showing push target) be worth the complexity?
- Should we auto-delete remote feature branches after PR merge on both repos?
