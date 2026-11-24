#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

setup() {
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
  use_path_without_gh find ls mkdir ln unlink mv date touch hostname whoami chmod sort
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

  local claude_user="$SUBSTANCE_DIR/claude-user"
  assert_links_to "$HOME/.claude/CLAUDE.md" "$claude_user/CLAUDE-USER.md"
  assert_links_to "$HOME/.claude/settings.json" "$claude_user/settings.json"

  local -a skills binaries
  mapfile -t skills < <(ls -1 "$SUBSTANCE_DIR/claude-user/skills")
  mapfile -t binaries < <(ls -1 "$SUBSTANCE_DIR/bin")

  ((${#skills[@]} > 0))
  ((${#binaries[@]} > 0))

  for name in "${skills[@]}"; do
    assert_links_to "$HOME/.claude/skills/$name" "$SUBSTANCE_DIR/claude-user/skills/$name"
  done

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

stale_skill_link_removed() { #@test
  local link_dir="$HOME/.claude/skills"
  mkdir -p "$link_dir"
  local skills_src="$SUBSTANCE_DIR/claude-user/skills"
  ln -s "$skills_src/sei-gone" "$link_dir/sei-gone"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ ! -L "$link_dir/sei-gone" ]
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

old_skills_symlink_torn_down() { #@test
  local old="$BATS_TEST_TMPDIR/old-skills"
  mkdir -p "$old" "$HOME/.claude"
  printf 'keep\n' >"$old/marker"
  ln -s "$old" "$HOME/.claude/skills"

  run --separate-stderr "$SCRIPT"

  assert_success
  assert [ -d "$HOME/.claude/skills" ]
  assert [ ! -L "$HOME/.claude/skills" ]

  local -a skills
  mapfile -t skills < <(ls -1 "$SUBSTANCE_DIR/claude-user/skills")

  local name
  for name in "${skills[@]}"; do
    assert_links_to "$HOME/.claude/skills/$name" "$SUBSTANCE_DIR/claude-user/skills/$name"
  done

  assert_equal "$(ls -A "$old")" marker
  assert_equal "$(<"$old/marker")" keep
}

skills_path_is_a_file() { #@test
  mkdir -p "$HOME/.claude"
  printf 'not a dir\n' >"$HOME/.claude/skills"

  run --separate-stderr "$SCRIPT"

  assert_failure
  [[ $stderr == *"$HOME/.claude/skills already exists and is not a directory or symlink"* ]] ||
    fail "unexpected stderr: $stderr"
  assert [ -f "$HOME/.claude/skills" ]
}
