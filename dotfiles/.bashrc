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
# ------------------------------------------------------------------------
# Environment variables

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
# Source the env-specific profile. This must stay the last line, so that the profile runs after,
# and may override, everything above.
sei::bash_post_init
