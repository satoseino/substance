# Shared `gh` pre-flight check for the sei-pr-review scripts. Sourced, not
# executed. Every script must call `_gh_preflight` before its first `gh` call.

# Checks that `gh` is installed, new enough (>= 2.81.0, for
# `gh auth status --json`), and logged into github.com. On success prints the
# current GitHub login and returns 0; on failure prints `ERROR: <reason>` and
# returns 1. Call it in a command substitution so callers can relay the output.
_gh_preflight() {
  if ! command -v gh &>/dev/null; then
    echo "ERROR: gh CLI not found. Install it: https://cli.github.com/"
    return 1
  fi

  local raw
  if ! raw=$(gh auth status --json hosts --jq '.hosts."github.com"[0].login' 2>&1); then
    if [[ $raw == *"unknown flag"* ]]; then
      echo "ERROR: gh CLI is too old (needs >= 2.81.0 for 'gh auth status --json'). Upgrade gh and try again."
    else
      echo "ERROR: $raw"
    fi
    return 1
  fi

  local login
  login=$(head -n1 <<<"$raw")

  if [[ -z $login ]] || [[ $login == "null" ]] || ! [[ $login =~ ^[A-Za-z0-9-]+$ ]]; then
    echo "ERROR: not logged into GitHub via gh. Run: gh auth login"
    return 1
  fi

  printf '%s' "$login"
}
