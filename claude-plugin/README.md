# Claude Code skills for PR-based development

Claude Code skills that cover a pull request's life, from the end of a design conversation to the follow-up review
after the author pushes fixes. They are in daily use, and their bundled scripts are tested with bats in CI.

## The workflow

```text
 design conversation
        │
        ▼
 /sei:write-specs ───► /sei:specs-review-loop ───► /sei:implement-spec ───► /sei:pr-message
   (spec files)         (fix specs in rounds)       (code + commits)        (PR title + body)

 reviewing someone's PR
        │
        ▼
 /sei:pr-review start ───► triage findings ───► /sei:pr-comment ───► /sei:pr-review followup
   (report + session)       (accept/dismiss)     (post on GitHub)     (did the fixes land?)

 any time
   /sei:fetch-single-comment   pull one PR comment into context and act on it
   /sei:session-file           save and reload the context for a multi-session task
   /sei:resolve-squash-conflicts   clean up a stacked branch after its base PR was squash-merged
```

Specs are the thread that ties the steps together. The spec written after a design discussion is what gets reviewed,
implemented, and later used as the yardstick in the PR review.

## Skills

| Skill | What it does | Invocation |
|---|---|---|
| [`write-specs`](skills/write-specs/SKILL.md) | Turns the decisions in the current conversation into one or more Markdown specs with file:line-cited changes, acceptance criteria and a files-to-change table. Never overwrites an existing file. | `/sei:write-specs "<path> :: <topic> ;; ..." "<shared instructions>"` |
| [`specs-review-loop`](skills/specs-review-loop/SKILL.md) | Reviews specs against themselves, each other, the current code and the session's decisions; fixes what has a clear fix, and stops on a clean round, a question for you, or the round cap. | `/sei:specs-review-loop <rounds> "<spec> ;; ..." [focus]` |
| [`implement-spec`](skills/implement-spec/SKILL.md) | Implements a spec on the current branch, committing as it goes. Refuses to run on the default branch (or `main`/`master`), on a detached HEAD, or with a dirty tree. | `/sei:implement-spec <spec> [focus]` |
| [`pr-message`](skills/pr-message/SKILL.md) | Writes a PR title and description from the conversation, ready for `/copy`. | `/sei:pr-message` |
| [`pr-review`](skills/pr-review/SKILL.md) | `start` checks that the local checkout matches the PR head, reviews the diff against a spec, writes a report with labelled findings (`[C1]`, `[M2]`, `[m3]`) and walks you through accepting or dismissing each. `followup` finds your posted comments by label, rates whether each was addressed, and looks for new problems. | `/sei:pr-review start <pr_url> <spec> <report> <session> [focus]`<br>`/sei:pr-review followup <session> [focus]` |
| [`pr-comment`](skills/pr-comment/SKILL.md) | Writes the GitHub comment for an accepted finding, opening with the `This is change request [Xn].` line that `followup` matches on. | `/sei:pr-comment <label>` |
| [`fetch-single-comment`](skills/fetch-single-comment/SKILL.md) | Fetches one conversation or inline review comment by URL and acts on it, by default judging whether it raises a real concern. The only skill Claude may invoke on its own. | `/sei:fetch-single-comment <url> [instructions]` |
| [`session-file`](skills/session-file/SKILL.md) | `new` scaffolds a manifest listing the files to load and a goal; `load` reads them all and waits for your first message. | `/sei:session-file new\|load <path>` |
| [`resolve-squash-conflicts`](skills/resolve-squash-conflicts/SKILL.md) | During `git merge <target>` on a stacked branch whose base PR was squash-merged, re-merges each path against the right ancestor, verifies that the branch's own changes survived, runs the project's checks and stages the result. It leaves the merge for you to conclude. | `/sei:resolve-squash-conflicts <old_pr_number>` |

## Design choices

- **Nothing is posted to GitHub.** Reviews, comments and PR messages are written to local files or printed for
  `/copy`; you decide what to post.
- **Git writes are opt-in.** Only `implement-spec` commits, and only on a clean feature branch, never the default branch.
  `resolve-squash-conflicts` runs `git add` and nothing more.
- **Facts come from scripts, not the model.** GitHub API calls, SHA checks and merge bookkeeping live in bash scripts
  that print a fixed `PASS` / `FAIL` / `ERROR:` protocol, which the skill relays verbatim on failure.
- **State lives in files.** Review reports carry their triage state in front matter, and session manifests list what to
  reload, so a review can resume days later in a new conversation.

## Install

**Marketplace (recommended).** In Claude Code:

```text
/plugin marketplace add satoseino/substance
/plugin install sei@substance
```

Skills are then invoked as `/sei:<skill>`, e.g. `/sei:pr-review start ...`.

Auto-update is off by default for third-party marketplaces such as this one, and refreshing the marketplace alone leaves
the installed plugin where it was. To update, run:

```bash
claude plugin marketplace update substance
claude plugin update sei@substance
```

Then restart Claude Code, or run `/reload-plugins` in a session. To get updates automatically instead, turn on
auto-update for `substance` in the Marketplaces tab of `/plugin`.

**From a clone, for hacking on the skills.** From the repo root:

```bash
ln -s "$PWD/claude-plugin" ~/.claude/skills/sei
```

Claude Code loads it in place as `sei@skills-dir`; run `claude plugin list` to confirm. Link the whole plugin folder,
never single skill folders: cross-skill calls such as `pr-review`'s use of `sei:fetch-single-comment` rely on the `sei:`
namespace, which a lone skill folder does not get.

- A marketplace-installed `sei` takes precedence over a `sei@skills-dir` copy. Use one or the other on a machine.
- This repo's [`set-up.sh`](../set-up.sh) is the author's personal installer. It also links dotfiles and needs Bash 5.1,
  so do not run it to get the skills.

## Requirements

| Skill | External tools | Assumptions |
|---|---|---|
| `pr-review` | `git`; `gh` >= 2.81.0 (for `gh auth status --json`), authenticated to github.com; `jq` | PRs on github.com only (`scripts/lib/gh-preflight.sh` reads the `github.com` host); invokes `sei:fetch-single-comment` when a focus prompt names a comment URL; uses any available web search tool, else reviews without one; `origin` must be the PR's base repository: `fetch-pr-data` reads the base commit from GitHub and, if it isn't local, fetches objects only from `origin`'s base branch (no refs written) |
| `fetch-single-comment` | `gh` (authenticated), `jq` | github.com comment URLs |
| `resolve-squash-conflicts` | `git` (`merge-file`, `ls-remote`, `fetch`) | `origin` serves `refs/pull/<n>/head`, as GitHub does |
| `implement-spec` | `git` (`symbolic-ref`, `ls-remote`) | Refuses `origin`'s default branch (from `origin/HEAD`, else `git ls-remote`), `main`, `master` and a detached HEAD; fails closed when `origin` exists but its default branch can't be determined; grants itself commits and other state-changing local git commands for the rest of the session, but never `push` |
| `write-specs`, `specs-review-loop`, `pr-message`, `pr-comment`, `session-file` | none | — |

- Bundled scripts run with the first `bash` on `PATH` and are tested on Bash 3.2 (stock macOS `/bin/bash`) and Bash 5.
  They also use `cat`, `sed`, `tr`, `awk`, `grep`, `sort`, `head`, `mktemp`, `rm`, `dirname` and `readlink -f`.
  `readlink -f` needs macOS 12.3+ or GNU coreutils.
- Tested with Claude Code 2.1.332. No minimum version is claimed.
- Where specs, reports and sessions go is up to you; every path is an argument. This repo keeps them in a
  `.working-docs/` folder that [`wdocs`](../bin/wdocs) scaffolds.

## Tests

The scripts under `skills/*/scripts/` have [bats](https://github.com/bats-core/bats-core) tests in [`test/`](../test)
with `gh` stubbed out, and CI runs them on every push and PR to `main`. See [CLAUDE.md](../CLAUDE.md#testing) for how to run them.
