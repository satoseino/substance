---
name: sei-specs-review-loop
description: "Review one or more existing Markdown spec files in rounds — for internal consistency, consistency against each other (when more than one is given), against the current code, and against decisions established in this session — fixing findings that have a clear fix, until a round turns up only minor problems, a finding needs the user's design decision, or the round cap is reached."
disable-model-invocation: true
argument-hint: "<count> <paths> [focus_prompt]"
arguments: [count, paths, focus_prompt]
allowed-tools: Bash Read Edit Grep Agent mcp__jarvis-registry__discover_servers mcp__jarvis-registry__execute_tool
---

## Arguments

| Argument | Description |
|----------|-------------|
| `count` | Maximum number of review rounds, a positive integer. Every round counts, including the final clean one — `1` means review once, fix, and stop. |
| `paths` | One or more spec file paths separated by `;;` (with spaces around it). Absolute paths and paths relative to CWD are both accepted. The last item does not need a trailing `;;`. |
| `focus_prompt` | *(Optional)* Additional instructions for this run — often the user's answers to deferred findings from a previous run. Treat every statement in this prompt as if it were written in **bold** — give it higher focal weight than the default review rules in this skill when the two conflict or compete for attention. |

Values received for this invocation (an empty value means the argument was not given):

- count: $count
- paths: $paths
- focus_prompt: $focus_prompt

**`count` and `paths` are required.** If either is missing, stop and tell the user which is absent before doing anything else. `focus_prompt` is optional; if absent, review against the sources of truth below with no extra emphasis.

### Validation — before any review begins

Stop and report to the user, without editing anything, if any of the following holds:

- `count` is not a positive integer.
- After splitting `paths` on `;;` and trimming whitespace, any item is empty, or any path does not exist or is not a regular file (check via `Bash test -f`). Name every offending path.
- `focus_prompt` starts with `;;` or looks like a spec file path — a sign the arguments were mis-quoted and `paths` was truncated.

**Symlinked specs.** If a path — or a parent directory in it — is a symlink, resolve it (e.g. `readlink -f`) and use the resolved path for validation, reading, and editing. A symlinked spec is not a separate project to investigate — just follow the link.

---

## Hard constraints — apply for the entire duration of this skill, not just at the start

- Do the review, bucketing, and editing yourself, directly, in this conversation — this session's context (prior research, finalized decisions) is an input to the review, and subagents don't inherit it. **Use the Task/Agent tool only for well-scoped, stand-alone research** whose brief can be fully self-contained (e.g. sweeping a large codebase for every caller of a function, or researching how a library behaves). Treat a subagent's result as evidence to verify, never as a finding or an edit.
- **Never call the Skill tool** for any skill while running this workflow. Everything needed is inlined below.
- **Edit only the spec files in `paths`.** Never modify code, tests, or any other file, even when a finding is about the code.
- No state-changing git operations (`add`, `commit`, `stash`, `checkout`, etc.). Read-only git commands (`log`, `blame`, `show`, `diff`) are fine for context.

---

## Sources of truth

Review each spec against:

1. **Itself** — internal consistency: sections agree with each other (e.g. for a spec in the `sei-write-specs` format, Background vs. Changes vs. Acceptance Criteria vs. Files to Change), no contradictions, no dangling references.
2. **The other specs** — when more than one spec is given: shared interfaces, names, ordering, and ownership of changes agree across specs; no change is claimed by two specs or by none.
3. **The current code** — every file path, line reference, symbol, signature, and described current behavior matches what is actually on disk. Verify by reading the code; a code-mismatch finding must cite the `file:line` you read.
4. **This session's established context** — decisions, research results, and constraints from the conversation that led to this invocation, including any discussion since a previous run of this skill, plus `focus_prompt`. A spec contradicting a decision is a finding. It is a clear fix only when the decision is unambiguous in context; context after `/compact` is lossy, so a vague recollection makes it a deferred finding, not an edit.

Web search is encouraged whenever a spec relies on a library, API, or technology you are uncertain about — verify rather than guess.

---

## Finding buckets

Sort every finding into exactly one bucket:

| Bucket | Meaning | Action |
|---|---|---|
| **fixed** | Substantive problem with a clear recommended fix. | Apply the fix this round. |
| **minor** | Wording, typo, formatting, or a stale line-range reference. | Apply the fix this round. Does not block stopping. |
| **deferred** | Needs the user's design decision — multiple reasonable resolutions, or the deciding information is not established in session context. | Do not edit. Record for the user. |

A finding whose fix depends on how a deferred finding gets resolved is itself **deferred** — do not guess the decision.

---

## Round procedure (repeat up to `count` times)

1. **Re-read every spec from disk, in full.** Do not rely on memory of earlier rounds or of edits you just made.
2. **Review** against all applicable sources of truth above. Re-verify code claims against the actual files each round — including claims you edited in a previous round.
3. **Bucket** every finding.
4. **Apply** all fixed and minor findings with `Edit`. Finish the whole round even if deferred findings exist — fixes independent of them still land.
5. **Print a one-line round summary:** `Round <n>: <a> fixed, <b> minor, <c> deferred`.
6. **Decide whether to continue:**
   - Any deferred findings → stop with outcome **deferred**.
   - Only minor findings (or none) → stop with outcome **clean**.
   - Otherwise, if `<n>` equals `count` → stop with outcome **cap reached**.
   - Otherwise → start the next round.

---

## Final report

Print:

1. **Outcome** — `clean`, `deferred`, or `cap reached`, and the number of rounds run. For `cap reached`, say that substantive fixes were still being made in the last round, so another run is likely worthwhile.
2. **Changes per spec** — for each spec path, a concise list of what was changed across all rounds (group minor fixes into one line per spec). The specs may be untracked, so this list is the user's record of the edits. Omit specs that were not changed.
3. **Deferred findings** (outcome `deferred` only) — numbered, each with:
   - The spec path and section (and line where useful).
   - The conflict or open question, citing the code `file:line` or the conflicting spec passage as evidence.
   - The options with their tradeoffs, and a recommendation when there is a clear one.

   Then stop and discuss with the user. Do not re-run review rounds in this invocation; the user will invoke the skill again once decisions are made.

Before finishing, confirm to yourself: did you avoid the Skill tool, use the Task/Agent tool only for well-scoped stand-alone research, and edit only files in `paths`, for this entire workflow? If not, say so explicitly rather than staying silent about it.
