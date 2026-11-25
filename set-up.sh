#!/usr/bin/env bash

set -eu -o pipefail

source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/lib/utils.sh"

# Check whether a symlink points into a given directory, i.e. whether it was
# created by this script and is therefore safe for it to remove. Works for
# broken symlinks too.
# Args:
#   $1: symlink path
#   $2: directory (canonical absolute path)
# Returns: 0 if the symlink's target is under the directory, 1 otherwise
_points_into() {
  local target

  # readlink -f fails on a broken symlink (and GNU readlink prints nothing when
  # a parent of the target is missing); fall back to the raw target, which is
  # absolute for every symlink this script creates.
  target="$(readlink -f "$1")" || target="$(readlink "$1")" || return 1

  [[ "$target" == "$2"/* ]]
}

# Create symlinks in source_dir and point them to actual files in sink_dir.
# Args:
#   $1: source_dir
#   $2: sink_dir
#   $3: name of the array variable that holds base names
# Returns: None
_link_files() {
  local -n base_names="$3"

  local name backup

  for name in "${base_names[@]}"; do
    if [[ -L "$1/$name" && ! -e "$1/$name" ]]; then
      sei::log_info "Symlink $1/$name is broken (target $(readlink "$1/$name")). Removing symlink"

      unlink "$1/$name"
    elif [[ -L "$1/$name" ]] && [[ "$1/$name" -ef "$2/$name" ]]; then
      # If already correctly symlinked, continue.
      continue
    elif [[ -L "$1/$name" ]]; then
      sei::log_info "$name is symlinked to $(readlink -f "$1/$name"). Removing symlink"

      unlink "$1/$name"
    elif [[ -f "$1/$name" ]]; then
      # If the ln target already exists as a regular file, back it up rather
      # than deleting it, so a first run never destroys user data.
      backup="$1/$name.bak.$(date +%Y%m%d%H%M%S)"

      # Explicit check instead of `mv -n`, whose exit status differs between
      # GNU coreutils versions and BSD.
      if [[ -e "$backup" ]]; then
        sei::log_error "Cannot back up $1/$name: $backup already exists"

        continue
      fi

      mv "$1/$name" "$backup"

      sei::log_info "Backed up existing file $1/$name to $backup"
    elif [[ -e "$1/$name" ]]; then
      # If the ln target exists as anything else (e.g. a directory), leave it
      # alone: ln -s would otherwise create the symlink inside it.
      sei::log_error "$1/$name already exists and is not a symlink or regular file"

      continue
    fi

    ln -s "$2/$name" "$1/$name"

    sei::log_info "$name has been correctly symlinked"
  done
}

# Ensure link_path is a symlink pointing to target_path.
# Creates the symlink if absent; recreate the symlink if target is wrong.
# Logs an error if the path exists but is not a symlink.
# Args:
#   $1: link_path
#   $2: target_path
# Returns: None
_ensure_symlink() {
  local link_path="$1"
  local target_path="$2"

  if [[ -L "$link_path" && ! -e "$link_path" ]]; then
    sei::log_info "Symlink $link_path is broken (target $(readlink "$link_path")). Removing symlink"

    unlink "$link_path"
  elif [[ -L "$link_path" ]] && [[ "$link_path" -ef "$target_path" ]]; then
    return 0
  elif [[ -L "$link_path" ]]; then
    sei::log_info "$link_path is incorrectly symlinked to $(readlink -f "$link_path"). Removing symlink"

    unlink "$link_path"
  elif [[ -e "$link_path" ]]; then
    sei::log_error "$link_path already exists and is not a symlink"

    return 0
  fi

  sei::log_info "Symlinking $link_path to $target_path"

  ln -s "$target_path" "$link_path"
}

# Ensure none of the given paths is a leftover symlink from an old scheme,
# removing it if present. A real directory is the happy default (the current
# scheme's steady state) and is left untouched. Non-existent paths are
# skipped without error. Logs an error and returns early with non-zero exit
# code if any path exists as something other than a directory or a symlink
# (e.g. a regular file).
# Args:
#   $@: paths to check
# Returns: None
_ensure_no_symlink() {
  local path

  for path in "$@"; do
    if [[ -L "$path" ]]; then
      sei::log_info "Removing symlink $path"

      unlink "$path"
    elif [[ -d "$path" ]]; then
      continue
    elif [[ -e "$path" ]]; then
      sei::log_error "$path already exists and is not a directory or symlink"

      return 1
    fi
  done
}

main() {
  # Tear down the old whole-folder Claude skills symlink, if present. A real
  # directory here is the current scheme's steady state (see mkdir -p below)
  # and is left alone.
  _ensure_no_symlink "$HOME/.claude/skills"

  # Make necessary directories first.
  mkdir -p "$HOME/.config/ghostty"
  mkdir -p "$HOME/.config/bat"
  mkdir -p "$HOME/.vim"
  mkdir -p "$HOME/.claude/skills"
  mkdir -p "$HOME/.local/bin"

  local substance_dir
  substance_dir="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

  local prefix
  sei::get_env_prefix "prefix"

  local -a linked=(
    .bash_logout
    .bash_profile
    .bashrc
    .gitconfig
    .gvimrc
    .inputrc
    .vimrc
  )

  [[ "$prefix" == "fedora" ]] && linked+=(".tmux.conf")

  _link_files "$HOME" "$substance_dir/dotfiles" "linked"

  # shellcheck disable=SC2034 # used via nameref
  linked=(.config/ghostty/config .config/bat/config)
  _link_files "$HOME" "$substance_dir" "linked"

  # Symlinking nvim folder
  _ensure_symlink "$HOME/.config/nvim" "$substance_dir/nvim/"

  # Symlinking own Vim plugin scripts
  _ensure_symlink "$HOME/.vim/plugin" "$substance_dir/.vim/plugin/"

  local name

  # Symlinking Claude related files and folders
  local -a skills
  mapfile -t skills < <(find "$HOME/.claude/skills" -maxdepth 1 -mindepth 1 -type l)

  # Clean up stale symlinks in ~/.claude/skills created by this script. This
  # also removes the pre-plugin per-skill links (~/.claude/skills/sei-*), whose
  # targets under claude-user/skills/ no longer exist.
  for name in "${skills[@]}"; do
    if [[ ! -e "$name" ]] && _points_into "$name" "$substance_dir"; then
      sei::log_info "Skill symlink $name should no longer exist. Removing"

      unlink "$name"
    fi
  done

  # One symlink to the `sei` plugin root; Claude Code loads it as
  # sei@skills-dir, so new skills appear without re-running this script.
  _ensure_symlink "$HOME/.claude/skills/sei" "$substance_dir/claude-plugin"

  _ensure_symlink "$HOME/.claude/CLAUDE.md" "$substance_dir/claude-user/CLAUDE-USER.md"
  _ensure_symlink "$HOME/.claude/settings.json" "$substance_dir/claude-user/settings.json"

  local -a binaries

  mapfile -t binaries < <(ls -1 "$substance_dir/bin")

  _link_files "$HOME/.local/bin" "$substance_dir/bin" "binaries"

  mapfile -t binaries < <(find "$HOME/.local/bin" -maxdepth 1 -mindepth 1 -type l)

  # Clean up stale symlinks in ~/.local/bin created by this script. The folder
  # is shared with other installers, whose symlinks must be left alone.
  for name in "${binaries[@]}"; do
    if [[ ! -x "$name" ]] && _points_into "$name" "$substance_dir"; then
      sei::log_info "Script $name should no longer exist. Removing"

      unlink "$name"
    fi
  done

  local -a dotfiles
  mapfile -t dotfiles < <(find "$HOME" -maxdepth 1 -mindepth 1 -type l)

  # Clean up stale symlinks to dot files created by this script
  for name in "${dotfiles[@]}"; do
    if ! _points_into "$name" "$substance_dir"; then
      continue
    fi

    if [[ ! -e "$name" ]] || [[ "$prefix" != "fedora" && "$name" == "$HOME/.tmux.conf" ]]; then
      sei::log_info "Dot file $name should no longer exist. Removing"

      unlink "$name"
    fi
  done

  # Suppress login(1)'s "Last login: ..." banner.
  if [[ ! -e "$HOME/.hushlogin" ]]; then
    touch "$HOME/.hushlogin"

    sei::log_info "Created $HOME/.hushlogin"
  fi

  # Install git hooks if pre-commit exists
  if ! type pre-commit &>/dev/null; then
    return 0
  fi

  local -a args=()
  [[ -e "$substance_dir/.git/hooks/pre-commit" ]] || args+=("-t" "pre-commit")
  [[ -e "$substance_dir/.git/hooks/post-merge" ]] || args+=("-t" "post-merge")

  if ((${#args[@]} > 0)); then
    (cd "$substance_dir" && pre-commit install "${args[@]}")
  fi
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
