# Alternative Approaches & Trade-offs

> Companion to `lessons-learned-consolidated.md`. Documents alternative strategies that
> were considered for the public/private split-repo workflow, along with their trade-offs,
> conflicts with the chosen approach, and the rationale for adopting or rejecting each.
>
> This document exists to preserve the reasoning behind decisions, so future sessions
> (or other contributors) can understand *why* the workflow is the way it is, and
> revisit alternatives if circumstances change.

---

## Table of Contents

1. [Repository Architecture Alternatives](#1-repository-architecture-alternatives)
2. [Public Work Branching Strategies](#2-public-work-branching-strategies)
3. [Automation Delivery Mechanisms](#3-automation-delivery-mechanisms)
4. [Sync Reconciliation Strategies](#4-sync-reconciliation-strategies)
5. [Private Content Protection](#5-private-content-protection)
6. [Working Directory Layouts](#6-working-directory-layouts)
7. [Merge Strategy on Public PRs](#7-merge-strategy-on-public-prs)
8. [Backup and Recovery Refs](#8-backup-and-recovery-refs)

---

## 1. Repository Architecture Alternatives

### 1a. Single public repo with `private` branch

**Concept:** Keep everything in one public repo; put private content on a `private`
branch.

| Aspect | Assessment |
|--------|------------|
| Privacy | ❌ Branches inherit repo visibility — `private` branch is publicly readable |
| Sharing | ✅ Public branch is shareable |
| Complexity | Low (one repo) |

**Verdict:** ❌ Rejected. Fundamentally cannot provide privacy. This is a GitHub
platform limitation, not a configuration issue.

---

### 1b. Single private repo with `public` branch

**Concept:** Keep everything in one private repo; push public-appropriate content to a
`public` branch and PR from there.

| Aspect | Assessment |
|--------|------------|
| Privacy | ✅ Everything is private |
| Sharing | ❌ GitHub does not allow PRs from private → public repos, even if you own both |
| Complexity | Low (one repo) |

**Verdict:** ❌ Rejected. Cannot contribute back to the public ecosystem. This is a
GitHub platform limitation.

---

### 1c. Two repos with shared history (current approach)

**Concept:** Clone the public repo to create the private repo, so they share history.
Configure `origin` = private, `upstream` = public. Rebase private `main` onto
`upstream/main` to sync.

| Aspect | Assessment |
|--------|------------|
| Privacy | ✅ Private repo holds secrets |
| Sharing | ✅ Public repo accepts PRs |
| Complexity | Medium (two remotes, tracking config, sync discipline) |

**Verdict:** ✅ Adopted. This is the only approach that satisfies both privacy and
sharing constraints on GitHub. All pain points in `lessons-learned-consolidated.md`
are operational challenges *within* this architecture, not reasons to abandon it.

---

### 1d. Two repos, no shared history (independent)

**Concept:** Maintain two completely separate repos with no git history relationship.
Copy files between them manually or via scripts.

| Aspect | Assessment |
|--------|------------|
| Privacy | ✅ Private repo holds secrets |
| Sharing | ✅ Public repo accepts PRs |
| Complexity | High (no rebase reconciliation; all sync is manual file copy) |
| Sync friction | Very high — every sync is a manual merge with no git assistance |

**Verdict:** ❌ Rejected. Loses the ability to rebase private `main` onto
`upstream/main`, which is the core mechanism that makes sync-back manageable. Every
public merge would require manual file-level reconciliation.

---

## 2. Public Work Branching Strategies

### 2a. Long-lived `public` branch tracking `upstream/main`

**Concept:** Keep a single local branch `public` (or `public/main`) that always tracks
`upstream/main`. Do all public-intended work there.

```bash
# One-time setup
git branch public upstream/main
git branch --set-upstream-to=upstream/main public

# Daily public work
git switch public
git pull --rebase           # pulls from upstream/main (tracked)
# ... make changes ...
git push upstream public:feature/xxx   # push as feature branch to public repo
```

| Aspect | Assessment |
|--------|------------|
| Friction | Low — `git pull` on `public` just works |
| Branch clutter | Medium — one persistent branch |
| Drift risk | Medium — long-lived branch can drift if not rebased regularly |
| Mental model | Clear separation: `main` = private, `public` = public work |

**Conflict with chosen approach:** The chosen approach uses fresh `public/*` branches
(see 2b). A long-lived branch risks accumulating stale state and makes it harder to
track which public changes are in-flight vs. merged.

**Verdict:** ⚠️ Considered, not adopted. Fresh branches are cleaner and the
`new-public-branch.sh` script makes them cheap to create.

---

### 2b. Fresh `public/*` branches from `upstream/main` (chosen)

**Concept:** For each public contribution, create a fresh branch from
`upstream/main`. After the PR merges, delete the branch.

```bash
git fetch upstream
git switch -c public/<descriptive-name> upstream/main
# ... make changes ...
git push upstream public/<descriptive-name>
# open PR, merge, then delete branch
```

| Aspect | Assessment |
|--------|------------|
| Friction | Low (with `new-public-branch.sh` script) |
| Branch clutter | Low — branches are deleted after merge |
| Drift risk | None — each branch starts fresh from current `upstream/main` |
| Mental model | Explicit — branch name describes the contribution |

**Verdict:** ✅ Adopted. All three lessons-learned documents converge here. Cleanest
approach; aligns with the "upstream/main is canonical" mental model.

---

### 2c. Cherry-pick from private `main` to public branch

**Concept:** Commit public-safe changes to private `main` first, then cherry-pick the
commit onto a public branch from `upstream/main`.

| Aspect | Assessment |
|--------|------------|
| Friction | Low (mechanically simple) |
| Sync conflict risk | **High** — creates duplicate history (different SHAs, same content) |
| Squash merge interaction | **Bad** — squash merge + cherry-pick = no commit correspondence at all |

**Conflict with chosen approach:** Directly conflicts with the "start public work on
a branch from `upstream/main`" principle. Creates the exact duplicate-history problem
documented in pain point #4.

**Verdict:** ❌ Rejected as a default. Only acceptable when:
- The commit will **not** also remain on private `main` (i.e., you're moving it, not
  copying it), OR
- You are prepared to drop/rebuild the private-side duplicate after the PR merges.

**Safe alternative:** Use `git restore -s main -- <paths>` to publish file *state*
(not commit identity) onto a public branch.

---

## 3. Automation Delivery Mechanisms

### 3a. Wrapper scripts under `scripts/`

**Concept:** Encapsulate error-prone multi-step operations in bash scripts
(`sync-from-upstream.sh`, `new-public-branch.sh`, `publish.sh`, `save.sh`, etc.).

| Aspect | Assessment |
|--------|------------|
| Readability | ✅ High — bash scripts are self-documenting |
| Testability | ✅ Can be tested independently |
| Error handling | ✅ Full control over messaging, edge cases, verification steps |
| Maintenance | Medium — more files to maintain |
| Discoverability | Medium — users must know the scripts exist |

**Verdict:** ✅ Preferred for complex logic (planned; these scripts aren’t in-repo yet), especially `sync-from-upstream.sh`, which
needs the verify-before-pull-rebase logic from pain point #10).

---

### 3b. Git aliases in `.gitconfig.local`

**Concept:** Add aliases like `git sync`, `git public-branch`, `git push-public` to
the repo-local git config.

```ini
[alias]
    sync = "!f() { git stash push --include-untracked -m 'auto: pre-sync' && git fetch upstream && git rebase upstream/main && git push --force-with-lease origin main && git stash pop; }; f"
    public-branch = "!f() { git fetch upstream && git switch -c \"${1:-feature/public-$(date +%Y%m%d)}\" upstream/main; }; f"
```

| Aspect | Assessment |
|--------|------------|
| Readability | ❌ Low — inline shell in git config is hard to read/debug |
| Testability | ❌ Low — hard to unit test |
| Error handling | ❌ Minimal — no room for verification steps or helpful output |
| Maintenance | Low — single config file |
| Discoverability | ✅ High — `git <tab>` shows available aliases |
| Convenience | ✅ High — `git sync` is very fast to type |

**Conflict with chosen approach:** The sync logic is too complex for an alias (needs
the verify-before-pull-rebase step from pain point #10). Aliases also can't do
`gh pr create` with `--repo` flag easily.

**Verdict:** ⚠️ Considered, not adopted as primary. Could be used for *simple*
operations (e.g., `git s = status -sb`), but complex operations belong in scripts.
If scripts prove stable, thin aliases could be added later as convenience wrappers
(`git sync = "!scripts/sync-from-upstream.sh"`).

---

### 3c. Shell functions in `.bashrc`

**Concept:** Define shell functions like `publish()`, `save()`, `sync()` in the
private `.bashrc`.

| Aspect | Assessment |
|--------|------------|
| Readability | ✅ High — bash functions are readable |
| Testability | ✅ Medium |
| Portability | ❌ Low — only available in interactive shells, not scripts/agents |
| Maintenance | Medium — lives in dotfiles, not repo |

**Conflict with chosen approach:** Functions in `.bashrc` aren't available to
non-interactive contexts (scripts, CI, agent instructions). Scripts under `scripts/`
are universally available.

**Verdict:** ❌ Rejected as primary. Could supplement scripts for interactive
convenience, but scripts are the canonical automation.

---

## 4. Sync Reconciliation Strategies

After `git rebase upstream/main`, private `main` may diverge from `origin/main` due to
hash rewriting. Three strategies for reconciling:

### 4a. Always force-push (`--force-with-lease`)

**Concept:** After rebasing onto `upstream/main`, always force-push to `origin/main`.

| Aspect | Assessment |
|--------|------------|
| Simplicity | ✅ Very simple — one command |
| Safety | ⚠️ Medium — `--force-with-lease` checks for remote changes, but rewrites history |
| Hash stability | ❌ Rewrites `origin/main` hashes every sync |
| Collaborator impact | If others share the private repo, force-push is disruptive |

**Verdict:** ⚠️ Fallback only. Acceptable for solo private repos, but not ideal as a
default because it rewrites history unnecessarily.

---

### 4b. Always `git pull --rebase` after upstream rebase

**Concept:** After `git rebase upstream/main`, run `git pull --rebase` (which rebases
onto `origin/main`). Git's patch-id detection skips already-applied commits.

| Aspect | Assessment |
|--------|------------|
| Simplicity | ✅ Simple — one extra command |
| Hash stability | ✅ Preserves `origin/main` hashes when possible |
| Safety | ⚠️ Risky if `origin/main` has genuinely new commits — could conflict or interleave |
| Collaborator impact | Safe for shared private repos (no force-push) |

**Conflict:** This is pain point #10's discovery. It works when `origin/main` has only
hash-rewritten equivalents, but fails badly if there are real new commits.

**Verdict:** ⚠️ Conditionally adopted. Use only after verifying behind-commits are
equivalents (see 4c).

---

### 4c. Verify first, then decide (chosen)

**Concept:** After `git rebase upstream/main`, check `git log main..origin/main`. If
the behind-commits are hash-rewritten equivalents (verified by patch-id), use
`git pull --rebase`. Otherwise, warn and fall back to `--force-with-lease` or abort.

| Aspect | Assessment |
|--------|------------|
| Simplicity | ❌ Complex — requires patch-id comparison logic |
| Safety | ✅ Highest — never silently picks the wrong strategy |
| Hash stability | ✅ Preserves hashes when safe, rewrites only when necessary |
| Collaborator impact | ✅ Safe for shared private repos |

**Verdict:** ✅ Adopted as the target design. The verification logic is non-trivial
and needs careful implementation in `sync-from-upstream.sh`. The script must fail
loudly if it can't confirm equivalence, rather than silently picking a strategy.

**Implementation note:** Comparing patch-ids of `origin/main`'s behind-commits
against the rebased `main` history:
```bash
# Get patch-ids of commits on origin/main not in main
behind_pids=$(git log --format='%H' main..origin/main | while read sha; do
    git show "$sha" | git patch-id --stable | awk '{print $1}'
done | sort)

# Get patch-ids of all commits in main's history
main_pids=$(git log --format='%H' main | while read sha; do
    git show "$sha" | git patch-id --stable | awk '{print $1}'
done | sort)

# If all behind_pids are in main_pids, they're equivalents → safe to pull --rebase
```

---

## 5. Private Content Protection

### 5a. Pre-push hook scanning for private paths

**Concept:** In `pre-push`, when `remote_name == "upstream"`, check if any pushed file
matches `private|git-private|secret|credential|\.ssh`. Block if so.

| Aspect | Assessment |
|--------|------------|
| Effectiveness | ✅ High — catches accidental `git add private/` before it reaches public |
| False positives | Low — pattern is specific to this repo's layout |
| False negatives | Medium — can't catch private content in public-named files |
| Maintenance | Low — pattern list is stable |

**Verdict:** ✅ Adopted (proposed). Low cost, high value. Belt-and-suspenders check.

---

### 5b. `.gitignore` for private-only paths

**Concept:** Add a `.gitignore` that ignores `git-private/` and `private/` so they
can't be accidentally committed.

| Aspect | Assessment |
|--------|------------|
| On public branch | ❌ Public repo shouldn't have entries for paths that don't exist there |
| On private `main` | ❌ We *want* to track `git-private/` and `private/` in the private repo |
| On public-contribution branches | ⚠️ Could use `.git/info/exclude` (local-only), but doesn't survive across clones |

**Conflict:** The split is repo-level, not branch-level. `.gitignore` is versioned and
can't serve both repos' needs simultaneously.

**Verdict:** ❌ Rejected. Doesn't fit the split-repo model. Rely on pre-push hooks
(5a) and careful `git add` practices instead.

---

### 5c. Patch-ID-based duplicate detection in `pre-push`

**Concept:** In `pre-push`, when pushing to `upstream`, check if any pushed commit also
exists on `origin/main` by patch ID. Warn if so (sync-back may conflict).

| Aspect | Assessment |
|--------|------------|
| Effectiveness | ✅ High — directly detects pain point #4 (duplicate history) |
| Complexity | Medium — requires patch-id comparison logic |
| False positives | Low — patch-id is content-based, not SHA-based |
| Performance | Acceptable — only runs on push, not every commit |

**Verdict:** ✅ Adopted (proposed). High value for preventing the most painful
sync-back conflicts. Implementation can reuse the patch-id logic from sync strategy
4c.

---

## 6. Working Directory Layouts

### 6a. Single clone with both remotes (current)

**Concept:** One working directory with `origin` = private, `upstream` = public.
Switch branches to switch between private and public work.

| Aspect | Assessment |
|--------|------------|
| Disk space | ✅ Minimal — one working tree |
| Mental overhead | ⚠️ High — must track which branch targets which remote |
| Risk of wrong-remote push | Medium (mitigated by hooks and `pushDefault`) |
| Stash friction | Medium — switching between private/public work requires stashing |

**Verdict:** ✅ Current approach. Acceptable with automation (hooks, scripts) to
reduce mental overhead.

---

### 6b. Separate worktree for public work

**Concept:** Use `git worktree add` to create a second working directory rooted at
`upstream/main` for public contributions.

```bash
git worktree add ../wsl-ubuntu-config-public upstream/main
cd ../wsl-ubuntu-config-public
# All work here is public-intended by default
```

| Aspect | Assessment |
|--------|------------|
| Disk space | ✅ Low — worktrees share the same .git directory |
| Mental overhead | ✅ Low — physical separation enforces mental separation |
| Risk of wrong-remote push | ✅ Low — public worktree has no `origin` context by default |
| Stash friction | ✅ None — no need to stash when switching contexts |
| Complexity | Medium — need to manage worktree lifecycle, and hooks/config may behave differently |

**Conflict:** Worktrees share the same `.git` config, so `remote.pushDefault = origin`
still applies. Need to verify that hooks fire correctly in worktrees (they should,
since `core.hooksPath` is repo-level).

**Verdict:** ⚠️ Strong candidate. Could eliminate pain points #2, #3, #6 entirely.
Worth prototyping. If it works well, could become the recommended approach.

---

### 6c. Separate clone for public work

**Concept:** Maintain a completely separate clone of the public repo for public
contributions.

```bash
git clone git@github.com:JAKimball/wsl-ubuntu-config.git ~/projects/systems/wsl-ubuntu-config
# All public work happens here; no private remote configured
```

| Aspect | Assessment |
|--------|------------|
| Disk space | ❌ High — full second clone |
| Mental overhead | ✅ Lowest — no private remote to accidentally push to |
| Risk of wrong-remote push | ✅ None — public clone has no `origin` pointing to private |
| Sync friction | Medium — must pull/push between clones to share work |
| Config duplication | Medium — hooks, scripts must be maintained in both clones |

**Conflict:** Loses the shared `.git` directory benefit of worktrees. Requires
duplicating hooks and config. But the safety benefit is maximal.

**Verdict:** ⚠️ Fallback if worktrees (6b) prove problematic. The safest option, but
the most maintenance-heavy.

---

## 7. Merge Strategy on Public PRs

### 7a. Create a merge commit

**Concept:** Use GitHub's "Create a merge commit" strategy for public PRs.

| Aspect | Assessment |
|--------|------------|
| Commit correspondence | ✅ Preserves — merge commit has ancestry to source branch |
| Sync-back ease | ✅ Git can recognize the merged commits during rebase |
| History cleanliness | ⚠️ Merge commits add noise to linear history |

**Verdict:** ✅ Preferred for this workflow. Best for sync-back reconciliation.

---

### 7b. Rebase and merge

**Concept:** Use GitHub's "Rebase and merge" strategy.

| Aspect | Assessment |
|--------|------------|
| Commit correspondence | ⚠️ Partial — commits are rebased onto `upstream/main`, SHAs change but content preserved |
| Sync-back ease | ⚠️ Medium — patch-id detection may help, but SHAs differ |
| History cleanliness | ✅ Linear history |

**Verdict:** ⚠️ Acceptable. Better than squash for sync-back, but not as clean as merge
commit for reconciliation.

---

### 7c. Squash and merge

**Concept:** Use GitHub's "Squash and merge" strategy (often the GitHub default).

| Aspect | Assessment |
|--------|------------|
| Commit correspondence | ❌ Destroys — single new commit, no ancestry to source |
| Sync-back ease | ❌ Worst — Git sees unrelated commits with similar content → conflicts |
| History cleanliness | ✅ Cleanest — one commit per PR |

**Conflict:** Directly causes pain point #5. When the same change exists on private
`main`, squash merge makes sync-back extremely conflict-prone.

**Verdict:** ❌ Discouraged. If used, treat `upstream/main` as canonical and rebuild
private `main` from it rather than trying to reconcile. Consider disabling squash
merge in public repo settings.

---

## 8. Backup and Recovery Refs

### 8a. Branches for backups (current ad-hoc approach)

**Concept:** Create branches like `backup/main-before-resync`, `rewrite/upstream-main`
for recovery.

| Aspect | Assessment |
|--------|------------|
| Visibility | ❌ Clutters `git branch -vv` output |
| Clarity | ⚠️ Ambiguous — looks like active branches |
| Cleanup | Manual — no routine |

**Verdict:** ⚠️ Current approach, but should be improved.

---

### 8b. Tags for backups

**Concept:** Use `git tag backup/<description>` instead of branches.

| Aspect | Assessment |
|--------|------------|
| Visibility | ✅ Tags are clearly separate from branches in `git tag` output |
| Clarity | ✅ Tags are point-in-time markers, not working branches |
| Cleanup | ✅ `git tag -d` is straightforward |
| Risk | ✅ Tags can't be accidentally committed to |

**Verdict:** ✅ Preferred going forward. Use tags for point-in-time backups; reserve
branches for active rewrite work (`rewrite/*`).

---

### 8c. Automated cleanup script

**Concept:** `scripts/cleanup-branches.sh` that lists and optionally deletes
`backup/*`, `rewrite/*`, and `template` branches after confirmation.

| Aspect | Assessment |
|--------|------------|
| Friction | Low — one command to review and clean |
| Safety | Medium — confirmation prompt prevents accidental deletion |
| Maintenance | Low |

**Verdict:** ✅ Adopted (proposed). Complements the tag-based backup approach (8b).

---

## Summary of Decisions

| Area | Chosen Approach | Rejected Alternatives |
|------|----------------|----------------------|
| Repo architecture | Two repos, shared history (1c) | Single repo branch-based (1a, 1b), independent repos (1d) |
| Public branching | Fresh `public/*` from `upstream/main` (2b) | Long-lived `public` branch (2a), cherry-pick from `main` (2c) |
| Automation delivery | Wrapper scripts (3a) | Git aliases for complex logic (3b), shell functions (3c) |
| Sync reconciliation | Verify first, then decide (4c) | Always force-push (4a), always pull-rebase (4b) |
| Private content protection | Pre-push path scan (5a) + patch-ID detection (5c) | `.gitignore` for private paths (5b) |
| Working directory | Single clone (6a), worktree (6b) under consideration | Separate clone (6c) as fallback |
| Merge strategy | Create a merge commit (7a) | Squash and merge (7c) |
| Backup refs | Tags (8b) + cleanup script (8c) | Ad-hoc branches (8a) |
