#!/usr/bin/env bash
set -e

# Navigate to the script's directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Claude Desktop Docker Launcher ==="

# 1. Authorize local container connections to the X11 display server
# (As explained in the GeeksforGeeks GUI Docker guide)
if command -v xhost >/dev/null 2>&1; then
    echo "Configuring X11 permissions with xhost..."
    xhost +si:localuser:$(whoami) >/dev/null 2>&1 || xhost +local: >/dev/null 2>&1 || true
fi

# 2. Export current user IDs and environment variables
export USER_UID=$(id -u)
export USER_GID=$(id -g)
export DOCKER_GID=$(getent group docker | cut -d: -f3 2>/dev/null || echo 984)
export DISPLAY="${DISPLAY:-:0}"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$USER_UID}"

# Create the shared Claude temp dir ourselves, otherwise Docker creates it owned by root
mkdir -p -m 700 "/tmp/claude-$USER_UID"

# 3. Check if image exists; if not, build it
if ! docker image inspect claude-desktop:latest >/dev/null 2>&1; then
    echo "Building Claude Desktop Docker image..."
    docker compose build
fi

# 4. Run the container
echo "Starting Claude Desktop inside Docker..."
docker compose run --rm claude-desktop "$@"
