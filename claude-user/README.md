# Claude Code skills for PR-based development

Nine Claude Code skills that cover a pull request's life, from the
end of a design conversation to the follow-up review after the author pushes fixes. They are in daily use, and their
bundled scripts are tested with bats in CI.

## The workflow

```text
 design conversation
        │
        ▼
 /sei-write-specs ───► /sei-specs-review-loop ───► /sei-implement-spec ───► /sei-pr-message
   (spec files)         (fix specs in rounds)       (code + commits)        (PR title + body)

 reviewing someone's PR
        │
        ▼
 /sei-pr-review start ───► triage findings ───► /sei-pr-comment ───► /sei-pr-review followup
   (report + session)       (accept/dismiss)     (post on GitHub)     (did the fixes land?)

 any time
   /sei-fetch-single-comment   pull one PR comment into context and act on it
   /sei-session-file           save and reload the context for a multi-session task
   /sei-resolve-squash-conflicts   clean up a stacked branch after its base PR was squash-merged
```

Specs are the thread that ties the steps together. The spec written after a design discussion is what gets reviewed,
implemented, and later used as the yardstick in the PR review.

## Skills

| Skill | What it does | Invocation |
|---|---|---|
| [`sei-write-specs`](skills/sei-write-specs/SKILL.md) | Turns the decisions in the current conversation into one or more Markdown specs with file:line-cited changes, acceptance criteria and a files-to-change table. Never overwrites an existing file. | `/sei-write-specs "<path> :: <topic> ;; ..." "<shared instructions>"` |
| [`sei-specs-review-loop`](skills/sei-specs-review-loop/SKILL.md) | Reviews specs against themselves, each other, the current code and the session's decisions; fixes what has a clear fix, and stops on a clean round, a question for you, or the round cap. | `/sei-specs-review-loop <rounds> "<spec> ;; ..." [focus]` |
| [`sei-implement-spec`](skills/sei-implement-spec/SKILL.md) | Implements a spec on the current branch, committing as it goes. Refuses to run on `main` or with a dirty tree. | `/sei-implement-spec <spec> [focus]` |
| [`sei-pr-message`](skills/sei-pr-message/SKILL.md) | Writes a PR title and description from the conversation, ready for `/copy`. | `/sei-pr-message` |
| [`sei-pr-review`](skills/sei-pr-review/SKILL.md) | `start` checks that the local checkout matches the PR head, reviews the diff against a spec, writes a report with labelled findings (`[C1]`, `[M2]`, `[m3]`) and walks you through accepting or dismissing each. `followup` finds your posted comments by label, rates whether each was addressed, and looks for new problems. | `/sei-pr-review start <pr_url> <spec> <report> <session> [focus]`<br>`/sei-pr-review followup <session> [focus]` |
| [`sei-pr-comment`](skills/sei-pr-comment/SKILL.md) | Writes the GitHub comment for an accepted finding, opening with the `This is change request [Xn].` line that `followup` matches on. | `/sei-pr-comment <label>` |
| [`sei-fetch-single-comment`](skills/sei-fetch-single-comment/SKILL.md) | Fetches one conversation or inline review comment by URL and acts on it, by default judging whether it raises a real concern. The only skill Claude may invoke on its own. | `/sei-fetch-single-comment <url> [instructions]` |
| [`sei-session-file`](skills/sei-session-file/SKILL.md) | `new` scaffolds a manifest listing the files to load and a goal; `load` reads them all and waits for your first message. | `/sei-session-file new\|load <path>` |
| [`sei-resolve-squash-conflicts`](skills/sei-resolve-squash-conflicts/SKILL.md) | During `git merge <target>` on a stacked branch whose base PR was squash-merged, re-merges each path against the right ancestor, verifies that the branch's own changes survived, runs the project's checks and stages the result. It leaves the merge for you to conclude. | `/sei-resolve-squash-conflicts <old_pr_number>` |

## Design choices

- **Nothing is posted to GitHub.** Reviews, comments and PR messages are written to local files or printed for
  `/copy`; you decide what to post.
- **Git writes are opt-in.** Only `sei-implement-spec` commits, and only on a clean non-`main` branch.
  `sei-resolve-squash-conflicts` runs `git add` and nothing more.
- **Facts come from scripts, not the model.** GitHub API calls, SHA checks and merge bookkeeping live in bash scripts
  that print a fixed `PASS` / `FAIL` / `ERROR:` protocol, which the skill relays verbatim on failure.
- **State lives in files.** Review reports carry their triage state in front matter, and session manifests list what to
  reload, so a review can resume days later in a new conversation.

## Using them elsewhere

[`set-up.sh`](../set-up.sh) links every skill folder into `~/.claude/skills/`. To use them without the rest of this
repo, copy or symlink the folders you want:

```bash
ln -s "$PWD/claude-user/skills/sei-pr-review" ~/.claude/skills/sei-pr-review
```

Requirements and assumptions:

- `git`, plus `jq` and the [`gh` CLI](https://cli.github.com/) (>= 2.81.0, authenticated) for `sei-pr-review` and
  `sei-fetch-single-comment`. `sei-resolve-squash-conflicts` needs only `git` and an `origin` that serves
  `refs/pull/<n>/head`, as GitHub does.
- `sei-pr-review` invokes `sei-fetch-single-comment` when a focus prompt points at a comment URL, so install both.
- `sei-pr-review` looks for a web search tool through a `jarvis-registry` MCP server when it is unsure about a library.
  Without that server it reviews without web search.
- The skills are written to sit alongside [`CLAUDE-USER.md`](CLAUDE-USER.md), whose global rule reserves git writes for
  the user. `sei-implement-spec` lifts that rule for its own session.
- Where specs, reports and sessions go is up to you; every path is an argument. This repo keeps them in a
  `.working-docs/` folder that [`wdocs`](../bin/wdocs) scaffolds.

## Tests

The scripts under `skills/*/scripts/` have [bats](https://github.com/bats-core/bats-core) tests in [`test/`](../test)
with `gh` stubbed out, and CI runs them on every push and PR to `main`. See [CLAUDE.md](../CLAUDE.md#testing) for how to run them.
