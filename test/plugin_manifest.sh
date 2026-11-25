#!/usr/bin/env bash
# shellcheck disable=SC2154

load "test_helper/common"

setup() {
  common_setup

  SUBSTANCE_DIR=$(readlink -f "$BATS_TEST_DIRNAME/..")
  MARKETPLACE="$SUBSTANCE_DIR/.claude-plugin/marketplace.json"
  PLUGIN="$SUBSTANCE_DIR/claude-plugin/.claude-plugin/plugin.json"
}

marketplace_lists_plugin() { #@test
  run jq -e . "$MARKETPLACE"
  assert_success

  run jq -r '.plugins | length' "$MARKETPLACE"
  assert_output 1

  local plugin_name
  plugin_name=$(jq -r '.name' "$PLUGIN")
  run jq -r '.plugins[0].name' "$MARKETPLACE"
  assert_output "$plugin_name"

  run jq -r '.plugins[0].source' "$MARKETPLACE"
  assert_output "./claude-plugin"

  [[ -f "$PLUGIN" ]]
}

no_version_pinned() { #@test
  run jq -e 'has("version") or any(.plugins[]; has("version"))' "$MARKETPLACE"
  assert_output false

  run jq -e 'has("version")' "$PLUGIN"
  assert_output false
}

skill_names_match_folders() { #@test
  local skill_md folder line name found
  for skill_md in "$SUBSTANCE_DIR"/claude-plugin/skills/*/SKILL.md; do
    folder=$(basename "$(dirname "$skill_md")")
    name=
    found=0
    # Read the frontmatter only: the lines between the opening and closing ---.
    while IFS= read -r line; do
      if [[ $line == "---" ]]; then
        if ((found)); then
          break
        fi
        found=1
        continue
      fi
      if [[ $line == name:* ]]; then
        name=$(sed -e 's/^name:[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^"\(.*\)"$/\1/' <<<"$line")
      fi
    done <"$skill_md"

    if [[ $name != "$folder" ]]; then
      echo "$skill_md: frontmatter name '$name' != folder '$folder'" >&2
      return 1
    fi
  done
}
