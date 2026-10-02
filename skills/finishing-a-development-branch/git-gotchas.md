# Git Gotchas

**Load this reference when:** a branch untracks files (`git rm --cached`), a commit needs a multi-line message, or history needs repair.

## Untracked files vanish on a later checkout or merge

- **Symptom:** files removed with `git rm --cached` survive the commit, then disappear after a branch switch, merge or pull — and `git status` stays clean.
- **Cause:** `git rm --cached` keeps the file on disk only at that moment. Any checkout, merge or pull that moves the working tree from a commit where the path is tracked to one where it isn't deletes the file, like any upstream deletion; `git worktree remove` deletes ignored files along with the worktree.
- **Fix:** copy the files outside the repository before committing the removal. After the integration finishes (every checkout, merge, pull and `git worktree remove`), compare each file with its outside copy (`cmp`); checking that it exists is not enough. A committed ignore pattern does not prevent the deletion. It also makes a checkout of a branch that still tracks the path overwrite the file silently instead of refusing, and it stops Step 6's `git worktree remove` from refusing over these files.

## A failed `&&` chain leaves history half-repaired

- **Symptom:** a history repair chained with `&&` (detach, cherry-pick, amend, move the branch) fails midway; HEAD is detached and the working tree sits several commits back.
- **Cause:** `&&` stops at the first failure but keeps every step before it — an unknown prefix of the sequence has been applied.
- **Fix:** create a backup ref first (`git branch <branch>-backup <branch>`), then run one state-changing git command per call and check each result before the next, then re-read every rewritten commit's message in a separate call.

## A multi-line commit message stored wrong

- **Symptom:** the stored subject is a literal fragment such as `$(cat <<'EOF'` and the body is gone, though the commit call's output looked right.
- **Cause:** a heredoc or `$(...)` interpolated into `-m` didn't expand in the shell that ran it; a read chained into the same call is not independent evidence.
- **Fix:** write the message to a file, commit with `git commit -F <file>` (for a PR body, `gh pr create --body-file <file>`), then verify in a separate call with `git log -1 --format=%B`.
