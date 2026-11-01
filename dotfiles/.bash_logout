main() {
  # fnm keeps multishell symlinks under $HOME/.local/state/fnm_multishells/ when there is no usable
  # $XDG_RUNTIME_DIR (always on macOS; on WSL when the login session failed to start). Nothing cleans
  # that dir up, so prune it here. Under $XDG_RUNTIME_DIR the symlinks live on a tmpfs already.
  if [[ "${FNM_MULTISHELL_PATH:-}" != "${HOME}/.local/state/fnm_multishells/"* ]]; then
    return
  fi

  # Disable exit on error for cleanup.
  set +e

  find "$(dirname "${FNM_MULTISHELL_PATH}")/" -type l -name '*_*' -mtime +60 -exec rm {} +
}

main
