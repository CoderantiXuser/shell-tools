#!/bin/bash

# This script is designed to diagnose and help resolve common display and login issues
# on Linux systems, particularly those related to the X server and window managers.
# It combines diagnostic checks with interactive repair options.
#
# Features:
#
# 1. Initial Setup:
#    - Verifies root privileges.
#
# 2. icewmbg Permissions Fix:
#    - Attempts to correct execute permissions for /usr/bin/icewmbg, a common fix for some login issues.
#
# 3. X Server Connection Diagnostics:
#    - Checks for running X server processes (Xorg, Xwayland).
#    - Analyzes Display Manager (e.g., LightDM, GDM) status.
#    - Inspects Xorg log files for errors and warnings.
#    - Reviews user-specific X session logs (~/.xsession-errors).
#    - Verifies critical file permissions related to X (e.g., /tmp/.X11-unix, ~/.Xauthority).
#    - Checks available disk space on the root filesystem.
#    - Examines relevant environment variables (e.g., DISPLAY).
#
# 4. Interactive xinitrc Configuration Fix:
#    - Displays the content of /etc/X11/xinit/xinitrc.
#    - Prompts the user to identify and comment out conflicting window manager entries.
#
# 5. Logging and Feedback:
#    - All actions and outputs are logged to a timestamped file in /tmp/.
#    - Provides real-time visual feedback using a spinner and colored messages.
#
# Usage:
#   Run this script with sudo privileges: sudo ./display_recovery.sh

# --- Configuration and Setup ---

# Color and Formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="/tmp/display_recovery_${TIMESTAMP}.log"

# Global Variables for Spinner
SPINNER_PID=""
CURRENT_ACTION=""

# --- Helper Functions ---

# Function to log messages to the log file (from sys_recovery2.sh)
log() {
    echo -e "$1" | tee -a "$LOG_FILE"
}

# Function to display messages to the console with color (adapted from _sys_recovery3.sh)
display_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log "DISPLAY: $message" # Log displayed messages
}

# Spinner function for visual feedback (from sys_recovery2.sh)
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-'
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\r ${CYAN}[%c]${NC}  ${YELLOW}%s${NC}" "$spinstr" "$CURRENT_ACTION"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\r\033[K" # Clear the line after spinner stops
}

# Dynamically updating status line (from sys_recovery2.sh)
update_status() {
    local message="$1"
    CURRENT_ACTION="$message" # Update global action for spinner
    printf "${CYAN}>>> %-70s${NC}" "$message"
}

# Function to run a command with a spinner and log its output (from sys_recovery2.sh)
run_command() {
    local description="$1"
    local command_to_run="$2"
    
    update_status "$description"
    
    # Execute command in the background to allow spinner to run
    ( # Subshell to capture output and exit code
        echo -e "\n--- Running: $description ---\n" >> "$LOG_FILE"
        eval "$command_to_run" >> "$LOG_FILE" 2>&1
    ) & # Run in background
    local pid=$!
    spinner $pid
    # Capture the exit code of the backgrounded command
    wait $pid
    local exit_code=$?
    
    # Clear the status line before printing success/failure
    printf "\r\033[K"

    # Check command exit status
    if [ $exit_code -eq 0 ]; then
        display_message "$GREEN" "✔ Success: $description"
    else
        display_message "$RED" "✖ Failed: $description (check $LOG_FILE for details)"
    fi
    return $exit_code
}

# --- Trap for cleanup on exit ---
cleanup() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null # Wait for the background process to terminate
        SPINNER_PID=""
        printf "\r\033[K" # Clear any lingering spinner
    fi
    log "Script finished or interrupted. Log saved to $LOG_FILE"
}
trap cleanup EXIT

# --- Diagnostic Phases (from sys_recovery2.sh) ---

check_xserver_process() {
    display_message "$YELLOW" "\n--- Phase: Checking for running X Server process ---"
    run_command "Searching for Xorg or Xwayland process..." "pgrep -afl Xorg || pgrep -afl Xwayland"
    if ! pgrep -af Xorg >/dev/null && ! pgrep -af Xwayland >/dev/null; then
        display_message "$YELLOW" "Warning: No running X server process found."
    else
        display_message "$GREEN" "Info: An X server process is running."
    fi
}

check_display_manager() {
    display_message "$YELLOW" "\n--- Phase: Checking Display Manager status ---"
    local dms=("lightdm" "gdm" "sddm" "lxdm" "xdm")
    local found_dm=false
    for dm in "${dms[@]}"; do
        if systemctl list-units --type=service --all | grep -q "${dm}.service"; then
            run_command "Checking status of ${dm}.service..." "systemctl status ${dm}.service --no-pager"
            found_dm=true
            break
        fi
    done
    if [ "$found_dm" = false ]; then
        display_message "$YELLOW" "Warning: Could not identify a common display manager service."
    fi
}

check_xorg_logs() {
    display_message "$YELLOW" "\n--- Phase: Analyzing Xorg log files ---"
    local xorg_log="/var/log/Xorg.0.log"
    if [ -f "$xorg_log" ]; then
        run_command "Checking for errors (EE) in $xorg_log..." "grep --color=always '(EE)' $xorg_log"
        run_command "Checking for warnings (WW) in $xorg_log..." "grep --color=always '(WW)' $xorg_log"
    else
        display_message "$RED" "Error: $xorg_log not found."
    fi
}

check_user_x_logs() {
    display_message "$YELLOW" "\n--- Phase: Analyzing user-specific X session logs ---"
    local user_log="$HOME/.xsession-errors"
    if [ -f "$user_log" ]; then
        run_command "Checking for recent errors in $user_log..." "tail -n 50 $user_log"
    else
        display_message "$YELLOW" "Info: $user_log not found."
    fi
}

check_permissions() {
    display_message "$YELLOW" "\n--- Phase: Verifying file permissions ---"
    run_command "Checking permissions for /tmp/.X11-unix..." "ls -ld /tmp/.X11-unix"
    if [ -f "$HOME/.Xauthority" ]; then
        run_command "Checking ownership of ~/.Xauthority..." "ls -l $HOME/.Xauthority"
    else
        display_message "$YELLOW" "Info: ~/.Xauthority does not exist."
    fi
}

check_disk_space() {
    display_message "$YELLOW" "\n--- Phase: Checking available disk space ---"
    run_command "Checking filesystem disk space usage..." "df -h /"
    local free_space=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
    if [ "$free_space" -gt 95 ]; then
        display_message "$RED" "Critical: Root filesystem is nearly full! (${free_space}% used). This can prevent X from starting."
    fi
}

check_env_variables() {
    display_message "$YELLOW" "\n--- Phase: Checking environment variables ---"
    run_command "Checking DISPLAY variable..." "echo \$DISPLAY"
    if [ -z "$DISPLAY" ]; then
        display_message "$YELLOW" "Warning: DISPLAY environment variable is not set."
    else
        display_message "$GREEN" "Info: DISPLAY is set to: $DISPLAY"
    fi
}

# --- Main Execution ---

main() {
    clear
    log "${MAGENTA}=====================================================${NC}"
    log "${MAGENTA}  Display and Login Recovery Script                  ${NC}"
    log "${MAGENTA}=====================================================${NC}"
    log "This script will perform a series of checks and offer repairs to diagnose common display and login issues."
    log "A detailed log will be saved to: ${BLUE}${LOG_FILE}${NC}"
    
    # 1. Initial Setup (Root Check)
    display_message "$BLUE" "\n--- Initial Setup: Checking for root privileges ---"
    if [[ $EUID -ne 0 ]]; then
        display_message "$RED" "Error: This script must be run as root. Please run with sudo."
        exit 1
    else
        display_message "$GREEN" "Root privileges confirmed."
    fi

    read -p "Press [Enter] to begin the analysis and repair process..."

    # 2. Phase 1: Fix icewmbg Permissions (from _sys_recovery3.sh)
    display_message "$BLUE" "\n--- Phase: Correcting icewmbg permissions ---"
    display_message "$MAGENTA" "This script will run 'sudo chmod +x /usr/bin/icewmbg'."
    display_message "$MAGENTA" "You may be prompted for your password."
    run_command "Correcting permissions for /usr/bin/icewmbg" "chmod +x /usr/bin/icewmbg"

    # 3. Phase 2: X Server Connection Diagnostics (from sys_recovery2.sh)
    check_xserver_process
    check_display_manager
    check_xorg_logs
    check_user_x_logs
    check_permissions
    check_disk_space
    check_env_variables

    # 4. Phase 3: Interactive xinitrc Configuration Fix (from _sys_recovery3.sh)
    display_message "$BLUE" "\n--- Phase: Checking for conflicting window managers in xinitrc ---"
    display_message "$YELLOW" "The contents of /etc/X11/xinit/xinitrc will be displayed."
    display_message "$YELLOW" "Look for lines that start a window manager (e.g., 'exec fluxbox')."
    echo ""
    sleep 2

    if [ -f /etc/X11/xinit/xinitrc ]; then
        nl /etc/X11/xinit/xinitrc
        echo ""
        display_message "$MAGENTA" "Enter the line number of the conflicting window manager to comment out."
        display_message "$MAGENTA" "If you don't see a conflict, just press Enter to skip."
        read -p "> " line_number

        if [[ ! -z "$line_number" && "$line_number" =~ ^[0-9]+$ ]]; then
            display_message "$BLUE" "Backing up /etc/X11/xinit/xinitrc to /etc/X11/xinit/xinitrc.bak"
            run_command "Backing up xinitrc" "cp /etc/X11/xinit/xinitrc /etc/X11/xinit/xinitrc.bak"

            display_message "$BLUE" "Commenting out line $line_number in /etc/X11/xinit/xinitrc..."
            run_command "Commenting out line $line_number" "sed -i \"${line_number}s/^/#/\" /etc/X11/xinit/xinitrc"
        else
            display_message "$YELLOW" "Skipping modification of /etc/X11/xinit/xinitrc."
        fi
    else
        display_message "$RED" "Error: /etc/X11/xinit/xinitrc not found."
    fi

    # 5. Final Summary
    display_message "$GREEN" "\n====================================================="
    display_message "$GREEN" "  Analysis and Repair Complete.                      "
    display_message "$GREEN" "====================================================="
    display_message "$GREEN" "Please review the output above. For full details, check the log file:"
    display_message "$BLUE" "$LOG_FILE"
    display_message "$GREEN" "It is recommended to reboot your system to apply changes and re-test."
}

# Run the script
main
