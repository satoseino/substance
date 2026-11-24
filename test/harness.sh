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
  use_path_without_gh

  run ! command -v gh
  run -0 command -v git
  run -0 command -v jq
  run -0 command -v mktemp
  run -0 command -v readlink
}
