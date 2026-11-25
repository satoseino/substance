#!/usr/bin/env bash
# on_* hooks are called by name from minimal_scenario; BASE is exported by it.
# shellcheck disable=SC2153,SC2154,SC2329

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  SCRIPT="$SKILLS_DIR/resolve-squash-conflicts/scripts/verify-own-changes"
}

# The correct resolution of the default f.txt.
resolve_f() {
  text_lines 10 2=two 5=five 8=eight >f.txt
}

# take REV PATH...: write REV's version of each PATH to the working tree.
take() {
  local rev=$1
  shift
  git checkout -q "$rev" -- "$@"
}

stage() {
  git add -A
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: verify-own-changes [-h] <base>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: verify-own-changes takes exactly one positional argument: <base>'
}

not_a_git_repo() { #@test
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR

  run --separate-stderr "$SCRIPT" HEAD

  assert_success
  assert_output --regexp "^ERROR: cannot enter the repository's top level:"
}

no_merge_in_progress() { #@test
  minimal_scenario
  git merge --abort

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output --regexp '^ERROR: no merge in progress \(MERGE_HEAD missing\)'
}

base_not_a_commit() { #@test
  minimal_scenario

  run --separate-stderr "$SCRIPT" nope

  assert_success
  assert_output --regexp "^ERROR: 'nope' is not a commit"
}

unresolved_paths_remain() { #@test
  on_squash() { text_lines 10 2=two 5=five 8=EIGHT >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'ERROR: unresolved paths remain; resolve and stage them first'
}

match() { #@test
  minimal_scenario
  resolve_f
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'VERIFY: MATCH'
}

match_despite_shifted_lines() { #@test
  on_squash() { printf '%s\n' p1 p2 p3 "$(text_lines 10 2=two 5=five)" >f.txt; }
  minimal_scenario
  printf '%s\n' p1 p2 p3 "$(text_lines 10 2=two 5=five 8=eight)" >f.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'VERIFY: MATCH'
}

only_expected_merge_head() { #@test
  minimal_scenario
  take MERGE_HEAD f.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-expected\t=MERGE_HEAD\tf.txt')"
}

only_actual_head() { #@test
  on_root() { text_lines 3 1=other >other.txt; }
  on_squash() { text_lines 3 1=other 2=b >other.txt; }
  minimal_scenario
  take HEAD other.txt
  resolve_f
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-actual\t=HEAD\tother.txt')"
}

differs_head() { #@test
  minimal_scenario
  take HEAD f.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\ndiffers\t=HEAD\tf.txt')"
}

differs_mixed() { #@test
  minimal_scenario
  text_lines 10 2=two 5=five 8=eight 9=nine >f.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\ndiffers\tmixed\tf.txt')"
}

differs_when_target_changed_adjacent_line() { #@test
  on_squash() { text_lines 10 2=two 5=five 7=seven >f.txt; }
  minimal_scenario
  text_lines 10 2=two 5=five 7=seven 8=eight >f.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\ndiffers\tmixed\tf.txt')"
}

only_expected_both() { #@test
  on_own() { text_lines 3 1=g >g.txt; }
  on_squash() { text_lines 3 1=g >g.txt; }
  minimal_scenario
  resolve_f
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-expected\t=both\tg.txt')"
}

mode_change_kept() { #@test
  on_root() { text_lines 3 1=run >run.sh; }
  on_own() { chmod +x run.sh; }
  minimal_scenario
  resolve_f
  stage
  [[ "$(git ls-files -s run.sh)" == 100755* ]]

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'VERIFY: MATCH'
}

mode_change_dropped() { #@test
  on_root() { text_lines 3 1=run >run.sh; }
  on_own() { chmod +x run.sh; }
  minimal_scenario
  resolve_f
  chmod -x run.sh
  stage
  [[ "$(git ls-files -s run.sh)" == 100644* ]]

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-expected\t=both\trun.sh')"
}

removed_double_dash_line_is_compared() { #@test
  on_root() { text_lines 9 5='-- a' >sql.txt; }
  on_own() { text_lines 9 5='-- a' | sed 5d >sql.txt; }
  on_squash() { text_lines 9 5='-- b' >sql.txt; }
  minimal_scenario
  resolve_f
  take HEAD sql.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\ndiffers\t=HEAD\tsql.txt')"
}

rename_is_delete_plus_add() { #@test
  on_root() { text_lines 3 1=a >a.txt; }
  on_own() { git mv a.txt b.txt; }
  minimal_scenario
  resolve_f
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'VERIFY: MATCH'
}

deletion_counts_absent_as_identical() { #@test
  on_root() { text_lines 3 1=x >x.txt; }
  on_own() { rm x.txt; }
  on_squash() { text_lines 3 1=x 2=squash >x.txt; }
  minimal_scenario
  resolve_f
  rm -f x.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\ndiffers\t=HEAD\tx.txt')"
}

binary_kept_head() { #@test
  on_root() { printf 'root\0\n' >bin.dat; }
  on_own() { printf 'own\0\n' >bin.dat; }
  on_squash() { printf 'squash\0\n' >bin.dat; }
  minimal_scenario
  resolve_f
  take HEAD bin.dat
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'VERIFY: MATCH'
}

binary_third_version() { #@test
  on_root() { printf 'root\0\n' >bin.dat; }
  on_own() { printf 'own\0\n' >bin.dat; }
  on_squash() { printf 'squash\0\n' >bin.dat; }
  minimal_scenario
  resolve_f
  printf 'third\0\n' >bin.dat
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nbinary-differs\tmixed\tbin.dat')"
}

special_path_names() { #@test
  on_root() {
    text_lines 3 1=space >'a b.txt'
    text_lines 3 1=star >'a*.txt'
    text_lines 3 1=ab >ab.txt
  }
  on_own() {
    text_lines 3 1=space 2=own >'a b.txt'
    text_lines 3 1=star 2=own >'a*.txt'
    text_lines 3 1=ab 2=own >ab.txt
  }
  minimal_scenario
  resolve_f
  take MERGE_HEAD ab.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-expected\t=MERGE_HEAD\tab.txt')"
}

runs_from_subdirectory() { #@test
  on_root() {
    mkdir dir
    text_lines 3 1=g >dir/g.txt
  }
  on_own() { text_lines 3 1=g 2=own >dir/g.txt; }
  minimal_scenario
  resolve_f
  take MERGE_HEAD dir/g.txt
  stage
  cd dir || return

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\nonly-expected\t=MERGE_HEAD\tdir/g.txt')"
}

multiple_mismatches_sorted() { #@test
  on_root() {
    mkdir dir
    text_lines 3 1=g >dir/g.txt
    text_lines 3 1=other >other.txt
  }
  on_own() {
    text_lines 3 1=g 2=own >dir/g.txt
    text_lines 3 1=other 2=own >other.txt
  }
  minimal_scenario
  take MERGE_HEAD f.txt dir/g.txt other.txt
  stage

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf 'VERIFY: MISMATCH\n%s\n%s\n%s' \
    "$(printf 'only-expected\t=MERGE_HEAD\tdir/g.txt')" \
    "$(printf 'only-expected\t=MERGE_HEAD\tf.txt')" \
    "$(printf 'only-expected\t=MERGE_HEAD\tother.txt')")"
}
