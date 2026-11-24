# Shell & Substance

## Getting started

- Install dependencies according to [BOOTSTRAP.md](./BOOTSTRAP.md) or [BOOTSTRAP-WSL.md](./BOOTSTRAP-WSL.md).

- Clone `substance` repo and run set-up script.

  ```bash
  mkdir -p ~/.config
  git clone https://github.com/satoseino/substance ~/.config/substance
  ~/.config/substance/set-up.sh
  ```

- To run the skill script tests, also run `git submodule update --init --recursive` (see [CLAUDE.md](./CLAUDE.md#testing-skill-scripts)).

- Open up `nvim` and run `:MasonInstallAll`, `:TSInstallAll`, `:checkhealth`.
