#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"
load "test_helper/git_repo"

PR_URL=https://github.com/o/r/pull/7

setup() {
  common_setup
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"test-user","active":true}]}}'
  SCRIPT="$SKILLS_DIR/sei-pr-review/scripts/verify-sha"

  repo_init
  text_lines 3 >f.txt
  commit_all root
  HEAD_SHA=$(git rev-parse HEAD)
}

# respond_head_sha SHA_JSON
respond_head_sha() {
  fake_gh_respond pr-view "{\"headRefOid\":$1}"
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: verify-sha [-h] PR_URL'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: verify-sha requires exactly one positional argument PR_URL'
}

invalid_pr_url() { #@test
  run --separate-stderr "$SCRIPT" https://github.com/o/r/issues/7

  assert_success
  assert_output 'ERROR: not a GitHub PR URL: https://github.com/o/r/issues/7'
}

preflight_failure_relayed() { #@test
  fake_gh_respond auth '{"hosts":{}}' 0 \
    'You are not logged into any GitHub hosts. To log in, run: gh auth login'

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output 'ERROR: not logged into GitHub via gh. Run: gh auth login'
}

gh_pr_view_error() { #@test
  fake_gh_respond pr-view '' 1 'HTTP 404: Not Found'

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output 'ERROR: HTTP 404: Not Found'
}

unexpected_sha() { #@test
  respond_head_sha '"abc"'

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output "ERROR: unexpected PR head SHA from gh: 'abc'"

  respond_head_sha null

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output "ERROR: unexpected PR head SHA from gh: ''"
}

not_a_git_repo() { #@test
  respond_head_sha "\"$HEAD_SHA\""
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output --regexp '^ERROR: '
  assert_output --partial 'not a git repository'
}

pass_on_branch() { #@test
  respond_head_sha "\"$HEAD_SHA\""

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output 'VERIFY-SHA: PASS'
}

pass_on_detached_head() { #@test
  git checkout -q --detach
  respond_head_sha "\"$HEAD_SHA\""

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output 'VERIFY-SHA: PASS'
}

fail_on_mismatch() { #@test
  local other=0123456789abcdef0123456789abcdef01234567
  respond_head_sha "\"$other\""

  run --separate-stderr "$SCRIPT" "$PR_URL"

  assert_success
  assert_output "VERIFY-SHA: FAIL — local HEAD $HEAD_SHA ≠ PR head $other"
}
