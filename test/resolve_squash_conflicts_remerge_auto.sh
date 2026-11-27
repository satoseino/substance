#!/usr/bin/env bash
# on_* hooks are called by name from minimal_scenario; BASE is exported by it.
# shellcheck disable=SC2153,SC2329

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  SCRIPT="$SKILLS_DIR/resolve-squash-conflicts/scripts/remerge-auto"
}

# own reverts base's line 2. Git's merge base `root` keeps squash's `two`; with
# <base> as the ancestor the revert is an own change and wins.
differs_scenario() {
  on_own() { text_lines 10 8=eight >f.txt; }
  minimal_scenario
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: remerge-auto [-h] <base>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: remerge-auto takes exactly one positional argument: <base>'

  run --separate-stderr "$SCRIPT" a b

  assert_success
  assert_output 'ERROR: remerge-auto takes exactly one positional argument: <base>'
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
  assert_output 'ERROR: no merge in progress (MERGE_HEAD missing)'
}

base_not_a_commit() { #@test
  minimal_scenario
  local base
  for base in 0000000000000000000000000000000000000000 'HEAD^{tree}'; do
    run --separate-stderr "$SCRIPT" "$base"

    assert_success
    assert_output "ERROR: '$base' is not a commit"
  done
}

clean_result_equal_to_git_not_listed() { #@test
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'REMERGE: 1 checked, 0 listed'
  [[ "$(cat f.txt)" == "$(text_lines 10 2=two 5=five 8=eight)" ]]
}

differs() { #@test
  differs_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'REMERGE: 1 checked, 1 listed' $'differs\tf.txt')"
  [[ "$(cat f.txt)" == "$(text_lines 10 5=five 8=eight)" ]]
}

conflicts() { #@test
  # Against `root` only squash changed line 8 (own restored root's); against
  # <base> both did.
  on_base() { text_lines 10 2=two 8=b8 >f.txt; }
  on_own() { text_lines 10 2=two >f.txt; }
  on_squash() { text_lines 10 2=two 8=s8 >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'REMERGE: 1 checked, 1 listed' $'conflicts\tf.txt\t1')"
  grep -q '^<<<<<<< HEAD$' f.txt
}

lockfile_changed_on_both_sides() { #@test
  on_root() { text_lines 10 >uv.lock; }
  on_base() { text_lines 10 1=b >uv.lock; }
  on_own() { text_lines 10 1=b 3=own >uv.lock; }
  on_squash() { text_lines 10 1=b 8=squash >uv.lock; }
  minimal_scenario
  local before
  before=$(cat uv.lock)

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'REMERGE: 2 checked, 1 listed' $'lockfile\tuv.lock')"
  [[ "$(cat uv.lock)" == "$before" ]]
}

lockfile_changed_on_one_side() { #@test
  on_root() { text_lines 5 >uv.lock; }
  on_own() { text_lines 5 2=own >uv.lock; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'REMERGE: 2 checked, 0 listed'
}

dirty_path_preserved() { #@test
  differs_scenario
  echo 'hand edit' >>f.txt
  local before
  before=$(cat f.txt)

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'REMERGE: 1 checked, 1 listed' $'dirty\tf.txt')"
  [[ "$(cat f.txt)" == "$before" ]]
}

error_for_binary_changed_on_both_sides() { #@test
  # root holds squash's version, so Git sees only HEAD changing bin.dat and takes
  # it; against <base> both sides changed it.
  on_root() { printf 'squash\0\n' >bin.dat; }
  on_base() { printf 'base\0\n' >bin.dat; }
  on_own() { printf 'own\0\n' >bin.dat; }
  on_squash() { printf 'squash\0\n' >bin.dat; }
  minimal_scenario
  local before
  before=$(od -c bin.dat)

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_line --index 0 'REMERGE: 2 checked, 1 listed'
  assert_line --index 1 --regexp $'^error\tbin\\.dat\tgit merge-file failed for \'bin\\.dat\':'
  [[ "$(od -c bin.dat)" == "$before" ]]
}

unmerged_paths_skipped() { #@test
  on_squash() { text_lines 10 2=two 5=five 8=EIGHT >f.txt; }
  minimal_scenario
  local before
  before=$(cat f.txt)

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'REMERGE: 0 checked, 0 listed'
  [[ "$(cat f.txt)" == "$before" ]]
}

stages_nothing() { #@test
  differs_scenario
  local staged_before
  staged_before=$(git ls-files -s)

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_line --index 1 $'differs\tf.txt'
  [[ "$(git ls-files -s)" == "$staged_before" ]]
}

runs_from_subdirectory() { #@test
  on_root() {
    mkdir dir
    text_lines 3 >dir/k.txt
  }
  differs_scenario
  cd dir || return

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'REMERGE: 1 checked, 1 listed' $'differs\tf.txt')"
  [[ "$(cat ../f.txt)" == "$(text_lines 10 5=five 8=eight)" ]]
}

one_sided_add_and_delete_not_listed() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() {
    text_lines 10 2=two 8=eight >f.txt
    rm gone.txt
    text_lines 3 1=own >own.txt
  }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'REMERGE: 3 checked, 0 listed'
  [[ ! -e gone.txt ]]
}
