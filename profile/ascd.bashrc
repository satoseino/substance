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
source "$SEI_SUBSTANCE_DIR/lib/commands.sh"
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

# Run the morning update steps in Ghostty's quick terminal, at most once every 24 hours.
# The stamp is touched only when every step succeeds, so a failure or Ctrl-C retries next time.
_sei_ascd::daily_update() {
  local stamp="$SEI_SUBSTANCE_DIR/_cache/daily-update.stamp"
  local reply

  # Child processes inherit GHOSTTY_QUICK_TERMINAL, so also require the top-level interactive shell.
  if [[ $- != *i* ]] || ((SHLVL != 1)) || [[ -z "${GHOSTTY_QUICK_TERMINAL:+x}" ]]; then
    return 0
  fi

  # find prints the stamp only if it was modified within the last 24 hours.
  if [[ -n "$(find "$stamp" -mmin -1440 2>/dev/null)" ]]; then
    return 0
  fi

  sei::log_info "Daily update: subp"
  subp || return 1

  sei::log_info "Daily update: claude update"
  claude update || return 1

  sei::log_info "Daily update: brew update"
  brew update || return 1

  sei::log_info "Proceed with brew upgrade? [Y/n]"
  read -r reply || return 1

  if [[ -z "$reply" || "$reply" == [Yy]* ]]; then
    brew upgrade || return 1
  fi

  mkdir -p "${stamp%/*}"
  touch "$stamp"
}

_sei_ascd::daily_update
# ------------------------------------------------------------------------
