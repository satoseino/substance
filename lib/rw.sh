if [[ -n "${_sei_module_set_rw+x}" ]]; then
  return
fi

_sei_module_set_rw=1

source "$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)/utils.sh"

_sei_rw::detect_project() {
  local remote_url
  if ! remote_url="$(git remote get-url origin 2>/dev/null)"; then
    sei::log_error "Not inside a git repository with an 'origin' remote"

    return 1
  fi

  case "$(basename "$remote_url" .git)" in
  jarvis-registry)
    printf 'registry\n'
    ;;
  jarvis-registry-cli)
    printf 'cli\n'
    ;;
  *)
    sei::log_error "Unrecognized remote repository: $(basename "$remote_url" .git)"

    return 1
    ;;
  esac
}

_sei_rw::select_projects() {
  local -a selected
  mapfile -t selected < <(
    printf '%s\n' "jarvis-registry" "jarvis-registry-cli" |
      fzf -m --height=50% --layout=reverse --bind 'load:select-all'
  )

  printf '%s\n' "${selected[@]}"
}

_sei_rw::select_project() {
  printf '%s\n' "jarvis-registry" "jarvis-registry-cli" |
    fzf --height=50% --layout=reverse
}

# Worktree folder names that `rw renew` scans for, per repo:
# registry `*-reviews*` minus `cli-*`, cli `cli-*-reviews`.
_sei_rw_new_name_regex_registry='^[a-z0-9-]+-reviews(-[0-9]+)?$'
_sei_rw_new_name_regex_cli='^cli-[a-z0-9-]+-reviews$'

_sei_rw::new() {
  local repo
  repo="$(_sei_rw::select_project)"

  if [[ -z $repo ]]; then
    sei::log_info "No project selected"

    return 0
  fi

  if [[ ! -d $repo ]]; then
    sei::log_error "No $repo folder here. You are probably not in the workspace folder"

    return 1
  fi

  local regex hint
  case "$repo" in
  jarvis-registry)
    regex=$_sei_rw_new_name_regex_registry
    hint="<name>-reviews or <name>-reviews-<N>, not starting with cli-"
    ;;
  jarvis-registry-cli)
    regex=$_sei_rw_new_name_regex_cli
    hint="cli-<name>-reviews"
    ;;
  esac

  local name
  while true; do
    read -r -p "Worktree name for $repo ($hint; empty to cancel): " name

    if [[ -z $name ]]; then
      sei::log_info "Cancelled"

      return 0
    fi

    if ! [[ $name =~ $regex ]]; then
      sei::log_error "'$name' does not match $hint"
    elif [[ $repo == jarvis-registry && $name == cli-* ]]; then
      sei::log_error "jarvis-registry worktree names must not start with cli-"
    elif [[ -e $name ]]; then
      sei::log_error "'$name' already exists in this folder"
    elif git -C "$repo" rev-parse --verify --quiet "refs/heads/parking/$name" >/dev/null; then
      sei::log_error "Branch parking/$name already exists in $repo"
    else
      break
    fi
  done

  if ! git -C "$repo" worktree add "../$name" -b "parking/$name" main; then
    sei::log_error "Failed to create worktree $name"

    return 1
  fi

  sei::log_info "Created worktree $name on parking/$name. Next: cd $name && rw bootstrap"
}

_sei_rw::print_header() {
  if [[ -t 1 ]]; then
    printf '\n\033[33m%s\033[0m\n\n' "== $1 =="
  else
    printf '\n%s\n\n' "== $1 =="
  fi
}

_sei_rw::bootstrap_registry() {
  ln -s ../registry-working-docs/ .working-docs

  local files=(.env .env.no-db .env.mongodb docker-compose.sei.yml docker-compose.no-db.yml)
  for file in "${files[@]}"; do
    ln -s ../"${file}" "$file"
  done

  if ! playwright-cli install --skills; then
    sei::log_error "Failed to install the playwright-cli Claude skill to project local"
  fi
}

_sei_rw::bootstrap_cli() {
  ln -s ../registry-working-docs/ .working-docs
}

_sei_rw::bootstrap() {
  local project
  project="$(_sei_rw::detect_project)" || return 1

  case "$project" in
  registry)
    _sei_rw::bootstrap_registry
    ;;
  cli)
    _sei_rw::bootstrap_cli
    ;;
  esac
}

_sei_rw::renew_registry() {
  if ! (
    if ! cd "jarvis-registry"; then
      sei::log_error "Failed to cd into jarvis-registry. You are probably not in the correct directory"

      exit 1
    fi

    uv run poe -q cleanup-artifacts

    git pull

    printf "\n"

    sei::log_info "Current git worktree status:"

    git branch

    printf "\n"

    read -r -p "Rebase parking branches? [Y/n] " reply

    [[ "${reply:-Y}" =~ ^[Yy]$ ]] || exit 1
  ); then
    sei::log_error "Do nothing. Exit"

    return 1
  fi

  local -a worktrees

  mapfile -t worktrees < <(find . -maxdepth 1 -mindepth 1 -type d -name "*-reviews*" ! -name "cli-*")

  if ((${#worktrees[@]} == 0)); then
    sei::log_info "No worktree directories found"

    return 0
  fi

  worktrees=("${worktrees[@]#./}")

  local target
  for target in "${worktrees[@]}"; do
    if [[ "parking/$(basename "$target")" != "$(git -C "$target" branch --show-current)" ]]; then
      continue
    fi

    if ! git -C "$target" rebase main; then
      git -C "$target" rebase --abort

      sei::log_error "Failed to rebase parking branch of worktree ${target} onto main"
    fi

    if ! (cd "$target" && uv run poe -q cleanup-artifacts); then
      sei::log_error "Failed to clean up build artifacts in worktree ${target}"
    fi
  done

  printf "\n"

  local reply
  read -r -p "Delete merged branches? [Y/n] " reply

  [[ "${reply:-Y}" =~ ^[Yy]$ ]] || return 1

  local -a to_delete
  mapfile -t to_delete < <(
    git -C "jarvis-registry" branch |
      awk '/^  / && !/  parking\// && !/^  main$/ { sub(/^  /, ""); print }' |
      fzf -m --height=50% --layout=reverse --bind 'load:select-all'
  )

  if ((${#to_delete[@]} == 0)); then
    sei::log_info "No branches selected for deletion"

    return 0
  fi

  git -C "jarvis-registry" branch -D "${to_delete[@]}"
}

_sei_rw::renew_cli() {
  if ! (
    if ! cd "jarvis-registry-cli"; then
      sei::log_error "Failed to cd into jarvis-registry-cli. You are probably not in the correct directory"

      exit 1
    fi

    git pull

    printf "\n"

    sei::log_info "Current git worktree status:"

    git branch

    printf "\n"

    read -r -p "Rebase parking branches? [Y/n] " reply

    [[ "${reply:-Y}" =~ ^[Yy]$ ]] || exit 1
  ); then
    sei::log_error "Do nothing. Exit"

    return 1
  fi

  local -a worktrees

  mapfile -t worktrees < <(find . -maxdepth 1 -mindepth 1 -type d -name "cli-*-reviews")

  if ((${#worktrees[@]} == 0)); then
    sei::log_info "No worktree directories found"

    return 0
  fi

  worktrees=("${worktrees[@]#./}")

  local target
  for target in "${worktrees[@]}"; do
    if [[ "parking/$(basename "$target")" != "$(git -C "$target" branch --show-current)" ]]; then
      continue
    fi

    if ! git -C "$target" rebase main; then
      git -C "$target" rebase --abort

      sei::log_error "Failed to rebase parking branch of worktree ${target} onto main"
    fi
  done

  printf "\n"

  local reply
  read -r -p "Delete merged branches? [Y/n] " reply

  [[ "${reply:-Y}" =~ ^[Yy]$ ]] || return 1

  local -a to_delete
  mapfile -t to_delete < <(
    git -C "jarvis-registry-cli" branch |
      awk '/^  / && !/  parking\// && !/^  main$/ { sub(/^  /, ""); print }' |
      fzf -m --height=50% --layout=reverse --bind 'load:select-all'
  )

  if ((${#to_delete[@]} == 0)); then
    sei::log_info "No branches selected for deletion"

    return 0
  fi

  git -C "jarvis-registry-cli" branch -D "${to_delete[@]}"
}

_sei_rw::renew() {
  local -a projects
  mapfile -t projects < <(_sei_rw::select_projects)

  if ((${#projects[@]} == 0)); then
    sei::log_info "No project selected"

    return 0
  fi

  local project
  for project in "${projects[@]}"; do
    if ((${#projects[@]} > 1)); then
      _sei_rw::print_header "$project"
    fi

    case "$project" in
    jarvis-registry)
      _sei_rw::renew_registry
      ;;
    jarvis-registry-cli)
      _sei_rw::renew_cli
      ;;
    esac
  done
}

_sei_rw::sync_registry() {
  if (($# > 0)); then
    if ! git ls-remote --exit-code --heads origin "$1" >/dev/null; then
      sei::log_error "The remote branch '$1' does not exist."

      return 1
    fi

    git fetch origin

    git switch "$1"

    git pull
  elif [[ "$(git branch --show-current)" != "parking/$(basename "$(pwd)")" ]]; then
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null; then
      git pull
    else
      sei::log_info "The current branch does not track any remote one. Skip git pull."
    fi
  fi

  uv sync

  source .venv/bin/activate
}

_sei_rw::sync_cli() {
  if (($# > 0)); then
    if ! git ls-remote --exit-code --heads origin "$1" >/dev/null; then
      sei::log_error "The remote branch '$1' does not exist."

      return 1
    fi

    git fetch origin

    git switch "$1"

    git pull
  elif [[ "$(git branch --show-current)" != "parking/$(basename "$(pwd)")" ]]; then
    if git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null; then
      git pull
    else
      sei::log_info "The current branch does not track any remote one. Skip git pull."
    fi
  fi
}

_sei_rw::sync() {
  local project
  project="$(_sei_rw::detect_project)" || return 1

  case "$project" in
  registry)
    _sei_rw::sync_registry "$@"
    ;;
  cli)
    _sei_rw::sync_cli "$@"
    ;;
  esac
}

_sei_rw::branch_registry() {
  (
    if ! cd "jarvis-registry"; then
      sei::log_error "Failed to cd into jarvis-registry. You are probably not in the correct directory"

      exit 1
    fi

    git branch
  )
}

_sei_rw::branch_cli() {
  (
    if ! cd "jarvis-registry-cli"; then
      sei::log_error "Failed to cd into jarvis-registry-cli. You are probably not in the correct directory"

      exit 1
    fi

    git branch
  )
}

_sei_rw::branch() {
  local -a projects
  mapfile -t projects < <(_sei_rw::select_projects)

  if ((${#projects[@]} == 0)); then
    sei::log_info "No project selected"

    return 0
  fi

  local project
  for project in "${projects[@]}"; do
    if ((${#projects[@]} > 1)); then
      _sei_rw::print_header "$project"
    fi

    case "$project" in
    jarvis-registry)
      _sei_rw::branch_registry
      ;;
    jarvis-registry-cli)
      _sei_rw::branch_cli
      ;;
    esac
  done
}

_sei_rw::park_registry() {
  local base
  base="$(basename "$(pwd)")"

  if [[ "$base" == "jarvis-registry" ]]; then
    if ! git checkout main; then
      sei::log_error "Failed to check out the main branch"

      return 1
    fi

    return 0
  fi

  if ! git rev-parse --verify "refs/heads/parking/$base" &>/dev/null; then
    sei::log_error "No parking branch named 'parking/$base'"

    return 1
  fi

  if ! git checkout "parking/$base"; then
    sei::log_error "Failed to check out parking/$base branch"

    return 1
  fi
}

_sei_rw::park_cli() {
  local base
  base="$(basename "$(pwd)")"

  if [[ "$base" == "jarvis-registry-cli" ]]; then
    if ! git checkout main; then
      sei::log_error "Failed to check out the main branch"

      return 1
    fi

    return 0
  fi

  if ! git rev-parse --verify "refs/heads/parking/$base" &>/dev/null; then
    sei::log_error "No parking branch named 'parking/$base'"

    return 1
  fi

  if ! git checkout "parking/$base"; then
    sei::log_error "Failed to check out parking/$base branch"

    return 1
  fi
}

_sei_rw_pr_url_regex='^https://github\.com/([^/]+)/([^/]+)/pull/([0-9]+)/?$'

# Paths whose changes can make a later local action (launching Claude Code,
# opening an editor, entering the folder, installing, testing, committing,
# building) run code or instructions supplied by the PR author.
_sei_rw_pr_risky_path_regexes=(
  '(^|/)\.claude/'
  '(^|/)\.mcp\.json$'
  '(^|/)CLAUDE(\.local)?\.md$'
  '(^|/)AGENTS\.md$'
  '(^|/)\.pre-commit-config\.ya?ml$'
  '(^|/)pyproject\.toml$'
  '(^|/)uv\.lock$'
  '(^|/)(setup\.py|setup\.cfg)$'
  '(^|/)go\.mod$'
  '(^|/)\.golangci\.ya?ml$'
  '(^|/)\.goreleaser\.ya?ml$'
  '(^|/)conftest\.py$'
  '(^|/)pytest\.ini$'
  '(^|/)package(-lock)?\.json$'
  '(^|/)(\.npmrc|yarn\.lock|pnpm-lock\.yaml)$'
  '(^|/)Dockerfile[^/]*$'
  '(^|/)docker-compose[^/]*\.ya?ml$'
  '(^|/)Makefile$'
  '(^|/)\.envrc$'
  '(^|/)\.vscode/'
  '(^|/)\.idea/'
  '^\.github/'
)

# Prints "owner/repo" for the origin remote, from either an https or ssh URL.
_sei_rw::origin_slug() {
  local remote_url
  remote_url="$(git remote get-url origin)" || return 1

  remote_url="${remote_url%.git}"
  remote_url="${remote_url%/}"

  local repo="${remote_url##*/}"
  local rest="${remote_url%/*}"
  local owner="${rest##*[/:]}"

  printf '%s/%s\n' "$owner" "$repo"
}

_sei_rw::pr_precheck() {
  local slug=$1 number=$2

  local listing
  if ! listing="$(
    gh api "repos/$slug/pulls/$number/files" --paginate \
      --jq '.[] | .filename, (.previous_filename // empty)'
  )"; then
    sei::log_error "Failed to list the files changed by PR #$number"

    return 1
  fi

  local -a files
  mapfile -t files <<<"$listing"

  local -a flagged=()
  local file pattern
  for file in "${files[@]}"; do
    for pattern in "${_sei_rw_pr_risky_path_regexes[@]}"; do
      if [[ $file =~ $pattern ]]; then
        flagged+=("$file")

        break
      fi
    done
  done

  if ((${#flagged[@]} == 0)); then
    sei::log_info "Pre-check: none of the ${#files[@]} changed files is an agent-config or code-execution entry point"

    return 0
  fi

  printf '\n'
  sei::log_error "Pre-check: PR #$number changes files that can run code or instructions locally:"
  printf '  %s\n' "${flagged[@]}"
  printf '\nRead them first with: gh pr diff %s --repo %s\n\n' "$number" "$slug"

  local reply
  read -r -p "Fetch the PR into this worktree anyway? [y/N] " reply

  [[ "${reply:-N}" =~ ^[Yy]$ ]]
}

_sei_rw::pr() {
  local pr_url=$1

  local toplevel
  if ! toplevel="$(git rev-parse --show-toplevel)"; then
    sei::log_error "Not inside a git worktree"

    return 1
  fi

  # From a subdirectory, --git-dir and --git-common-dir can print the same
  # directory in different forms (absolute vs relative), which would defeat the
  # linked-worktree check below. Requiring the top-level folder keeps it exact.
  if [[ "$(pwd -P)" != "$(cd "$toplevel" && pwd -P)" ]]; then
    sei::log_error "Run this from the top-level folder of the review worktree: $toplevel"

    return 1
  fi

  if [[ "$(git rev-parse --git-dir)" == "$(git rev-parse --git-common-dir)" ]]; then
    sei::log_error "Not in a linked git worktree. Run this from a dedicated review worktree, not the main checkout"

    return 1
  fi

  local slug
  if ! slug="$(_sei_rw::origin_slug)"; then
    sei::log_error "Failed to read the origin remote"

    return 1
  fi

  if ! [[ $pr_url =~ $_sei_rw_pr_url_regex ]]; then
    sei::log_error "Not a GitHub PR URL: $pr_url"

    return 1
  fi

  local number=${BASH_REMATCH[3]}

  if [[ "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}" != "$slug" ]]; then
    sei::log_error "PR URL is for ${BASH_REMATCH[1]}/${BASH_REMATCH[2]}, but origin is $slug"

    return 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    sei::log_error "The worktree has uncommitted changes or untracked files. Clean it before fetching a PR"

    return 1
  fi

  local info
  if ! info="$(gh pr view "$number" --repo "$slug" --json title,author,isCrossRepository,headRepositoryOwner,headRefName,headRefOid,state)"; then
    sei::log_error "Failed to read PR #$number from $slug"

    return 1
  fi

  local head_sha
  head_sha="$(jq -r '.headRefOid' <<<"$info")"

  jq -r '
    "PR #'"$number"': \(.title)",
    "  author: \(.author.login); state: \(.state)",
    "  head:   \(.headRepositoryOwner.login):\(.headRefName) @ \(.headRefOid)",
    "  fork:   \(.isCrossRepository)"
  ' <<<"$info"
  printf '\n'

  _sei_rw::pr_precheck "$slug" "$number" || return 1

  if ! git fetch origin main; then
    sei::log_error "Failed to refresh origin/main. Nothing was checked out"

    return 1
  fi

  # Fetch into FETCH_HEAD only, and verify it is the pre-checked commit before
  # anything lands in the worktree. Never pull, merge, or rebase here: the
  # shared post-merge hook would run pre-commit hooks defined by the PR's tree.
  git fetch origin "pull/$number/head" || return 1

  local fetched_sha
  fetched_sha="$(git rev-parse FETCH_HEAD)" || return 1

  if [[ $fetched_sha != "$head_sha" ]]; then
    sei::log_error "Fetched $fetched_sha differs from the pre-checked PR head $head_sha (the author probably pushed meanwhile). Nothing was checked out. Run 'rw pr $pr_url' again"

    return 1
  fi

  local branch="pr/$number"
  if [[ "$(git branch --show-current)" == "$branch" ]]; then
    git reset --hard "$head_sha" || return 1
  else
    git switch -C "$branch" "$head_sha" || return 1
  fi

  sei::log_info "Worktree is on $branch at $head_sha. No dependencies were installed and no PR code was run"
}

_sei_rw::park() {
  local project
  project="$(_sei_rw::detect_project)" || return 1

  case "$project" in
  registry)
    _sei_rw::park_registry
    ;;
  cli)
    _sei_rw::park_cli
    ;;
  esac
}

rw() {
  if (($# == 0)) || [[ $1 == "-h" ]]; then
    cat <<'EOF'
USAGE: rw [-h] [SUBCOMMAND]

SUBCOMMANDS:
    new                     Interactively create a review worktree with its parking branch for the selected project (does not bootstrap it); must be in the workspace folder
    bootstrap               Bootstrap a jarvis-registry or jarvis-registry-cli worktree (project auto-detected via git remote); must be in a worktree folder
    renew                   Pull the latest commits on main; rebase parking branches; delete merged branches, for the selected project(s); must be in the workspace folder
    sync        [BRANCH]    Pull from the remote branch or switch and pull (project auto-detected via git remote; additionally runs uv sync and activates the virtual environment for jarvis-registry only); must be in a worktree folder
    branch                  List all branches with worktree occupancy markings, for the selected project(s); must be in the workspace folder
    park                    Checkout the corresponding parking branch of the worktree (project auto-detected via git remote)
    pr          PR_URL      Pre-check a PR's changed files, refresh origin/main, then fetch its head into branch pr/<N> of this worktree without installing or running anything; must be in the top-level folder of a linked worktree

OPTIONS:
    -h            Show this help message
EOF

    return 0
  fi
  case "$1" in
  new)
    shift 1

    if (($# > 0)); then
      cat <<'EOF'
Usage: rw new [-h]

Interactively create a review worktree: pick jarvis-registry or
jarvis-registry-cli, then enter a folder name, which must be
<name>-reviews or <name>-reviews-<N> (not starting with cli-) for
jarvis-registry, or cli-<name>-reviews for jarvis-registry-cli. Creates
../<name> with branch parking/<name> from local main. Does not run
rw bootstrap. Must be used in the workspace folder. Takes no arguments.

OPTIONS:
    -h          Show this help message
EOF

      [[ $1 == "-h" ]]

      return
    fi

    _sei_rw::new
    ;;
  bootstrap)
    _sei_rw::bootstrap
    ;;
  renew)
    _sei_rw::renew
    ;;
  sync)
    shift 1

    if (($# > 0)) && [[ $1 == "-h" ]]; then
      cat <<'EOF'
Usage: rw sync [-h] [BRANCH]

If BRANCH is given, git switch to this remote branch. Then perform git pull.
Must be used in a git worktree folder. For jarvis-registry worktrees, this additionally runs
uv sync and activates the virtual environment; jarvis-registry-cli worktrees skip this step.

ARGUMENTS:
    BRANCH      The remote branch to git switch to

OPTIONS:
    -h          Show this help message
EOF

      return 0
    fi

    _sei_rw::sync "$@"
    ;;
  branch)
    _sei_rw::branch
    ;;
  park)
    _sei_rw::park
    ;;
  pr)
    shift 1

    if (($# != 1)) || [[ $1 == "-h" ]]; then
      cat <<'EOF'
Usage: rw pr [-h] PR_URL

Fetch a pull request into this worktree for review, including PRs from forks.
First lists the PR's changed files via `gh` (nothing is fetched yet) and asks
for confirmation if any of them can run code or instructions locally (agent
config, CLAUDE.md, pre-commit, pyproject.toml, package.json, Docker, CI...).
Then runs `git fetch origin main` to refresh origin/main (and stops if that
fails), before fetching refs/pull/<N>/head from origin into branch pr/<N> and
switching to it, or hard-resetting pr/<N> if it is already checked out. Nothing
is checked out unless the fetched commit is the one whose files were
pre-checked. Never runs git pull, uv sync, or anything from the PR. Must be
used in the top-level folder of a clean linked worktree.

ARGUMENTS:
    PR_URL      Full GitHub URL of the PR, e.g.
                https://github.com/owner/repo/pull/123 (must match origin)

OPTIONS:
    -h          Show this help message
EOF

      [[ $# == 1 && $1 == "-h" ]]

      return
    fi

    _sei_rw::pr "$1"
    ;;
  *)
    sei::log_error "Unknown subcommand $1"

    return 1
    ;;
  esac
}

_sei_rw::complete() {
  local -a opts
  opts=("'-h  (Show help message)'" "'new  (Create review worktree)'" "'bootstrap  (bootstrap worktree)'" "'renew  (Renew workspace)'" "'sync  (Sync worktree)'" "'branch  (List branches)'" "'park  (Checkout parking branch)'" "'pr  (Fetch PR for review)'")

  if ((COMP_CWORD == 1)) && [[ $2 == "" ]]; then
    compgen -V COMPREPLY -W "${opts[*]}"

    return 0
  elif ((COMP_CWORD == 1)) && [[ $2 =~ ^-h?$ ]]; then
    COMPREPLY=("-h")

    return 0
  elif ((COMP_CWORD == 1)); then
    compgen -V COMPREPLY -W "new bootstrap renew sync branch park pr" -- "$2"

    return 0
  elif ((COMP_CWORD == 2)) && [[ $3 == "sync" ]] && [[ $2 =~ ^-h?$ ]]; then
    compgen -V COMPREPLY -W "-h" -- "$2"

    return 0
  elif ((COMP_CWORD == 2)) && [[ $3 == "sync" ]]; then
    local -a remote_branches

    mapfile -t remote_branches < <(git for-each-ref --format='%(refname:lstrip=3)' refs/remotes/origin | grep -v '^HEAD$')

    compgen -V COMPREPLY -W "${remote_branches[*]}" -- "$2"

    return 0
  fi
} && complete -o bashdefault -F _sei_rw::complete rw

_sei_commands_list+=("rw")
