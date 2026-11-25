# Shell & Substance

The author's personal setup for AI-assisted work: shell config, NeoVim, CLI scripts and libs, plus bootstrap guides
for macOS and Fedora on WSL2. These are tailored to specific machines and one user's workflow, and are not maintained
for reuse.
The one part published for others is the `sei` Claude Code plugin in [`claude-plugin/`](./claude-plugin).

## Claude Code skills

[`claude-plugin/skills/`](./claude-plugin/skills) holds Claude Code skills that cover PR-based development from end to end:
writing and reviewing specs, implementing them, writing PR messages, reviewing PRs across follow-up rounds, and resolving
conflicts in stacked branches after a squash merge.
Install them in Claude Code:

```text
/plugin marketplace add satoseino/substance
/plugin install sei@substance
```

See [`claude-plugin/README.md`](./claude-plugin/README.md) for the workflow, requirements and the clone-based install.

## Getting started (author's machines)

- Install dependencies according to [BOOTSTRAP.md](./BOOTSTRAP.md) or [BOOTSTRAP-WSL.md](./BOOTSTRAP-WSL.md).

- Clone `substance` repo and run set-up script.

  ```bash
  mkdir -p ~/.config
  git clone https://github.com/satoseino/substance ~/.config/substance
  ~/.config/substance/set-up.sh
  ```

- Open up `nvim` and run `:MasonInstallAll`, `:TSInstallAll`, `:checkhealth`.

## Testing

Skill scripts and `set-up.sh` are tested with [bats-core](https://github.com/bats-core/bats-core), vendored as git submodules under `test/`.
Initialize them once per clone, then run the suite from the repo root:

```bash
git submodule update --init --recursive
BATS_FILE_EXTENSION=sh ./test/bats/bin/bats test/
```

CI runs the suite and `shellcheck`/`shfmt` on every push and PR to `main`.
See [CLAUDE.md](./CLAUDE.md#testing) for test conventions.
