#!/usr/bin/env bash

# Git fixture helpers for the sei-resolve-squash-conflicts script tests.
# Every repo lives under $BATS_TEST_TMPDIR; `origin` is always a local bare repo.

# repo_init [DIR]
# Create a repo on `main`, cd into it and export REPO with its path.
repo_init() {
  REPO=${1:-$BATS_TEST_TMPDIR/work}
  export REPO
  git init -q -b main "$REPO"
  cd "$REPO" || return 1
}

# text_lines N [K=TEXT ...]
# Print lines 1…N, one per line, with line K replaced by TEXT.
text_lines() {
  local n=$1 i kv
  shift
  local -A replace=()
  for kv in "$@"; do
    replace[${kv%%=*}]=${kv#*=}
  done
  for ((i = 1; i <= n; i++)); do
    printf '%s\n' "${replace[$i]-$i}"
  done
}

# commit_all MSG
commit_all() {
  git add -A && git commit -q -m "$1"
}

# start_merge BRANCH
# `--no-commit` leaves MERGE_HEAD in place even when the merge is clean.
start_merge() {
  git merge -q --no-commit --no-ff "$1" || true
}

# Build the situation the skill is for: `stack` was branched from `old-base`, whose
# PR #1 was then squash-merged into `main`; a merge of `main` into `stack` is in
# progress. Exports ROOT, BASE (A2), OWN and OLD_TIP.
squash_scenario() {
  git init -q --bare -b main "$BATS_TEST_TMPDIR/origin.git"
  repo_init
  git remote add origin "$BATS_TEST_TMPDIR/origin.git"

  text_lines 10 >f.txt
  text_lines 3 >other.txt
  mkdir dir
  text_lines 3 >dir/g.txt
  commit_all root
  ROOT=$(git rev-parse HEAD)

  git checkout -q -b old-base
  text_lines 10 2=two >f.txt
  commit_all A1
  text_lines 10 2=two 3=three >f.txt
  commit_all A2
  BASE=$(git rev-parse HEAD)

  git checkout -q -b stack
  text_lines 10 2=two 3=three 8=eight >f.txt
  commit_all "own change"
  OWN=$(git rev-parse HEAD)

  git checkout -q old-base
  text_lines 10 2=two 3=three 5=five >f.txt
  commit_all "review fix"
  OLD_TIP=$(git rev-parse HEAD)
  git push -q origin old-base:refs/pull/1/head

  git checkout -q main
  text_lines 10 2=two 3=three 5=five >f.txt
  commit_all "squash #1"
  text_lines 3 2=b >other.txt
  text_lines 3 2=g >dir/g.txt
  commit_all unrelated
  git push -q origin main

  git checkout -q stack
  start_merge main
  export ROOT BASE OWN OLD_TIP
}

# Make OLD_TIP exist only on origin.
drop_local_old_tip() {
  git branch -q -D old-base
  git reflog expire --expire=now --all
  git gc -q --prune=now
  if git cat-file -e "$OLD_TIP^{commit}" 2>/dev/null; then
    echo "drop_local_old_tip: $OLD_TIP is still present locally" >&2
    return 1
  fi
}

# Build the minimal three-commit layout: `root` on `main`; branch `stack` with
# commits `base` and `own`; `main` with commit `squash`; then a merge of `main`
# into `stack` is started. Exports BASE (the `base` commit).
#
# f.txt holds, per commit:
#   root:   text_lines 10
#   base:   text_lines 10 2=two
#   own:    text_lines 10 2=two 8=eight
#   squash: text_lines 10 2=two 5=five
#
# A test changes a commit's contents by defining on_root, on_base, on_own or
# on_squash before calling this; each hook runs right before its commit, after
# the default f.txt has been written.
minimal_scenario() {
  repo_init

  text_lines 10 >f.txt
  _git_repo::hook on_root
  commit_all root

  git checkout -q -b stack
  text_lines 10 2=two >f.txt
  _git_repo::hook on_base
  commit_all base
  BASE=$(git rev-parse HEAD)

  text_lines 10 2=two 8=eight >f.txt
  _git_repo::hook on_own
  commit_all own

  git checkout -q main
  text_lines 10 2=two 5=five >f.txt
  _git_repo::hook on_squash
  commit_all squash

  git checkout -q stack
  start_merge main
  export BASE
}

_git_repo::hook() {
  if declare -F "$1" >/dev/null; then
    "$1"
  fi
}
