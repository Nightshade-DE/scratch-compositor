# Morph Environment Guide

This document describes runtime environment variables used by
testing/morph_run and passed to morph.

## Scope

Use this file for environment-based runtime setup.
Launcher runtime flow and files are documented in testing/LAUNCHER.md.

## Resolution Order

Launcher settings are resolved in this order:

1. Caller environment (for example VAR=value ./testing/morph_run)
2. User environment file (`$XDG_CONFIG_HOME/morph/environment` or `~/.config/morph/environment`)
3. System environment file (`$MORPH_SYSTEM_CONFIG_DIR/environment`, defaulting to `config/environment` in the dev launcher)
4. Built-in defaults in testing/morph_run

If `MORPH_ENV_FILE` is set, it replaces the dev launcher's system environment file path but keeps the same priority level.

## Launcher Variables

### MORPH_DBG

Controls launcher runtime mode:

- 0: release mode
  - --log-level error
  - --no-crash-handler
- 1: release-debug mode
  - --log-level info
  - crash handler remains off
- 2: debug mode
  - --log-level debug
  - crash handler on with --crash-log

Invalid values fall back to the launcher default (currently 0) and emit a warning.

### MORPH_CONFIG

Optional alternate config file path passed as -c.

- If readable: used directly
- If not readable: launcher exits with an error

### MORPH_ALLOW_BUILTIN_FALLBACK

Optional compatibility switch for config resolution.

- unset or `0`: missing config is a hard error
- `1` / `true` / `yes` / `on`: allow synthesized builtin binds when no config file resolves

This mirrors binary CLI flag `--allow-builtin-fallback`.

### MORPH_X11

Controls xwayland-satellite startup in compositor:

- 0: disable satellite
- 1: enable satellite

If unset, launcher applies session-aware defaults:

- nested backends (x11/wayland): default 0
- native backend (drm,libinput): default 1

### MORPH_X11_DISPLAY

Optional forced display number for satellite, for example :12.

### MORPH_LOG_DIR

Optional runtime log directory override.

Default if unset:

- $XDG_STATE_HOME/morph
- fallback: ~/.local/state/morph

Note:

- The morph suffix is a fixed project runtime namespace.
- It does not depend on launcher install path or binary name.

### MORPH_ENV_FILE

Optional path to environment override file.
If set and readable, it is sourced before launcher defaults are applied.

### MORPH_DEBUG_XDG

Optional verbose XDG lifecycle debug flag forwarded to morph.

- unset or `0`: disabled
- non-empty and not `0`: enabled

Use this when debugging early xdg_toplevel requests/state transitions.

## XKB Variables

These variables are read by morph keyboard initialization via getenv().
The launcher does not parse them; it only sources config/environment.

- XKB_DEFAULT_LAYOUT
- XKB_DEFAULT_MODEL
- XKB_DEFAULT_VARIANT
- XKB_DEFAULT_OPTIONS

Behavior:

- unset/empty values are passed as NULL-equivalent to libxkbcommon system defaults
- set values are forwarded to xkb_rule_names and used for keymap compile

Example:

```bash
XKB_DEFAULT_LAYOUT=de,us \
XKB_DEFAULT_OPTIONS=grp:alt_shift_toggle \
./testing/morph_run
```

## Practical Keyboard Test

sfwbar is not a good target for keyboard layout validation.
Use a text editor client such as geany, mousepad, or another editor inside the compositor session.

Suggested check:

1. Start with XKB vars set.
2. Open geany (or another editor) and type text.
3. Switch layout (for example Alt+Shift when configured in options).
4. Verify that character output changes as expected.

## Related Docs

- testing/LAUNCHER.md for launcher flow and runtime files
- testing/test-howto_start-variants.nfo for test runbook and triage commands
