#!/bin/bash

# RAM-Based Application Sandbox Launcher - Enhanced Version
# Usage: ./run_ram.sh -e <executable_name>
# Example: ./run_ram.sh -e brave-browser-stable

set -euo pipefail

# Configuration
RAM_MOUNT="/mnt/ram_app"
MOUNT_SIZE="2G"
LOG_FILE="/tmp/ram_app_$(date +%Y%m%d_%H%M%S).log"

# Initialize logging
exec > >(tee -a "$LOG_FILE") 2>&1

# Functions
log() {
    echo -e "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error() {
    log "[ERROR] $1" >&2
    exit 1
}

cleanup() {
    if mountpoint -q "$RAM_MOUNT"; then
        log "Unmounting RAM disk at $RAM_MOUNT"
        sudo umount "$RAM_MOUNT" || error "Failed to unmount RAM disk"
    fi
    [ -d "$RAM_MOUNT" ] && sudo rmdir "$RAM_MOUNT"
}

# Parse arguments
while getopts ":e:" opt; do
    case $opt in
        e) EXECUTABLE="$OPTARG" ;;
        \?) error "Invalid option -$OPTARG" ;;
    esac
done

[ -z "${EXECUTABLE:-}" ] && error "Usage: $0 -e <executable_name>"

# Step 1: Identify the application
log "=== Starting RAM Sandbox Setup for $EXECUTABLE ==="
log "Phase 1: Locating application and dependencies"

APP_PATH=$(which "$EXECUTABLE" 2>/dev/null || true)
[ -z "$APP_PATH" ] && error "Application $EXECUTABLE not found in PATH"

APP_DIR=$(dirname "$APP_PATH")
APP_NAME=$(basename "$APP_PATH")
log "Found $APP_NAME at $APP_PATH"

# Step 2: Find dependencies
log "Gathering dependencies using ldd..."
DEPS=$(ldd "$APP_PATH" 2>/dev/null | awk 'NF == 4 {print $3}; NF == 2 {print $1}' | grep -v "linux-vdso.so\|ld-linux-x86-64.so" || true)
log "Dependencies found:\n$DEPS"

# Step 3: Find configuration files
log "Looking for configuration files..."
CONFIG_DIRS=(
    "$HOME/.config/${APP_NAME%-*}"  # Remove suffix (e.g., -stable)
    "$HOME/.config/$APP_NAME"
    "$HOME/.${APP_NAME%-*}"
    "$HOME/.$APP_NAME"
    "$HOME/.cache/${APP_NAME%-*}"
    "$HOME/.cache/$APP_NAME"
    "/etc/${APP_NAME%-*}"
    "/etc/$APP_NAME"
)
CONFIG_PATHS=()
for dir in "${CONFIG_DIRS[@]}"; do
    [ -d "$dir" ] && CONFIG_PATHS+=("$dir")
done
log "Configuration locations found:\n${CONFIG_PATHS[*]:-None found}"

# Step 4: Setup RAM disk
log "\nPhase 2: Setting up RAM disk"
sudo mkdir -p "$RAM_MOUNT" || error "Failed to create mount directory"
log "Created mount point at $RAM_MOUNT"

sudo mount -t tmpfs -o "size=$MOUNT_SIZE,mode=0755" tmpfs "$RAM_MOUNT" || error "Failed to mount tmpfs"
log "Mounted $MOUNT_SIZE tmpfs at $RAM_MOUNT"

# Change ownership to current user
sudo chown "$USER:$USER" "$RAM_MOUNT"

trap cleanup EXIT

# Step 5: Copy application files
log "\nPhase 3: Copying files to RAM"
log "Copying application binary..."
mkdir -p "$RAM_MOUNT/bin"
cp "$APP_PATH" "$RAM_MOUNT/bin/$APP_NAME"

log "Copying application directory..."
APP_BASE_DIR=$(dirname "$APP_DIR")
mkdir -p "$RAM_MOUNT$APP_BASE_DIR"
cp -r "$APP_DIR" "$RAM_MOUNT$APP_BASE_DIR/"

log "Copying dependencies..."
mkdir -p "$RAM_MOUNT/lib64" "$RAM_MOUNT/lib/x86_64-linux-gnu"
for dep in $DEPS; do
    if [ -f "$dep" ]; then
        mkdir -p "$RAM_MOUNT$(dirname "$dep")"
        cp "$dep" "$RAM_MOUNT$dep"
    fi
done

log "Copying configuration files..."
for config in "${CONFIG_PATHS[@]}"; do
    mkdir -p "$RAM_MOUNT$(dirname "$config")"
    cp -r "$config" "$RAM_MOUNT$(dirname "$config")/"
done

# Step 6: Prepare environment
log "\nPhase 4: Preparing execution environment"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:$RAM_MOUNT/lib64:$RAM_MOUNT/lib/x86_64-linux-gnu"
export PATH="$RAM_MOUNT/bin:$PATH"

# Step 7: Run in Firejail
log "\nPhase 5: Launching application in RAM sandbox"

# Create a custom Firejail profile if needed
FIREJAIL_PROFILE="$HOME/.config/firejail/$APP_NAME.profile"
if [ ! -f "$FIREJAIL_PROFILE" ]; then
    mkdir -p "$(dirname "$FIREJAIL_PROFILE")"
    cat > "$FIREJAIL_PROFILE" <<EOF
include /etc/firejail/default.profile
private-dev
private-tmp
netfilter
no3d
nodvd
nogroups
nonewprivs
noroot
notv
novideo
protocol unix,inet,inet6
seccomp
shell none
tracelog
whitelist $RAM_MOUNT
EOF
fi

if command -v firejail >/dev/null; then
    log "Command: firejail --private=$RAM_MOUNT --profile=$FIREJAIL_PROFILE $RAM_MOUNT/bin/$APP_NAME"
    firejail --private="$RAM_MOUNT" --profile="$FIREJAIL_PROFILE" "$RAM_MOUNT/bin/$APP_NAME"
else
    log "Warning: Firejail not found, running without sandboxing"
    "$RAM_MOUNT/bin/$APP_NAME"
fi

log "\n=== Execution complete ==="