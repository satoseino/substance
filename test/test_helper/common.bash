#!/usr/bin/env bash

load "test_helper/bats-support/load"
load "test_helper/bats-assert/load"

bats_require_minimum_version 1.5.0

# Call first from every test file's setup().
common_setup() {
  # Confine mktemp output of the scripts under test to the per-test dir,
  # which bats removes afterwards.
  export TMPDIR="$BATS_TEST_TMPDIR"
  _common::shim_mktemp
  _common::shim_script_bash
}

# macOS mktemp ignores TMPDIR when called without a template, so put a mktemp
# first on PATH that passes `-p "$TMPDIR"` in that case. use_path_without_gh
# resolves tools against the current PATH, so it links this shim too.
_common::shim_mktemp() {
  local shim_dir="$BATS_TEST_TMPDIR/shim-bin" real
  real=$(type -P mktemp)
  mkdir -p "$shim_dir"
  cat >"$shim_dir/mktemp" <<EOF
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ \$arg != -* ]]; then
    exec "$real" "\$@"
  fi
done
exec "$real" -p "\$TMPDIR" "\$@"
EOF
  chmod +x "$shim_dir/mktemp"
  export PATH="$shim_dir:$PATH"
}

# Opt-in: when SEI_TEST_SCRIPT_BASH names a bash binary (e.g. /bin/bash 3.2
# on macOS), put a `bash` symlink to it first on PATH. Scripts start with
# `#!/usr/bin/env bash`, so they run on it, while bats and these helpers stay
# on the bash running the suite. use_path_without_gh resolves `bash` against
# the current PATH, so it links the same binary. The `#!/usr/bin/env bash`
# test stand-ins (test_helper/fake-gh and the mktemp shim) also run on it, so
# they must stay Bash 3.2-compatible.
# Fail fast on anything but an absolute path to an executable file: a relative
# target would make the symlink dangle, and PATH lookup would then silently
# skip it and run the scripts on the suite's own bash.
_common::shim_script_bash() {
  if [[ -z ${SEI_TEST_SCRIPT_BASH:-} ]]; then
    return 0
  fi
  if [[ $SEI_TEST_SCRIPT_BASH != /* || ! -f $SEI_TEST_SCRIPT_BASH || ! -x $SEI_TEST_SCRIPT_BASH ]]; then
    echo "SEI_TEST_SCRIPT_BASH must be an absolute path to an executable file: '$SEI_TEST_SCRIPT_BASH'" >&2
    return 1
  fi
  local shim_dir="$BATS_TEST_TMPDIR/script-bash"
  mkdir -p "$shim_dir"
  ln -sf "$SEI_TEST_SCRIPT_BASH" "$shim_dir/bash"
  export PATH="$shim_dir:$PATH"
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

# Executables the skill scripts use. `bash` is needed because every script
# starts with `#!/usr/bin/env bash`.
NO_GH_TOOLS=(bash cat dirname git jq mktemp readlink rm sed tr)

# use_path_without_gh [EXTRA_TOOL...]
# Replace PATH with a single folder holding symlinks to NO_GH_TOOLS plus any
# EXTRA_TOOLs, resolved against the current PATH; `gh` is never linked.
# Dropping PATH entries is not enough: on GitHub's Ubuntu runner `gh` lives
# in /usr/bin next to git and jq.
use_path_without_gh() {
  local bin_dir="$BATS_TEST_TMPDIR/no-gh-bin" tool file
  mkdir -p "$bin_dir"
  for tool in "${NO_GH_TOOLS[@]}" "$@"; do
    if [[ $tool == gh ]]; then
      echo "use_path_without_gh: refusing to link gh" >&2
      return 1
    fi
    if ! file=$(type -P "$tool"); then
      echo "use_path_without_gh: '$tool' not found on PATH" >&2
      return 1
    fi
    ln -sf "$file" "$bin_dir/$tool"
  done
  export PATH="$bin_dir"
}
