#!/bin/bash
set -e

# Ensure runtime directory exists with proper permissions
mkdir -p -m 700 "${XDG_RUNTIME_DIR:-/tmp/runtime-claude}"

# Start isolated D-Bus session inside the container
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax)
    export DBUS_SESSION_BUS_ADDRESS
fi

# Unlock and initialize isolated container keyring (password: empty)
mkdir -p "$HOME/.local/share/keyrings"
if [ -f "$HOME/.local/share/keyrings/Default_keyring.keyring" ] && [ ! -f "$HOME/.local/share/keyrings/Default_keyring.keyring.bak" ]; then
    mv "$HOME/.local/share/keyrings/Default_keyring.keyring" "$HOME/.local/share/keyrings/Default_keyring.keyring.bak" 2>/dev/null || true
fi
echo -n "login" > "$HOME/.local/share/keyrings/default"
printf "\n" | gnome-keyring-daemon --unlock 2>/dev/null || true
eval $(gnome-keyring-daemon --start --components=secrets 2>/dev/null) || true

# Ensure URL scheme handlers inside the container always pass --no-sandbox (and match keyring store)
sudo sed -i 's|Exec=claude-desktop|Exec=/usr/bin/claude-desktop --no-sandbox|g' /usr/share/applications/com.anthropic.Claude.desktop 2>/dev/null || true
sudo sed -i 's|--password-store=basic ||g' /usr/local/bin/xdg-open 2>/dev/null || true
mkdir -p "$HOME/.local/share/applications"
sed 's|Exec=claude-desktop|Exec=/usr/bin/claude-desktop --no-sandbox|g' /usr/share/applications/com.anthropic.Claude.desktop > "$HOME/.local/share/applications/com.anthropic.Claude.desktop" 2>/dev/null || true

# Filter out default invocation arguments if passed by Docker CMD
if [ "$1" = "claude-desktop" ] || [ "$1" = "/usr/bin/claude-desktop" ]; then
    shift
fi

# If a custom shell command is provided (e.g. bash, sh), run it directly
if [ $# -gt 0 ] && [ "$1" != "--help" ] && [ "$1" != "--version" ] && ! [[ "$1" == -* ]] && ! [[ "$1" =~ ^claude:// ]]; then
    exec "$@"
fi

# Rename the window class so the host dock groups our windows under claude-docker.desktop
# instead of the host's com.anthropic.Claude.desktop (Electron ignores --class)
if command -v xdotool >/dev/null 2>&1; then
    (
        while sleep 1; do
            for w in $(xdotool search --classname '^com\.anthropic\.claude$' 2>/dev/null); do
                xdotool set_window --classname claude-docker --class claude-docker "$w" 2>/dev/null || true
            done
        done
    ) &
fi

# Launch Claude Desktop with --no-sandbox
exec /usr/bin/claude-desktop --no-sandbox "$@"
