# Lessons Learned & Workflow Brainstorm

> Scratchpad for streamlining the public/private split-repo workflow.
> Once strategies are settled here, promote them to `WORKFLOW.md` and any agent instructions.

## Why Two Repos, Not Branches

GitHub's visibility model is **repo-level, not branch-level**. This means no single-repo, branch-based design can give you both privacy and shareability simultaneously:

| Approach | Privacy | Sharing | Verdict |
|---|---|---|---|
| Single public repo, `private` branch | ❌ Branch is visible to everyone | ✅ Public branch is shareable | Fails on privacy — secrets exposed |
| Single private repo, `public` branch | ✅ Everything is private | ❌ Can't PR from private → public (GitHub limitation) | Fails on sharing — can't contribute back |
| Two repos (current) | ✅ Private repo holds secrets | ✅ Public repo accepts PRs | Works on both |

Key constraints that force this:

- **All forks of a public repo are public** — you cannot make a fork private, and you cannot change a fork's visibility ([GitHub Docs](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/working-with-forks/about-permissions-and-visibility-of-forks)).
- **GitHub does not allow PRs from private → public repos** — even if you own both.
- **Branches inherit the repo's visibility** — a "private" branch in a public repo is still publicly readable.

The two-repo architecture with shared history (via clone + `bootstrap-private-fork.sh`) makes them feel like branches of the same repo, but the visibility boundary is what makes it actually work. The shared history enables clean rebasing; the separate repos enable privacy + PRs.

## Pain Points Encountered

### 1. Accidental private content in public commits

- **What happened:** Working tree mixed public-appropriate Stow layout changes with private-only files (`git-private/.gitconfig`, `private/`).
- **Risk:** Could have pushed private content to the public repo.
- **Mitigation that worked:** Stash everything → branch from `upstream/main` → manually recreate only public-appropriate files → verify with `git diff --cached --name-only | grep -E 'private|secret|credential'` before committing.

### 2. Untracked files blocking rebase

- **What happened:** After the public PR merged, untracked Stow package files (`core/`, `git/`, `shell/`) in the working tree blocked the rebase because Git refused to overwrite them.
- **Mitigation that worked:** `git stash --include-untracked` before rebasing.
- **Friction:** Had to reason carefully about which untracked files would collide vs. which were private-only and safe.

### 3. Stash pop partial failure

- **What happened:** After rebase, `git stash pop` failed partially — three untracked files already existed (from the merged PR), so Git skipped them but kept the stash.
- **Confusion:** The "error: could not restore untracked files" message looked alarming but was actually benign — the private-only files (`git-private/`, `private/`) were restored successfully.
- **Resolution:** Drop the stash; commit only the private-only files.

### 4. `git pull upstream` vs `git fetch upstream && git rebase upstream/main`

- **What happened:** `main` tracks `origin/main` (private), not `upstream/main` (public). So `git pull upstream` behavior is ambiguous — it works but requires understanding tracking-branch resolution.
- **Mitigation that worked:** Use the explicit form `git pull --rebase upstream main` or `git fetch upstream && git rebase upstream/main`.

### 5. Force-push required after rebase

- **What happened:** Rebase rewrote commit hashes, so `main` diverged from `origin/main` (10 ahead, 5 behind) even though content was equivalent.
- **Mitigation that worked:** `git push --force-with-lease origin main`.
- **Friction:** Force-push feels dangerous; need confidence that no one else pushed in the meantime.

### 6. Pre-commit hook blocks commits on `main` when origin looks public

- **What happened:** The pre-commit hook refuses commits on `main` if `origin` appears to be the public remote (safety guard against direct public pushes).
- **Friction:** In a freshly cloned public repo (before bootstrap), you can't commit on `main` until you run `bootstrap-private-fork.sh` to retarget `origin` to the private remote.

### 7. Post-rebase divergence from `origin/main` is confusing

- **What happened:** After `git rebase upstream` (rebasing private `main` onto `upstream/main`), commit hashes were rewritten, so `main` diverged from `origin/main` (4 ahead, 2 behind) even though the content was equivalent. This left uncertainty about whether a force-push was needed and whether it was safe.
- **What helped:** Running `git pull` immediately after the rebase. Since `pull.rebase=true` and `main` tracks `origin/main`, this ran `git rebase origin/main`. Git's patch-id detection recognized the 2 "behind" commits as already-applied and skipped them, leaving `main` just 1 ahead — a clean, non-force push.
- **Why it worked:** `origin/main` had no genuinely new commits — only hash-rewritten versions of the same content. Git's cherry-pick detection reconciled the divergence automatically.
- **Caveat:** This only works when `origin/main` has no real new commits. If a collaborator had pushed actual new work, the `git pull` rebase could have produced conflicts or interleaved unrelated history. Always check `git log main..origin/main` to verify the "behind" commits are just hash-rewritten equivalents before relying on this.
- **Lesson:** After rebasing onto `upstream/main`, a `git pull` (which rebases onto `origin/main`) can reconcile hash-only divergence without a force-push — but verify the behind-commits are equivalent first.

---

## Proposed Strategies

### A. Dedicated public-contribution branch

**Idea:** Keep a long-lived local branch `public` (or `public/main`) that always tracks `upstream/main`. Do all public-intended work there; never commit public work on `main`.

**Workflow:**

```bash
# One-time setup
git branch public upstream/main
git branch --set-upstream-to=upstream/main public

# Daily public work
git switch public
git pull --rebase           # pulls from upstream/main (tracked)
# ... make changes ...
git push upstream public:feature/xxx   # push as feature branch to public repo
# open PR
```

**Pros:**

- Eliminates ambiguity about where public work happens.
- `git pull` on `public` branch just works (tracks `upstream/main`).
- No need to remember `git pull --rebase upstream main` explicitly.

**Cons:**

- Two branches to manage (`main` for private, `public` for public work).
- Risk of accidentally starting work on the wrong branch.

**Open questions:**

- Should `public` be a single long-lived branch, or should we always create fresh `feature/*` branches from `upstream/main`?
- How to make the branch switch frictionless (aliases, script)?

### B. Helper scripts for common operations

**Idea:** Add small scripts under `scripts/` that encapsulate the error-prone multi-step operations.

#### `scripts/sync-upstream.sh`

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

# Reconcile hash-only divergence with origin/main (see pain point #7).
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

> **Note:** The previous version of this script used `git push --force-with-lease origin main`.
> The `git pull --rebase` step (pain point #7) can often reconcile hash-only divergence
> without a force-push. However, if `origin/main` has genuinely new commits from a
> collaborator, the pull-rebase may produce conflicts or interleave unrelated history.
> Consider adding a verification step that checks `git log main..origin/main` before
> the pull, and falls back to `--force-with-lease` only when the behind-commits are
> confirmed equivalent. This automation needs careful design before implementation.

#### `scripts/public-branch.sh`

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

#### `scripts/pre-commit-public-check.sh` (or hook enhancement)

- Pre-commit hook already guards against committing on `main` when origin looks public.
- Could extend to warn (not block) when committing files matching `private|secret|credential|git-private` on a branch that will be pushed to `upstream`.

**Pros:**

- Encapsulates the multi-step sync/branch logic in one tested place.
- Reduces cognitive load — run `scripts/sync-upstream.sh` instead of remembering 4 commands.
- Self-documenting (the script is the documentation).

**Cons:**

- More scripts to maintain.
- Scripts can hide what's happening; need good echo output.

### C. Git aliases for common operations

**Idea:** Add aliases to `scripts/.gitconfig.local` (repo-local, shared across clones).

```ini
[alias]
    sync = "!f() { git stash push --include-untracked -m 'auto: pre-sync' && git fetch upstream && git rebase upstream/main && git push --force-with-lease origin main && git stash pop; }; f"
    public-branch = "!f() { git fetch upstream && git switch -c \"${1:-feature/public-$(date +%Y%m%d)}\" upstream/main; }; f"
    push-public = "!f() { branch=$(git rev-parse --abbrev-ref HEAD); git push upstream \"$branch\"; }; f"
```

**Usage:**

```bash
git sync                 # sync private main with upstream
git public-branch        # create fresh public branch from upstream/main
git public-branch fix/typo
git push-public          # push current branch to upstream for PR
```

**Pros:**

- Minimal overhead — just `git sync`.
- Lives in the repo, so it's shared across machines.
- No separate scripts to maintain.

**Cons:**

- Inline shell in git config is harder to read/debug than scripts.
- Less opportunity for error handling and helpful output.
- `git sync` doing force-push could surprise; needs clear messaging.

### D. `.gitignore` for private-only paths

**Idea:** Add a `.gitignore` on the `public` branch (or in public-appropriate work) that ignores `git-private/` and `private/` so they can't be accidentally committed.

**Problem:** `.gitignore` is versioned, and the public repo shouldn't have entries for private paths that don't exist there. Also, in the private repo we *want* to track `git-private/` and `private/`.

**Alternative:** Use a local-only `.git/info/exclude` in the private clone to ignore nothing (we want to track private files), but on public-contribution branches, rely on the pre-commit check (Strategy B) or careful `git add` practices.

**Verdict:** Probably not useful here — the split is repo-level, not branch-level. Discard this idea unless we move to a single-repo model.

### E. Pre-push hook enhancement for public safety

**Idea:** Extend `.githooks/pre-push` to scan pushed file paths for private patterns when the target remote is `upstream`.

```bash
# In pre-push, when remote_name == "upstream":
#   Check if any pushed file matches private|git-private|secret|credential|\.ssh
#   If so, block the push with a clear message.
```

**Pros:**

- Last line of defense against leaking private content to the public repo.
- Catches mistakes that slip past manual review.

**Cons:**

- Pattern matching is imperfect (false positives/negatives).
- Already partially covered by the existing `pre-push` block on `upstream main`.

**Verdict:** Worth adding as a belt-and-suspenders check. Low cost, high value.

---

## Decision Matrix

| Strategy | Solves | Effort | Maintenance | Recommended? |
|---|---|---|---|---|
| A. Dedicated `public` branch | #1, #4 | Low | Low | ✅ Yes |
| B. Helper scripts | #2, #3, #5, #7 | Medium | Medium | ✅ Yes (sync + public-branch) |
| C. Git aliases | #2, #3, #5, #7 | Low | Low | ⚠️ Maybe (simpler than B, but less robust) |
| D. `.gitignore` for private paths | #1 | Low | Low | ❌ No (doesn't fit split-repo model) |
| E. Pre-push hook enhancement | #1 | Low | Low | ✅ Yes |

---

## Current Open Questions

1. **Long-lived `public` branch vs. fresh `feature/*` branches from `upstream/main`?**
   - Long-lived: less friction, but branch can drift if not rebased regularly.
   - Fresh: cleaner, but more typing. The `public-branch` script/alias makes this cheap.
   - **Leaning toward:** fresh branches via `git public-branch <name>` — explicit and clean.

2. **Scripts vs. aliases?**
   - Scripts are more readable and testable; aliases are more convenient.
   - **Leaning toward:** start with aliases for convenience, promote to scripts if logic grows.

3. **Should `git sync` auto-stash, or should we require a clean tree?**
   - Auto-stash is convenient but can mask mistakes (stashing private work that should be committed first).
   - `rebase.autoStash = true` is already set in `.gitconfig.local`, but that only stashes *tracked* changes — untracked files still block.
   - **Leaning toward:** `git sync` should stash `--include-untracked` explicitly, with clear messaging.

4. **How to handle the stash-pop partial failure gracefully?**
   - After sync + stash pop, if pop fails, the user is in a confusing state.
   - **Idea:** `git sync` could detect which stashed files already exist post-rebase and skip them, only restoring truly new files. This is complex; maybe just document the expected behavior.

5. **Should we add a `git status` alias that's more informative for the split-repo context?**
   - E.g., `git s` that shows branch, tracking, ahead/behind for both origin and upstream.
   - **Idea:** `git s = status -sb` plus a reminder of which remote is public vs. private.

6. **How should `git sync` handle the two-stage rebase (upstream → origin reconciliation)?**
   - Pain point #7 showed that `git pull --rebase` after `git rebase upstream` can reconcile hash-only divergence without a force-push.
   - **But:** this is only safe when `origin/main` has no genuinely new commits. If a collaborator pushed real work, the pull-rebase could conflict or interleave unrelated history.
   - **Options for automation:**
     - (a) Always force-push (`--force-with-lease`) — simple, but rewrites `origin/main` hashes every sync.
     - (b) Always `git pull --rebase` after upstream rebase — avoids force-push when possible, but risky if origin has new commits.
     - (c) Verify before pulling: check `git log main..origin/main` and only `pull --rebase` if the behind-commits are hash-rewritten equivalents; otherwise warn and fall back to force-push or abort.
   - **Leaning toward:** (c) — verify first, then decide. This needs careful implementation; the verification logic is non-trivial (comparing patch-ids of behind-commits against upstream history).
   - **Key principle:** The verification step must not be skipped. Automating it is fine, but the script must fail loudly if it can't confirm equivalence, rather than silently picking a strategy.

---

## Next Steps

- [ ] Settle on strategies A + B (or C) + E.
- [ ] Implement chosen strategies.
- [ ] Test the full round-trip: private work → public branch → PR → merge → sync → private commit.
- [ ] Promote finalized workflow to `WORKFLOW.md`.
- [ ] Update agent instructions (`.instructions.md` or `AGENTS.md`) with the streamlined workflow.
