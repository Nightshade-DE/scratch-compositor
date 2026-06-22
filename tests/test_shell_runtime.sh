#!/bin/sh
set -eu

repo_root=${1:?expected repository root as first argument}

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    exit 1
}

assert_file_contains() {
    file=$1
    expected=$2
    if ! grep -F -- "$expected" "$file" >/dev/null 2>&1; then
        printf 'Missing expected text in %s:\n%s\n' "$file" "$expected" >&2
        if [ -f "$file" ]; then
            printf '%s\n' '--- file contents ---' >&2
            cat "$file" >&2
            printf '%s\n' '---------------------' >&2
        fi
        exit 1
    fi
}

assert_equals() {
    expected=$1
    actual=$2
    label=$3
    if [ "$expected" != "$actual" ]; then
        fail "$label: expected '$expected', got '$actual'"
    fi
}

make_tmpdir() {
    mktemp -d "${TMPDIR:-/tmp}/stackcomp-shell-test.XXXXXX"
}

test_launch_helpers_track_expected_processes() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    mkdir -p "$tmpdir/bin"
    cat > "$tmpdir/bin/stdbuf" <<'EOF'
#!/bin/sh
shift 2
"$@"
EOF
    cat > "$tmpdir/bin/dummy-service" <<'EOF'
#!/bin/sh
printf 'dummy service output\n'
EOF
    chmod +x "$tmpdir/bin/stdbuf" "$tmpdir/bin/dummy-service"

    export PATH="$tmpdir/bin:$PATH"
    export CURRENT_LOG_FILE="$tmpdir/startup.log"
    export STACKCOMP_SHUTDOWN_LIST="$tmpdir/shutdown_list.nfo"
    export STACKCOMP_SESSION_MODE=native
    : > "$CURRENT_LOG_FILE"
    : > "$STACKCOMP_SHUTDOWN_LIST"

    # shellcheck disable=SC1090
    . "$repo_root/scripts/shell-helpers.sh"

    launch "$tmpdir/bin/dummy-service"
    launch_nokill "$tmpdir/bin/dummy-service"
    launch_nested "$tmpdir/bin/dummy-service"

    count=$(grep -c '^dummy-service$' "$STACKCOMP_SHUTDOWN_LIST" || true)
    assert_equals "1" "$count" "launch helper shutdown tracker count"
    assert_file_contains "$CURRENT_LOG_FILE" "Starting $tmpdir/bin/dummy-service (registered for automatic shutdown)."
    assert_file_contains "$CURRENT_LOG_FILE" "Starting $tmpdir/bin/dummy-service (not registered for shutdown)."
    assert_file_contains "$CURRENT_LOG_FILE" "Skipping $tmpdir/bin/dummy-service (launch_nested only runs in nested sessions)."

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_system_startup_nested_sets_wayland_display() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    export COMP_ROOT_DIR="$repo_root"
    export STACKCOMP_STARTUP_LOG_FILE="$tmpdir/startup.log"
    export STACKCOMP_SESSION_MODE=nested
    export WLR_WL_SOCKET="wayland-test-socket"
    export XDG_CONFIG_HOME="$tmpdir/xdg-config"
    unset WAYLAND_DISPLAY
    : > "$STACKCOMP_STARTUP_LOG_FILE"

    # shellcheck disable=SC1090
    . "$repo_root/scripts/system_startup.sh"

    assert_equals "wayland-test-socket" "${WAYLAND_DISPLAY:-}" "nested WAYLAND_DISPLAY"
    assert_file_contains "$STACKCOMP_STARTUP_LOG_FILE" "Nested clients use WAYLAND_DISPLAY=wayland-test-socket."

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_system_startup_native_runs_managed_portals() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    mkdir -p "$tmpdir/scripts" "$tmpdir/config"
    ln -s "$repo_root/scripts/system_startup.sh" "$tmpdir/scripts/system_startup.sh"
    ln -s "$repo_root/scripts/shell-helpers.sh" "$tmpdir/scripts/shell-helpers.sh"
    cat > "$tmpdir/config/portals" <<'EOF'
#!/bin/sh
stackcomp_start_portals() {
    : "${PORTAL_MARKER_FILE:?PORTAL_MARKER_FILE is not set}"
    printf 'managed portals called\n' > "$PORTAL_MARKER_FILE"
    log_startup INFO "Stub portal runtime started."
}
EOF
    chmod +x "$tmpdir/config/portals"

    export COMP_ROOT_DIR="$tmpdir"
    export STACKCOMP_STARTUP_LOG_FILE="$tmpdir/startup.log"
    export STACKCOMP_SESSION_MODE=native
    export STACKCOMP_SYSTEM_CONFIG_DIR="$tmpdir/config"
    export XDG_CONFIG_HOME="$tmpdir/xdg-config"
    export PORTAL_MARKER_FILE="$tmpdir/portal-marker"
    : > "$STACKCOMP_STARTUP_LOG_FILE"

    # Source the managed runtime directly so the test can validate ordering
    # without having to start the full compositor binary.
    # shellcheck disable=SC1091
    . "$tmpdir/scripts/system_startup.sh"

    assert_file_contains "$PORTAL_MARKER_FILE" "managed portals called"
    assert_file_contains "$STACKCOMP_STARTUP_LOG_FILE" "Loaded managed portals file: $tmpdir/config/portals."
    assert_file_contains "$STACKCOMP_STARTUP_LOG_FILE" "Stub portal runtime started."

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_system_startup_runs_user_hook_command() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    export COMP_ROOT_DIR="$repo_root"
    export STACKCOMP_STARTUP_LOG_FILE="$tmpdir/startup.log"
    export STACKCOMP_SESSION_MODE=nested
    export WLR_WL_SOCKET="wayland-test-socket"
    export XDG_CONFIG_HOME="$tmpdir/xdg-config"
    export USER_STARTUP_MARKER="$tmpdir/user-startup.marker"
    export STACKCOMP_USER_STARTUP_HOOK_CMD='printf "user startup hook\n" > "$USER_STARTUP_MARKER"'
    : > "$STACKCOMP_STARTUP_LOG_FILE"

    # In managed mode the startup runtime receives the resolved config command
    # through the environment rather than reparsing the config itself.
    # shellcheck disable=SC1090
    . "$repo_root/scripts/system_startup.sh"

    assert_file_contains "$USER_STARTUP_MARKER" "user startup hook"
    assert_file_contains "$STACKCOMP_STARTUP_LOG_FILE" "Running user startup hook from config."

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_stackcomp_config_hook_from_file_reads_hooks_section() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    cat > "$tmpdir/config.conf" <<'EOF'
[hooks]
startup = /tmp/startup-hook
shutdown = echo shutdown
reload = /tmp/reload-hook
EOF

    export CURRENT_LOG_FILE="$tmpdir/helpers.log"
    : > "$CURRENT_LOG_FILE"

    # shellcheck disable=SC1090
    . "$repo_root/scripts/shell-helpers.sh"

    startup_hook=$(stackcomp_config_hook_from_file startup "$tmpdir/config.conf")
    shutdown_hook=$(stackcomp_config_hook_from_file shutdown "$tmpdir/config.conf")
    reload_hook=$(stackcomp_config_hook_from_file reload "$tmpdir/config.conf")

    assert_equals "/tmp/startup-hook" "$startup_hook" "startup hook command"
    assert_equals "echo shutdown" "$shutdown_hook" "shutdown hook command"
    assert_equals "/tmp/reload-hook" "$reload_hook" "reload hook command"

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_portals_log_effective_runtime_values() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    export CURRENT_LOG_FILE="$tmpdir/startup.log"
    export STACKCOMP_SESSION_MODE=native
    export XDG_CURRENT_DESKTOP="GNOME"
    : > "$CURRENT_LOG_FILE"

    # shellcheck disable=SC1090
    . "$repo_root/scripts/shell-helpers.sh"
    # shellcheck disable=SC1090
    . "$repo_root/config/portals"

    launch_nokill() {
        :
    }
    pkill() {
        return 0
    }
    sleep() {
        :
    }

    stackcomp_start_portals

    assert_file_contains \
        "$CURRENT_LOG_FILE" \
        "Set portal variables (QT_QPA_PLATFORM=wayland;xcb, GDK_BACKEND=wayland,x11, GTK_USE_PORTAL=1, XDG_CURRENT_DESKTOP=GNOME)."

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_system_shutdown_cleans_registered_processes() {
    tmpdir=$(make_tmpdir)
    trap 'rm -rf "$tmpdir"' EXIT HUP INT TERM

    export COMP_ROOT_DIR="$repo_root"
    export STACKCOMP_SHUTDOWN_LOG_FILE="$tmpdir/shutdown.log"
    export STACKCOMP_SHUTDOWN_LIST="$tmpdir/shutdown_list.nfo"
    export STACKCOMP_SESSION_MODE=native
    export XDG_CONFIG_HOME="$tmpdir/xdg-config"
    export SHUTDOWN_ORDER_FILE="$tmpdir/shutdown-order.log"
    export STACKCOMP_USER_SHUTDOWN_HOOK_CMD='printf "user hook\n" >> "$SHUTDOWN_ORDER_FILE"'
    : > "$STACKCOMP_SHUTDOWN_LOG_FILE"
    printf '%s\n' dummy-service > "$STACKCOMP_SHUTDOWN_LIST"
    export PKILL_LOG_FILE="$tmpdir/pkill.log"
    : > "$PKILL_LOG_FILE"

    pkill() {
        printf '%s\n' "cleanup $*" >> "$SHUTDOWN_ORDER_FILE"
        printf '%s\n' "$*" >> "$PKILL_LOG_FILE"
        case "$1" in
            -0)
                return 1
                ;;
            *)
                return 0
                ;;
        esac
    }
    sleep() {
        return 0
    }

    # Source the shutdown runtime so the shell overrides above can capture the
    # exact user-hook-before-cleanup ordering contract.
    # shellcheck disable=SC1090
    . "$repo_root/scripts/system_shutdown.sh"

    first_line=$(sed -n '1p' "$SHUTDOWN_ORDER_FILE")
    assert_equals "user hook" "$first_line" "shutdown hook ordering"
    assert_file_contains "$STACKCOMP_SHUTDOWN_LOG_FILE" "Sent SIGTERM to registered process: dummy-service."
    assert_file_contains "$STACKCOMP_SHUTDOWN_LOG_FILE" "Stopping xdg-desktop-portal processes."
    assert_file_contains "$STACKCOMP_SHUTDOWN_LOG_FILE" "Running user shutdown hook from config."
    assert_file_contains "$PKILL_LOG_FILE" "-x dummy-service"
    assert_file_contains "$PKILL_LOG_FILE" "-x xdg-desktop-portal-wlr|xdg-desktop-portal-gtk|xdg-desktop-portal-hyprland|xdg-desktop-portal-gnome|xdg-desktop-portal-kde|xdg-desktop-portal-lxqt|xdg-desktop-portal"

    rm -rf "$tmpdir"
    trap - EXIT HUP INT TERM
}

test_launch_helpers_track_expected_processes
test_system_startup_nested_sets_wayland_display
test_system_startup_native_runs_managed_portals
test_system_startup_runs_user_hook_command
test_stackcomp_config_hook_from_file_reads_hooks_section
test_portals_log_effective_runtime_values
test_system_shutdown_cleans_registered_processes
