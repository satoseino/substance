# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Personal dotfiles and Claude Code skills for AI-assisted work.

- Everything except `claude-plugin/` is the author's own (shell config, NeoVim, `bin/`, `lib/`, `profile/`,
  `claude-user/`) and is not designed for reuse by others.
- `claude-plugin/` is the public `sei` plugin. It is published through the repo-root `.claude-plugin/marketplace.json`.
  Changes there must not depend on anything outside `claude-plugin/`: marketplace installs copy only the plugin folder.
  Its scripts must stay Bash 3.2-compatible (see "Shell version").

`set-up.sh` creates symlinks from `$HOME` (and `~/.config/nvim`) pointing into this repo,
so edits here take effect immediately for the running shell (after re-sourcing the relevant file).

`BOOTSTRAP.md` documents the macOS + Homebrew dependency installation that must be done before
`./set-up.sh` is run for the first time on a new machine. Consult it when in doubt about what tools,
languages, and CLIs are assumed to be present.

`BOOTSTRAP-WSL.md` is the counterpart for the `fedora` host: a Fedora distro on WSL2 (Windows 11), with
dnf as the primary package manager and Homebrew on Linux (`/home/linuxbrew/.linuxbrew`) for the rest.

## Common commands

```bash
# Re-run the installer (idempotent — safe to re-run after any structural change)
./set-up.sh
```

`pre-commit` is configured in `.pre-commit-config.yaml` with five hooks:
- **gelato** — secret scanning on every commit.
- **shellcheck** and **shfmt** (`shfmt -w -i 2`) — lint and format the shell files on every commit.
- **shell-cmd-on-change** `set-up` — automatically re-runs `set-up.sh` on `post-merge` if tracked files changed.
- **shell-cmd-on-change** `nvim-lazy-restore` — runs `nvim --headless '+Lazy! restore' +qa` on `post-merge` when
  `nvim/lazy-lock.json` changes.

### Resolving gelato findings

When `gelato` flags a string that is not a secret (typically a long path in a test), do not rewrite the code to dodge it.
Add the finding's signature to `exclude-signatures` in `tartufo.toml`, with a `reason`:

```toml
{signature = "<signature from the report>", reason = "file path in set-up.sh test is not credential"},
```

Prefer this narrowest entry. Reach for `exclude-entropy-patterns` only when one pattern recurs across many lines, as with the
`$SEI_SUBSTANCE_DIR/lib/*.sh` source paths. Never put the matched string itself in the file. If it is a real secret,
remove it and rotate it instead. `gelato pre-commit --help` covers the options.

## Shell version

All shell code targets **Bash 5.1+**. Features unavailable in older Bash (e.g. `mapfile`, `compgen -V`, extended globs, `@(...)` patterns) are fair game.

The exception is `claude-plugin/skills/*/scripts/`. These ship to other users and must run on Bash 3.2 (stock macOS
`/bin/bash`), so they avoid `mapfile`/`readarray`, associative arrays, namerefs (`local -n`), `${var,,}`/`${var^^}`,
negative array indices, and empty-array expansion under `set -u`. Verify on macOS with
`SEI_TEST_SCRIPT_BASH=/bin/bash BATS_FILE_EXTENSION=sh ./test/bats/bin/bats test/`.

## Shell init architecture

`dotfiles/.bashrc` is the entry point. It sets `$SEI_SUBSTANCE_DIR` first, then sources `lib/it-shell.sh` and immediately calls `sei::bash_init` (which sets up PATH, fnm, completion, and man pager). A `trap … RETURN` is armed to fire `sei::bash_post_init` once `dotfiles/.bashrc` finishes returning; that function resolves the current environment prefix (via `hostname`) and sources the matching `profile/<prefix>.bashrc`. After the trap, `dotfiles/.bashrc` sources the remaining interactive lib files: `lib/aliases.sh`, `lib/commands.sh`, `lib/cplan.sh`, and `lib/acmd.sh`.

All module files guard against double-sourcing via a `_sei_module_set_<name>` env var at the top.

`$SEI_SUBSTANCE_DIR` is the canonical env var pointing to the repo root; use it instead of hard-coding the path anywhere.

## Shell utility conventions

### Double-loading guard

Every sourced `.sh` module in `lib/` must open with a guard that prevents re-sourcing:

```bash
if [[ -n "${_sei_module_set_<name>+x}" ]]; then
  return
fi
_sei_module_set_<name>=1
```

`<name>` is the module's filename stem with hyphens replaced by underscores (e.g. `it-shell.sh` → `it_shell`). The `+x` form tests for the variable being set without treating an empty value as unset.

`profile/` files do not use this guard — they are sourced for their side effects, and idempotency is provided by the guards in the lib files they source.

### Function namespacing

| Scope | Convention | Example |
|---|---|---|
| User-facing interactive commands | Plain hyphenated name | `acmd`, `subp` |
| Shared internal helpers (cross-module) | `sei::` prefix | `sei::log_info`, `sei::bash_post_init` |
| Module-private helpers | `_sei_<module>::` prefix | `_sei_it_shell::prompt` |

The `_sei_<module>::` prefix applies to all bash functions that must not leak into the global namespace — including completion handlers and their helpers in `completions/` files, not just private helpers inside sourced `.sh` modules. `<module>` is always the filename stem with hyphens replaced by underscores. Local names after `::` also use underscores (e.g. `_sei_keyring_aws::only_missing_arg`, not `only-missing-arg`).

Never define bare helper functions without a namespace for the interactive shell — they pollute its function namespace.

### Environment variable naming

All exported env vars use the `SEI_` prefix (e.g. `SEI_SUBSTANCE_DIR`, `SEI_SHELL_INIT`). Guard vars use the `_sei_module_set_` prefix and are intentionally not exported.

## lib/ and profile/ file rules

### lib/ files

- Must have a module-load guard.
- Declare lib-to-lib dependencies by sourcing directly, using a path relative to the file's own disk location (the `readlink -f "${BASH_SOURCE[0]}"` pattern). Never rely on load order.
- May not access env vars set by other lib functions _at source time_. `$SEI_SUBSTANCE_DIR` is the one exception — it is a bootstrap var set by `dotfiles/.bashrc` before any lib is sourced.
- For platform, host, and user detection, call `$(uname -s)`, `$(hostname)`, `$(whoami)` inline. Do not introduce cached `SEI_*` vars for these. (`SEI_SHELL_INIT` is a session-state flag, not a cache — do not confuse the two.)
- Non-`utils.sh` lib files are for interactive shell use only and may be sourced only by `dotfiles/.bashrc` or `profile/` files — never by scripts.

### profile/ files

- No module-load guard — idempotency comes from the guards inside the lib files they source.
- Source lib files using `$SEI_SUBSTANCE_DIR`-relative paths (`$SEI_SUBSTANCE_DIR` is guaranteed present by the time any profile file is sourced).
- May source any lib file from `lib/`.

## Adding a complex interactive shell function

When an interactive shell function is non-trivial (needs its own completion, keybindings, or private helpers), give it its own `lib/<name>.sh` module instead of putting it in `lib/commands.sh`:

1. Create `lib/<name>.sh` with the standard double-loading guard at the top.
2. Source `lib/utils.sh` using the `readlink -f "${BASH_SOURCE[0]}"` relative path pattern. If the module depends on another lib file (e.g., `lib/it-shell.sh`), source it the same way — explicit, never implicit.
3. Define the public function, any `_sei_<name>::` private helpers, and the bash completion function + `complete` registration inline in the file.
4. The public function's help text **must** use a quoted heredoc (`cat <<'EOF'`), never unquoted (`cat <<EOF`). The `acmd` preview system locates the help range by searching for the literal string `<<'EOF'`; an unquoted heredoc will not be detected and the preview falls back to a 5-line stub.
5. Append the function name to `_sei_commands_list` so it appears in `acmd -l`.
6. Add `source "$SEI_SUBSTANCE_DIR/lib/<name>.sh"` to `dotfiles/.bashrc` if the function is needed in all environments, or to the relevant `profile/<prefix>.bashrc` if it is env-specific.
7. Run `acmd -d` to invalidate the cache; the next `acmd -l` or `acmd -p` invocation will rebuild it.

## Adding a new script to `bin/`

Every `bin/` script must follow this standard structure (required for `acmd` preview to work):

```bash
#!/usr/bin/env bash

set -eu -o pipefail

source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/../lib/utils.sh"

main() {
  if (($# > 0)) && [[ $1 == "-h" ]]; then
    cat <<'EOF'
Usage: <name> [-h] ...
...
EOF

    return 0
  fi

  # implementation
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
```

Key rules:
- Scripts may only source `lib/utils.sh` — no other lib file.
- The `-h` help block **must** use `cat <<'EOF'` (quoted). The `acmd` preview system finds the help range by matching the literal `<<'EOF'` marker; an unquoted heredoc will not be detected.
- The entry-point guard must call `main "$@"`, not bare `main`.

Steps to add a new script:

1. Create the executable in `bin/<name>` using the structure above.
2. Add a matching bash completion file in `completions/<name>`.
3. Run `./set-up.sh` — it symlinks everything in `bin/` into `~/.local/bin` automatically.
4. Run `date > .keep` and commit the result. The `shell-cmd-on-change` pre-commit hook watches `.keep`; when other clones pull this commit, their `post-merge` hook will detect the change and automatically run `./set-up.sh` to pick up the new script.
5. Run `acmd -d` to invalidate the cache; the next `acmd -l` or `acmd -p` invocation will rebuild it.

## Claude Code configuration

`claude-user/` holds user-scoped Claude Code config, symlinked into `~/.claude/` by `set-up.sh`:

- `claude-user/CLAUDE-USER.md` → `~/.claude/CLAUDE.md`
- `claude-user/settings.json` → `~/.claude/settings.json`

It is deliberately not named `.claude/`, so Claude Code does not also load these files as project-scoped config when working in this repo. For the same reason the global instructions file is not named `CLAUDE.md`, which Claude Code would auto-load from subfolders.

`claude-plugin/` is the `sei` Claude Code plugin (`.claude-plugin/plugin.json` + `skills/<skill-name>/SKILL.md`), and `set-up.sh` symlinks `~/.claude/skills/sei` → `claude-plugin/`. Claude Code loads it as `sei@skills-dir`, and skills are invoked as `/sei:<skill-name>`. It is kept apart from `claude-user/` so that `settings.json` never sits at a plugin root.

`.claude-plugin/marketplace.json` at the repo root lists the plugin. Its entry `name` must match `claude-plugin/.claude-plugin/plugin.json`'s `name`, and neither file sets `version`.

Skills live in `claude-plugin/skills/<skill-name>/SKILL.md`. Skill folder names and frontmatter `name` carry no prefix; the plugin supplies `sei:`. One skill refers to another by its qualified `sei:<skill-name>`. Each `SKILL.md` begins with YAML front matter (`name`, `description`, `allowed-tools`, etc.) followed by the instruction body.

## Testing

Scripts under `claude-plugin/skills/*/scripts/` and `set-up.sh` (in `test/set_up.sh`) are tested with [bats-core](https://github.com/bats-core/bats-core),
vendored as git submodules under `test/`. Initialize them once per clone:

```bash
git submodule update --init --recursive
```

Run the suite from the repo root:

```bash
BATS_FILE_EXTENSION=sh ./test/bats/bin/bats test/
```

Conventions:

- Test files live flat in `test/*.sh`, named `<skill-prefix>_<script>.sh` (e.g. `pr_review_verify_sha.sh`). Never run
  bats with `-r`: with `BATS_FILE_EXTENSION=sh` it would pick up `*.sh` files inside the bats submodule. Helper files
  use the `.bash` extension so they are never collected as tests.
- Mark each test with the inline marker: `name() { #@test`.
- Every test file runs `load "test_helper/common"`, and its `setup()` calls `common_setup` first (points `TMPDIR` at the
  per-test temp dir).
- Build script paths from `$SKILLS_DIR` (set by `test/setup_suite.bash`), e.g. `"$SKILLS_DIR/pr-review/scripts/verify-sha"`.
- Stub `gh` with `use_fake_gh` and `fake_gh_respond KEY STDOUT [EXIT [STDERR]]`; use `use_path_without_gh [TOOL...]` to
  simulate `gh` not being installed. It leaves only the tools in `NO_GH_TOOLS` (in `test/test_helper/common.bash`) plus
  any `TOOL`s on `PATH`. When a skill script starts using a new external command, add it to `NO_GH_TOOLS`. Tests must
  never invoke the real `gh` or touch the network.
- Set `SEI_TEST_SCRIPT_BASH` to a bash binary (e.g. `/bin/bash`) to run the scripts under test on it; `common_setup`
  puts a `bash` symlink to it first on `PATH`, while bats and the helpers stay on the suite's Bash. `test/set_up.sh`
  unsets it, since `set-up.sh` targets Bash 5.1. The `bats-test-bash32` CI job runs the suite this way on macOS.
- `set-up.sh` is tested in `test/set_up.sh`, an exception to the `<skill-prefix>_<script>.sh` naming and the
  `$SKILLS_DIR` rule; it builds paths from `$SUBSTANCE_DIR` instead. Its tests point `HOME` at the per-test dir, pin
  the prefix with `SEI_WORK_MODE`, and must keep `pre-commit` off `PATH` via `use_path_without_gh`, so they never touch
  the real `$HOME` or `.git/hooks`.
- `test/plugin_manifest.sh` follows the same exception: it builds paths from `$SUBSTANCE_DIR` and checks the
  marketplace and plugin manifests with `jq` and that each skill's frontmatter `name` matches its folder.

New or changed skill scripts, and changes to `set-up.sh`, must come with tests in `test/`.

Agents may run the suite without asking — it is local-only (`gh` is stubbed, no network) — and should do so after
changing any skill script, `set-up.sh`, or test, reporting failures verbatim. To iterate on one file, pass it directly:
`BATS_FILE_EXTENSION=sh ./test/bats/bin/bats test/<file>.sh`. If `test/bats/` is empty, run
`git submodule update --init --recursive` first.
