# Understanding `pull.rebase = true` in Git

## What does `pull.rebase = true` do?

When you set:

```ini
[pull]
    rebase = true
```

in your `.gitconfig`, running `git pull` will use **rebase** instead of the default **merge** to integrate upstream changes into your current branch.

---

## How does it change your workflow?

**Default (merge):**
- `git pull` = `git fetch` + `git merge`
- Merges upstream changes into your branch, possibly creating a merge commit.

**With rebase:**
- `git pull` = `git fetch` + `git rebase`
- Re-applies your local commits on top of the updated upstream branch, creating a linear history.

---

## Visual Example

**Without rebase (merge):**
```
A---B---C (origin/main)
     \
      D---E (your local commits)
           \
            F (merge commit created by pull)
```

**With rebase (linear history):**
```
A---B---C---D'---E' (origin/main with your commits replayed on top)
```

---

## Timestamps: Author vs. Committer

- **Author timestamp**: When you originally made the commit (preserved during rebase)
- **Committer timestamp**: When the commit was applied to the branch (updated to the rebase time)

After a rebase, your commits keep their original author date, but the committer date is set to when the rebase happened.

---

## Benefits of `pull.rebase = true`

- **Cleaner history**: No unnecessary merge commits
- **Linear timeline**: Easier to follow project progression
- **Simpler `git log`**: More readable commit history
- **Preserves authorship**: Your original commit times are kept

---

## Potential Complications

- **Conflicts**: You may need to resolve conflicts for each commit being replayed
- **Rewriting history**: Your commit SHAs will change (important if you have already pushed your commits)

---

## Recommended Workflow with Rebase

1. Make and commit your changes locally
2. Run `git pull` (which rebases your work on top of upstream)
3. Resolve any conflicts and continue the rebase if needed
4. Re-test your code
5. Push your changes

### Traditional Workflow (Merge-based)
```bash
git pull              # fetch + merge (creates merge commits)
# resolve conflicts if needed
# re-test changes
git add .
git commit -m "message"
git push
```

### Rebase Workflow
```bash
git add .
git commit -m "message"    # Commit your work first
git pull                   # fetch + rebase (linear history)
# resolve conflicts if needed, git rebase --continue
# re-test if needed
git push
```

### Why commit first with rebase?
- **Cleaner conflict resolution** - Each of your commits is replayed individually
- **Preserves your work** - Your commits are safe even if rebase has issues
- **Better history** - No unnecessary merge commits from pulls

### Team-dependent variations:
- **Feature branches**: Create branches for features, PR/MR to main
- **Squash commits**: Some teams prefer squashing before merge
- **No-rebase teams**: Some prefer preserve exact merge history

---

## Summary

Setting `pull.rebase = true` helps keep your project history clean and linear, making collaboration and code review easier. It is a common best practice for teams that want to avoid unnecessary merge commits and maintain a straightforward commit timeline.
