#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

setup() {
  # set-up.sh targets Bash 5.1 and is not a skill script, so never run it on
  # the Bash 3.2 that SEI_TEST_SCRIPT_BASH may select.
  unset SEI_TEST_SCRIPT_BASH
  common_setup

  # Resolve like set-up.sh resolves its own directory, so -ef and
  # _points_into comparisons line up.
  SUBSTANCE_DIR=$(readlink -f "$BATS_TEST_DIRNAME/..")
  SCRIPT="$SUBSTANCE_DIR/set-up.sh"

  # Never touch the developer's real home directory.
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"

  # Deterministic prefix, independent of the host's hostname.
  export SEI_WORK_MODE=sei

  # Keeps pre-commit off PATH, so set-up.sh never writes to the real
  # .git/hooks.
  use_path_without_gh find ls mkdir ln unlink mv date touch hostname chmod sort
}

# assert_links_to LINK TARGET
assert_links_to() {
  if [[ ! -L $1 ]]; then
    fail "$1 is not a symlink"
  fi
  if [[ ! $1 -ef $2 ]]; then
    fail "$1 does not resolve to $2 (points to $(readlink "$1"))"
  fi
}

# List every symlink under $HOME with its raw target, sorted.
list_links() {
  local link
  while IFS= read -r link; do
    printf '%s -> %s\n' "$link" "$(readlink "$link")"
  done < <(find "$HOME" -type l | sort)
}

fresh_install() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success

  local name
  for name in .bash_logout .bash_profile .bashrc .gitconfig .gvimrc .inputrc .vimrc; do
    assert_links_to "$HOME/$name" "$SUBSTANCE_DIR/dotfiles/$name"
  done

  assert_links_to "$HOME/.config/ghostty/config" "$SUBSTANCE_DIR/.config/ghostty/config"
  assert_links_to "$HOME/.config/bat/config" "$SUBSTANCE_DIR/.config/bat/config"
  assert_links_to "$HOME/.config/nvim" "$SUBSTANCE_DIR/nvim"
  assert_links_to "$HOME/.vim/plugin" "$SUBSTANCE_DIR/.vim/plugin"
  assert_links_to "$HOME/.claude/CLAUDE.md" "$SUBSTANCE_DIR/claude-user/CLAUDE-USER.md"
  assert_links_to "$HOME/.claude/settings.json" "$SUBSTANCE_DIR/claude-user/settings.json"

  assert_links_to "$HOME/.claude/skills/sei" "$SUBSTANCE_DIR/claude-plugin"
  assert_equal "$(ls -A "$HOME/.claude/skills")" sei

  local -a binaries
  # Regular, non-hidden files only (e.g. no .DS_Store), as base names.
  mapfile -t binaries < <(find "$SUBSTANCE_DIR/bin" -maxdepth 1 -mindepth 1 -type f ! -name '.*')
  binaries=("${binaries[@]##*/}")

  ((${#binaries[@]} > 0))

  for name in "${binaries[@]}"; do
    assert_links_to "$HOME/.local/bin/$name" "$SUBSTANCE_DIR/bin/$name"
  done

  assert [ -e "$HOME/.hushlogin" ]
  assert [ ! -e "$HOME/.tmux.conf" ]
  assert [ ! -L "$HOME/.tmux.conf" ]
}

fedora_adds_tmux() { #@test
  export SEI_WORK_MODE=fedora

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_links_to "$HOME/.tmux.conf" "$SUBSTANCE_DIR/dotfiles/.tmux.conf"
}

non_fedora_removes_tmux_link() { #@test
  ln -s "$SUBSTANCE_DIR/dotfiles/.tmux.conf" "$HOME/.tmux.conf"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ ! -L "$HOME/.tmux.conf" ]
  assert [ ! -e "$HOME/.tmux.conf" ]
}

idempotent() { #@test
  run --separate-stderr "$SCRIPT"
  assert_success

  local before
  before=$(list_links)

  run --separate-stderr "$SCRIPT"

  assert_success
  refute_output --partial 'Removing'
  refute_output --partial 'Backed up'
  assert_equal "$(list_links)" "$before"
}

broken_link_replaced() { #@test
  ln -s "$BATS_TEST_TMPDIR/missing" "$HOME/.bashrc"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output --partial "is broken (target $BATS_TEST_TMPDIR/missing)"
  assert_links_to "$HOME/.bashrc" "$SUBSTANCE_DIR/dotfiles/.bashrc"
}

wrong_target_link_replaced() { #@test
  local other="$BATS_TEST_TMPDIR/other-bashrc"
  printf 'other\n' >"$other"
  ln -s "$other" "$HOME/.bashrc"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_links_to "$HOME/.bashrc" "$SUBSTANCE_DIR/dotfiles/.bashrc"
  assert [ -f "$other" ]
  assert_equal "$(<"$other")" other
}

regular_file_backed_up() { #@test
  printf 'my own bashrc\n' >"$HOME/.bashrc"

  run --separate-stderr "$SCRIPT"

  assert_success

  local -a backups
  mapfile -t backups < <(find "$HOME" -maxdepth 1 -name '.bashrc.bak.*')

  assert_equal "${#backups[@]}" 1
  [[ ${backups[0]} =~ /\.bashrc\.bak\.[0-9]{14}$ ]] || fail "unexpected backup name: ${backups[0]}"
  assert [ -f "${backups[0]}" ]
  assert [ ! -L "${backups[0]}" ]
  assert_equal "$(<"${backups[0]}")" 'my own bashrc'
  assert_output --partial "Backed up existing file $HOME/.bashrc to ${backups[0]}"
  assert_links_to "$HOME/.bashrc" "$SUBSTANCE_DIR/dotfiles/.bashrc"
}

backup_collision_leaves_file_alone() { #@test
  # Pin the timestamp so the backup name collides with a pre-existing file.
  local fake_bin="$BATS_TEST_TMPDIR/fake-date-bin"
  mkdir -p "$fake_bin"
  printf '#!/usr/bin/env bash\necho 20260101000000\n' >"$fake_bin/date"
  chmod +x "$fake_bin/date"
  export PATH="$fake_bin:$PATH"

  local backup="$HOME/.bashrc.bak.20260101000000"
  printf 'my own bashrc\n' >"$HOME/.bashrc"
  printf 'earlier backup\n' >"$backup"

  run --separate-stderr "$SCRIPT"

  assert_success
  [[ $stderr == *"Cannot back up $HOME/.bashrc: $backup already exists"* ]] ||
    fail "unexpected stderr: $stderr"
  refute_output --partial "Backed up existing file $HOME/.bashrc"
  assert [ -f "$HOME/.bashrc" ]
  assert [ ! -L "$HOME/.bashrc" ]
  assert_equal "$(<"$HOME/.bashrc")" 'my own bashrc'
  assert_equal "$(<"$backup")" 'earlier backup'
}

ensure_symlink_broken_link_replaced() { #@test
  mkdir -p "$HOME/.config"
  ln -s "$BATS_TEST_TMPDIR/missing" "$HOME/.config/nvim"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output --partial "Symlink $HOME/.config/nvim is broken (target $BATS_TEST_TMPDIR/missing). Removing symlink"
  assert_links_to "$HOME/.config/nvim" "$SUBSTANCE_DIR/nvim"
}

ensure_symlink_wrong_target_replaced() { #@test
  local other="$BATS_TEST_TMPDIR/other-nvim"
  mkdir -p "$other" "$HOME/.config"
  printf 'keep\n' >"$other/marker"
  ln -s "$other" "$HOME/.config/nvim"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output --partial "$HOME/.config/nvim is incorrectly symlinked to $(readlink -f "$other"). Removing symlink"
  assert_links_to "$HOME/.config/nvim" "$SUBSTANCE_DIR/nvim"
  assert_equal "$(ls -A "$other")" marker
  assert_equal "$(<"$other/marker")" keep
}

directory_left_alone() { #@test
  mkdir "$HOME/.bashrc"

  run --separate-stderr "$SCRIPT"

  assert_success
  [[ $stderr == *"$HOME/.bashrc already exists and is not a symlink or regular file"* ]] ||
    fail "unexpected stderr: $stderr"
  assert [ -d "$HOME/.bashrc" ]
  assert [ ! -L "$HOME/.bashrc" ]
  assert_equal "$(ls -A "$HOME/.bashrc")" ''
}

non_symlink_at_ensure_symlink_path() { #@test
  mkdir -p "$HOME/.config/nvim"

  run --separate-stderr "$SCRIPT"

  assert_success
  [[ $stderr == *"$HOME/.config/nvim already exists and is not a symlink"* ]] ||
    fail "unexpected stderr: $stderr"
  assert [ -d "$HOME/.config/nvim" ]
  assert [ ! -L "$HOME/.config/nvim" ]
  assert_equal "$(ls -A "$HOME/.config/nvim")" ''
}

foreign_skill_entries_kept() { #@test
  local foreign="$BATS_TEST_TMPDIR/foreign-skill"
  mkdir -p "$foreign" "$HOME/.claude/skills/other-plugin/.claude-plugin"
  printf 'keep\n' >"$HOME/.claude/skills/other-plugin/.claude-plugin/plugin.json"
  ln -s "$foreign" "$HOME/.claude/skills/foreign"
  ln -s "$BATS_TEST_TMPDIR/nowhere" "$HOME/.claude/skills/broken"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ -d "$HOME/.claude/skills/other-plugin" ]
  assert [ ! -L "$HOME/.claude/skills/other-plugin" ]
  assert_equal "$(ls -A "$HOME/.claude/skills/other-plugin/.claude-plugin")" plugin.json
  assert_equal "$(<"$HOME/.claude/skills/other-plugin/.claude-plugin/plugin.json")" keep
  assert_links_to "$HOME/.claude/skills/foreign" "$foreign"
  assert [ -L "$HOME/.claude/skills/broken" ]
  assert_equal "$(readlink "$HOME/.claude/skills/broken")" "$BATS_TEST_TMPDIR/nowhere"
}

plugin_link_wrong_target_replaced() { #@test
  local other="$BATS_TEST_TMPDIR/other-plugin"
  mkdir -p "$other" "$HOME/.claude/skills"
  printf 'keep\n' >"$other/marker"
  ln -s "$other" "$HOME/.claude/skills/sei"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_links_to "$HOME/.claude/skills/sei" "$SUBSTANCE_DIR/claude-plugin"
  assert_equal "$(ls -A "$other")" marker
  assert_equal "$(<"$other/marker")" keep
}

stale_bin_link_removed() { #@test
  mkdir -p "$HOME/.local/bin"
  ln -s "$SUBSTANCE_DIR/bin/gone" "$HOME/.local/bin/gone"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ ! -L "$HOME/.local/bin/gone" ]
}

foreign_bin_link_kept() { #@test
  local foreign="$BATS_TEST_TMPDIR/foreign-tool"
  printf '#!/bin/sh\n' >"$foreign"
  chmod +x "$foreign"

  mkdir -p "$HOME/.local/bin"
  ln -s "$foreign" "$HOME/.local/bin/other"
  ln -s "$BATS_TEST_TMPDIR/nowhere" "$HOME/.local/bin/broken"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_links_to "$HOME/.local/bin/other" "$foreign"
  assert [ -L "$HOME/.local/bin/broken" ]
  assert_equal "$(readlink "$HOME/.local/bin/broken")" "$BATS_TEST_TMPDIR/nowhere"
}

stale_dotfile_link_removed() { #@test
  ln -s "$SUBSTANCE_DIR/dotfiles/.gone" "$HOME/.gone"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ ! -L "$HOME/.gone" ]
}
