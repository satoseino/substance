#!/usr/bin/env bash

setup_suite() {
  export GIT_AUTHOR_NAME="Test User"
  export GIT_AUTHOR_EMAIL="test@example.com"
  export GIT_COMMITTER_NAME="Test User"
  export GIT_COMMITTER_EMAIL="test@example.com"

  # Isolate tests from the developer's git config (merge.conflictStyle,
  # diff.*, color.* etc. would change script output).
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_NOSYSTEM=1

  # Deterministic collation for `sort` in the scripts under test.
  export LC_ALL=C

  local test_dir
  test_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  export SKILLS_DIR="$test_dir/../claude-user/skills"
  SKILLS_DIR="$(cd "$SKILLS_DIR" && pwd)"
}
