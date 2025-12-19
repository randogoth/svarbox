Repository moved to [https://codeberg.org/randogoth/svarbox.git](https://codeberg.org/randogoth/svarbox.git)

# SvarBox 

This repository packages a repeatable SvarDOS environment that can be exposed over SSH (with optional X forwarding) and telnet. It wraps the upstream `dosemu2` emulator with automation for bootstrapping media, distributing pre-approved files, and hardening the guest runtime so multiple users can log in without trampling each other.

The project is split into small, testable shell helpers plus a Docker image that glues them together. You can run everything with `docker compose`, or treat the image as a standalone component inside an existing infrastructure.

---

- [Quick Start](#quick-start)
- [Repository Layout](#repository-layout)
- [How the Container Boots](#how-the-container-boots)
- [Customising the DOS Drive](#customising-the-dos-drive)
- [Controlling `dos-shell`](#controlling-dos-shell)
- [Environment Variables (Container / Compose)](#environment-variables-container--compose)
- [Managing the SvarDOS Base Image](#managing-the-svardos-base-image)
- [Running Without Docker Compose](#running-without-docker-compose)
- [Troubleshooting](#troubleshooting)
- [Maintenance & Housekeeping](#maintenance--housekeeping)
- [Security Notes](#security-notes)

---

## Quick Start

Bring the stack up:

```sh
docker compose up -d --build    # rebuilds the image so scripts stay in sync
```

Default access:

- **User:** `dosuser`
- **Password:** `dosuser`
- **SSH:** `ssh -X dosuser@localhost -p 2222`
- **Telnet (optional):** `telnet localhost 2323` (disabled if `ENABLE_TELNET=0`)
- **Web console:** `http://localhost:8080` (disable with `ENABLE_HTTP_CONSOLE=0`)

Use `exit` from the DOS shell to terminate the session; the container keeps running for the next login.

All persistent user data inside the guest lives under `/home/dosuser/.dosemu`, which is created on first login.

## How the Container Boots

1. **`prepare-svardos`** runs during build, downloading the latest SvarDOS ZIP (override with `SVARDOS_IMG_URL`) and staging it under `/opt/svardos/base`.
2. **`start-dos-services`** starts the optional web console, BusyBox `telnetd` (if enabled), and then `sshd`.
3. Whenever `dosuser` logs in, **`dos-shell`**:
   - Detects terminal mode (X11 window, terminal, or dumb) and composes the corresponding `dosemu` flags.
   - Ensures a private C: drive under `/home/dosuser/.dosemu/drive_c`, copying SvarDOS files if the sentinel `.svardos_installed` is missing or if you asked for a reinstall.
   - Synchronises approved host files from `/opt/allowed_repo` based on the policy (`DOS_ALLOW_MODE` and `/etc/dos_allowed`).
   - Applies optional `AUTOEXEC.BAT` / `CONFIG.SYS` templates from `/etc/dos_env`.
   - Automatically amends the user’s `dosemurc` when hardware features are unavailable (e.g. no `/dev/kvm`, no X11/PulseAudio) so dosemu starts quietly.
   - Falls back to the `dosuser` account if the login happened as root (useful for forced commands via sshd).

## Customising the DOS Drive

- **`allowed_repo/` volume** – drop files here on the host; they are copied into C:\ during login.
- **`config/dos_allowed`** – list relative paths (from `allowed_repo/`) to permit when `DOS_ALLOW_MODE=list`. With `DOS_ALLOW_MODE=all` every file in the repo is staged.
- **`dos_env/` templates** – place `AUTOEXEC.BAT` and/or `CONFIG.SYS` to control boot scripts.
- **`dos_home/` volume** – bind-mounted to `/home/dosuser`; persists the DOS user profile, `.dosemu` state, SSH keys, etc.
- **`dos_drives/` volume** – subdirectories named after drive letters (e.g. `F`, `G`) are exposed to DOS as additional drives. Letters `C`, `D`, and `E` are reserved by default (see `DOS_RESERVED_DRIVES` below); set that variable if you want to repurpose them.
- **Pre-boot hook** – create an executable `dos_env/pre-boot.sh` (or point `DOS_PRE_BOOT_HOOK` at another path). It runs as `dosuser` immediately before dosemu starts, with helper environment variables (`C_DRIVE`, `DOSEMU_DIR`, `ALLOWED_REPO`, `SVARDOS_ROOT`, `SVARDOS_BASE`) so you can copy, delete, or patch files on the DOS drive.
- **Forcing a reinstall** – set `DOS_FORCE_INSTALL=1` in the environment before logging in; the script re-seeds the drive from `/opt/svardos/base`.

Typical layout when using `docker compose`:

```
allowed_repo/
  games/
    doom/
      doom.exe
dos_home/
  .ssh/
    authorized_keys
dos_drives/
  F/
    demos/
      intro.exe
dos_env/
  AUTOEXEC.BAT
  CONFIG.SYS
```

## Controlling `dos-shell`

You can influence runtime behaviour with environment variables. Set them either in the container environment (e.g. via `compose.yml`, `.env`, or `docker run -e`).

| Variable              | Values / Default       | Effect                                                                                           |
|-----------------------|------------------------|--------------------------------------------------------------------------------------------------|
| `DOS_TERMINAL_MODE`   | `auto` (default), `x`, `sdl`, `terminal`, `dumb` | Forces the video backend used for dosemu.                                                        |
| `DOS_AUDIO_MODE`      | `auto` (default), `force`, `mute`                | Auto-mute when PulseAudio/PipeWire isn’t available over SSH, or force sound on/off.              |
| `DOS_LANDLOCK_MODE`   | `auto` (default), `force`, `off`                 | Controls Landlock sandboxing; `auto` disables it if kernel headers don’t expose the ABI we need. |
| `DOS_ALLOW_MODE`      | `all` (default) or `list`                        | Stage everything from `/opt/allowed_repo`, or only the entries listed in `/etc/dos_allowed`.     |
| `DOS_FORCE_INSTALL`   | `0` (default) or `1`                             | Rebuilds the C: drive from the SvarDOS base on the next login.                                   |
| `DOS_TERMINAL_MODE`   | `auto`                                            | Determines whether `dosemu` launches with X11 (`-X`), terminal (`-td`) or `-dumb`.               |
| `DOS_ENV_DIR`         | defaults to `/etc/dos_env`                       | Override if you mount templates somewhere else.                                                  |
| `DOS_PRE_BOOT_HOOK`   | `${DOS_ENV_DIR}/pre-boot.sh`                     | Custom shell script to run (as `dosuser`) before launching dosemu. Must be executable.           |
| `DOS_EXTRA_DRIVE_ROOT` | `/opt/dos_drives`                               | Override where `dos-shell` looks for extra drive directories (one per drive letter).             |
| `DOS_RESERVED_DRIVES` | `CDE`                                            | Letters to leave untouched when mapping extra drives (remove or change to claim `D:`/`E:` etc.). |
| `DOS_ALLOWED_REPO`    | `/opt/allowed_repo`                              | Alternate root for the allowed-repo staging area (useful in tests or custom mounts).             |
| `DOS_ALLOWED_LIST`    | `/etc/dos_allowed`                               | Path to the allowlist file consumed when `DOS_ALLOW_MODE=list`.                                  |
| `SVARDOS_ROOT`/`SVARDOS_BASE` | default `/opt/svardos`                   | Changes where the base image lives (mostly useful during debugging).                             |
| `AO_DRIVER`           | auto-set to `null` when sound is muted            | You can override to force libao to a specific backend.                                           |

`dos-shell` also writes a managed `~/.dosemu/dosemurc` (marked with `# Managed by dos-shell…`) when it needs to enforce CPU or audio fallbacks. Delete the file to restore defaults; it is regenerated on demand.

### Podman / Docker exec entrypoints

`dos-shell` remains the default login shell for `dosuser`, so a plain `podman exec -it svarbox dos-shell` (or `docker exec`) drops you straight into the DOS session. When you need a regular Linux shell in the same running container, reuse the wrapper but append `--linux-shell`:

```sh
podman exec -it svarbox dos-shell --linux-shell        # interactive bash as dosuser
podman exec -it svarbox dos-shell --linux-shell "ls"   # run a single command as dosuser
```

You can override which binary is used for the Linux side by setting `DOS_LINUX_SHELL` (defaults to `/bin/bash`).

## Environment Variables (Container / Compose)

`compose.yml` exposes a few knobs. You can drop a `.env` file next to it to override the defaults.

| Compose Variable         | Default             | Description                                              |
|--------------------------|---------------------|----------------------------------------------------------|
| `DOS_IMAGE_NAME`         | `svarbox`           | Tag assigned to the built image.                         |
| `DOS_CONTAINER_NAME`     | `svarbox`           | Name of the running container.                           |
| `DOS_SSH_PORT`           | `2222`              | Host port forwarded to container port 22.                |
| `DOS_TELNET_PORT`        | `2323`              | Host port forwarded to container port 23.                |
| `DOS_HTTP_PORT`          | `8080`              | Host port forwarded to the web console.                  |
| `DOS_HTTP_CRT`           | `1`                 | Toggle the CRT styling applied to the web console (`0` to disable). |
| `ENABLE_TELNET`          | `1`                 | Toggle BusyBox telnetd.                                  |
| `ENABLE_HTTP_CONSOLE`    | `1`                 | Launch the built-in web terminal.                        |
| `TELNET_PORT`            | `23`                | Port inside the container where telnetd listens.         |
| `TELNET_LOGIN`           | `/bin/login`        | Login command invoked by telnetd.                        |
| `DOS_ALLOW_MODE`         | `all`               | Passed straight through to `dos-shell`.                  |
| `SVARDOS_IMG_URL`        | *(empty)*           | When set, overrides the SvarDOS ZIP downloaded at build time. |

Example `.env` snippet:

```
DOS_SSH_PORT=2022
ENABLE_TELNET=0
ENABLE_HTTP_CONSOLE=0
DOS_ALLOW_MODE=list
SVARDOS_IMG_URL=https://example.com/custom-svardos.zip
```

## Managing the SvarDOS Base Image

`prepare-svardos` downloads and unpacks the official SvarDOS `svardos-*-dosemu.zip`. Key environment variables:

| Variable             | Purpose                                                                    |
|----------------------|----------------------------------------------------------------------------|
| `SVARDOS_IMG_URL`    | Fetch from a custom URL instead of the default published snapshot.        |
| `SVARDOS_ROOT`       | Root directory under which files are staged (defaults to `/opt/svardos`). |
| `SVARDOS_BASE_DIR`   | Override the final `base` directory location.                              |
| `SVARDOS_REFRESH`    | Set to any value to force a re-download even if `COMMAND.COM` already exists. |

During image build the script also patches `INSTALL.BAT` and `AUTOEXEC.BAT` to work smoothly with contemporary package paths.

If you want to refresh the base files inside a running container:

```sh
docker exec -e SVARDOS_REFRESH=1 svarbox /usr/local/bin/prepare-svardos
```

Subsequent logins should pick up the new contents once you also export `DOS_FORCE_INSTALL=1`.

## Running Without Docker Compose

You can launch the container directly:

```sh
docker build -t svarbox .
docker run -d --name svarbox \
  -p 2222:22 -p 2323:23 -p 8080:8080 \
  -v "$(pwd)/allowed_repo:/opt/allowed_repo" \
  -v "$(pwd)/config/dos_allowed:/etc/dos_allowed:ro" \
  -v "$(pwd)/dos_env:/etc/dos_env:ro" \
  svarbox
```

To override behaviour, append `-e` flags:

```sh
docker run … -e ENABLE_TELNET=0 -e ENABLE_HTTP_CONSOLE=0 -e DOS_ALLOW_MODE=list -e DOS_AUDIO_MODE=force …
```

## Troubleshooting

| Symptom / Log line                                                   | Cause & Fix                                                                                                        |
|----------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------------------|
| `dos-shell: disabling KVM acceleration (no usable /dev/kvm)`         | The kernel lacks `/dev/kvm` (common inside nested VMs). CPU emulation is already enabled; no action required.      |
| `dos-shell: muting DOS audio for this session`                       | No PulseAudio/PipeWire endpoint detected when logging in over SSH. Export `DOS_AUDIO_MODE=force` if you need sound.|
| `ERROR: ladspa: failed to load filter.so / libao: unable to open`    | Happens when audio is muted; harmless once the override is applied.                                                |
| `Landlock ABI … not defined / landlock_init() failed`                | Older kernels don’t expose `LANDLOCK_ACCESS_FS_REFER`. `dos-shell` disables Landlock automatically.                |
| `mkdir: cannot create directory '/home/dosuser/.dosemu'`             | Bind-mounted home directory isn’t writable. On Docker, ensure the path is owned by UID/GID 1000. For rootless Podman, keep the compose-provided `selinux: z` volume labels (or add `:z`/`:Z` when running manually) and, if needed, run `podman unshare chown -R 1000:1000 dos_home` so the namespace-mapped UID can write. |
| `ERROR: using outdated config file ~/.dosemurc`                      | Remove the legacy file (`rm ~/.dosemurc`). `dos-shell` now writes to `~/.dosemu/dosemurc`.                          |
| `ssh: connect … port 2222: Connection refused`                       | Container not running. `docker compose ps` or `docker compose up -d` to start it.                                   |

Enemy separation: `dos-shell` prints the config overrides it applies; review those messages first when diagnosing odd behaviour.

## Maintenance & Housekeeping

- **Backing up user data:** everything lives under `/home/dosuser`; mount a volume if you need persistence beyond container lifetimes.
- **Upgrading dosemu2/SvarDOS:** rebuild the image (`docker compose build`) after adjusting `Dockerfile` or `SVARDOS_IMG_URL`.
- **Resetting to stock files:** remove `/home/dosuser/.dosemu` or log in with `DOS_FORCE_INSTALL=1`.
- **Extending the allow-list:** add entries to `config/dos_allowed` (one per line) or switch the mode to `all`.
- **Audit logs:** `sshd` is configured to run in debug mode (`-e`); use `docker logs svarbox` for a quick view.

## Security Notes

- SSH is preferred; telnet is available only if explicitly enabled and should be disabled on untrusted networks.
- When audio is muted the script points libao to the `null` backend to avoid opening `/dev/dsp` or Pulse pipes.
- Landlock sandboxing provides extra filesystem isolation when available. The script downgrades gracefully when the kernel is too old.
- The default credentials are intentionally simple for local development. Change them (or add public keys) before exposing the service.
