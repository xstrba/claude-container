# AGENTS.md

Guidance for AI coding agents working on this repository **and** for agents running inside the container it builds. Full user docs: [README.md](README.md).

## What this repo is

A Docker setup that runs the official Claude Desktop (Linux, Electron) inside an `ubuntu:24.04` container and shows it on the host display through X11/XWayland. It is a personal setup for one specific host. There's no build system, test suite or CI, only these files:

| File | Role |
|---|---|
| `Dockerfile` | Image: deps, Claude Desktop APT package, user `claude`, CLI tools, Chrome, `xdg-open` shim, keyring, ssh/rsync/xdotool |
| `docker-compose.yml` | Single service `claude-desktop`: env, mounts, `network_mode: host`, `ipc: host`, docker group |
| `entrypoint.sh` | Bind-mounted at runtime. Starts D-Bus, keyring, WM_CLASS rename loop, then `exec claude-desktop --no-sandbox` |
| `run.sh` | Host launcher used by the `.desktop` file: xhost, env exports, creates `/tmp/claude-$UID`, builds if missing, `docker compose run --rm` |
| `assets/` | Docker-badged window/tray icons copied over the app's `resources/` |
| `.env` / `.env.example` | Sentry variables. **`.env` is gitignored and may contain a real token: never print, copy or commit it.** |
| `docker-compose.override.yml` | Gitignored, machine-specific project mounts (template: `docker-compose.override.example.yml`). Never move its contents into `docker-compose.yml`. |

Outside the repo, on the host: `~/.local/share/applications/claude-docker.desktop` (`StartupWMClass=claude-docker`, `Exec=…/run.sh %U`) and `~/.local/share/icons/hicolor/*/apps/claude-docker.png`.

## Host constraints (the reference setup: don't "generalize" them away)

- Ubuntu 24.04 LTS, amd64, GNOME Shell 46 + Ubuntu Dock, **Wayland session with XWayland**.
- Host user with UID/GID **1000:1000**, `docker` group GID **984** (detected by `run.sh`).
- Audio via PipeWire's PulseAudio socket `/run/user/1000/pulse/native`.
- Intel/AMD GPU through `/dev/dri` (Mesa).
- Docker Engine 29.x with Compose v2 plugin (`docker compose`).
- Host also runs a native Claude Desktop (`/usr/share/applications/com.anthropic.Claude.desktop`, `StartupWMClass=com.anthropic.Claude`). The container instance must stay visually and functionally separate from it.

## Invariants: keep these working when you change things

1. **X11 only.** The app must keep running through `/tmp/.X11-unix`. Don't mount the Wayland socket or force `--ozone-platform=wayland`: the dock-grouping fix relies on changing `WM_CLASS`, which is impossible for a native Wayland `app_id`.
2. **WM_CLASS rename loop** in `entrypoint.sh` (needs `xdotool` in the image). Electron ignores `--class`; the window class comes from the app's `desktopName` (`com.anthropic.Claude`). Without the loop the host dock merges the container window into host Claude.
3. **`--no-sandbox`** for `claude-desktop` and Chrome (wrapper at `/usr/bin/google-chrome-stable`, shim at `/usr/local/bin/xdg-open`, sed patches in the entrypoint).
4. **Layer order in the Dockerfile.** The Claude Desktop and Chrome layers are slow, so add new packages in a **new `RUN` layer near the end**, before the `ARG CLAUDE_VERSION` upgrade layer. Don't edit the first big `apt-get install` unless necessary.
5. **UID/GID match.** The user `claude` is created from the build args `USER_UID`/`USER_GID`; bind-mount ownership and SSH key permissions depend on it.
6. **Host bind sources must exist before start**, or Docker creates root-owned directories. For new host-path mounts under `/tmp` or similar, create them in `run.sh` (see `/tmp/claude-$UID`).
7. **Read-only identity mounts.** `~/.ssh`, `~/.gitconfig`, `~/.config/git` stay `:ro`.
8. **Isolated keyring and D-Bus.** Never mount the host D-Bus session bus or host keyring.
9. `/home/claude` is the named volume `claudecontainer_claude-home` (login, settings, keyring). Never delete it unless the user asks.

## Making changes

- `entrypoint.sh` changes apply on the next container start (it's bind-mounted); no rebuild needed.
- `docker-compose.yml` changes apply on the next `./run.sh`; no rebuild needed (except build args).
- `Dockerfile` changes need `docker compose build`. `run.sh` only builds when the image is missing.
- Check compose syntax with `USER_UID=1000 docker compose config --quiet`, and shell scripts with `bash -n`.
- To test image behavior without touching the user's running instance or home volume, use a throwaway container, e.g. `docker run --rm --entrypoint bash claude-desktop:latest -c '…'`. For GUI tests, mount `/tmp/.X11-unix`, set `DISPLAY`, use a temporary `HOME`, and `docker rm -f` it afterwards.
- Inspect window classes from the host with `xprop -root _NET_CLIENT_LIST` and `xprop -id <id> WM_CLASS`. Only XWayland windows show up; host Wayland windows don't.
- Don't restart, stop or rebuild the user's running container unless asked; they may be using it.
- Keep README.md in sync when you add mounts, packages or constraints.

## If you are an agent running *inside* the container

- You are user `claude` (UID 1000) with passwordless `sudo`, home `/home/claude` (persistent volume). Anything installed with `apt` outside the home folder **disappears on restart**; add it to the Dockerfile instead.
- Projects: the folders from `docker-compose.override.yml`, mounted under `/home/claude/…`; on the host the same folders are under the host user's home.
- `/tmp/claude-1000` is shared with the host (same path on both sides). Use it to exchange files with the host Claude.
- Git commits use the host user's identity from the read-only `~/.gitconfig`. `git config --global` fails; set per-repo config if needed. Don't try to "fix" a missing identity with a different name.
- ssh/rsync use the host keys from read-only `~/.ssh`. `known_hosts` can't be written, so host-key warnings are expected. Use `-o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/tmp/claude-1000/known_hosts` if a writable file is needed.
- `docker` talks to the **host** daemon. Bind-mount paths are resolved on the host, so translate `/home/claude/…` → the host user's home in `-v` arguments (check the mapping in `docker-compose.override.yml`). Don't stop or remove containers you didn't start; the host may run other dev containers.
- Networking is the host's (`network_mode: host`): `localhost` reaches host services.
- Links open in the container's Chrome (`--no-sandbox`); `claude://` links go to the container's Claude.
- Available tools: `git`, `gh`, `docker`, `sentry-cli`, `ssh`, `rsync`, `curl`, `xdotool`, `node` 18, `npm`, `python3` 3.12, `pip`, `venv`.
