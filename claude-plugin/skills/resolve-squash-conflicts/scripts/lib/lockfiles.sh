# Shared list of generated lockfiles for the resolve-squash-conflicts scripts. Sourced,
# not executed.

# _is_generated_lockfile <path>
# Returns 0 when <path>'s basename is a lockfile that a package manager generates from
# its manifests, 1 otherwise.
_is_generated_lockfile() {
  case "${1##*/}" in
  uv.lock | package-lock.json | poetry.lock | Cargo.lock | yarn.lock | pnpm-lock.yaml)
    return 0
    ;;
  esac

  return 1
}
