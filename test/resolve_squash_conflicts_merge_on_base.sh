#!/usr/bin/env bash
# on_* hooks are called by name from minimal_scenario; BASE is exported by it.
# shellcheck disable=SC2016,SC2153,SC2154,SC2329

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  SCRIPT="$SKILLS_DIR/resolve-squash-conflicts/scripts/merge-on-base"
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: merge-on-base [-h] <base> <path>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT" a

  assert_success
  assert_output 'ERROR: merge-on-base takes exactly two positional arguments: <base> <path>'

  run --separate-stderr "$SCRIPT" a b c

  assert_success
  assert_output 'ERROR: merge-on-base takes exactly two positional arguments: <base> <path>'
}

not_a_git_repo() { #@test
  mkdir "$BATS_TEST_TMPDIR/empty"
  cd "$BATS_TEST_TMPDIR/empty" || return
  export GIT_CEILING_DIRECTORIES=$BATS_TEST_TMPDIR

  run --separate-stderr "$SCRIPT" HEAD f.txt

  assert_success
  assert_output --regexp "^ERROR: cannot enter the repository's top level:"
}

no_merge_in_progress() { #@test
  minimal_scenario
  git merge --abort

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'ERROR: no merge in progress (MERGE_HEAD missing)'
}

base_not_a_commit() { #@test
  minimal_scenario
  local base
  for base in 0000000000000000000000000000000000000000 'HEAD^{tree}'; do
    run --separate-stderr "$SCRIPT" "$base" f.txt

    assert_success
    assert_output "ERROR: '$base' is not a commit"
  done
}

path_absent_from_head() { #@test
  on_squash() { text_lines 3 1=new >new.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" new.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat new.txt)" == "$(text_lines 3 1=new)" ]]
}

path_absent_from_merge_head() { #@test
  on_own() { text_lines 3 1=own >own.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" own.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat own.txt)" == "$(text_lines 3 1=own)" ]]
}

one_sided_add_creates_missing_file() { #@test
  on_squash() {
    text_lines 3 1=new >new.txt
    mkdir -p d/e
    text_lines 3 1=nested >d/e/new.txt
  }
  minimal_scenario
  rm -r new.txt d

  run --separate-stderr "$SCRIPT" "$BASE" new.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat new.txt)" == "$(text_lines 3 1=new)" ]]
  [[ ! -x new.txt ]]

  run --separate-stderr "$SCRIPT" "$BASE" d/e/new.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat d/e/new.txt)" == "$(text_lines 3 1=nested)" ]]
}

one_sided_add_created_executable() { #@test
  on_own() {
    text_lines 3 1=x >x.sh
    chmod +x x.sh
  }
  minimal_scenario
  rm x.sh

  run --separate-stderr "$SCRIPT" "$BASE" x.sh

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ -x x.sh ]]
  [[ "$(cat x.sh)" == "$(text_lines 3 1=x)" ]]
}

head_deleted_merge_head_unchanged() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { rm gone.txt; }
  minimal_scenario
  text_lines 3 >gone.txt

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ ! -e gone.txt ]]
}

merge_head_deleted_head_unchanged() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_squash() { rm gone.txt; }
  minimal_scenario
  text_lines 3 >gone.txt

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ ! -e gone.txt ]]
}

both_deleted() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { rm gone.txt; }
  on_squash() { rm gone.txt; }
  minimal_scenario
  text_lines 3 >gone.txt

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ ! -e gone.txt ]]
}

absent_from_all_revisions() { #@test
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" nope.txt

  assert_success
  assert_output "ERROR: 'nope.txt' is absent from HEAD, MERGE_HEAD and $BASE"
}

modify_delete_is_error() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { rm gone.txt; }
  on_squash() { text_lines 3 2=squash >gone.txt; }
  minimal_scenario
  local before
  before=$(cat gone.txt)

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output "ERROR: 'gone.txt' is absent from HEAD and changed in MERGE_HEAD since $BASE; resolve it as a modify/delete case"
  [[ "$(cat gone.txt)" == "$before" ]]
}

modify_delete_mode_only_is_error() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { chmod +x gone.txt; }
  on_squash() { rm gone.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output "ERROR: 'gone.txt' is absent from MERGE_HEAD and changed in HEAD since $BASE; resolve it as a modify/delete case"
  [[ "$(cat gone.txt)" == "$(text_lines 3)" ]]
}

symlink_on_one_side_rejected() { #@test
  on_squash() { ln -s f.txt link; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" link

  assert_success
  assert_output "ERROR: 'link' is not a regular file in MERGE_HEAD (mode 120000); resolve it by hand"
}

removal_stages_nothing() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { rm gone.txt; }
  minimal_scenario
  text_lines 3 >gone.txt
  local staged_before
  staged_before=$(git ls-files -s)

  run --separate-stderr "$SCRIPT" "$BASE" gone.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(git ls-files -s)" == "$staged_before" ]]
}

binary_changed_on_one_side() { #@test
  # Git's merge base `root` makes both sides change bin.dat; against <base> only
  # own does, so own's version is taken without `git merge-file`.
  on_root() { printf 'root\0\n' >bin.dat; }
  on_base() { printf 'base\0\n' >bin.dat; }
  on_own() { printf 'own\0\n' >bin.dat; }
  on_squash() { printf 'base\0\n' >bin.dat; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" bin.dat

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(od -c bin.dat)" == "$(printf 'own\0\n' | od -c)" ]]
}

filter_path_changed_on_one_side() { #@test
  on_root() {
    git config filter.b64.clean 'base64 | tr -d "\n"'
    git config filter.b64.smudge 'base64 --decode'
    echo 'f.txt filter=b64' >.gitattributes
  }
  on_squash() { text_lines 10 2=two >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat f.txt)" == "$(text_lines 10 2=two 8=eight)" ]]
}

symlink_rejected() { #@test
  on_root() {
    text_lines 3 1=target >target.txt
    ln -s target.txt link
  }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" link

  assert_success
  assert_output "ERROR: 'link' is not a regular file in HEAD (mode 120000); resolve it by hand"
  [[ "$(cat target.txt)" == "$(text_lines 3 1=target)" ]]
}

submodule_rejected() { #@test
  on_root() {
    mkdir sub
    git update-index --add --cacheinfo "160000,$(git hash-object -t commit --stdin --literally </dev/null),sub"
  }
  minimal_scenario
  [[ "$(git ls-tree --format='%(objectmode)' MERGE_HEAD -- sub)" == 160000 ]]

  run --separate-stderr "$SCRIPT" "$BASE" sub

  assert_success
  assert_output "ERROR: 'sub' is not a regular file in HEAD (mode 160000); resolve it by hand"
}

clean_merge_uses_given_base() { #@test
  # own reverts base's line 2. Against <base> that revert is an own change and
  # wins; against Git's merge base `root`, own leaves line 2 alone and squash's
  # `two` would win instead.
  on_own() { text_lines 10 8=eight >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat f.txt)" == "$(text_lines 10 5=five 8=eight)" ]]
}

stages_nothing() { #@test
  # own reverts base's line 2, so the merged f.txt differs from the version
  # Git's own merge staged; staging it would change `git ls-files -s`.
  on_own() { text_lines 10 8=eight >f.txt; }
  minimal_scenario
  local staged_before
  staged_before=$(git ls-files -s f.txt)

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  [[ "$(git ls-files -s f.txt)" == "$staged_before" ]]
}

conflict_in_diff3_order() { #@test
  on_squash() { text_lines 10 2=two 5=five 8=EIGHT >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CONFLICTS 1'
  run sed -n '/^<<<<<<< /,/^>>>>>>> /p' f.txt
  assert_output "$(printf '%s\n' '<<<<<<< HEAD' eight '||||||| BASE' 8 '=======' EIGHT '>>>>>>> MERGE_HEAD')"
}

conflict_count() { #@test
  on_own() { text_lines 10 2=X2 9=X9 >f.txt; }
  on_squash() { text_lines 10 2=Y2 9=Y9 >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CONFLICTS 2'
}

base_lacks_path_identical_adds() { #@test
  on_own() { text_lines 3 1=new >new.txt; }
  on_squash() { text_lines 3 1=new >new.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" new.txt

  assert_success
  assert_output 'MERGE: CLEAN'
}

base_lacks_path_different_adds() { #@test
  on_own() { text_lines 3 1=ours >new.txt; }
  on_squash() { text_lines 3 1=theirs >new.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" new.txt

  assert_success
  assert_output 'MERGE: CONFLICTS 1'
}

runs_from_subdirectory() { #@test
  on_root() {
    mkdir dir
    text_lines 5 1=g >dir/g.txt
  }
  on_own() { text_lines 5 1=g 2=own >dir/g.txt; }
  on_squash() { text_lines 5 1=g 4=squash >dir/g.txt; }
  minimal_scenario
  cd dir || return

  run --separate-stderr "$SCRIPT" "$BASE" dir/g.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat g.txt)" == "$(text_lines 5 1=g 2=own 4=squash)" ]]
}

literal_pathspec() { #@test
  on_root() {
    text_lines 5 1=star >'a*.txt'
    text_lines 5 1=ab >ab.txt
  }
  on_own() { text_lines 5 1=star 2=own >'a*.txt'; }
  on_squash() { text_lines 5 1=star 4=squash >'a*.txt'; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" 'a*.txt'

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat 'a*.txt')" == "$(text_lines 5 1=star 2=own 4=squash)" ]]
  [[ "$(cat ab.txt)" == "$(text_lines 5 1=ab)" ]]
}

keeps_executable_mode() { #@test
  on_root() {
    text_lines 5 1=x >x.sh
    chmod +x x.sh
  }
  on_own() { text_lines 5 1=x 2=own >x.sh; }
  on_squash() { text_lines 5 1=x 4=squash >x.sh; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" x.sh

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ -x x.sh ]]
  [[ "$(cat x.sh)" == "$(text_lines 5 1=x 2=own 4=squash)" ]]
}

binary_is_error() { #@test
  on_base() { printf 'base\0\n' >bin.dat; }
  on_own() { printf 'own\0\n' >bin.dat; }
  on_squash() { printf 'squash\0\n' >bin.dat; }
  minimal_scenario
  local before
  before=$(od -c bin.dat)

  run --separate-stderr "$SCRIPT" "$BASE" bin.dat

  assert_success
  assert_output --regexp "^ERROR: git merge-file failed for 'bin.dat':"
  [[ "$(od -c bin.dat)" == "$before" ]]
}

ident_merged_in_clean_form() { #@test
  on_root() {
    echo 'f.txt ident' >.gitattributes
    text_lines 10 1='$Id$' >f.txt
  }
  on_base() { text_lines 10 1='$Id$' 2=two >f.txt; }
  on_own() { text_lines 10 1='$Id$' 2=two 8=eight >f.txt; }
  on_squash() { text_lines 10 1='$Id$' 2=two 5=five >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  run head -n 1 f.txt
  assert_output --regexp '^\$Id: [0-9a-f]{40} \$$'
}

filter_path_merged_smudged() { #@test
  on_root() {
    git config filter.b64.clean 'base64 | tr -d "\n"'
    git config filter.b64.smudge 'base64 --decode'
    echo 'f.txt filter=b64' >.gitattributes
  }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output 'MERGE: CLEAN'
  [[ "$(cat f.txt)" == "$(text_lines 10 2=two 5=five 8=eight)" ]]
}

unwritable_path() { #@test
  minimal_scenario
  chmod 444 f.txt

  run --separate-stderr "$SCRIPT" "$BASE" f.txt

  assert_success
  assert_output --regexp "^ERROR: cannot write 'f.txt':"
}
