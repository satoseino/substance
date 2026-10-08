# -----------------------------------------------------------------------
# Locate substance directory
if [[ -z "${SEI_SUBSTANCE_DIR:+x}" ]]; then
  SEI_SUBSTANCE_DIR="$(cd "$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")" && pwd)"

  export SEI_SUBSTANCE_DIR
fi
# -----------------------------------------------------------------------
# Source personal library functions.
source "$SEI_SUBSTANCE_DIR/lib/it-shell.sh"
# -----------------------------------------------------------------------
# Initialization

sei::bash_init
trap 'sei::bash_post_init; trap - RETURN' RETURN
# ------------------------------------------------------------------------
# Environment variables

# Tell gpg-agent which terminal to use for TTY/curses pinentry (headless Linux, SSH).
# No-op with pinentry-mac.
GPG_TTY=$(tty)
export GPG_TTY

# C-x C-e invokes Vim on the current command line.
export EDITOR=vim
# ------------------------------------------------------------------------
# Load aliases for interactive use.
source "$SEI_SUBSTANCE_DIR/lib/aliases.sh"
# ------------------------------------------------------------------------
# Load custom commands for interactive use.
source "$SEI_SUBSTANCE_DIR/lib/commands.sh"
source "$SEI_SUBSTANCE_DIR/lib/cplan.sh"
source "$SEI_SUBSTANCE_DIR/lib/acmd.sh"
source "$SEI_SUBSTANCE_DIR/lib/rm-images.sh"
# ------------------------------------------------------------------------
