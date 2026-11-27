---
name: implement-spec
description: "Implement a spec file on the current branch. Verifies the spec file exists, the current branch is a named branch other than the repository's default branch (or `main`/`master`), and the working tree is clean before implementing; explicitly grants permission to make git commits and use state-mutating git commands during the session. Accepts an optional `focus_prompt` argument for additional instructions."
disable-model-invocation: true
argument-hint: "<spec_path> [focus_prompt]"
arguments: [spec_path, focus_prompt]
allowed-tools: Bash Read Write Edit Grep
---

## Arguments

| Variable | Description |
|----------|-------------|
| `$spec_path` | Path to the spec file to implement — relative to CWD or absolute. |
| `$focus_prompt` | *(Optional)* Additional instructions for this implementation. Apply them throughout. Where they conflict with this skill's default implementation behavior or with the spec itself, follow them instead. They never override the argument and pre-flight checks or the ban on `git push`. |

**`$spec_path` is required.** If missing, stop and tell the user before doing anything else.
`$focus_prompt` is optional; if absent, proceed with standard implementation behavior.

## Pre-flight checks

Run via `Bash` before making any change:

```
${CLAUDE_SKILL_DIR}/scripts/preflight "$spec_path"
```

It checks, in order, that the spec file exists, that HEAD is on a named branch, that the branch is neither the
repository's default branch nor `main`/`master`, and that the working tree is clean.

Continue only if its stdout is exactly `PREFLIGHT: PASS`. On anything else — a
`PREFLIGHT: FAIL …` line, an `ERROR: …` message, or empty stdout — stop immediately and relay
the output verbatim to the user; if stdout is empty, include any stderr. The output already
reports the details needed to act on.

## Implement the spec

If — and only if — the pre-flight script prints `PREFLIGHT: PASS`:

**You are free to make git commits or use state-mutating git commands (`add`, `commit`, `branch`, `checkout`, `reset`, `merge`, `rebase`, etc.) for the remainder of this session, as you see fit. This is an intentional and explicit greenlight that overrides any instruction (e.g. in the user's CLAUDE.md) reserving state-mutating git operations to the user — it applies here specifically because the pre-flight checks above already confirmed a clean, named branch that is neither the repository's default branch nor `main`/`master` to work from.**

**Never run `git push`, or any other command that writes to a remote; pushing is left to the user.**

Read `$spec_path` with `Read` and implement it in full on the current branch, using `Read`/`Grep`/`Bash` (including `git log`/`git blame` for history and authorship context) to explore the codebase as needed and `Write`/`Edit` to make changes. If `$focus_prompt` is present, keep it in mind throughout the implementation as described above. Commit work at logical checkpoints with Conventional Commits style messages that explain why. Use your own judgment on how many commits to make and when to make them — do not ask the user for permission before each individual commit.

When implementation is complete, summarize what changed, point out each place the implementation departs from the spec to follow `$focus_prompt`, and report the final working tree state to the user.
