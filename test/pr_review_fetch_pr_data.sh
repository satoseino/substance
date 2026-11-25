#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

setup() {
  common_setup
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"test-user","active":true}]}}'
  SCRIPT="$SKILLS_DIR/pr-review/scripts/fetch-pr-data"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/pr-review"
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: fetch-pr-data [-h] PR_URL'
}

wrong_arg_count() { #@test
  local msg='ERROR: fetch-pr-data requires exactly one positional argument PR_URL'

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output "$msg"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7 extra

  assert_success
  assert_output "$msg"
}

invalid_pr_url() { #@test
  local url
  for url in \
    https://github.com/o/r/issues/7 \
    http://github.com/o/r/pull/7 \
    https://github.com/o/r/pull/abc \
    'https://github.com/o/r/pull/7#discussion_r1' \
    https://gitlab.com/o/r/pull/7; do
    run --separate-stderr "$SCRIPT" "$url"

    assert_success
    assert_output "ERROR: not a GitHub PR URL: $url"
  done
  [[ ! -e $FAKE_GH_DIR/calls.log ]]
}

trailing_slash_accepted() { #@test
  fake_gh_respond pr-view "$(<"$FIXTURES/pr_view.json")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7/

  assert_success
  assert_output --regexp "^$BATS_TEST_TMPDIR/"
  [[ -f $output ]]
}

preflight_failure_relayed() { #@test
  use_path_without_gh

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output 'ERROR: gh CLI not found. Install it: https://cli.github.com/'
}

gh_pr_view_error() { #@test
  fake_gh_respond pr-view '' 1 'GraphQL: Could not resolve to a PullRequest'

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output 'ERROR: GraphQL: Could not resolve to a PullRequest'
}

success_output_file() { #@test
  fake_gh_respond pr-view "$(<"$FIXTURES/pr_view.json")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_equal "${#lines[@]}" 1
  [[ $output == "$BATS_TEST_TMPDIR"/* ]]
  [[ -f $output ]]
  diff -u - "$output" <<'EOF'
PR_TITLE: Add 100% coverage
BASE_BRANCH: main

PR_MESSAGE:
<pr_message>
First line.

Second line.
</pr_message>
EOF
  # calls.log quotes each arg with printf %q, which may escape the commas.
  local expected
  printf -v expected '%q ' pr view https://github.com/o/r/pull/7 --json title,body,baseRefName
  run cat "$FAKE_GH_DIR/calls.log"
  assert_line "${expected% }"
}

null_body() { #@test
  fake_gh_respond pr-view '{"title":"T","baseRefName":"dev","body":null}'

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  diff -u - "$output" <<'EOF'
PR_TITLE: T
BASE_BRANCH: dev

PR_MESSAGE:
<pr_message>

</pr_message>
EOF
}
