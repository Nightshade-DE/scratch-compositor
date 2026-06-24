# Morph Launcher Guide

This document describes the runtime launcher behavior shared by **Morph**'s two shell wrappers:

- the development launcher [`testing/morph_run`](../testing/morph_run)
- the installed production wrapper [`scripts/morph-session`](../scripts/morph-session)

Use this guide for:
- development versus production wrapper behavior
- environment and config resolution order
- runtime log location and shutdown list behavior
- managed portal, startup, reload, and shutdown hook resolution

## Scope

The compositor INI syntax is documented in [`docs/CONFIG.md`](CONFIG.md).
This file covers wrapper runtime flow and wrapper-owned files only.

For all environment variables and examples, including XKB settings, see:

- [`docs/ENVIRONMENT.md`](ENVIRONMENT.md)

## Wrapper Roles

[`testing/morph_run`](../testing/morph_run) is the repo-local development wrapper.
It is meant for nested testing, local builds, fast validation, and launcher experiments.

[`scripts/morph-session`](../scripts/morph-session) is the installed production wrapper.
It is meant for display-manager sessions and production startup outside the repository.

Both wrappers keep the same managed hook model around **Morph**:

- they resolve environment layers before **Morph** starts
- they resolve the active config path before **Morph** starts
- they export [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks)
- they let the compositor dispatch [`system_startup.sh`](../scripts/system_startup.sh), [`system_reload.sh`](../scripts/system_reload.sh), and [`system_shutdown.sh`](../scripts/system_shutdown.sh)
- they keep user hooks as the user-facing extension points

**See flow chart [`Wrapper Flow`](OVERVIEW.md#wrapper-flow) and [`Managed Session Overview`](OVERVIEW.md#managed-session-overview) in `docs/OVERVIEW.md` for more details.**

## Wrapper Differences

### Development launcher: [`testing/morph_run`](../testing/morph_run)

- uses repository-local defaults such as `./build/morph`
- prefers repository files under `config/` and `testing/`
- is the wrapper used by the automated shell-runtime tests
- is the best entrypoint for local nested/native smoke checks during development

### Production wrapper: [`scripts/morph-session`](../scripts/morph-session)

- uses installed defaults such as `morph` in `PATH`
- prefers installed files under `/etc/morph`
- is the wrapper referenced by [`sessions/morph.desktop`](../sessions/morph.desktop)
- is the production entrypoint for greetd, SDDM, LightDM, and similar session managers

## Runtime Files

Typical files under **Morph**s state/log directory:

- `morph.log`
- `morph-crash.log`
- `morph-startup.log`
- `morph-shutdown.log`
- `morph-nested-startup.log`
- `morph-nested-shutdown.log`
- `shutdown_list.nfo`

Default location:

- `$XDG_STATE_HOME/morph`
- fallback: `~/.local/state/morph`

Both wrappers can override the log directory through [`MORPH_LOG_DIR`](ENVIRONMENT.md#morph-log-dir).

## Environment Resolution

Both wrappers follow the same high-level layering model:

1. Caller environment

   Example: `MORPH_DBG=2 ./testing/morph_run`

   Example: `MORPH_CONFIG=/tmp/debug.conf morph-session`

2. System environment file

   Example source path in development: [`config/environment`](../config/environment)

   Example installed path: `/etc/morph/environment`

3. User environment file

   Example path: `~/.config/morph/environment`

   Example use case: per-user `XKB_DEFAULT_LAYOUT=de,us`

4. Wrapper defaults

   Example: default log directory under `$XDG_STATE_HOME/morph`

   Example: nested sessions default [`MORPH_X11`](ENVIRONMENT.md#morph-x11) to `0`

5. Caller environment restored as highest priority

Common behavior:

- caller-provided variables win over sourced files
- user environment can override system environment
- wrapper defaults only fill values that remain unset
- the wrapper exports [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks) before launching **Morph**

Default environment files differ by wrapper:

- [`testing/morph_run`](../testing/morph_run) uses the repository-local [`config/environment`](../config/environment)
- [`scripts/morph-session`](../scripts/morph-session) uses `/etc/morph/environment` by default; repo source: [`config/environment`](../config/environment)
- both wrappers also read the user override `~/.config/morph/environment` when it exists

**See flow chart [`Wrapper Flow`](OVERVIEW.md#wrapper-flow) in `docs/OVERVIEW.md` for more details.** 

## Config Resolution

Both wrappers resolve the active config before **Morph** starts.

Shared priority:

1. [`MORPH_CONFIG`](ENVIRONMENT.md#morph-config) when set to a readable path
2. user config fallback
3. system config fallback
4. optional builtin fallback when [`MORPH_ALLOW_BUILTIN_FALLBACK=1`](ENVIRONMENT.md#morph-allow-builtin-fallback)

Default config paths differ by wrapper:

- [`testing/morph_run`](../testing/morph_run) uses the repository-local config as its system-side default; repo source: [`config/morph.conf`](../config/morph.conf)
- [`scripts/morph-session`](../scripts/morph-session) uses `/etc/morph/morph.conf` as its system-side default; repo source: [`config/morph.conf`](../config/morph.conf)
- both wrappers still prefer `~/.config/morph/morph.conf` as the user fallback

After config resolution, both wrappers export the resolved user hook commands so the managed system hooks can still honor them during fallback cleanup.

**See flow chart [`Wrapper Flow`](OVERVIEW.md#wrapper-flow) in `docs/OVERVIEW.md` for more details.**

## Portal Resolution

Portal startup is managed separately from user autostarts.

Resolution order in the managed flow:

1. The wrapper exports [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks)
2. The compositor dispatches [`scripts/system_startup.sh`](../scripts/system_startup.sh)
3. Managed base file: [`config/portals`](../config/portals) in development, installed portal file in production
4. Optional user override: `~/.config/morph/portals`

Behavior:

- The config keeps the user hook paths. The managed runtime reads those commands from the active config and passes them through environment variables.
- [`scripts/system_startup.sh`](../scripts/system_startup.sh) loads startup helpers, prepares nested/native runtime state, and then runs the configured user startup hook or its XDG fallback.
- Native sessions load the managed base portal setup before any session components are started.
- If the user override exists, it is sourced after the managed base file and may replace [`morph_start_portals()`](../config/portals).
- Nested sessions skip portal startup entirely.
- Users do not need a portal file unless they intentionally want to override the managed default behavior.

**See flow chart [`Startup Flow`](OVERVIEW.md#startup-flow) and [`Managed Session Overview`](OVERVIEW.md#managed-session-overview) in `docs/OVERVIEW.md` for more details.**

## Startup Hook Resolution

The user startup hook is where session components such as bars, terminals, applets, and optional services should be started.

Behavior in the managed flow:

- With [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks), the compositor dispatches [`scripts/system_startup.sh`](../scripts/system_startup.sh) instead of running the configured startup hook directly.
- [`scripts/system_startup.sh`](../scripts/system_startup.sh) prepares nested/native runtime state, starts managed portal setup when needed, and then runs the configured user startup hook or its XDG fallback.
- [`config/startup.sh`](../config/startup.sh) is therefore the main user entrypoint for session autostarts, while [`config/portals`](../config/portals) remains reserved for managed portal setup.
- Services started through `launch <cmd ...>` in the user startup hook are tracked for shutdown cleanup in [`shutdown_list.nfo`](#launcher-managed-shutdown-process-list-file-do-not-edit-this-file).
- `launch_nokill <cmd ...>` is available for helper processes that should not be registered for shutdown tracking.
- Nested sessions still run the user startup hook, but skip the native-only managed portal startup path.

**See flow chart [`Startup Flow`](OVERVIEW.md#startup-flow) in `docs/OVERVIEW.md` for more details.**

## Reload Resolution

Reload uses the compositor IPC entrypoint `reload config` / `reload`.

Behavior in the managed flow:

- With [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks), the compositor dispatches [`scripts/system_reload.sh`](../scripts/system_reload.sh) instead of running the configured reload hook directly.
- [`scripts/system_reload.sh`](../scripts/system_reload.sh) exposes the same helper library as startup/shutdown and then runs the configured user reload hook or its XDG fallback.
- User reload hooks can restart managed session components in-place with `reload <cmd ...>`, for example `reload sfwbar`.
- User reload hooks can also start optional components once with `reload_once <cmd ...>`, for example `reload_once mutagen`.
- The `reload` helper stops the currently running process by basename, starts the replacement command, and keeps the shutdown tracker free of duplicate entries.

**See flow chart [`Reload Flow`](OVERVIEW.md#reload-flow) in `docs/OVERVIEW.md` for more details.**

## Shutdown Hook Resolution

The user shutdown hook is the place for manual cleanup that should happen before
**Morph** performs its managed session teardown.

Behavior in the managed flow:

- With [`MORPH_MANAGED_HOOKS=1`](ENVIRONMENT.md#morph-managed-hooks), the compositor dispatches [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) instead of running the configured shutdown hook directly.
- [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) first runs the configured user shutdown hook or its XDG fallback.
- [`config/shutdown.sh`](../config/shutdown.sh) is therefore the user entrypoint for optional manual cleanup such as stopping user-managed helper processes.
- After the user shutdown hook returns, [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) performs the managed cleanup, including tracked process termination from [`shutdown_list.nfo`](#launcher-managed-shutdown-process-list-file-do-not-edit-this-file).
- The shutdown hook runs synchronously: **Morph** waits for the user shutdown hook to finish before the managed cleanup continues.
- Nested sessions still follow the same hook resolution path, but the managed cleanup remains scoped to the nested session state.

**See flow chart [`Shutdown Flow`](OVERVIEW.md#shutdown-flow) in `docs/OVERVIEW.md` for more details.**

## Launcher-managed shutdown process list file (DO NOT EDIT THIS FILE!)

- [`shutdown_list.nfo`](#launcher-managed-shutdown-process-list-file-do-not-edit-this-file)

Path:

- `$XDG_STATE_HOME/morph/shutdown_list.nfo`
- fallback: `~/.local/state/morph/shutdown_list.nfo`

This file is runtime state, not user configuration.
Do not edit it manually.

### Short lifecycle

1. At wrapper start, the file is recreated or cleared.
2. Each service started via `launch` in [`config/startup.sh`](../config/startup.sh) is appended to this file.
3. On abnormal compositor exit, the wrapper runs [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) directly.
4. [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) first runs the configured user shutdown hook or its XDG fallback.
5. [`scripts/system_shutdown.sh`](../scripts/system_shutdown.sh) then reads this list and terminates the registered services with `TERM`, then `KILL` if needed.
6. Manual edits can desync this list and lead to unclean shutdown with leftover or wrongly terminated processes.

**See flow chart [`Shutdown Flow`](OVERVIEW.md#shutdown-flow) in `docs/OVERVIEW.md` for more details.**

## Typical Runs

Development wrapper:

```sh
./testing/morph_run
MORPH_DBG=1 ./testing/morph_run
MORPH_DBG=2 ./testing/morph_run
MORPH_CONFIG=/path/to/other.conf ./testing/morph_run
MORPH_X11=0 ./testing/morph_run
MORPH_X11_DISPLAY=:12 ./testing/morph_run
MORPH_LOG_DIR=/tmp/morph-test ./testing/morph_run
MORPH_ALLOW_BUILTIN_FALLBACK=1 ./testing/morph_run
```

Production wrapper:

```sh
morph-session
MORPH_DBG=1 morph-session
MORPH_CONFIG=/etc/morph/morph.conf morph-session
MORPH_LOG_DIR=/tmp/morph-session-test morph-session
MORPH_ALLOW_BUILTIN_FALLBACK=1 morph-session
```

**See flow chart [`Managed Session Overview`](OVERVIEW.md#managed-session-overview) and [`Standalone Binary Flow`](OVERVIEW.md#standalone-binary-flow) in `docs/OVERVIEW.md` for more details.**

## Related Docs

- [`docs/CONFIG.md`](CONFIG.md) for compositor INI syntax
- [`README.md`](../README.md) for project overview and entrypoints
- [`docs/ENVIRONMENT.md`](ENVIRONMENT.md) for runtime environment variables and XKB settings
- [`testing/test-howto_start-variants.nfo`](../testing/test-howto_start-variants.nfo) for test-oriented command sequences
- [`docs/OVERVIEW.md`](OVERVIEW.md) for the repository map and managed session flow diagrams
