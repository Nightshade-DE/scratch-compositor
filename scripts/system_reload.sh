#!/bin/sh
# Managed reload runtime for stackcomp config reloads.
# - Activates shared logging and helper functions for reload hooks.
# - Keeps a dedicated entrypoint for future managed reload work.
# - Runs the configured user reload hook or its XDG fallback.
################################################################################

# Reuse the startup log until reload gets its own dedicated runtime log file.
CURRENT_LOG_FILE="${STACKCOMP_STARTUP_LOG_FILE:?STACKCOMP_STARTUP_LOG_FILE is not set}"
HELPER_LIB="${STACKCOMP_HELPER_LIB:-$(dirname "$(readlink -f "$0")")/shell-helpers.sh}"
. "$HELPER_LIB"

log_message INFO "Starting managed reload hook."

# Keep the managed reload layer explicit even when it currently only exposes
# helper functions and stable ordering around the user hook.
stackcomp_run_optional_user_hook reload "${STACKCOMP_USER_RELOAD_HOOK_CMD:-}"

log_message INFO "Managed reload hook completed."
