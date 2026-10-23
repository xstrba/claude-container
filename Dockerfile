FROM ubuntu:24.04

# Prevent interactive prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Arguments for non-root user (defaults to 1000:1000 to match host user)
ARG USER_NAME=claude
ARG USER_UID=1000
ARG USER_GID=1000

# Install base dependencies and X11/Wayland support libraries
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    gnupg \
    sudo \
    dbus-x11 \
    libsecret-1-0 \
    libsecret-tools \
    xdg-utils \
    libnotify4 \
    libnss3 \
    libatspi2.0-0 \
    libdrm2 \
    libgbm1 \
    libxcb-dri3-0 \
    libxtst6 \
    libuuid1 \
    libasound2t64 \
    pulseaudio-utils \
    libgl1-mesa-dri \
    libgl1 \
    mesa-utils \
    fonts-liberation \
    fonts-dejavu-core \
    fontconfig \
    git \
    nodejs \
    npm \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Add official Anthropic APT repository and install Claude Desktop
RUN curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc \
    && echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" > /etc/apt/sources.list.d/claude-desktop.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends claude-desktop \
    && rm -rf /var/lib/apt/lists/*

# Create or configure user with matching UID/GID and add to audio/video/render groups
RUN userdel -r ubuntu 2>/dev/null || true \
    && (groupadd -g ${USER_GID} ${USER_NAME} 2>/dev/null || true) \
    && useradd -u ${USER_UID} -g ${USER_GID} -m -s /bin/bash ${USER_NAME} \
    && usermod -aG audio,video ${USER_NAME} 2>/dev/null || true \
    && (getent group render && usermod -aG render ${USER_NAME} 2>/dev/null || true) \
    && echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Additional CLI tools (added at the end so Claude Desktop layers remain fully cached)
RUN apt-get update && apt-get install -y --no-install-recommends \
    gh \
    docker.io \
    python-is-python3 \
    && rm -rf /var/lib/apt/lists/* \
    && curl -sL https://sentry.io/get-cli/ | bash

# Install Google Chrome Stable for OAuth and browser links (new layer at the end)
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb -o /tmp/chrome.deb \
    && apt-get update \
    && apt-get install -y --no-install-recommends /tmp/chrome.deb \
    && rm -f /tmp/chrome.deb \
    && rm -rf /var/lib/apt/lists/* \
    && dpkg-divert --add --rename --divert /usr/bin/google-chrome-stable.real /usr/bin/google-chrome-stable \
    && echo '#!/bin/bash\nexec /usr/bin/google-chrome-stable.real --no-sandbox "$@"' > /usr/bin/google-chrome-stable \
    && chmod +x /usr/bin/google-chrome-stable \
    && ln -sf /usr/bin/google-chrome-stable /usr/bin/google-chrome

# Fix custom URL scheme redirection (claude://) and xdg-open protocol handling for OAuth
RUN apt-get update && apt-get install -y --no-install-recommends libglib2.0-bin \
    && rm -rf /var/lib/apt/lists/* \
    && printf '%s\n' \
       '#!/bin/bash' \
       'URL="$1"' \
       'if [[ "$URL" =~ ^claude:// ]]; then' \
       '    exec /usr/bin/claude-desktop --no-sandbox "$URL"' \
       'fi' \
       'if [[ "$URL" =~ ^https?:// ]]; then' \
       '    exec /usr/bin/google-chrome-stable --no-sandbox "$URL"' \
       'fi' \
       'exec /usr/bin/xdg-open "$@"' \
       > /usr/local/bin/xdg-open \
    && chmod +x /usr/local/bin/xdg-open \
    && update-desktop-database 2>/dev/null || true

# Install gnome-keyring for secure isolated credential storage inside container (new layer at the end)
RUN apt-get update && apt-get install -y --no-install-recommends gnome-keyring \
    && rm -rf /var/lib/apt/lists/*

# SSH client and rsync for remote access and file sync, xdotool for renaming the window class (new layer at the end)
RUN apt-get update && apt-get install -y --no-install-recommends openssh-client rsync xdotool \
    && rm -rf /var/lib/apt/lists/*

# Add official Anthropic APT repository and install a pinned version of Claude Desktop
ARG CLAUDE_VERSION=1.3

RUN echo ${CLAUDE_VERSION} && apt-get update && apt-get upgrade -y --no-install-recommends

# Custom Docker-badged window and tray icons
COPY assets/* /usr/lib/claude-desktop/resources/

USER ${USER_NAME}
WORKDIR /home/${USER_NAME}

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/claude-desktop"]
