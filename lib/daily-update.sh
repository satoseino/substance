if [[ -n "${_sei_module_set_daily_update+x}" ]]; then
  return
fi

_sei_module_set_daily_update=1

source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/utils.sh"

# Fast-forward the substance repo's local main to origin/main, whatever branch is checked out.
# `fetch origin main:main` refuses to update a checked-out branch, so pull when main is checked out.
# Both refuse a non-fast-forward, so local commits on main are never overwritten.
_sei_daily_update::update_substance_main() {
  if [[ "$(git -C "$SEI_SUBSTANCE_DIR" symbolic-ref --short -q HEAD)" == main ]]; then
    git -C "$SEI_SUBSTANCE_DIR" pull --ff-only origin main
  else
    git -C "$SEI_SUBSTANCE_DIR" fetch origin main:main
  fi
}

# Run the morning update steps in Ghostty's quick terminal, at most once every 24 hours.
# The stamp is touched only when every step succeeds, so a failure or Ctrl-C retries next time.
_sei_daily_update::run() {
  # Child processes inherit GHOSTTY_QUICK_TERMINAL, so also require the top-level interactive shell.
  if [[ $- != *i* ]] || ((SHLVL != 1)) || [[ -z "${GHOSTTY_QUICK_TERMINAL:+x}" ]]; then
    return 0
  fi

  local stamp="$SEI_SUBSTANCE_DIR/_cache/daily-update.stamp"
  local reply head_before all_ok=1

  # find prints the stamp only if it was modified within the last 24 hours.
  if [[ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ]]; then
    return 0
  fi

  # A failure here shouldn't block the other steps, but it leaves the stamp untouched.
  sei::log_info "Daily update: fast-forward main"
  head_before=$(git -C "$SEI_SUBSTANCE_DIR" rev-parse HEAD)
  if ! _sei_daily_update::update_substance_main; then
    sei::log_error "Daily update: could not fast-forward main. Continuing with the other steps."
    all_ok=0
  fi

  # This shell has already sourced the pre-pull code.
  if [[ "$(git -C "$SEI_SUBSTANCE_DIR" rev-parse HEAD)" != "$head_before" ]]; then
    sei::log_info "The substance repo was updated. Open a new shell to load the changes."
  fi

  sei::log_info "Daily update: claude update"
  claude update || return 1

  sei::log_info "Daily update: brew update"
  brew update || return 1

  sei::log_info "Proceed with brew upgrade? [Y/n]"
  read -r reply || return 1

  if [[ -z "$reply" || "$reply" == [Yy]* ]]; then
    brew upgrade || return 1
  fi

  if ((all_ok)); then
    mkdir -p "${stamp%/*}"
    touch "$stamp"
  fi
}

# The PROMPT_COMMAND hook. It removes itself before running, so it fires once.
_sei_daily_update::hook() {
  local i

  for i in "${!PROMPT_COMMAND[@]}"; do
    if [[ "${PROMPT_COMMAND[i]}" == _sei_daily_update::hook ]]; then
      unset 'PROMPT_COMMAND[i]'
    fi
  done

  _sei_daily_update::run
}

# Schedule the daily update to run once, at the next prompt. It runs from the prompt rather than during
# startup because a Ctrl-C while startup files run aborts all of the remaining startup code.
# Calling it again before that prompt (e.g. `enter-work-mode` re-sourcing the profile) adds nothing.
sei::daily_update_once() {
  local cmd

  for cmd in "${PROMPT_COMMAND[@]}"; do
    if [[ "$cmd" == _sei_daily_update::hook ]]; then
      return 0
    fi
  done

  PROMPT_COMMAND+=(_sei_daily_update::hook)
}
