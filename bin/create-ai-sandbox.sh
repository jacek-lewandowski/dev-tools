#!/bin/bash

# Define the project directory or use current directory
PROJECT_DIR=${1:-.}
cd "$PROJECT_DIR" || exit 1

ENV_DIR=".env-config"
ISOLATED_GCLOUD_DIR="$ENV_DIR/gcloud-isolated"
ANTIGRAVITY_DATA_DIR="$ENV_DIR/antigravity-data"

# Ensure host variables are available immediately for text replacement
export HOST_UID=$(id -u)
export HOST_GID=$(id -g)
export HOST_USER="$USER"

# Create necessary directories
mkdir -p "$ENV_DIR"
mkdir -p "$ISOLATED_GCLOUD_DIR"
mkdir -p "$ANTIGRAVITY_DATA_DIR"

# Determine project name from git (handles worktrees seamlessly) or fallback to current directory name
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROJECT_NAME=$(basename "$(git rev-parse --show-toplevel)")
else
    PROJECT_NAME=$(basename "$PWD")
fi

# Sanitize project name for Docker compatibility (lowercase, alphanumeric, dashes)
PROJECT_NAME=$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g')

# Fetch available Google Cloud accounts from the host system
echo "Fetching available Google Cloud accounts..."
mapfile -t ACCOUNTS < <(gcloud auth list --format="value(account)")

if [ ${#ACCOUNTS[@]} -eq 0 ]; then
    echo "Error: No Google Cloud accounts found. Please run 'gcloud auth login' on your host system first."
    exit 1
fi

# Prompt the user to select a specific account for this sandbox
echo "------------------------------------------------"
echo "Select the Google Cloud account to authorize for this project sandbox ($PROJECT_NAME):"
select SELECTED_ACCOUNT in "${ACCOUNTS[@]}"; do
    if [ -n "$SELECTED_ACCOUNT" ]; then
        echo "Selected account: $SELECTED_ACCOUNT"
        break
    else
        echo "Invalid selection. Please try again."
    fi
done
echo "------------------------------------------------"

echo "Generating isolated Application Default Credentials for $SELECTED_ACCOUNT..."
# Force gcloud to use the isolated directory and generate credentials only for the selected account.
# This will open a browser window to confirm the authorization for this specific sandbox.
env CLOUDSDK_CONFIG="$ISOLATED_GCLOUD_DIR" gcloud auth application-default login --account="$SELECTED_ACCOUNT"

# Generate the Dockerfile
cat << 'EOF' > "$ENV_DIR/Dockerfile"
# Use a minimal Ubuntu 22.04 base image
FROM ubuntu:22.04

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive

# Install base prerequisites for adding custom repositories
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Add all custom GPG keys and repositories
RUN mkdir -p /etc/apt/keyrings /usr/share/keyrings && \
    # Google Antigravity
    curl -fsSL https://us-central1-apt.pkg.dev/doc/repo-signing-key.gpg | gpg --dearmor -o /etc/apt/keyrings/antigravity-repo-key.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/antigravity-repo-key.gpg] https://us-central1-apt.pkg.dev/projects/antigravity-auto-updater-dev/ antigravity-debian main" > /etc/apt/sources.list.d/antigravity.list && \
    # Google Cloud CLI
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg | gpg --dearmor -o /usr/share/keyrings/cloud.google.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" > /etc/apt/sources.list.d/google-cloud-sdk.list && \
    # Cloudflare daemon
    curl -fsSL https://pkg.cloudflare.com/cloudflare-main.gpg | tee /usr/share/keyrings/cloudflare-main.gpg >/dev/null && \
    echo "deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared jammy main" > /etc/apt/sources.list.d/cloudflared.list && \
    # GitHub CLI
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg && \
    chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list && \
    # Node.js (NodeSource)
    curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg && \
    echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_24.x nodistro main" > /etc/apt/sources.list.d/nodesource.list

# Perform a single apt-get update and install all required packages
RUN wget -q -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb && \
    apt-get update && apt-get install -y --no-install-recommends \
    # Core dependencies
    git \
    sudo \
    python3 \
    libwayland-client0 \
    libwayland-egl1 \
    libwayland-cursor0 \
    xwayland \
    libnss3 \
    libatk1.0-0 \
    libatk-bridge2.0-0 \
    libdrm2 \
    libgtk-3-0 \
    libgbm1 \
    libasound2 \
    xdg-utils \
    dbus-x11 \
    xauth \
    # Custom repository packages
    antigravity \
    google-cloud-cli \
    cloudflared \
    gh \
    nodejs \
    # Multimedia tools
    ffmpeg \
    imagemagick \
    sox \
    libsox-fmt-all \
    # Chrome dependencies and Chrome itself
    fonts-liberation \
    /tmp/chrome.deb \
    # Cleanup
    && rm -rf /tmp/chrome.deb /var/lib/apt/lists/* \
    && dbus-uuidgen > /etc/machine-id

# Install Firebase CLI and Gemini CLI via NPM, then clean NPM cache
RUN npm install -g firebase-tools @google/gemini-cli && npm cache clean --force

# Relax ImageMagick security policy to allow the agent to freely manipulate all document/image types
RUN sed -i 's/rights="none" pattern="PDF"/rights="read|write" pattern="PDF"/g' /etc/ImageMagick-6/policy.xml

# Create a wrapper for Google Chrome to always run with --no-sandbox in the Docker environment.
# Using --disable-dev-shm-usage as a fallback for shared memory optimization.
RUN mv /usr/bin/google-chrome /usr/bin/google-chrome-original && \
    echo '#!/bin/bash' > /usr/bin/google-chrome && \
    echo 'exec /usr/bin/google-chrome-original --no-sandbox --disable-dev-shm-usage --disable-gpu "$@"' >> /usr/bin/google-chrome && \
    chmod +x /usr/bin/google-chrome

# Override xdg-open to intercept URLs (like login links) and print them to all active pseudo-terminals.
# This bypasses Electron's TTY detachment by broadcasting directly to the active session.
RUN mv /usr/bin/xdg-open /usr/bin/xdg-open-original && \
    echo '#!/bin/bash' > /usr/bin/xdg-open && \
    echo 'for term in /dev/pts/*; do' >> /usr/bin/xdg-open && \
    echo '  if [ -w "$term" ]; then' >> /usr/bin/xdg-open && \
    echo '    echo -e "\n============================================================" > "$term"' >> /usr/bin/xdg-open && \
    echo '    echo -e "🔗 ACTION REQUIRED: Please open this link in your host browser:" > "$term"' >> /usr/bin/xdg-open && \
    echo '    echo -e "$1" > "$term"' >> /usr/bin/xdg-open && \
    echo '    echo -e "============================================================\n" > "$term"' >> /usr/bin/xdg-open && \
    echo '  fi' >> /usr/bin/xdg-open && \
    echo 'done' >> /usr/bin/xdg-open && \
    echo 'exit 0' >> /usr/bin/xdg-open && \
    chmod +x /usr/bin/xdg-open
    
# Write a startup script that initializes an isolated DBus session,
# then keeps the container alive. This replaces the need to mount
# the host's session bus socket.
RUN echo '#!/bin/bash' > /usr/local/bin/entrypoint.sh && \
    echo '# Start an isolated D-Bus session daemon and export its address' >> /usr/local/bin/entrypoint.sh && \
    echo 'eval $(dbus-launch --sh-syntax)' >> /usr/local/bin/entrypoint.sh && \
    echo 'export DBUS_SESSION_BUS_ADDRESS' >> /usr/local/bin/entrypoint.sh && \
    echo '# Save the address so interactive exec sessions can find it' >> /usr/local/bin/entrypoint.sh && \
    echo 'echo "export DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS" > /run/user/$(id -u)/dbus-env.sh' >> /usr/local/bin/entrypoint.sh && \
    echo '# Hand off to whatever command was passed (or keep alive)' >> /usr/local/bin/entrypoint.sh && \
    echo 'exec "$@"' >> /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/entrypoint.sh

# Define arguments for user and group IDs to map host permissions
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USER_NAME=developer

# Create a non-root user matching the host UID/GID for GUI socket access.
# SECURITY WARNING: NOPASSWD:ALL allows the agent to execute any command as root.
# While typical for dev sandboxes to allow package installation, a compromised
# or rogue agent could cause damage. For stricter environments, limit sudo capabilities.
RUN groupadd -g ${GROUP_ID} ${USER_NAME} && \
    useradd -l -u ${USER_ID} -g ${USER_NAME} -m ${USER_NAME} && \
    usermod -aG sudo ${USER_NAME} && \
    echo "${USER_NAME} ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers && \
    # Create necessary configuration and runtime directories
    mkdir -p /home/${USER_NAME}/.config /home/${USER_NAME}/.antigravity /run/user/${USER_ID} && \
    # Change ownership to the user
    chown -R ${USER_NAME}:${USER_NAME} /home/${USER_NAME}/.config /home/${USER_NAME}/.antigravity /run/user/${USER_ID} && \
    # Set strict permissions for the XDG_RUNTIME_DIR as required by Linux security standards
    chmod 700 /run/user/${USER_ID}

# Set the working directory and switch user
WORKDIR /home/${USER_NAME}/workspace
USER ${USER_NAME}

# Add aliases and source DBus environment for interactive shell sessions
RUN echo 'alias antigravity="antigravity --no-sandbox --disable-gpu --ozone-platform-hint=auto --enable-features=WaylandWindowDecorations"' >> /home/${USER_NAME}/.bashrc && \
    echo 'source /run/user/$(id -u)/dbus-env.sh 2>/dev/null' >> /home/${USER_NAME}/.bashrc

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
EOF

# Ensure the .env file exists and populate it with required variables
if [ ! -f "$ENV_DIR/.env" ]; then
    echo "# Environment variables for your sandbox" > "$ENV_DIR/.env"
    echo "# GEMINI_API_KEY=your_api_key_here" >> "$ENV_DIR/.env"
fi

# Generate secure X11 authentication cookie
XAUTH_FILE="/tmp/.docker.xauth"
touch $XAUTH_FILE
xauth nlist $DISPLAY | sed -e 's/^..../ffff/' | xauth -f $XAUTH_FILE nmerge -

# Clean up any existing host variable entries and append the current ones
sed -i '/^HOST_UID=/d' "$ENV_DIR/.env"
sed -i '/^HOST_GID=/d' "$ENV_DIR/.env"
sed -i '/^HOST_USER=/d' "$ENV_DIR/.env"
sed -i '/^XAUTHORITY=/d' "$ENV_DIR/.env"
echo "HOST_UID=${HOST_UID}" >> "$ENV_DIR/.env"
echo "HOST_GID=${HOST_GID}" >> "$ENV_DIR/.env"
echo "HOST_USER=${HOST_USER}" >> "$ENV_DIR/.env"
echo "XAUTHORITY=${XAUTH_FILE}" >> "$ENV_DIR/.env"

# Dynamically configure Wayland mounts if the variable exists
WAYLAND_ENV_CONF=""
WAYLAND_VOL_CONF=""

if [ -n "$WAYLAND_DISPLAY" ]; then
    echo "Wayland session detected ($WAYLAND_DISPLAY). Configuring Wayland mounts..."
    WAYLAND_ENV_CONF="- WAYLAND_DISPLAY=\${WAYLAND_DISPLAY}"
    WAYLAND_VOL_CONF="- /run/user/\${HOST_UID}/\${WAYLAND_DISPLAY}:/run/user/\${HOST_UID}/\${WAYLAND_DISPLAY}"
else
    echo "Wayland not detected. Falling back to strict X11 configuration..."
fi

# Generate docker-compose.yml
cat << EOF > "docker-compose.yml"
# Docker Compose configuration for the Antigravity developer environment

services:
  ${PROJECT_NAME}-agent:
    build:
      context: .
      dockerfile: .env-config/Dockerfile
      args:
        # Pass dynamic host IDs
        USER_ID: \${HOST_UID}
        GROUP_ID: \${HOST_GID}
        USER_NAME: \${HOST_USER}
    image: antigravity-dev-slim:latest
    container_name: ${PROJECT_NAME}-agent
    network_mode: host
    restart: "no"
    init: true
    shm_size: '2gb'
    environment:
      # Inject necessary display variables
      - DISPLAY=\${DISPLAY}
      - XAUTHORITY=\${XAUTHORITY}
      - XDG_RUNTIME_DIR=/run/user/\${HOST_UID}
      ${WAYLAND_ENV_CONF}
    env_file:
      # Load API keys and other secrets from the .env file
      - .env-config/.env
    volumes:
      # Mount X11 socket (works for Xorg and XWayland)
      - /tmp/.X11-unix:/tmp/.X11-unix
      # Secure X11 authentication cookie
      - \${XAUTHORITY}:\${XAUTHORITY}:ro
      ${WAYLAND_VOL_CONF}
      # Mount the current project into the workspace directory
      - .:/home/${HOST_USER}/workspace
      # Mount ONLY the isolated gcloud configuration for this specific sandbox
      - .env-config/gcloud-isolated:/home/${HOST_USER}/.config/gcloud
      # Persist Antigravity IDE state (login, settings, extensions) inside the sandbox
      - .env-config/antigravity-data:/home/${HOST_USER}/.config/Antigravity
    # Keep the container running in the background
    command: tail -f /dev/null
EOF

# Generate workspace rules for the agent
cat << 'EOF' > .agentrules
# Agent Environment Context
You are operating inside a sandboxed Linux Docker container (Ubuntu 22.04). You have full CLI access and sudo privileges.

# Available CLI Tools
For multimedia processing use the following pre-installed command-line tools:

* ffmpeg2
* ImageMagick 6
* Sound eXchange

Double check what you are doing, whether it is correct and addresses the request.
EOF

# Update .gitignore to prevent committing sensitive sandbox data
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Updating .gitignore..."
    if [ ! -f ".gitignore" ]; then
        echo "# Ignore sandbox environment variables" > .gitignore
    fi
    
    # Append .env-config/.env if it's not already in the file
    if ! grep -q "^.env-config/\.env$" .gitignore; then
        echo ".env-config/.env" >> .gitignore
    fi
    
    # Append .env-config/ if it's not already in the file
    if ! grep -q "^.env-config/$" .gitignore && ! grep -q "^.env-config$" .gitignore; then
        echo ".env-config/" >> .gitignore
    fi

    # Append .agentrules if it's not already in the file
    if ! grep -q "^.agentrules$" .gitignore; then
        echo ".agentrules" >> .gitignore
    fi

    # append docker-compose.yml if it's not already in the file
    if ! grep -q "^docker-compose.*$" .gitignore; then
        echo "docker-compose.*" >> .gitignore
    fi
fi

# Automatically start the container in the background
echo "------------------------------------------------"
echo "Starting Docker Compose for project: $PROJECT_NAME..."
# Adding --build to force recreation of the image with the new configuration
docker compose up -d --build

echo "------------------------------------------------"
echo "Środowisko zostało pomyślnie wygenerowane i uruchomione!"
echo "Klucze dostępowe zostały zapisane w izolowanym katalogu .env-config/gcloud-isolated"
echo "Sekrety powiązane ze środowiskiem dodano do .gitignore"
echo "Możesz teraz wejść do środowiska wpisując: docker compose exec ${PROJECT_NAME}-agent bash"