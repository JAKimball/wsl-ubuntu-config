# Lessons Learned Addendum 1

> Temporary scratchpad from one chat session.
> Capture pain points, mistakes, recovery steps, and candidate workflow improvements.
> Merge later with findings from other sessions before updating `WORKFLOW.md` and any agent instructions.

## Scope Of This Addendum

This session focused on the split-repo workflow between:

- `wsl-ubuntu-config` as the public repo
- `wsl-ubuntu-config-private` as the private repo

It surfaced several failure modes around branch tracking, default push behavior, publishing public-safe changes, and recovering from history mistakes.

## Pain Points Observed

### 1. Tracking configuration was easy to misread

- Local `main` in the private clone was, at one point, tracking `upstream/main` instead of `origin/main`.
- That meant plain `git push` from `main` targeted the public repo.
- This was not obvious from everyday usage unless `git branch -vv` or `.git/config` was inspected directly.

### 2. `git push` defaulted to the wrong remote for the task at hand

- After adding `remote.pushDefault = origin`, plain `git push` became safer for private work.
- But this also meant a public-update branch created from `upstream/main` could still be pushed to `origin` by mistake if the remote was omitted.
- The cognitive load is high: branch ancestry and push destination are separate concerns.

### 3. Public-safe changes were duplicated across histories

- Public-safe changes were first committed on private `main`.
- Then they were cherry-picked onto a branch from `upstream/main`.
- That produced two distinct commits with overlapping content.
- Once the public PR was merged, syncing back into private became conflict-prone.

### 4. Squash merge amplified the duplicate-history problem

- A public PR built from cherry-picked content was squash-merged.
- The resulting commit on `upstream/main` had no one-to-one correspondence with the private-side commit.
- Git could no longer easily recognize the changes as equivalent during sync.

### 5. Merge commit to the wrong remote created cleanup work

- A docs branch intended for upstream was pushed to `origin` instead.
- A PR was then opened and merged on the private repo by mistake.
- This added unwanted public-safe docs history to `origin/main`, which then had to be separated back out.

### 6. Feature branches tracking `upstream/main` can look "mysteriously" ahead/behind

- A local feature branch based on `upstream/main` showed `ahead 1, behind 1` after the public PR merged.
- The reason was that the branch still tracked `upstream/main`, and the merged commit on `upstream/main` was a different commit object from the local branch commit.
- This was correct Git behavior, but not intuitive at first glance.

### 7. Branch clutter accumulated during recovery

- Recovery created temporary branches such as:
  - `backup/*`
  - `rewrite/*`
  - `public/*`
  - `template`
- These were useful safety rails, but they also made `git branch -vv` harder to scan.

## Specific Mistakes Made

### A. Assuming clone/rename/add-remote bootstrap automatically made `main` safe

- It did not.
- After `git remote rename origin upstream` and `git remote add origin ...private...`, local `main` could still track `upstream/main`.
- The fix was to explicitly run:

```bash
git branch --set-upstream-to=origin/main main
```

### B. Treating cherry-pick as a general-purpose publication mechanism

- Cherry-pick is mechanically valid, but it is not the safest default when the same change already exists on private `main`.
- It is better treated as an exception, not the normal path.

### C. Using squash merge for work that already existed in sibling history

- Squash merge was a poor fit once the same public-safe content already existed in private history.
- It erased commit correspondence and made later reconciliation harder.

### D. Forgetting that plain `git push` follows push configuration, not branch ancestry

- Branch created from `upstream/main` does not imply pushes go to `upstream`.
- With `remote.pushDefault = origin`, plain `git push` still targets the private repo unless the remote is named explicitly.

### E. Opening and merging a PR before confirming which repo the branch lived in

- The push output link was followed without confirming whether the PR target repo was public or private.
- This turned a minor push mistake into a history cleanup task.

## Recovery Strategies That Worked

### 1. Explicitly reset private `main` to the intended private-only state

- After an accidental merge on `origin/main`, private history was cleaned by resetting back to the intended private-only commit and force-pushing with lease.
- Backup branches/tags were created first.

### 2. Recreate the intended public change on a clean branch from `upstream/main`

- Instead of trying to salvage the mistaken private PR branch, the intended docs changes were restored onto a fresh branch from `upstream/main`.
- That produced a clean public PR branch with no accidental private history.

### 3. Treat `upstream/main` as canonical after public merges

- Once a public PR is merged, `upstream/main` should be treated as the source of truth for public content.
- Private history should be rebased onto it, or rebuilt from it, rather than trying to preserve duplicate public-safe commits on private `main`.

### 4. Keep backup branches during risky history operations

- Recovery was much safer because backup branches existed for:
  - pre-rewrite states
  - mistaken merges
  - prior public/private main tips

### 5. Use file-based publication when content already exists on private `main`

- Safer pattern:

```bash
git fetch upstream
git switch -c feature/publish-safe upstream/main
git restore -s main -- path/to/file1 path/to/file2
git add path/to/file1 path/to/file2
git commit -m "docs: publish selected files"
git push upstream feature/publish-safe
```

- This avoids creating a second commit for the same logical change.

## Clarified Workflow Guidance

### Recommended default split

- Private-only work belongs on private `main`.
- Public-intended work should start on a branch from `upstream/main`.
- If public-safe content already exists on private `main`, publish it by restoring specific paths onto a branch from `upstream/main`.
- Only cherry-pick when the commit will not also remain as the long-term copy on private `main`, or when the private-side duplicate will be intentionally dropped later.

### Recommended sync-back model

- After public PR merges, treat `upstream/main` as canonical.
- Sync private with:

```bash
git switch main
git fetch upstream
git rebase upstream/main
git push origin main
```

- If the private branch contains an obsolete duplicate of public-safe work, drop or rebuild that duplicate rather than merging both copies.

## Candidate Improvements To Brainstorm

### A. Dedicated public work branch or worktree

Possibilities:

- Long-lived local branch such as `public/main` tracking `upstream/main`
- Separate worktree rooted at `upstream/main`
- Separate clone for public work only

Why this may help:

- Stronger mental separation between private work and public work
- Lower chance of pushing public-intended branches to `origin`
- Easier to reason about what belongs where

Open question:

- Is a second worktree or second clone simpler in practice than trying to make one clone carry both roles?

### B. Push helpers that require explicit intent

Potential helper scripts or aliases:

- `scripts/new-public-branch.sh`
  - create branch from `upstream/main`
  - set a clear name
  - print reminder that pushes to upstream must be explicit
- `scripts/push-public.sh`
  - push current branch to `upstream`
  - show target repo before pushing
- `scripts/sync-private-main.sh`
  - fetch upstream
  - rebase private main
  - push origin

### C. Stronger hooks

Potential safeguards:

- Pre-push hook that blocks pushes to `origin` for branches named `public/*`
- Pre-push hook that blocks pushes to `upstream` if paths like `private/` or `git-private/` appear in the pushed range
- Pre-commit or pre-push warning when current branch tracks `upstream/main` but push default is `origin`
- Pre-push confirmation message showing resolved remote URL and branch target

### D. Branch naming conventions with policy attached

Candidate policy:

- `main` = private integration branch
- `public/*` = public-intended branches created from `upstream/main`
- `private/*` = private-only feature branches

Potential automation:

- If branch name matches `public/*`, require explicit `git push upstream <branch>`
- If branch name matches `public/*`, block pushes to `origin`

### E. PR checklist before merge

Short checklist that might have prevented multiple mistakes:

1. Which remote hosts this branch?
2. Which repo will the PR be opened against?
3. Did this work already exist on private `main`?
4. If yes, am I publishing by file-restore rather than cherry-pick?
5. If using cherry-pick anyway, do I intend to drop the private-side duplicate later?
6. Is merge strategy appropriate for the branch history?

## Questions To Revisit Later

- Should public-intended work always happen in a separate worktree or clone?
- Should `public/*` branches automatically track `upstream/<branch>` instead of `upstream/main` after first push?
- Should the repo-local Git config include aliases for public publishing and private syncing?
- Should the hooks become stricter, even at the cost of more friction?
- Which backup/rewrite branches should be retained, and which should be cleaned up after each successful recovery?

## Summary Of The Biggest Lessons

- In a split public/private workflow, identical content in two different histories is where complexity starts.
- The safest default is public-first branching from `upstream/main` for anything intended to be shared.
- If public-safe content already exists on private `main`, publish file state, not commit identity.
- Plain `git push` is only safe when the local config and branch policy make the destination obvious.
- Recovery is manageable when backups are cheap and `upstream/main` is treated as canonical public history.