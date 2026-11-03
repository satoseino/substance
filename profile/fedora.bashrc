# ------------------------------------------------------------------------
# Environment variables.

# xdg-open can't find explorer.exe (appendWindowsPath = false), so route it through bin/wsl-browser.
export BROWSER=wsl-browser

# ------------------------------------------------------------------------
# Aliases.

alias gs='git status'
# ------------------------------------------------------------------------
# Functions.

source "$SEI_SUBSTANCE_DIR/lib/tn.sh"
source "$SEI_SUBSTANCE_DIR/lib/ta.sh"

tl() {
  tmux list-sessions -F '#{session_name}: #{session_windows}win'
}
# ------------------------------------------------------------------------
