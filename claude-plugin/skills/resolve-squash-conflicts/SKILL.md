---
name: resolve-squash-conflicts
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
- Do not use `git stash` during this skill, even if other instructions allow it: stashing
  mid-merge removes `MERGE_HEAD` and silently ends the merge.
- To take one side's version of a file, write it out with `git cat-file --filters :2:<path>`
  (ours) or `git cat-file --filters :3:<path>` (theirs) redirected into the file; for a path
  without conflict stages, use `HEAD:<path>`, `MERGE_HEAD:<path>` or `:<path>` (the index). Do
  not use `git show` for this: it prints the raw blob and skips checkout filters (Git LFS
  smudge, eol conversion, `ident`, `working-tree-encoding`).
- Resolve conflicts only. Do not refactor, reformat, or "improve" code while resolving. The one
  exception is step 4: extending the stacked branch's own renames and removals to the target's
  new code.
- A file may be resolved by a small inline script (e.g. one that picks a side per conflict block
  and applies a substitution), not only by hand edits; the conflict-marker grep before staging
  still applies.

## Pre-flight check

Run via `Bash`:

```
${CLAUDE_SKILL_DIR}/scripts/preflight "$old_pr"
```

Continue only if the first line of stdout is exactly `PREFLIGHT: PASS`; take `OLD_TIP`, `BASE`,
`FETCHED`, the stacked branch's own commits (`OWN_COMMITS:`), and the paths the target changed
since `BASE` (`TARGET_CHANGES:`, `git diff --name-status` format) from the lines that follow. On
anything else — a `PREFLIGHT: FAIL …` line, an `ERROR: …` message, or empty stdout — stop
immediately and relay the output verbatim to the user; if stdout is empty, include any stderr.
If the error indicates an authentication failure, also ask the user to authenticate.

## Process

After each step, print one line of progress (e.g.
`Step 2 done: 4 auto-merged paths differed, kept merge-on-base for 3`).

1. **Inventory.** Run `${CLAUDE_SKILL_DIR}/scripts/inventory "$BASE"`. It prints
   `INVENTORY: <n>` followed by one `<action>\t<xy>\town=<yes|no>\ttarget=<yes|no>\t<path>`
   line per conflicted path: `<xy>` is its `git status --porcelain` code (`UU` content, `AA`
   add/add, `UD`/`DU` modify/delete, ...), `own` says whether the stacked branch changed the
   path since `BASE`, `target` whether the target did, and `<action>` is the resolution step 3's
   rules suggest (`take-theirs`, `take-ours`, `delete`, `lockfile`, `merge-on-base` or
   `modify-delete`). A `DD` path next to `AU`/`UA` paths is usually a rename/rename conflict
   (each side renamed the same file differently): taking every suggested action would keep both
   renamed copies, so decide the group together.
   On `ERROR: …`, list the conflicted paths with `git diff --name-only --diff-filter=U` and note
   each one's conflict kind from `git status --porcelain` instead. Re-running
   `git diff --name-only --diff-filter=U` at any point lists what is still unresolved;
   resolution is complete when it is empty. If `CLAUDE.md`, `AGENTS.md` or a file one of them
   links to is conflicted, the copy loaded at session start contains both sides' text and
   conflict markers: do not rely on its conflicted parts.
2. **Re-merge auto-merged paths.** Git merged the paths that did not conflict against the same
   wrong ancestor, so a clean auto-merge can still be wrong: e.g. it duplicates a block the
   stacked branch moved, or resurrects old-base code that a review fix removed — also in paths
   the stacked branch never changed. Run `${CLAUDE_SKILL_DIR}/scripts/remerge-auto "$BASE"`
   now, before any conflicted path is resolved, and only once: it skips paths with unmerged
   index entries, so a conflicted path staged earlier would be re-merged over its resolution.
   It runs `merge-on-base` on every other path either side changed since `BASE`, stages
   nothing, and prints `REMERGE: <checked> checked, <listed> listed` followed by one line per
   path that needs you:
   - `differs\t<path>` (clean, but not Git's result) or `conflicts\t<path>\t<n>`: read
     `git diff -- <path>` and keep the `merge-on-base` result unless that diff shows Git's was
     right; to keep Git's result instead, restore it from the index with
     `git cat-file --filters :<path> > <path>`, or, if the index lacks the path (Git's
     auto-merge deleted it), remove the file. Resolve any conflict blocks as in step 3, grep
     for conflict markers, stage the path, and record a judgment call.
   - `lockfile\t<path>`: a generated lockfile both sides changed; handle it with step 3's
     lockfile rule.
   - `dirty\t<path>`: the working tree already differed from the index, so the path was left
     alone; inspect it and decide by hand.
   - `error\t<path>\t<reason>`: `merge-on-base` left the file untouched; step 6 checks it.
3. **Resolve each conflicted path.** If `CLAUDE.md`, `AGENTS.md` or a file one of them links to
   is conflicted, resolve it before the other conflicted paths and re-read the resolved version.
   Each path's `<action>` from step 1 is the starting point; the bullets below are the rules
   behind it.
   - If the stacked branch did not change the path (`own=no`), the conflict is purely
     original-vs-squashed old-base content: take `MERGE_HEAD`'s version
     (`git cat-file --filters :3:<path> > <path>`).
   - If both sides have the file and the target did not change it since `BASE` (`target=no`),
     `HEAD`'s version is already `BASE` + own changes: take it
     (`git cat-file --filters :2:<path> > <path>`).
   - If neither `HEAD` nor `MERGE_HEAD` has the path (`DD`, both deleted it), delete it.
   - If the path is a generated lockfile (e.g. `uv.lock`, `package-lock.json`, `poetry.lock`,
     `Cargo.lock`) and both sides changed it, do not merge its hunks. Take `MERGE_HEAD`'s version,
     resolve the manifests it is generated from first, then regenerate it with the project's lock
     command in its minimal-update form, which keeps existing pins and only resolves what the
     manifests changed: e.g. `uv lock`, `npm install --package-lock-only`, `poetry lock`
     (Poetry 2.0+; `poetry lock --no-update` on 1.x), `cargo update --workspace`. Never use a
     form that re-resolves everything (`poetry lock --regenerate`, `cargo generate-lockfile`,
     `uv lock --upgrade`). Record a judgment call. If regeneration fails (e.g. no network),
     keep `MERGE_HEAD`'s version, stage it, and continue; record the failure, with its error
     and the lock command to run, for the final summary.
   - Otherwise, run `${CLAUDE_SKILL_DIR}/scripts/merge-on-base "$BASE" <path>`. It redoes the
     three-way merge with `BASE` as the ancestor, so it merges only the stacked branch's own
     changes and the target's changes since `BASE`, and writes the result over the path. It
     prints `MERGE: CLEAN`, `MERGE: CONFLICTS <n>` (diff3 blocks remain where both sides
     changed the same lines, in Git's order: `<<<<<<< HEAD`, `||||||| BASE`, `=======`,
     `>>>>>>> MERGE_HEAD`), or `ERROR: …`. It resolves a change only one side made since
     `BASE` itself (also for a binary file, a deletion, or a file only one side added), so it
     errors only on a real modify/delete, a binary file both sides changed differently since
     `BASE`, or a path that is not a regular file. On an error, start from `MERGE_HEAD`'s
     version and re-apply the stacked branch's own hunks by hand. Do not use
     `git apply --3way`: it rejects paths with unmerged index entries.
   - If a stacked-branch hunk touches code that `MERGE_HEAD` changed in a different way (each
     conflict block `merge-on-base` leaves is one; review fixes pushed to the old base after the
     fork are typical — `git log --oneline "$BASE..$OLD_TIP"` lists them), merge the intent of
     both and record it as a **judgment call** for the summary.
   - If the target changed code that the stacked branch's own changes delete or replace (e.g. a
     review fix to a function the stacked branch removed), keep the deletion: do not bring the
     code back to carry the change. Record a judgment call that names the target's change (its
     commit in `git log --oneline "$BASE..$OLD_TIP"`, if it is one) and says whether the stacked
     branch's replacement code addresses the concern that change fixed. Read the replacement to
     decide; do not assume. If it does not, or you cannot tell, flag it as an open question in
     the summary rather than fixing it.
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
4. **Extend own renames and removals to the target's new code.** If the stacked branch's own
   changes include a rename, a library or API migration, or another mechanical replacement
   applied across the codebase (e.g. `import httpx` → `import httpx2`, a renamed function or
   test, or a Helm template block pattern rewritten in every template, such as
   `{{- with (include "x.env" .) }}` → `{{- $env := include "x.env" . }}`), or remove a
   function, class, module or other symbol, the target may have added new uses of the old
   form — e.g. a test for a review fix to removed code — both in conflicted paths and in
   auto-merged ones that no conflict flagged. Grep the working-tree version of every path in
   `TARGET_CHANGES` (skip deleted ones) for the old or removed symbols, module names and
   identifiers, including in comments and docstrings. Apply the same replacement to each
   target-introduced occurrence of a renamed or migrated form. Drop a target-introduced use of a
   removed symbol, or switch it to the replacement when that is mechanical, and record it under
   step 3's removed-code judgment call. Re-stage each path and record each change as a judgment
   call. Skip this step if the own changes contain no such rename, migration or removal.
5. **No leftover markers or stray edits.** `git diff --cached --check MERGE_HEAD` must report no
   `leftover conflict marker` lines, and `git diff` (working tree vs. index) must be empty —
   anything there is an unstaged edit that the merge would not include. `--check` also reports
   whitespace errors and exits non-zero for them. Those come from the stacked branch's own
   content: they do not block, so leave them as they are.
6. **Verify the stacked branch's own changes survived.** Compare:
   - expected: `git diff "$BASE" HEAD`
   - actual: `git diff --cached MERGE_HEAD` (target vs. what `git merge --continue` will commit)

   Run `${CLAUDE_SKILL_DIR}/scripts/verify-own-changes "$BASE"`. It prints `VERIFY: MATCH`, or
   `VERIFY: MISMATCH` followed by one `<kind>\t<staged>\t<path>` line per path where the two
   diffs differ, or `ERROR: …` — on an error, fall back to comparing the two diffs directly.
   `<kind>` is `only-expected`, `only-actual`, `differs` or `binary-differs` (run the script
   with `-h` for their meaning). It compares changed lines together with one line of context,
   so a hunk that landed in the wrong place is reported as `differs`, and so is a hunk next to a
   line `MERGE_HEAD` changed. A `binary-differs` path is a binary file whose staged blob is not
   `HEAD`'s, i.e. the stacked branch's version of it was not kept. `<staged>` triages the rest:
   - `=both`: `HEAD` and `MERGE_HEAD` have the same version and it is staged, so nothing was
     dropped: `MERGE_HEAD` already contains the own changes (e.g. the stacked branch had earlier
     merged the target). Accept it.
   - `=HEAD`: the staged file is `HEAD`'s, so every target change to it since `BASE` was
     dropped. Accept it only when each dropped change is a judgment call from step 2, 3 or 4;
     `git diff "$BASE" MERGE_HEAD -- <path>` lists them. For an `only-actual` path (the stacked
     branch did not change it), this is old-base content the target changed or removed since
     `BASE`: take `MERGE_HEAD`'s version.
   - `=MERGE_HEAD`: every own change to the path was dropped. Accept it only when `MERGE_HEAD`
     already contains them; otherwise it is a resolution mistake.
   - `mixed`: compare `git diff "$BASE" HEAD -- <path>` with
     `git diff --cached MERGE_HEAD -- <path>`.

   Every hunk in *expected* should appear in *actual*, and every hunk in *actual* should trace
   back to *expected*. Investigate each mismatch — including in auto-merged files that never
   conflicted (a typical one: old-base code that a review fix later removed, resurrected by an
   auto-merge). Acceptable mismatches are those caused by `MERGE_HEAD` having changed the
   surrounding code, or by an *expected* hunk that `MERGE_HEAD` already contains (e.g. the
   stacked branch had earlier merged the target), by a regenerated lockfile (or one left at
   `MERGE_HEAD`'s version because regeneration failed), by a step 4 extension, or by a dropped
   target change recorded in step 3 — record them; anything else is a resolution mistake — fix
   it, re-stage, and re-check from step 5.
7. **Run the project's checks.** Look for the project's own lint, typecheck, and test commands
   (e.g. in `CLAUDE.md`, `README`, `Makefile`, `package.json`, `pyproject.toml` task runners)
   and run them, including the full test suite. Use check-only modes (no `--fix`, `--write`,
   etc.); the checks must leave `git diff` empty. For each failure, determine whether it stems
   from the resolution — if so, fix the resolution, re-stage, re-run steps 5–6, and re-run the
   checks. Do not check out, stash, or create worktrees to compare against `MERGE_HEAD` or
   `HEAD`; judge by reasoning instead. A failure is unrelated if it lies in code that neither
   the stacked branch's own changes, the conflicted paths, nor the step 6 mismatches touch, or
   if it needs an unavailable service — leave it and report it with that reasoning. If
   no checks can be found, or a check cannot be run, say so in the summary rather than
   working around it. When a composite check (a task sequence, a `Makefile` target that runs
   several tools) aborts on a missing tool, run its remaining sub-checks that do not need that
   tool, and report the missing tool and the sub-checks that did not run. A check that needs
   network access or downloads (e.g. `terraform init`, plugin installs) is optional: skip it and
   report it, saying whether the resolution touched any file it covers.

## Final summary

Report to the user:

- PR `$old_pr`, `OLD_TIP` and `BASE` (short SHAs), whether the fetch was needed, and the
  stacked branch's own commits.
- One line per conflicted path: the conflict kind and how it was resolved (took target's
  version / took ours (target unchanged) / took ours/theirs per `inventory` / merged on `BASE`
  (clean, or with N conflict blocks resolved by hand) / regenerated / deleted / ...).
- Every **judgment call**, with what each side had and what was chosen and why.
- Any lockfile whose regeneration failed: the error, and that it holds `MERGE_HEAD`'s version
  until the user runs the lock command (give it).
- The step 2 result: each auto-merged path whose `merge-on-base` result differed from Git's,
  and which one was kept.
- The step 4 result: the renames and removals extended to target code (or that there were none).
- Every target change dropped because the stacked branch removed the code it changed, and whether
  the replacement addresses that change's concern; list the unresolved ones as open questions.
- The result of the step 6 verification, listing any accepted mismatches.
- The step 7 results: each check run and its outcome, any failures judged unrelated to the
  resolution and the reasoning behind each, and any check that could not be found or run.
- A reminder that the resolution is fully staged but the merge is not concluded: the user should
  review (e.g. `git diff --cached MERGE_HEAD`) and run `git merge --continue`.

List the sections with nothing to report together on one line (e.g. "No judgment calls,
lockfiles, step 4 extensions or dropped target changes.") instead of one "none" line per
section.
