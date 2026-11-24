#!/usr/bin/env bash

load "test_helper/bats-support/load"
load "test_helper/bats-assert/load"

bats_require_minimum_version 1.5.0

# Call first from every test file's setup().
common_setup() {
  # Confine mktemp output of the scripts under test to the per-test dir,
  # which bats removes afterwards.
  export TMPDIR="$BATS_TEST_TMPDIR"
}

# Put a fake `gh` first on PATH. Register responses with fake_gh_respond.
use_fake_gh() {
  mkdir -p "$BATS_TEST_TMPDIR/fake-bin" "$BATS_TEST_TMPDIR/fake-gh"
  ln -s "$BATS_TEST_DIRNAME/test_helper/fake-gh" "$BATS_TEST_TMPDIR/fake-bin/gh"
  export FAKE_GH_DIR="$BATS_TEST_TMPDIR/fake-gh"
  export PATH="$BATS_TEST_TMPDIR/fake-bin:$PATH"
}

# fake_gh_respond KEY STDOUT [EXIT [STDERR]]
fake_gh_respond() {
  local key=$1 stdout=$2 exit_code=${3:-0} stderr=${4:-}
  printf '%s' "$stdout" >"$FAKE_GH_DIR/$key.stdout"
  printf '%s' "$exit_code" >"$FAKE_GH_DIR/$key.exit"
  printf '%s' "$stderr" >"$FAKE_GH_DIR/$key.stderr"
}

# Replace PATH with a single folder holding symlinks to every executable on
# the current PATH except `gh`. Dropping PATH entries is not enough: on
# GitHub's Ubuntu runner `gh` lives in /usr/bin next to git and jq.
use_path_without_gh() {
  local bin_dir="$BATS_TEST_TMPDIR/no-gh-bin" dir file name
  local -a dirs
  mkdir -p "$bin_dir"
  IFS=: read -r -a dirs <<<"$PATH"
  for dir in "${dirs[@]}"; do
    [[ -d $dir ]] || continue
    for file in "$dir"/*; do
      name=${file##*/}
      [[ $name == gh ]] && continue
      [[ -f $file && -x $file ]] || continue
      # First match wins, as with PATH lookup.
      [[ -e $bin_dir/$name || -L $bin_dir/$name ]] && continue
      ln -s "$file" "$bin_dir/$name"
    done
  done
  export PATH="$bin_dir"
}
