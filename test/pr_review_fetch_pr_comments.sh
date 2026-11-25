#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

PR_URL=https://github.com/o/r/pull/7

setup() {
  common_setup
  use_fake_gh
  SCRIPT="$SKILLS_DIR/pr-review/scripts/fetch-pr-comments"
  FIXTURES="$BATS_TEST_DIRNAME/fixtures/pr-review"

  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"reviewer","active":true}]}}'
  fake_gh_respond api_repos_o_r_pulls_7_comments "$(<"$FIXTURES/inline_comments.json")"
  fake_gh_respond api_repos_o_r_issues_7_comments "$(<"$FIXTURES/issue_comments.json")"
}

# run_script ARG... — run the script, assert success and keep its stdout (the
# output file path, on the success path) in `outfile`.
run_script() {
  run --separate-stderr "$SCRIPT" "$@"
  assert_success
  outfile=$output
}

# label_map — print the LABEL_MAP entries of `outfile` (heading excluded).
label_map() {
  sed -n '2,/^$/p' "$outfile" | sed '$d'
}

# --- Argument and error handling ---

help_flag() { #@test
  run_script -h

  assert_output --partial 'Usage: fetch-pr-comments [-h] PR_URL LABEL [LABEL...]'
}

no_args() { #@test
  run_script

  assert_output 'ERROR: fetch-pr-comments requires at least a PR_URL argument'
}

no_labels() { #@test
  run_script "$PR_URL"

  assert_output 'ERROR: no finding labels provided'

  run_script "$PR_URL" ""

  assert_output 'ERROR: no finding labels provided'
}

invalid_pr_url() { #@test
  run_script https://github.com/o/r/issues/7 C1

  assert_output 'ERROR: not a GitHub PR URL: https://github.com/o/r/issues/7'
}

preflight_failure_relayed() { #@test
  use_path_without_gh

  run_script "$PR_URL" C1

  assert_output 'ERROR: gh CLI not found. Install it: https://cli.github.com/'
}

inline_api_error() { #@test
  fake_gh_respond api_repos_o_r_pulls_7_comments '' 1 'HTTP 403: rate limit'

  run_script "$PR_URL" C1

  assert_output 'ERROR: HTTP 403: rate limit'
}

issue_api_error() { #@test
  fake_gh_respond api_repos_o_r_issues_7_comments '' 1 'HTTP 500'

  run_script "$PR_URL" C1

  assert_output 'ERROR: HTTP 500'
}

calls_expected_endpoints() { #@test
  fake_gh_respond api_repos_acme_widget_pulls_42_comments '[[]]'
  fake_gh_respond api_repos_acme_widget_issues_42_comments '[[]]'

  run_script "$PR_URL" C1
  run_script https://github.com/acme/widget/pull/42 C1

  run cat "$FAKE_GH_DIR/calls.log"
  assert_line 'api repos/o/r/pulls/7/comments --paginate --slurp'
  assert_line 'api repos/o/r/issues/7/comments --paginate --slurp'
  assert_line 'api repos/acme/widget/pulls/42/comments --paginate --slurp'
  assert_line 'api repos/acme/widget/issues/42/comments --paginate --slurp'
}

# --- Output content ---

full_output() { #@test
  run_script "$PR_URL" "C1 C2 C5" M1 M2 m10 X9

  diff -u "$FIXTURES/expected_comments.txt" "$outfile"
}

labels_split_on_whitespace() { #@test
  run_script "$PR_URL" C1 C2 C5 M1 M2 m10 X9

  diff -u "$FIXTURES/expected_comments.txt" "$outfile"
}

label_map_follows_argument_order() { #@test
  run_script "$PR_URL" X9 C1

  run label_map
  assert_output "$(printf '%s\n' '  [X9] → NOT_FOUND' '  [C1] → FOUND')"
}

only_current_user_comments() { #@test
  run_script "$PR_URL" C9 C3
  local out
  out=$(cat "$outfile")

  run label_map
  assert_output "$(printf '%s\n' '  [C9] → NOT_FOUND' '  [C3] → NOT_FOUND')"
  [[ $out != *'## Thread: [C9]'* ]]
  [[ $out != *'## Thread: [C3]'* ]]
}

first_paragraph_must_match_exactly() { #@test
  run_script "$PR_URL" M3 M4

  run label_map
  assert_output "$(printf '%s\n' '  [M3] → NOT_FOUND' '  [M4] → NOT_FOUND')"
}

first_label_in_thread_wins() { #@test
  run_script "$PR_URL" C5 M2
  local out
  out=$(cat "$outfile")

  run label_map
  assert_output "$(printf '%s\n' '  [C5] → NOT_FOUND' '  [M2] → FOUND')"
  [[ $out != *'## Thread: [C5]'* ]]
  # The C5 reply is rendered inside the first [M2] thread, before its `---`.
  local m2_thread=${out#*'## Thread: [M2]'}
  m2_thread=${m2_thread%%---*}
  [[ $m2_thread == *'> This is change request [C5].'* ]]
}

no_carriage_returns() { #@test
  run_script "$PR_URL" M2

  # -1, not !: grep exits 2 on a missing file, which must not count as a pass.
  run -1 grep -q $'\r' "$outfile"
}

no_comments() { #@test
  fake_gh_respond api_repos_o_r_pulls_7_comments '[[]]'
  fake_gh_respond api_repos_o_r_issues_7_comments '[[]]'

  run_script "$PR_URL" C1 M1

  diff -u - "$outfile" <<'EOF'
LABEL_MAP:
  [C1] → NOT_FOUND
  [M1] → NOT_FOUND

---

## Unlinked labels (no matching reviewer comment found):
- [C1]
- [M1]
EOF
}
