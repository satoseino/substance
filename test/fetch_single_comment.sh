#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

# No `auth` response is registered: the script has no gh preflight, so any
# `gh auth` call would fail loudly in the fake.
setup() {
  common_setup
  use_fake_gh
  SCRIPT="$SKILLS_DIR/fetch-single-comment/scripts/fetch-single-comment"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/fetch-single-comment"
  ISSUE_KEY=api_repos_o_r_issues_comments_456
  PULLS_KEY=api_repos_o_r_pulls_comments_789
  ISSUE_URL='https://github.com/o/r/pull/7#issuecomment-456'
  REVIEW_URL='https://github.com/o/r/pull/7#discussion_r789'
  BLOCK_A=$(
    cat <<'EOF'
## PR comment issuecomment-456

AUTHOR: alice

> Line one.
>
> Line three.
EOF
  )
  BLOCK_B=$(
    cat <<'EOF'
## PR comment discussion_r789

AUTHOR: bob; PATH: src/a.py; LINE: 12

> Inline note.
EOF
  )
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: fetch-single-comment [-h] COMMENT_URL'
}

wrong_arg_count() { #@test
  local msg='ERROR: fetch-single-comment requires exactly one positional argument COMMENT_URL'

  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output "$msg"

  run --separate-stderr "$SCRIPT" "$ISSUE_URL" extra

  assert_success
  assert_output "$msg"
}

unrecognized_url() { #@test
  local url
  for url in \
    https://github.com/o/r/pull/7 \
    'https://github.com/o/r/pull/7#issuecomment-abc' \
    'https://github.com/o/r/pull/7#discussion_rx' \
    'https://github.com/o/r/issues/7#issuecomment-1' \
    'https://github.com/o/r/pull/7#pullrequestreview-1' \
    'https://github.com/o/r/pull/7#issuecomment-1x'; do
    run --separate-stderr "$SCRIPT" "$url"

    assert_success
    assert_output "ERROR: not a recognized PR comment URL: $url"
  done
  [[ ! -e $FAKE_GH_DIR/calls.log ]]
}

issue_comment() { #@test
  fake_gh_respond "$ISSUE_KEY" "$(<"$FIXTURES/issue_comment.json")"

  run --separate-stderr "$SCRIPT" "$ISSUE_URL"

  assert_success
  assert_equal "${#lines[@]}" 1
  [[ $output == "$BATS_TEST_TMPDIR"/* ]]
  [[ -f $output ]]
  local outfile=$output

  run cat "$FAKE_GH_DIR/calls.log"
  assert_output 'api repos/o/r/issues/comments/456'

  run cat "$outfile"
  assert_output "$BLOCK_A"
}

review_comment() { #@test
  fake_gh_respond "$PULLS_KEY" "$(<"$FIXTURES/review_comment.json")"

  run --separate-stderr "$SCRIPT" "$REVIEW_URL"

  assert_success
  local outfile=$output

  run cat "$FAKE_GH_DIR/calls.log"
  assert_output 'api repos/o/r/pulls/comments/789'

  run cat "$outfile"
  assert_output "$BLOCK_B"
}

trailing_slash_before_fragment() { #@test
  fake_gh_respond "$ISSUE_KEY" "$(<"$FIXTURES/issue_comment.json")"

  run --separate-stderr "$SCRIPT" 'https://github.com/o/r/pull/7/#issuecomment-456'

  assert_success
  run cat "$output"
  assert_output "$BLOCK_A"
}

review_comment_original_line_fallback() { #@test
  fake_gh_respond "$PULLS_KEY" "$(jq -c '.line = null | .original_line = 7' "$FIXTURES/review_comment.json")"

  run --separate-stderr "$SCRIPT" "$REVIEW_URL"

  assert_success
  run cat "$output"
  assert_line 'AUTHOR: bob; PATH: src/a.py; LINE: 7'
}

review_comment_file_level() { #@test
  fake_gh_respond "$PULLS_KEY" "$(jq -c '.line = null | .original_line = null' "$FIXTURES/review_comment.json")"

  run --separate-stderr "$SCRIPT" "$REVIEW_URL"

  assert_success
  run cat "$output"
  assert_line 'AUTHOR: bob; PATH: src/a.py; LINE: (file)'
}

issue_comment_has_no_path_line() { #@test
  fake_gh_respond "$ISSUE_KEY" "$(<"$FIXTURES/issue_comment.json")"

  run --separate-stderr "$SCRIPT" "$ISSUE_URL"

  assert_success
  run cat "$output"
  assert_success
  refute_line --partial 'PATH:'
}

gh_api_error() { #@test
  fake_gh_respond "$ISSUE_KEY" '' 1 'HTTP 404: Not Found'

  run --separate-stderr "$SCRIPT" "$ISSUE_URL"

  assert_success
  assert_output 'ERROR: HTTP 404: Not Found'
}

gh_missing() { #@test
  use_path_without_gh

  run --separate-stderr "$SCRIPT" "$ISSUE_URL"

  assert_success
  assert_output --regexp '^ERROR: '
  assert_output --partial 'gh: command not found'
}

no_auth_preflight_call() { #@test
  fake_gh_respond "$ISSUE_KEY" "$(<"$FIXTURES/issue_comment.json")"

  run --separate-stderr "$SCRIPT" "$ISSUE_URL"

  assert_success
  run grep -c '^auth' "$FAKE_GH_DIR/calls.log"
  assert_failure 1
  assert_output 0
}
