#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"test-user","active":true}]}}'
  SCRIPT="$SKILLS_DIR/pr-review/scripts/fetch-pr-data"

  git init -q --bare -b main "$BATS_TEST_TMPDIR/origin.git"
  repo_init
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"
  text_lines 3 >f.txt
  commit_all root
  git push -q origin main
  HEAD_SHA=$(git rev-parse HEAD)
}

# pr_view_json BASE_SHA
# Print `gh pr view` JSON for a PR into `main` whose base commit is BASE_SHA.
pr_view_json() {
  jq -n --arg sha "$1" \
    '{title: "Add 100% coverage", baseRefName: "main", baseRefOid: $sha, body: "First line.\r\n\r\nSecond line."}'
}

# Push a new commit to origin's main from a second clone and print its SHA.
# The work repo does not have it.
push_from_other_clone() {
  local other=$BATS_TEST_TMPDIR/other
  git clone -q "$BATS_TEST_TMPDIR/origin.git" "$other"
  text_lines 3 2=two >"$other/f.txt"
  git -C "$other" commit -q -am "base moved"
  git -C "$other" push -q origin main
  git -C "$other" rev-parse HEAD
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
  fake_gh_respond pr-view "$(pr_view_json "$HEAD_SHA")"

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
  fake_gh_respond pr-view "$(pr_view_json "$HEAD_SHA")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_equal "${#lines[@]}" 1
  [[ $output == "$BATS_TEST_TMPDIR"/* ]]
  [[ -f $output ]]
  diff -u - "$output" <<EOF
PR_TITLE: Add 100% coverage
BASE_BRANCH: main
BASE_SHA: $HEAD_SHA

PR_MESSAGE:
<pr_message>
First line.

Second line.
</pr_message>
EOF
  # calls.log quotes each arg with printf %q, which may escape the commas.
  local expected
  printf -v expected '%q ' pr view https://github.com/o/r/pull/7 --json title,body,baseRefName,baseRefOid
  run cat "$FAKE_GH_DIR/calls.log"
  assert_line "${expected% }"
}

null_body() { #@test
  fake_gh_respond pr-view "{\"title\":\"T\",\"baseRefName\":\"dev\",\"baseRefOid\":\"$HEAD_SHA\",\"body\":null}"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  diff -u - "$output" <<EOF
PR_TITLE: T
BASE_BRANCH: dev
BASE_SHA: $HEAD_SHA

PR_MESSAGE:
<pr_message>

</pr_message>
EOF
}

base_commit_already_local_no_fetch() { #@test
  git remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
  fake_gh_respond pr-view "$(pr_view_json "$HEAD_SHA")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  [[ -f $output ]]
  grep -qx "BASE_SHA: $HEAD_SHA" "$output"
}

base_commit_fetched_without_writing_refs() { #@test
  local base_sha refs_before
  base_sha=$(push_from_other_clone)
  ! git cat-file -e "$base_sha^{commit}" 2>/dev/null
  refs_before=$(git for-each-ref)
  fake_gh_respond pr-view "$(pr_view_json "$base_sha")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  grep -qx "BASE_SHA: $base_sha" "$output"
  git cat-file -e "$base_sha^{commit}"
  assert_equal "$(git for-each-ref)" "$refs_before"
  [[ ! -e .git/FETCH_HEAD ]]
}

fetch_failure() { #@test
  local base_sha
  base_sha=$(push_from_other_clone)
  git remote set-url origin "$BATS_TEST_TMPDIR/missing.git"
  fake_gh_respond pr-view "$(pr_view_json "$base_sha")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output --regexp "^ERROR: failed to fetch origin's main: "
}

base_commit_not_on_origin() { #@test
  local foreign_sha
  git init -q "$BATS_TEST_TMPDIR/unrelated"
  git -C "$BATS_TEST_TMPDIR/unrelated" commit -q --allow-empty -m unrelated
  foreign_sha=$(git -C "$BATS_TEST_TMPDIR/unrelated" rev-parse HEAD)
  fake_gh_respond pr-view "$(pr_view_json "$foreign_sha")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output "ERROR: base commit $foreign_sha not found on origin's main; is origin the PR's base repository?"
}

malformed_base_sha() { #@test
  fake_gh_respond pr-view "$(pr_view_json abc)"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output "ERROR: unexpected PR base SHA from gh: 'abc'"

  fake_gh_respond pr-view '{"title":"T","baseRefName":"main","baseRefOid":null,"body":"B"}'

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output "ERROR: unexpected PR base SHA from gh: 'null'"
}

not_a_git_repo() { #@test
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR
  fake_gh_respond pr-view "$(pr_view_json "$HEAD_SHA")"

  run --separate-stderr "$SCRIPT" https://github.com/o/r/pull/7

  assert_success
  assert_output --regexp '^ERROR: '
  assert_output --partial 'not a git repository'
}
