---
name: sei-resolve-squash-conflicts
description: "Resolve the conflicts of an in-progress merge on a stacked PR branch whose former base branch was squash-merged into the merge target. Takes the number of the squash-merged PR, stages the resolution without concluding the merge, and summarizes how each conflict was resolved."
disable-model-invocation: true
argument-hint: "<old_pr>"
arguments: [old_pr]
allowed-tools: Bash Read Write Edit Grep
---

## Arguments

| Variable | Description |
|----------|-------------|
| `$old_pr` | Number of the squash-merged PR whose head branch was this branch's former base. A positive integer, no `#`. |

**`$old_pr` is required.** If missing, stop and tell the user before doing anything else.

## Background

The current branch (call it the *stacked branch*) was branched from the head branch of PR
`$old_pr` (the *old base*) and carries the original, unsquashed old-base commits plus its own
commits. PR `$old_pr` has since been squash-merged into the merge target, its branch deleted,
and the user has started `git merge <target>` locally. Git sees the original old-base commits
and the squash commit as unrelated changes to the same lines, which produces the conflicts.

In this merge:

- `HEAD` ("ours") — the stacked branch: original old-base content + the stacked branch's own changes.
- `MERGE_HEAD` ("theirs") — the target: the squash commit of PR `$old_pr` (including any changes
  pushed to the old base after the stacked branch forked from it, e.g. review fixes) + unrelated
  changes merged by others.

`OLD_TIP` is PR `$old_pr`'s final head; `BASE` is the last old-base commit the stacked branch
contains. The stacked branch's **own changes** — the only thing it should add on top of
`MERGE_HEAD` — are `git diff $BASE HEAD`.

## Hard constraints — apply for the entire duration of this skill

- The user grants `git add <path>` for this skill: stage each path once it is resolved —
  including deleted paths, since `git add` on a removed path stages the deletion — and re-stage
  it after any later fix. Never run `git merge --continue`, `git commit`, or any other
  state-changing git command; concluding the merge is the user's job.
- Do not use `git stash` during this skill, despite the global exception: stashing mid-merge
  removes `MERGE_HEAD` and silently ends the merge.
- To take one side's version of a file, write it out with `git cat-file --filters :2:<path>`
  (ours) or `git cat-file --filters :3:<path>` (theirs) redirected into the file. Do not use
  `git show` for this: it prints the raw blob and skips checkout filters (Git LFS smudge, eol
  conversion, `ident`, `working-tree-encoding`).
- Resolve conflicts only. Do not refactor, reformat, or "improve" code while resolving.

## Pre-flight check

Run via `Bash`:

```
${CLAUDE_SKILL_DIR}/scripts/preflight "$old_pr"
```

Continue only if the first line of stdout is exactly `PREFLIGHT: PASS`; take `OLD_TIP`, `BASE`,
`FETCHED`, and the stacked branch's own commits (`OWN_COMMITS:`) from the lines that follow. On
anything else — a `PREFLIGHT: FAIL …` line, an `ERROR: …` message, or empty stdout — stop
immediately and relay the output verbatim to the user; if stdout is empty, include any stderr.
If the error indicates an authentication failure, also ask the user to authenticate.

## Process

1. **Inventory.** List conflicted paths with `git diff --name-only --diff-filter=U`, and note
   each one's conflict kind from `git status --porcelain` (content, modify/delete, add/add,
   rename). Re-running `git diff --name-only --diff-filter=U` at any point lists what is still
   unresolved; resolution is complete when it is empty.
2. **Resolve each conflicted path**, using `MERGE_HEAD` as the starting point:
   - Look at the stacked branch's own change to that path: `git diff "$BASE" HEAD -- <path>`.
   - If the stacked branch did not change the path, the conflict is purely original-vs-squashed
     old-base content: take `MERGE_HEAD`'s version (`git cat-file --filters :3:<path> > <path>`).
   - Otherwise, start from `MERGE_HEAD`'s version and re-apply only the stacked branch's own
     hunks on top of it.
   - If a stacked-branch hunk touches code that `MERGE_HEAD` changed in a different way (e.g.
     review fixes pushed to the old base after the fork — `git log --oneline "$BASE..$OLD_TIP"`
     lists them), merge the intent of both and record it as a **judgment call** for the summary.
   - modify/delete, `MERGE_HEAD` deleted the file: if the stacked branch made no own changes to
     it, delete it; otherwise keep the file and record a judgment call.
   - modify/delete, `HEAD` deleted the file:
     - If the deletion is the stacked branch's own change (it appears in
       `git diff "$BASE" HEAD -- <path>`), delete it. If `MERGE_HEAD`'s version also differs
       from `OLD_TIP`'s (changes from others), record a judgment call.
     - Otherwise the deletion came from the original old-base commits, yet `MERGE_HEAD` still
       has the file (e.g. a review fix restored it, or the squash kept it). Take `MERGE_HEAD`'s
       version, since the target is authoritative for old-base content. If `OLD_TIP` has no
       such file or its version differs from `MERGE_HEAD`'s, record a judgment call.
   - Before staging the path, grep it for `^(<<<<<<<|\|\|\|\|\|\|\||=======|>>>>>>>)( |$)`; it
     must contain no conflict markers. Then `git add <path>`.
3. **No leftover markers or stray edits.** `git diff --cached --check MERGE_HEAD` must report no
   `leftover conflict marker` lines, and `git diff` (working tree vs. index) must be empty —
   anything there is an unstaged edit that the merge would not include. `--check` also reports
   whitespace errors and exits non-zero for them. Those come from the stacked branch's own
   content: they do not block, so leave them as they are.
4. **Verify the stacked branch's own changes survived.** Compare:
   - expected: `git diff "$BASE" HEAD`
   - actual: `git diff --cached MERGE_HEAD` (target vs. what `git merge --continue` will commit)

   Every hunk in *expected* should appear in *actual*, and every hunk in *actual* should trace
   back to *expected*. Investigate each mismatch — including in auto-merged files that never
   conflicted (a typical one: old-base code that a review fix later removed, resurrected by an
   auto-merge). Acceptable mismatches are those caused by `MERGE_HEAD` having changed the
   surrounding code, or by an *expected* hunk that `MERGE_HEAD` already contains (e.g. the
   stacked branch had earlier merged the target) — record them; anything else is a resolution
   mistake — fix it, re-stage, and re-check from step 3.
5. **Run the project's checks.** Look for the project's own lint, typecheck, and test commands
   (e.g. in `CLAUDE.md`, `README`, `Makefile`, `package.json`, `pyproject.toml` task runners)
   and run them, including the full test suite. Use check-only modes (no `--fix`, `--write`,
   etc.); the checks must leave `git diff` empty. For each failure, determine whether it stems
   from the resolution — if so, fix the resolution, re-stage, re-run steps 3–4, and re-run the
   checks. Do not check out, stash, or create worktrees to compare against `MERGE_HEAD` or
   `HEAD`; judge by reasoning instead. A failure is unrelated if it lies in code that neither
   the stacked branch's own changes, the conflicted paths, nor the step 4 mismatches touch, or
   if it needs an unavailable service — leave it and report it with that reasoning. If
   no checks can be found, or a check cannot be run, say so in the summary rather than
   working around it.

## Final summary

Report to the user:

- PR `$old_pr`, `OLD_TIP` and `BASE` (short SHAs), whether the fetch was needed, and the
  stacked branch's own commits.
- One line per conflicted path: the conflict kind and how it was resolved (took target's
  version / re-applied own hunks / deleted / ...).
- Every **judgment call**, with what each side had and what was chosen and why.
- The result of the step 4 verification, listing any accepted mismatches.
- The step 5 results: each check run and its outcome, any failures judged unrelated to the
  resolution and the reasoning behind each, and any check that could not be found or run.
- A reminder that the resolution is fully staged but the merge is not concluded: the user should
  review (e.g. `git diff --cached MERGE_HEAD`) and run `git merge --continue`.
