#!/bin/sh
# This is the shutdown script for stackcomp. It is called automatically when the
# compositor exits, to clean up any remaining processes and services that were
# started in the main session. 
#
# The script performs a series of cleanup steps, including stopping desktop
# components, panels, and XDG desktop portals. It also includes a gentle escalation
# mechanism to ensure that all processes are terminated, first with SIGTERM and then with SIGKILL if necessary.
#
# The script relies on environment variables to determine the mode (nested or native)
# and to configure logging. Make sure to set these variables correctly before running.
#
# Additional helper functions for logging and launching services are defined in
# scripts/shell-helpers.sh and sourced here. This allows both startup.sh and
# shutdown.sh to use the same logging functions and maintain consistent log formatting.
#
# log_shutdown <level> <message> is used for logging, and the messages will
# be written to the shutdown log file defined in $STACKCOMP_SHUTDOWN_LOG_FILE.
################################################################################

# Activate helper functions for shutdown logging and shared runtime checks.
# shellcheck disable=SC2034
CURRENT_LOG_FILE="${STACKCOMP_SHUTDOWN_LOG_FILE:?STACKCOMP_SHUTDOWN_LOG_FILE is not set}"
. "$COMP_ROOT_DIR/scripts/shell-helpers.sh"

log_shutdown INFO "Starting session cleanup."

# Stop every process recorded through launch()/launch_nested() and escalate
# only when a registered process ignores the initial SIGTERM.
run_registered_shutdown_cleanup() {
    if [ ! -s "$STACKCOMP_SHUTDOWN_LIST" ]; then
        log_shutdown INFO "No programs registered to kill."
        return 0
    fi

    log_shutdown INFO "Performing dynamic session cleanup."

    # Registered helpers are part of the managed lifecycle in both nested and
    # native sessions, so shutdown must always process the tracker file.
    while IFS= read -r prog || [ -n "$prog" ]; do
        [ -z "$prog" ] && continue

        if pkill -x "$prog" >/dev/null 2>&1; then
            log_shutdown INFO "Sent SIGTERM to registered process: $prog."
        fi
    done < "$STACKCOMP_SHUTDOWN_LIST"

    sleep 1

    while IFS= read -r prog || [ -n "$prog" ]; do
        [ -z "$prog" ] && continue

        if pkill -0 -x "$prog" >/dev/null 2>&1; then
            log_shutdown ERROR "$prog did not exit after SIGTERM. Forcing SIGKILL."
            pkill -9 -x "$prog" 2>/dev/null
        fi
    done < "$STACKCOMP_SHUTDOWN_LIST"
}

# Nested Mode
# ==============================================================================
if stackcomp_session_is_nested; then
    log_shutdown INFO "Nested mode detected. Cleaning registered nested helpers only."
    run_registered_shutdown_cleanup
    log_shutdown INFO "Session cleanup completed (nested mode)."
    exit 0
fi

# Native Mode
# ==============================================================================
log_shutdown INFO "Native Wayland mode detected. Performing full session cleanup."
run_registered_shutdown_cleanup

# Portals are native-only runtime plumbing and are not tracked via launch().
log_shutdown INFO "Stopping xdg-desktop-portal processes."
pkill -x "xdg-desktop-portal-wlr|xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland|xdg-desktop-portal-gnome|xdg-desktop-portal-kde|xdg-desktop-portal-lxqt|xdg-desktop-portal" 2>/dev/null

for portal in xdg-desktop-portal-wlr xdg-desktop-portal-gtk xdg-desktop-portal-hyprland xdg-desktop-portal-gnome xdg-desktop-portal-kde xdg-desktop-portal-lxqt xdg-desktop-portal; do
    if pkill -0 -x "$portal" >/dev/null 2>&1; then
        # The broker/backends are runtime infrastructure. Force-stop leftovers so
        # the next session can rebuild a clean portal stack.
        pkill -9 -x "$portal" 2>/dev/null
    fi
done

# ==============================================================================
log_shutdown INFO "Session cleanup completed."
