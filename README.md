# Shell & Substance

A personal setup for AI-assisted work: shell config, Neovim, CLI scripts, and Claude Code skills,
plus bootstrap guides for macOS and Fedora on WSL2.
It is tailored to specific machines and a single user's workflow, so expect to adapt it rather than use it as-is.

## Getting started

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
