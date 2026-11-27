# ------------------------------------------------------------------------
# Environment variables.

# ASCENDING AWS profiles and regions.
export SEI_AWS_PROFILE_PREFIX="ascending"
export SEI_AWS_REGIONS="us-east-1"
# ------------------------------------------------------------------------
# Aliases.

alias gs='git status'
# ------------------------------------------------------------------------
# Functions.

source "$SEI_SUBSTANCE_DIR/lib/utils.sh"
source "$SEI_SUBSTANCE_DIR/lib/rw.sh"
source "$SEI_SUBSTANCE_DIR/lib/jarvis-logs.sh"
source "$SEI_SUBSTANCE_DIR/lib/jarvis-dc.sh"
source "$SEI_SUBSTANCE_DIR/lib/jarvis-pf.sh"

sso-login() {
  PATH="$HOME/.local/bin:/usr/local/bin:$PATH" aws sso login --sso-session sso-ascending
}

kjd() {
  export AWS_PROFILE=ascending-saas-admin

  if ! aws sts get-caller-identity &>/dev/null; then
    PATH="$HOME/.local/bin:/usr/local/bin:$PATH" aws sso login --sso-session sso-ascending
  fi

  k9s -n jarvis-demo
}

gjrw() {
  mkdir -p "$HOME/temp/dump"

  cd "$HOME/temp/dump" || return 1

  gt k9s

  gn "$HOME/projects/jarvis-registry-workspace/registry-working-docs/"

  gn "$HOME/projects/jarvis-registry-workspace"

  printf '\033[H\033[2J'
}
# ------------------------------------------------------------------------
# Daily update.

# Fast-forward the substance repo's local main to origin/main, whatever branch is checked out.
# `fetch origin main:main` refuses to update a checked-out branch, so pull when main is checked out.
# Both refuse a non-fast-forward, so local commits on main are never overwritten.
_sei_ascd::update_substance_main() {
  if [[ "$(git -C "$SEI_SUBSTANCE_DIR" symbolic-ref --short -q HEAD)" == main ]]; then
    git -C "$SEI_SUBSTANCE_DIR" pull --ff-only origin main
  else
    git -C "$SEI_SUBSTANCE_DIR" fetch origin main:main
  fi
}

# Run the morning update steps in Ghostty's quick terminal, at most once every 24 hours.
# The stamp is touched only when every step succeeds, so a failure or Ctrl-C retries next time.
_sei_ascd::daily_update() {
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
  if ! _sei_ascd::update_substance_main; then
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

# Run the daily update from the first prompt rather than during startup: a Ctrl-C while startup files
# run aborts all of the remaining startup code. The hook removes itself before running, so it fires once.
_sei_ascd::daily_update_once() {
  local i

  for i in "${!PROMPT_COMMAND[@]}"; do
    if [[ "${PROMPT_COMMAND[i]}" == _sei_ascd::daily_update_once ]]; then
      unset 'PROMPT_COMMAND[i]'
    fi
  done

  _sei_ascd::daily_update
}

PROMPT_COMMAND+=(_sei_ascd::daily_update_once)
# ------------------------------------------------------------------------
