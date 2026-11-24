#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2154

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  squash_scenario
  SCRIPT="$SKILLS_DIR/sei-resolve-squash-conflicts/scripts/preflight"
}

# expected_pass FETCHED
expected_pass() {
  printf '%s\n' \
    "PREFLIGHT: PASS" \
    "OLD_TIP=$OLD_TIP" \
    "BASE=$BASE" \
    "FETCHED=$1" \
    "OWN_COMMITS:" \
    "$(git log --oneline -1 "$OWN")" \
    "TARGET_CHANGES:"
  printf 'M\t%s\n' dir/g.txt f.txt other.txt
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: preflight [-h] <old_pr>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: preflight takes exactly one positional argument: <old_pr>'

  run --separate-stderr "$SCRIPT" 1 2

  assert_success
  assert_output 'ERROR: preflight takes exactly one positional argument: <old_pr>'
}

old_pr_not_positive_integer() { #@test
  local arg
  for arg in 0 01 '#1' abc -1; do
    run --separate-stderr "$SCRIPT" "$arg"

    assert_success
    assert_output "PREFLIGHT: FAIL — old_pr '$arg' is not a positive integer"
  done
}

not_a_git_repo() { #@test
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output --regexp '^ERROR: '
  assert_output --partial 'not a git repository'
}

no_merge_in_progress() { #@test
  git merge --abort

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output 'PREFLIGHT: FAIL — no merge in progress; run `git merge <target>` first'
}

origin_unreachable() { #@test
  git remote set-url origin "$BATS_TEST_TMPDIR/missing.git"

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output --regexp '^ERROR: '
}

pr_ref_absent() { #@test
  run --separate-stderr "$SCRIPT" 2

  assert_success
  assert_output 'PREFLIGHT: FAIL — PR #2 not found on origin (refs/pull/2/head)'
}

decoy_ref_only() { #@test
  git push -q origin :refs/pull/1/head
  git push -q origin "$OWN":refs/heads/x/refs/pull/1/head

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output 'PREFLIGHT: FAIL — PR #1 not found on origin (refs/pull/1/head)'
}

decoy_ref_ignored_next_to_real() { #@test
  git push -q origin "$OWN":refs/heads/x/refs/pull/1/head

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_line --index 0 'PREFLIGHT: PASS'
  assert_line --index 1 "OLD_TIP=$OLD_TIP"
}

pass_with_local_old_tip() { #@test
  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output "$(expected_pass no)"
}

pass_after_fetching_old_tip() { #@test
  drop_local_old_tip
  rm -f .git/FETCH_HEAD
  local refs_before
  refs_before=$(git for-each-ref)

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output "$(expected_pass yes)"
  git cat-file -e "$OLD_TIP^{commit}"
  [[ ! -e .git/FETCH_HEAD ]]
  [[ "$(git for-each-ref)" == "$refs_before" ]]
}

paths_are_top_level_relative() { #@test
  cd dir || return

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_line --index 0 'PREFLIGHT: PASS'
  assert_line "$(printf 'M\tdir/g.txt')"
}

unrelated_history() { #@test
  local orphan
  orphan=$(git commit-tree -m orphan "$(git mktree </dev/null)")
  git push -q -f origin "$orphan":refs/pull/1/head

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output "PREFLIGHT: FAIL — HEAD and PR #1's head $orphan share no history"
}

pr_head_is_not_behind_head() { #@test
  git push -q -f origin "$OWN":refs/pull/1/head

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output --regexp "^PREFLIGHT: FAIL — HEAD has no commits beyond PR #1's head"
}

base_already_on_target() { #@test
  git push -q -f origin main:refs/pull/1/head

  run --separate-stderr "$SCRIPT" 1

  assert_success
  assert_output --partial 'is already on the merge target; PR #1 does not look like this branch'"'"'s former base'
}
