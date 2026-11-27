#!/usr/bin/env bash
# shellcheck disable=SC2016

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  SCRIPT="$SKILLS_DIR/implement-spec/scripts/preflight"
  ORIGIN="$BATS_TEST_TMPDIR/origin.git"

  repo_init
  echo spec >spec.md
  commit_all root
}

# add_origin
# Add a local bare `origin` without fetching, so `origin/HEAD` stays unset.
add_origin() {
  git init -q --bare -b main "$ORIGIN"
  git remote add origin "$ORIGIN"
}

assert_refused() {
  assert_success
  assert_output "PREFLIGHT: FAIL — refusing to run on '$1' (the default branch or main/master); check out a feature branch first"
}

assert_pass() {
  assert_success
  assert_output 'PREFLIGHT: PASS'
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: preflight [-h] <spec_path>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: preflight takes exactly one positional argument: <spec_path>'

  run --separate-stderr "$SCRIPT" spec.md extra

  assert_success
  assert_output 'ERROR: preflight takes exactly one positional argument: <spec_path>'
}

spec_file_missing() { #@test
  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" missing.md

  assert_success
  assert_output 'PREFLIGHT: FAIL — spec file not found: missing.md'
}

spec_file_absolute_path() { #@test
  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" "$REPO/spec.md"

  assert_pass
}

not_a_git_repo() { #@test
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  echo spec >spec.md
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output --regexp '^ERROR: '
  assert_output --partial 'not a git repository'
}

detached_head() { #@test
  git checkout -q --detach

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output 'PREFLIGHT: FAIL — HEAD is detached; check out a feature branch first'
}

no_origin_refuses_main() { #@test
  run --separate-stderr "$SCRIPT" spec.md

  assert_refused main
}

no_origin_refuses_master() { #@test
  git checkout -q -b master

  run --separate-stderr "$SCRIPT" spec.md

  assert_refused master
}

no_origin_passes_feature() { #@test
  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" spec.md

  assert_pass
}

origin_head_set() { #@test
  add_origin
  git branch -q -m main trunk
  git push -q origin trunk
  git fetch -q origin
  git remote set-head origin trunk

  run --separate-stderr "$SCRIPT" spec.md

  assert_refused trunk

  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" spec.md

  assert_pass
}

origin_head_unset_falls_back_to_ls_remote() { #@test
  add_origin
  git branch -q -m main trunk
  git push -q origin trunk
  git -C "$ORIGIN" symbolic-ref HEAD refs/heads/trunk
  run git symbolic-ref -q refs/remotes/origin/HEAD
  assert_failure

  run --separate-stderr "$SCRIPT" spec.md

  assert_refused trunk

  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" spec.md

  assert_pass
}

origin_unreachable() { #@test
  add_origin
  git checkout -q -b feature
  git remote set-url origin "$BATS_TEST_TMPDIR/missing.git"

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output "PREFLIGHT: FAIL — could not determine origin's default branch; set it with 'git remote set-head origin --auto'"
}

origin_head_unborn() { #@test
  # `ls-remote --symref` lists nothing for an unborn remote HEAD.
  add_origin
  git checkout -q -b feature

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output "PREFLIGHT: FAIL — could not determine origin's default branch; set it with 'git remote set-head origin --auto'"
}

master_refused_when_origin_head_names_another_branch() { #@test
  add_origin
  git branch -q -m main trunk
  git push -q origin trunk
  git fetch -q origin
  git remote set-head origin trunk
  git checkout -q -b master

  run --separate-stderr "$SCRIPT" spec.md

  assert_refused master
}

dirty_tree_untracked_file() { #@test
  git checkout -q -b feature
  echo new >untracked.txt

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output 'PREFLIGHT: FAIL — the working tree has uncommitted changes; commit, stash, or discard them first'
}

dirty_tree_staged_change() { #@test
  git checkout -q -b feature
  echo changed >spec.md
  git add spec.md

  run --separate-stderr "$SCRIPT" spec.md

  assert_success
  assert_output 'PREFLIGHT: FAIL — the working tree has uncommitted changes; commit, stash, or discard them first'
}
