#!/bin/sh
# Main stackcomp shutdown hook.
# Keep this file focused on user-facing shutdown content:
# - optional user cleanup
# - optional user-managed service shutdown
# The managed runtime invokes this hook before compositor-owned cleanup begins.
################################################################################

# Activate helper functions for shutdown logging so user cleanup can emit
# messages into the standard shutdown log when needed.
# shellcheck disable=SC2034
CURRENT_LOG_FILE="${STACKCOMP_SHUTDOWN_LOG_FILE:?STACKCOMP_SHUTDOWN_LOG_FILE is not set}"
. "$COMP_ROOT_DIR/scripts/shell-helpers.sh"

# Optional user cleanup goes here.
# Example:
# log_shutdown INFO "Running user shutdown cleanup."
# pkill -x my-user-service
