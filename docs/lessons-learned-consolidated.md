# Lessons Learned — Consolidated

> Consolidated, deduplicated record of pain points, mistakes, and lessons from the
> public/private split-repo workflow. Merged from three independent session notes
> (`docs/archive/lessons-learned-original.md`, `docs/archive/lessons-learned-addendum-1.md`, `docs/archive/lessons-learned-addendum-2.md`).
>
> This document is the **canonical lessons-learned reference**. The original addenda
> are preserved under `docs/archive/` for historical context. Alternative approaches
> and trade-offs that were considered but not adopted are documented in
> `docs/alternative-approaches.md`.
>
> As strategies here are settled and implemented, they are promoted to `WORKFLOW.md`
> and supporting automation (hooks, scripts, aliases, config). Open questions remain
> here until resolved.

---

## Why Two Repos, Not Branches

GitHub's visibility model is **repo-level, not branch-level**. No single-repo,
branch-based design can give you both privacy and shareability simultaneously:

| Approach | Privacy | Sharing | Verdict |
|---|---|---|---|
| Single public repo, `private` branch | ❌ Branch is visible to everyone | ✅ Public branch is shareable | Fails on privacy — secrets exposed |
| Single private repo, `public` branch | ✅ Everything is private | ❌ Can't PR from private → public (GitHub limitation) | Fails on sharing — can't contribute back |
| Two repos (current) | ✅ Private repo holds secrets | ✅ Public repo accepts PRs | Works on both |

Key constraints that force this:

- **All forks of a public repo are public** — you cannot make a fork private, and you cannot change a fork's visibility ([GitHub Docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-permissions-and-visibility-of-forks)).
- **GitHub does not allow PRs from private → public repos** — even if you own both.
- **Branches inherit the repo's visibility** — a "private" branch in a public repo is still publicly readable.

The two-repo architecture with shared history (via clone + `bootstrap-private-fork.sh`)
makes them feel like branches of the same repo, but the visibility boundary is what makes
it actually work. The shared history enables clean rebasing; the separate repos enable
privacy + PRs.

---

## Key Mental Model

The single most important principle:

> **`upstream/main` is the canonical public history. Private `main` is always a
> superset of `upstream/main` plus private-only commits.**

If this relationship breaks (e.g., private `main` diverges with its own version of
public-safe changes), recovery is painful. The way to keep it intact:

1. **Public-intended work:** Start from `upstream/main` on a `public/*` branch. Never
   commit it to private `main` first.
2. **Private-only work:** Commit on private `main`. It will never go upstream.
3. **After a public PR merges:** Rebase private `main` onto the new `upstream/main`.
   This replays private-only commits on top of the updated public history.
4. **If the same change exists on both sides:** Treat `upstream/main` as canonical.
   Drop the private-side duplicate. Do not try to "merge" them.

---

## Pain Points

### 1. Branch tracking retargets silently after `git remote rename`

**What happened:** Following the bootstrap pattern, `git remote rename origin upstream`
silently retargeted `branch.main.remote` from `origin` to `upstream`. The subsequent
`git remote add origin <private>` did **not** retarget `main` back. Plain `git push`
on `main` pushed to the public repo.

**Root cause:** `git remote rename` updates all refs that pointed at the old remote
name, including branch tracking config. `git remote add` does not retarget any
branches. The original bootstrap script used `git push origin main` without `-u`, so
it did not change tracking either.

**Impact:** A private-only commit (`private/.gitconfig`) was pushed to the public repo.

**Current mitigation:** `scripts/setup.sh` and `scripts/bootstrap-private-fork.sh` now
run `git branch --set-upstream-to=origin/main main` when both `origin` and `upstream`
remotes exist. Docs updated to include this step explicitly.

**Still fragile:** If a user skips `setup.sh` or bootstraps manually, the foot-gun
remains. The `pre-commit` hook guards against committing on `main` when `origin` equals
`upstream`, but it cannot guard against the more subtle case where `origin` is private
but `branch.main.remote` is still `upstream`.

**Ideas:**

- Add a `pre-push` hook check: if pushing `main` and `branch.main.remote != origin`,
  warn or block.
- Add a setup verification step that prints `branch.main.remote` and warns if it is
  not `origin`.
- Document the `git remote rename` side effect prominently in `WORKFLOW.md`.

---

### 2. `git push` with no explicit remote is ambiguous in a split-remote repo

**What happened:** On a branch created from `upstream/main` (e.g., `public/updates`),
plain `git push` went to `upstream` because `branch.<name>.remote = upstream`. On
`main`, before the tracking fix, plain `git push` also went to `upstream`. In another
case, a branch intended for upstream was pushed to `origin` because
`remote.pushDefault = origin` was set and the branch had no explicit
`branch.<name>.remote`.

**Root cause:** Git's push remote resolution has multiple layers
(`branch.<name>.pushRemote` > `remote.pushDefault` > `branch.<name>.remote` >
`push.default`). In a split-remote repo, the "default" is context-dependent and easy
to get wrong.

**Impact:** Docs changes were pushed to the private repo instead of the public repo,
then merged via a PR on the wrong repo. Required history rewrite to undo.

**Current mitigation:** `remote.pushDefault = origin` is set in
`scripts/.gitconfig.local`, making plain `git push` default to private. The `pre-push`
hook blocks pushes of `main` to `upstream`.

**Still fragile:** Public contribution branches (e.g., `public/updates`,
`public/docs-sync`) are configured with `branch.<name>.remote = upstream`, which
overrides `remote.pushDefault`. This is correct for those branches, but the user must
be aware that plain `git push` on those branches goes to `upstream`. If a branch is
created with `git switch -c <name> upstream/main`, `push.autoSetupRemote = true` sets
tracking to `upstream/main`, which may or may not be what the user wants.

**Ideas:**

- Always use explicit remote in push commands: `git push upstream <branch>` or
  `git push origin <branch>`.
- Add a pre-push warning (not block) when the remote being pushed to does not match
  the user's likely intent. This is hard to determine automatically.
- Create wrapper scripts: `push-public` and `push-private` that explicitly target the
  correct remote.
- Document the push resolution hierarchy in `WORKFLOW.md` with a decision tree.
- Consider a shell prompt or pre-commit status check that shows the current branch's
  push target.

---

### 3. Accidental private content in public commits

**What happened:** Working tree mixed public-appropriate Stow layout changes with
private-only files (`git-private/.gitconfig`, `private/`).

**Risk:** Could have pushed private content to the public repo.

**Mitigation that worked:** Stash everything → branch from `upstream/main` → manually
recreate only public-appropriate files → verify with
`git diff --cached --name-only | grep -E 'private|secret|credential'` before committing.

**Ideas:**

- Pre-push hook that scans pushed file paths for private patterns when the target
  remote is `upstream` (see [Proposed Automation](#proposed-automation)).

---

### 4. Cherry-picking from private `main` to a public branch creates duplicate history

**What happened:** Public-safe changes were committed to private `main` first. Then a
public branch was created from `upstream/main` and the commit was cherry-picked onto
it. The PR was squash-merged on GitHub. When syncing back to private `main`, everything
conflicted because Git saw two unrelated commits with similar content.

**Root cause:** Cherry-pick creates a new commit with a different SHA but the same
content. Squash merge creates yet another new commit. Git cannot recognize these as
"the same change" during rebase, so it reports conflicts on every overlapping line.

**Impact:** Full conflict resolution required across all changed files. Required
rebuilding private `main` from `upstream/main` and reapplying only the private-only
commit.

**Current mitigation:** `WORKFLOW.md` and `plan.md` now explicitly recommend:

- Public-intended work should start on a branch from `upstream/main`, not on private
  `main`.
- If public-safe content already exists on private `main`, use
  `git restore -s main -- <paths>` to copy file contents onto a public branch, rather
  than cherry-picking commits.
- Cherry-pick only when the commit will not also remain on private `main`.

**Still fragile:** The docs describe the correct flow, but there is no automated guard
against cherry-picking a commit that also exists on private `main` into a public
branch.

**Ideas:**

- Add a pre-push hook that checks if any commit being pushed to `upstream` also exists
  on `origin/main` (by patch ID, not SHA). If so, warn that sync-back may conflict.
- Create a `publish-files` script that automates the `git restore -s main` flow and
  opens the PR.
- Document a "decision tree" for publishing: Is the change already on private `main`?
  → Use file restore. Is it new? → Work on a public branch from `upstream/main`.
- Consider maintaining a separate public-only clone/worktree to eliminate the mental
  overhead entirely.

---

### 5. Squash merge destroys commit correspondence

**What happened:** A PR was squash-merged on GitHub. The squashed commit on
`upstream/main` had no ancestry relationship to the original commits on the feature
branch or on private `main`.

**Root cause:** Squash merge creates a single new commit that collapses all branch
commits into one. It does not preserve any commit SHAs or ancestry from the source
branch.

**Impact:** Syncing private `main` onto the new `upstream/main` caused conflicts
because the same content changes existed as different commits on both sides.

**Current mitigation:** `WORKFLOW.md` now warns that squash merge makes sync-back more
conflict-prone when the same change exists on private `main`.

**Still fragile:** GitHub's default merge button is often "Squash and merge". Users may
not notice which strategy is selected.

**Ideas:**

- For this workflow, prefer "Create a merge commit" or "Rebase and merge" on public
  PRs.
- Configure GitHub repo settings to disable squash merge on the public repo (or at
  least document the preference).
- If squash merge is used, treat `upstream/main` as canonical and rebuild private
  `main` from it, rather than trying to reconcile.
- Add a post-merge sync checklist: after PR merge,
  `git fetch upstream && git rebase upstream/main` and resolve by taking
  `upstream/main` versions of public files.

---

### 6. Accidental PR on the wrong repo (origin instead of upstream)

**What happened:** A branch intended for the public repo was pushed to the private repo
(`origin`) because `remote.pushDefault = origin` was set and the branch's tracking was
configured to `origin`. The GitHub PR link in the push output was followed without
noticing it pointed at the private repo. The PR was merged on the private repo before
the mistake was noticed.

**Root cause:** Multiple factors:

1. `remote.pushDefault = origin` correctly defaults to private, but public branches
   need explicit `git push upstream <branch>`.
2. The branch was created with `git switch -c <name> upstream/main`, which set tracking
   to `upstream/main` via `push.autoSetupRemote`. But after stash pop and commit, the
   user ran plain `git push`, which may have used `remote.pushDefault` instead of the
   branch tracking, depending on Git version and config.
3. The GitHub PR link in push output says
   `github.com:JAKimball/wsl-ubuntu-config-private.git` for origin and
   `github.com:JAKimball/wsl-ubuntu-config.git` for upstream, but the user did not
   notice the difference.

**Impact:** Docs changes were merged into the private repo via a PR, creating a merge
commit on `origin/main` that diverged from `upstream/main`. Required force-push to
reset `origin/main` and re-creation of the docs changes on a clean public branch.

**Current mitigation:** No automated guard exists for this specific mistake.

**Ideas:**

- Always read the push output carefully, especially the remote URL in the "Create a
  pull request" line.
- Add a pre-push hook that prints a warning when pushing to `origin` on a branch whose
  name starts with `public/` or `feature/pub`, since those are likely intended for
  upstream.
- Create wrapper scripts: `publish` (pushes to upstream and opens PR) and `save`
  (pushes to origin).
- Use `gh pr create` with explicit `--repo` flag to avoid creating PRs on the wrong
  repo.
- Add a visual cue in the shell prompt showing which remote the current branch will
  push to.
- Document a pre-push checklist: "Which remote am I pushing to? Which repo will the PR
  be created on?"

---

### 7. Untracked files blocking rebase

**What happened:** After the public PR merged, untracked Stow package files (`core/`,
`git/`, `shell/`) in the working tree blocked the rebase because Git refused to
overwrite them.

**Mitigation that worked:** `git stash --include-untracked` before rebasing.

**Friction:** Had to reason carefully about which untracked files would collide vs.
which were private-only and safe.

**Note:** `rebase.autoStash = true` (set in `.gitconfig.local`) only stashes *tracked*
changes — untracked files still block. Any sync automation must stash
`--include-untracked` explicitly.

---

### 8. Stash pop partial failure

**What happened:** After rebase, `git stash pop` failed partially — three untracked
files already existed (from the merged PR), so Git skipped them but kept the stash.

**Confusion:** The "error: could not restore untracked files" message looked alarming
but was actually benign — the private-only files (`git-private/`, `private/`) were
restored successfully.

**Resolution:** Drop the stash; commit only the private-only files.

**Lesson:** After a sync + stash pop, if pop fails, check which stashed files already
exist post-rebase (those are safe to skip) vs. which are genuinely new (those need
restoring). Sync automation should detect this and report clearly rather than failing
opaquely.

---

### 9. `git pull upstream` vs `git fetch upstream && git rebase upstream/main`

**What happened:** `main` tracks `origin/main` (private), not `upstream/main` (public).
So `git pull upstream` behavior is ambiguous — it works but requires understanding
tracking-branch resolution.

**Mitigation that worked:** Use the explicit form `git pull --rebase upstream main` or
`git fetch upstream && git rebase upstream/main`.

**Lesson:** When the branch's tracking remote differs from the remote you want to pull
from, always use the explicit form. Document common fetch/pull patterns in
`WORKFLOW.md`.

---

### 10. Post-rebase divergence from `origin/main` is confusing

**What happened:** After `git rebase upstream` (rebasing private `main` onto
`upstream/main`), commit hashes were rewritten, so `main` diverged from `origin/main`
(e.g., 4 ahead, 2 behind) even though the content was equivalent. This left
uncertainty about whether a force-push was needed and whether it was safe.

**What helped:** Running `git pull` immediately after the rebase. Since
`pull.rebase=true` and `main` tracks `origin/main`, this ran `git rebase origin/main`.
Git's patch-id detection recognized the 2 "behind" commits as already-applied and
skipped them, leaving `main` just 1 ahead — a clean, non-force push.

**Why it worked:** `origin/main` had no genuinely new commits — only hash-rewritten
versions of the same content. Git's cherry-pick detection reconciled the divergence
automatically.

**Caveat:** This only works when `origin/main` has no real new commits. If a
collaborator had pushed actual new work, the `git pull` rebase could have produced
conflicts or interleaved unrelated history. Always check
`git log main..origin/main` to verify the "behind" commits are just hash-rewritten
equivalents before relying on this.

**Lesson:** After rebasing onto `upstream/main`, a `git pull` (which rebases onto
`origin/main`) can reconcile hash-only divergence without a force-push — but verify
the behind-commits are equivalent first.

---

### 11. Feature branches tracking `upstream/main` look "mysteriously" ahead/behind

**What happened:** A local feature branch based on `upstream/main` showed
`ahead 1, behind 1` after the public PR merged.

**Reason:** The branch still tracked `upstream/main`, and the merged commit on
`upstream/main` was a different commit object from the local branch commit. This was
correct Git behavior, but not intuitive at first glance.

**Lesson:** After a public PR merges, local feature branches tracking `upstream/main`
will show ahead/behind divergence because the merge commit differs from the local
commit. This is expected; rebase or delete the branch.

---

### 12. Force-push required after rebase

**What happened:** Rebase rewrote commit hashes, so `main` diverged from
`origin/main` (10 ahead, 5 behind) even though content was equivalent.

**Mitigation that worked:** `git push --force-with-lease origin main`.

**Friction:** Force-push feels dangerous; need confidence that no one else pushed in
the meantime.

**Relationship to pain point #10:** When `origin/main` has only hash-rewritten
equivalents, `git pull --rebase` can avoid the force-push (see #10). When
`origin/main` has genuinely new commits, force-push (or conflict resolution) is
required. The sync script must verify which case applies before choosing a strategy.

---

### 13. Pre-commit hook blocks commits on `main` when origin looks public

**What happened:** The pre-commit hook refuses commits on `main` if `origin` appears
to be the public remote (safety guard against direct public pushes).

**Friction:** In a freshly cloned public repo (before bootstrap), you can't commit on
`main` until you run `bootstrap-private-fork.sh` to retarget `origin` to the private
remote.

**Lesson:** This is intentional friction. The fix is always to bootstrap the private
fork, not to weaken the hook. Document this in `WORKFLOW.md` so users understand why
the hook blocks and how to proceed.

---

### 14. `GIT_AUTHOR_DATE` / `GIT_COMMITTER_DATE` environment variables leak across repos

**What happened:** Environment variables `GIT_AUTHOR_DATE` and `GIT_COMMITTER_DATE`
were set in a PowerShell session to fix timestamps in an unrelated repo. Subsequent
`git commit` commands in this repo inherited those variables, producing incorrect
timestamps.

**Root cause:** These environment variables override Git's default timestamp behavior
globally for the current shell session. They are not scoped to a specific repo.

**Impact:** Commit history showed dates that did not match actual commit times, making
the timeline confusing and harder to reason about.

**Current mitigation:** `pre-commit` hook blocks commits when `GIT_COMMITTER_DATE` is
set. (It does not block `GIT_AUTHOR_DATE` because Git itself can set that variable
during certain operations.)

**Still fragile:** The hook only checks `GIT_COMMITTER_DATE`, not `GIT_AUTHOR_DATE`.
If a user sets only `GIT_AUTHOR_DATE`, the hook will not catch it. Also, hooks can be
bypassed with `--no-verify`.

**Ideas:**

- Document the risk of setting these variables in shell profiles or session scripts.
- Consider a shell function or alias for `git commit` that unsets these variables
  unless explicitly requested.
- Add a `pre-commit` hook check for `GIT_AUTHOR_DATE` as well, with a warning (not
  block) if it is set and appears to be a manual override. This is tricky because Git
  may set it internally.
- Use `git commit --date=now` explicitly when you want the current time, rather than
  relying on environment variable absence.

---

### 15. Branch clutter from recovery operations

**What happened:** Multiple backup, rewrite, and recovery branches accumulated:
`backup/main-before-resync`, `backup/origin-main`, `backup/upstream-main`,
`backup/upstream-main-2026-06-20`, `backup/origin-main-doc-pr-2026-06-21`,
`rewrite/origin-main`, `rewrite/upstream-main`, `template`, `hooks`, `public/updates`,
`feature/pub-safe`, `public/docs-sync`, `public/stow-layout`, `docs/public`.

**Root cause:** Each recovery operation created new branches for safety, but there was
no cleanup routine.

**Impact:** `git branch -vv` output became noisy and hard to parse. Risk of confusing
backup branches with active branches.

**Current mitigation:** None automated.

**Ideas:**

- Create a `scripts/cleanup-branches.sh` that lists branches matching `backup/*`,
  `rewrite/*`, and `template`, and offers to delete them after confirmation.
- Use tags instead of branches for backups: `git tag backup/<description>` is more
  clearly a point-in-time marker.
- Document a cleanup cadence: after each successful sync, delete backup branches older
  than the last sync.
- Add a `scripts/branch-status.sh` that shows which branches are merged into `main` or
  `upstream/main` and can be safely deleted.

---

### 16. `git fetch origin upstream` is not `git fetch origin && git fetch upstream`

**What happened:** Running `git fetch origin upstream` produced
`fatal: couldn't find remote ref upstream` because Git interpreted it as "fetch ref
`upstream` from remote `origin`", not "fetch from both `origin` and `upstream`".

**Root cause:** `git fetch <remote> <refspec>` syntax. The second argument is a
refspec, not a remote name.

**Impact:** Minor; the error was immediately recognizable. But it highlighted that Git
CLI syntax is not always intuitive.

**Mitigation:** None needed; this is a knowledge gap, not a workflow flaw. Document
common fetch patterns in `WORKFLOW.md`. Consider a shell alias:
`git fetch-all` = `git fetch --all` or `git fetch --multiple origin upstream`.

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

### File-based publication when content already exists on private `main`

Safer pattern than cherry-pick when the same public-safe content already exists on
private `main`:

```bash
git fetch upstream
git switch -c feature/publish-safe upstream/main
git restore -s main -- path/to/file1 path/to/file2
git add path/to/file1 path/to/file2
git commit -m "docs: publish selected files"
git push upstream feature/publish-safe
```

This avoids creating a second commit for the same logical change.

---

## Proposed Automation

### Wrapper scripts

| Script | Purpose | Status |
|--------|---------|--------|
| `scripts/sync-from-upstream.sh` | Stashes untracked files, fetches `upstream`, rebases `main` onto `upstream/main`, reconciles hash-only divergence with `origin/main` (verifying behind-commits are equivalents first), pushes to `origin`, restores stash. | Proposed |
| `scripts/new-public-branch.sh` | Creates a fresh public contribution branch from `upstream/main` with a clear name. Prints reminder that pushes to `upstream` must be explicit. | Proposed |
| `scripts/publish.sh <branch>` | Pushes a branch to `upstream` and creates a PR via `gh pr create --repo JAKimball/wsl-ubuntu-config`. | Proposed |
| `scripts/save.sh` | Pushes current branch to `origin` (private). | Proposed |
| `scripts/cleanup-branches.sh` | Lists and optionally deletes `backup/*`, `rewrite/*`, and `template` branches. | Proposed |
| `scripts/branch-status.sh` | Shows each branch's tracking remote, ahead/behind, and whether it is merged. | Proposed |

#### `scripts/sync-from-upstream.sh` (draft)

```bash
#!/usr/bin/env bash
# Sync private main with merged upstream changes.
# Stashes untracked files, rebases, reconciles with origin, pushes, restores stash.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

stashed=false
if ! git diff --quiet || ! git diff --cached --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
    git stash push --include-untracked -m "auto: pre-sync stash"
    stashed=true
fi

git fetch upstream
git rebase upstream/main

# Reconcile hash-only divergence with origin/main (see pain point #10).
# git pull (with pull.rebase=true) rebases onto origin/main; Git's patch-id
# detection skips commits already applied via upstream, often avoiding a force-push.
# IMPORTANT: verify the "behind" commits are hash-rewritten equivalents, not real
# new work, before relying on this. Check with: git log main..origin/main
git pull --rebase

git push origin main

if $stashed; then
    git stash pop || echo "Warning: stash pop had conflicts; resolve manually."
fi
```

> **Note:** The `git pull --rebase` step (pain point #10) can often reconcile hash-only
> divergence without a force-push. However, if `origin/main` has genuinely new commits
> from a collaborator, the pull-rebase may produce conflicts or interleave unrelated
> history. Consider adding a verification step that checks
> `git log main..origin/main` before the pull, and falls back to
> `--force-with-lease` only when the behind-commits are confirmed equivalent. This
> automation needs careful design before implementation.

#### `scripts/new-public-branch.sh` (draft)

```bash
#!/usr/bin/env bash
# Create a fresh public contribution branch from upstream/main.
set -euo pipefail
branch="${1:-feature/$(date +%Y%m%d)-public}"
git fetch upstream
git switch -c "$branch" upstream/main
echo "On public branch '$branch' based on upstream/main."
echo "Make public-appropriate changes, then: git push upstream $branch"
```

### Hook enhancements

| Hook | Check | Action | Status |
|------|-------|--------|--------|
| `pre-commit` | `GIT_COMMITTER_DATE` set | Block | ✅ Implemented |
| `pre-commit` | Committing on `main` when `origin == upstream` | Block | ✅ Implemented |
| `pre-commit` | `GIT_AUTHOR_DATE` set | Warn | Proposed |
| `pre-push` | Pushing `main` to `upstream` | Block | ✅ Implemented |
| `pre-push` | Pushing to `upstream` when commit range contains `private/` paths | Block | Proposed |
| `pre-push` | Pushing to `upstream` when commit range contains `scripts/.gitconfig.local` | Block | Proposed |
| `pre-push` | Pushing branch named `public/*` or `feature/pub*` to `origin` | Warn | Proposed |
| `pre-push` | Pushing to `upstream` when any commit also exists on `origin/main` by patch ID | Warn | Proposed |
| `pre-push` | Non-fast-forward push to `upstream` | Warn unless `ALLOW_UPSTREAM_REWRITE=1` | Proposed |

### Config enhancements

| Setting | Value | Purpose | Status |
|---------|-------|---------|--------|
| `remote.pushDefault` | `origin` | Default plain `git push` to private | ✅ Existing |
| `branch.main.remote` | `origin` | Track private main | ✅ Existing (enforced by `setup.sh`) |
| `branch.main.pushRemote` | `origin` | Explicitly set push target for `main` | Proposed (redundant but explicit) |
| `push.default` | `current` | Push current branch name | ✅ Existing |
| `pull.rebase` | `true` | Use rebase instead of merge on pull | ✅ Existing |
| `push.autoSetupRemote` | `true` | Auto-setup tracking branches | ✅ Existing |
| `rebase.autoStash` | `true` | Stash tracked changes before rebasing | ✅ Existing |
| `fetch.prune` | `true` | Prune deleted remote refs | ✅ Existing |

### Branch naming conventions (proposed)

| Prefix | Meaning | Push target |
|--------|---------|-------------|
| `main` | Private main (public history + private-only commits) | `origin` |
| `public/*` | Public contribution branches | `upstream` |
| `feature/*` | Private feature branches | `origin` |
| `backup/*` | Point-in-time recovery refs | (not pushed) |
| `rewrite/*` | History rewrite working branches | (not pushed) |

### GitHub repo settings (proposed)

- Disable "Squash and merge" on the public repo, or at minimum document that "Create a
  merge commit" is preferred.
- Enable branch protection on `upstream/main` with "Include administrators".
- Consider auto-deleting head branches after merge on both repos.

---

## Decision Matrix

| Strategy | Solves | Effort | Maintenance | Recommended? |
|---|---|---|---|---|
| Dedicated `public/*` branches from `upstream/main` | #3, #4, #9 | Low | Low | ✅ Yes |
| Wrapper scripts (sync, new-public-branch, publish, save) | #7, #8, #10, #12, #6 | Medium | Medium | ✅ Yes |
| Pre-push hook enhancements (private path scan, wrong-remote warn) | #3, #6 | Low | Low | ✅ Yes |
| `branch.main.pushRemote = origin` (explicit redundant safeguard) | #1, #2 | Low | Low | ✅ Yes |
| Branch naming conventions with policy | #6, #15 | Low | Low | ✅ Yes |
| Separate public-only clone/worktree | #3, #4, #6 | High | Low | ⚠️ Maybe (see alternative-approaches.md) |
| `.gitignore` for private paths | #3 | Low | Low | ❌ No (doesn't fit split-repo model) |

---

## Current Open Questions

1. **Should public-intended work happen in a separate worktree or clone?**
   - A second worktree or clone rooted at `upstream/main` would eliminate split-remote
     mental overhead entirely.
   - Trade-off: more disk space, separate working directories to sync.
   - See `docs/alternative-approaches.md` for detailed analysis.

2. **Should `setup.sh` verify and warn if `branch.main.remote != origin` after setup?**
   - Low-cost safeguard against pain point #1.
   - Could print a warning and exit non-zero if misconfigured.

3. **Is it worth implementing patch-ID-based duplicate detection in `pre-push`?**
   - Would warn when pushing to `upstream` a commit that also exists on `origin/main`.
   - Non-trivial to implement correctly (comparing patch-ids of pushed commits against
     `origin/main` history).
   - High value for preventing pain point #4.

4. **How should `sync-from-upstream.sh` handle the two-stage rebase
   (upstream → origin reconciliation)?**
   - Pain point #10 showed that `git pull --rebase` after `git rebase upstream` can
     reconcile hash-only divergence without a force-push.
   - **But:** this is only safe when `origin/main` has no genuinely new commits.
   - **Options for automation:**
     - (a) Always force-push (`--force-with-lease`) — simple, but rewrites
       `origin/main` hashes every sync.
     - (b) Always `git pull --rebase` after upstream rebase — avoids force-push when
       possible, but risky if origin has new commits.
     - (c) Verify before pulling: check `git log main..origin/main` and only
       `pull --rebase` if the behind-commits are hash-rewritten equivalents; otherwise
       warn and fall back to force-push or abort.
   - **Leaning toward:** (c) — verify first, then decide. The verification step must
     not be skipped. The script must fail loudly if it can't confirm equivalence,
     rather than silently picking a strategy.

5. **Should `git sync` auto-stash, or should we require a clean tree?**
   - Auto-stash is convenient but can mask mistakes (stashing private work that should
     be committed first).
   - `rebase.autoStash = true` only stashes *tracked* changes — untracked files still
     block.
   - **Leaning toward:** `sync-from-upstream.sh` should stash `--include-untracked`
     explicitly, with clear messaging.

6. **How to handle the stash-pop partial failure gracefully?**
   - After sync + stash pop, if pop fails, the user is in a confusing state.
   - **Idea:** `sync-from-upstream.sh` could detect which stashed files already exist
     post-rebase and skip them, only restoring truly new files. This is complex; maybe
     just document the expected behavior.

7. **Should we add a `git status` alias that's more informative for the split-repo
   context?**
   - E.g., `git s` that shows branch, tracking, ahead/behind for both origin and
     upstream.
   - **Idea:** `git s = status -sb` plus a reminder of which remote is public vs.
     private.

8. **Should `public/*` branches automatically track `upstream/<branch>` instead of
   `upstream/main` after first push?**
   - `push.autoSetupRemote = true` already handles this, but the behavior may be
     surprising.

9. **Should the hooks become stricter, even at the cost of more friction?**
   - Trade-off between safety and usability.
   - **Leaning toward:** add the proposed pre-push enhancements (private path scan,
     wrong-remote warn) as belt-and-suspenders checks.

10. **Which backup/rewrite branches should be retained, and which should be cleaned up
    after each successful recovery?**
    - **Idea:** use tags instead of branches for backups; delete backup branches after
      each successful sync.

---

## Next Steps

- [ ] Resolve open questions (especially #1, #4, #5).
- [ ] Implement chosen automation (scripts, hooks, config).
- [ ] Test the full round-trip: private work → public branch → PR → merge → sync →
      private commit.
- [ ] Promote finalized workflow to `WORKFLOW.md`.
- [ ] Update agent instructions (`.instructions.md` or `AGENTS.md`) with the
      streamlined workflow.
