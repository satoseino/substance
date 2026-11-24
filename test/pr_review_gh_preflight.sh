#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2154

load "test_helper/common"

AUTH_OK='{"hosts":{"github.com":[{"login":"test-user","active":true}]}}'
NOT_LOGGED_IN='ERROR: not logged into GitHub via gh. Run: gh auth login'

setup() {
  common_setup
  LIB="$SKILLS_DIR/sei-pr-review/scripts/lib/gh-preflight.sh"
}

run_preflight() {
  run --separate-stderr bash -c 'source "$1"; _gh_preflight' _ "$LIB"
}

gh_missing() { #@test
  use_path_without_gh

  run_preflight

  assert_failure 1
  assert_output 'ERROR: gh CLI not found. Install it: https://cli.github.com/'
}

gh_too_old() { #@test
  use_fake_gh
  fake_gh_respond auth '' 1 'unknown flag: --json'

  run_preflight

  assert_failure 1
  assert_output --partial 'ERROR: gh CLI is too old (needs >= 2.81.0'
}

gh_auth_other_error() { #@test
  use_fake_gh
  fake_gh_respond auth '' 1 'connection refused'

  run_preflight

  assert_failure 1
  assert_output 'ERROR: connection refused'
}

logged_out() { #@test
  use_fake_gh
  fake_gh_respond auth '{"hosts":{}}' 0 \
    'You are not logged into any GitHub hosts. To log in, run: gh auth login'

  run_preflight

  assert_failure 1
  assert_output "$NOT_LOGGED_IN"
}

empty_host_list() { #@test
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[]}}'

  run_preflight

  assert_failure 1
  assert_output "$NOT_LOGGED_IN"
}

invalid_login() { #@test
  use_fake_gh
  fake_gh_respond auth '{"hosts":{"github.com":[{"login":"bad user","active":true}]}}'

  run_preflight

  assert_failure 1
  assert_output "$NOT_LOGGED_IN"
}

success() { #@test
  use_fake_gh
  fake_gh_respond auth "$AUTH_OK"

  run_preflight

  assert_success
  assert_output 'test-user'
  run cat "$FAKE_GH_DIR/calls.log"
  assert_output --partial 'auth status --json hosts --jq'
}
