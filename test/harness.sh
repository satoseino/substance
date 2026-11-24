#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

setup() {
  common_setup
}

fake_gh_serves_registered_response() { #@test
  use_fake_gh
  fake_gh_respond api_repos_o_r_x '{"a":1}'

  run gh api repos/o/r/x

  assert_success
  assert_output '{"a":1}'
  run cat "$FAKE_GH_DIR/calls.log"
  assert_line 'api repos/o/r/x'
}

fake_gh_applies_jq() { #@test
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"test-user"}]}}'

  run gh auth status --json hosts --jq '.hosts."github.com"[0].login'

  assert_success
  assert_output 'test-user'
}

fake_gh_jq_prints_objects_compact() { #@test
  use_fake_gh
  fake_gh_respond api_rate_limit '{"resources":{"core":{"limit":5000}}}'

  run gh api rate_limit --jq '.resources.core | {limit}'

  assert_success
  assert_output '{"limit":5000}'
}

fake_gh_jq_null_prints_empty() { #@test
  use_fake_gh
  fake_gh_respond auth '{"hosts":{}}'

  run gh auth status --json hosts --jq '.hosts."github.com"[0].login'

  assert_success
  assert_output ''
}

fake_gh_fails_on_unregistered_call() { #@test
  use_fake_gh

  run --separate-stderr gh pr view x

  assert_failure
  [[ $stderr == *"fake-gh: no response registered"* ]]
}

path_without_gh_hides_only_gh() { #@test
  local tool
  use_path_without_gh

  run ! command -v gh
  for tool in "${NO_GH_TOOLS[@]}"; do
    run -0 command -v "$tool"
  done
}

path_without_gh_links_extra_tools() { #@test
  use_path_without_gh sort

  run -0 command -v sort
  run ! command -v gh
}

path_without_gh_fails_on_unknown_or_gh_tool() { #@test
  run --separate-stderr use_path_without_gh no-such-tool-xyz
  assert_failure
  [[ $stderr == *"'no-such-tool-xyz' not found on PATH"* ]]

  run --separate-stderr use_path_without_gh gh
  assert_failure
  [[ $stderr == *"refusing to link gh"* ]]
}

mktemp_lands_in_test_tmpdir() { #@test
  local f d
  f=$(mktemp)
  d=$(mktemp -d)

  [[ $f == "$BATS_TEST_TMPDIR"/* && -f $f ]]
  [[ $d == "$BATS_TEST_TMPDIR"/* && -d $d ]]

  use_path_without_gh
  f=$(mktemp)
  [[ $f == "$BATS_TEST_TMPDIR"/* ]]
}
