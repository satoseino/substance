#!/usr/bin/env bash
# on_* hooks are called by name from minimal_scenario; BASE is exported by it.
# shellcheck disable=SC2153,SC2329

load "test_helper/common"
load "test_helper/git_repo"

setup() {
  common_setup
  SCRIPT="$SKILLS_DIR/resolve-squash-conflicts/scripts/inventory"
}

help_flag() { #@test
  run --separate-stderr "$SCRIPT" -h

  assert_success
  assert_output --partial 'Usage: inventory [-h] <base>'
}

wrong_arg_count() { #@test
  run --separate-stderr "$SCRIPT"

  assert_success
  assert_output 'ERROR: inventory takes exactly one positional argument: <base>'

  run --separate-stderr "$SCRIPT" a b

  assert_success
  assert_output 'ERROR: inventory takes exactly one positional argument: <base>'
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

clean_merge() { #@test
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output 'INVENTORY: 0'
}

take_theirs() { #@test
  # Only the old base and the squash (a review fix) changed c.txt.
  on_root() { text_lines 5 >c.txt; }
  on_base() { text_lines 5 1=base >c.txt; }
  on_squash() { text_lines 5 1=fix >c.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'take-theirs\tUU\town=no\ttarget=yes\tc.txt')"
}

take_ours() { #@test
  on_root() { text_lines 5 >c.txt; }
  on_base() { text_lines 5 1=base >c.txt; }
  on_own() { text_lines 5 1=own >c.txt; }
  on_squash() { text_lines 5 1=base >c.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'take-ours\tUU\town=yes\ttarget=no\tc.txt')"
}

lockfile() { #@test
  on_root() {
    mkdir sub
    text_lines 5 >sub/uv.lock
  }
  on_base() { text_lines 5 1=base >sub/uv.lock; }
  on_own() { text_lines 5 1=own >sub/uv.lock; }
  on_squash() { text_lines 5 1=squash >sub/uv.lock; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'lockfile\tUU\town=yes\ttarget=yes\tsub/uv.lock')"
}

merge_on_base() { #@test
  on_squash() { text_lines 10 2=two 5=five 8=EIGHT >f.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'merge-on-base\tUU\town=yes\ttarget=yes\tf.txt')"
}

modify_delete() { #@test
  on_root() { text_lines 3 >gone.txt; }
  on_own() { rm gone.txt; }
  on_squash() { text_lines 3 2=squash >gone.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'modify-delete\tDU\town=yes\ttarget=yes\tgone.txt')"
}

rename_rename_both_deleted() { #@test
  # Each side renamed a.txt differently: Git records a.txt as DD (both deleted).
  on_root() { text_lines 50 >a.txt; }
  on_own() { git mv a.txt b.txt; }
  on_squash() { git mv a.txt c.txt; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 3' \
    $'delete\tDD\town=yes\ttarget=yes\ta.txt' \
    $'take-ours\tAU\town=yes\ttarget=no\tb.txt' \
    $'take-theirs\tUA\town=no\ttarget=yes\tc.txt')"
}

conflict_codes() { #@test
  on_root() {
    text_lines 3 >du.txt
    text_lines 3 >ud.txt
  }
  on_own() {
    echo 'added by own' >aa.txt
    rm du.txt
    text_lines 3 1=own >ud.txt
  }
  on_squash() {
    text_lines 10 2=two 5=five 8=EIGHT >f.txt
    echo 'added by squash' >aa.txt
    text_lines 3 1=squash >du.txt
    rm ud.txt
  }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 4' \
    $'merge-on-base\tAA\town=yes\ttarget=yes\taa.txt' \
    $'modify-delete\tDU\town=yes\ttarget=yes\tdu.txt' \
    $'merge-on-base\tUU\town=yes\ttarget=yes\tf.txt' \
    $'modify-delete\tUD\town=yes\ttarget=yes\tud.txt')"
}

path_with_spaces() { #@test
  on_root() { text_lines 5 >'a b.txt'; }
  on_base() { text_lines 5 1=base >'a b.txt'; }
  on_squash() { text_lines 5 1=fix >'a b.txt'; }
  minimal_scenario

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'take-theirs\tUU\town=no\ttarget=yes\ta b.txt')"
}

runs_from_subdirectory() { #@test
  on_root() {
    mkdir dir
    text_lines 5 >dir/c.txt
  }
  on_base() { text_lines 5 1=base >dir/c.txt; }
  on_squash() { text_lines 5 1=fix >dir/c.txt; }
  minimal_scenario
  cd dir || return

  run --separate-stderr "$SCRIPT" "$BASE"

  assert_success
  assert_output "$(printf '%s\n' 'INVENTORY: 1' $'take-theirs\tUU\town=no\ttarget=yes\tdir/c.txt')"
}
