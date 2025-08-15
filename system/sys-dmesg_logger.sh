#!/bin/bash

# This script collects various dmesg outputs to help diagnose kernel-related issues.
# It executes a series of 'dmesg' commands and logs their output to a dedicated file.
#
# Performed Tests and Information Gathered:
#
# 1. Command Availability Check:
#    - Verifies the presence of the 'dmesg' command.
#
# 2. dmesg Command Execution and Logging (Output saved to 'dmesg_user.log'):
#    - 'dmesg': Raw kernel messages.
#    - 'dmesg -r': Raw output, useful for debugging.
#    - 'dmesg -k': Kernel messages only.
#    - 'dmesg -u': Userspace messages only.
#    - 'dmesg -T': Displays human-readable timestamps.
#    - 'dmesg -x': Decodes facility and level to human-readable prefixes.
#    - 'dmesg -l err': Filters messages by error level.
#    - 'dmesg -l warn': Filters messages by warning level.
#
# A detailed log of the script's execution is saved to '_dmesg_logger.log'.

# --- Configuration ---
LOG_FILE="_dmesg_logger.log"
DMESG_OUTPUT_FILE="dmesg_user.log"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[0;37m'
NC='\033[0m' # No Color

# --- Global Variables ---
SPINNER_PID=""
CURRENT_ACTION=""

# --- Functions ---

# Function to log messages to the log file
log_message() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "$LOG_FILE"
}

# Function to display messages to the console with color
display_message() {
    local color="$1"
    local message="$2"
    echo -e "${color}${message}${NC}"
    log_message "DISPLAY: $message"
}

# Function to start the spinner
start_spinner() {
    CURRENT_ACTION="$1"
    # Start a subshell to run the spinner in the background
    (
        local delay=0.1
        local spinstr='|/-\'
        while true; do
            local temp=${spinstr#?}
            printf "\r ${CYAN}[%c]${NC}  ${YELLOW}%s${NC}\033[K" "$spinstr" "$CURRENT_ACTION"
            local spinstr=$temp${spinstr%"$temp"}
            sleep $delay
        done
    ) &
    SPINNER_PID=$!
    disown # Detach from the current shell
}

# Function to stop the spinner
stop_spinner() {
    if [ -n "$SPINNER_PID" ]; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null # Wait for the background process to terminate
        SPINNER_PID=""
        printf "\r\033[K" # Clear the line
    fi
}

# Function to check for required commands
check_commands() {
    display_message "$BLUE" "PHASE: Checking for required commands..."
    if ! command -v dmesg &> /dev/null; then
        display_message "$RED" "ERROR: 'dmesg' command not found. Please install it to proceed."
        log_message "ERROR: 'dmesg' command not found."
        exit 1
    fi
    display_message "$GREEN" "SUCCESS: All required commands found."
    log_message "SUCCESS: All required commands found."
}

# Function to execute dmesg commands and log them
execute_dmesg_commands() {
    display_message "$BLUE" "PHASE: Executing dmesg commands and logging output..."
    log_message "PHASE: Starting dmesg command execution."

    # Clear previous dmesg_user.log content
    > "$DMESG_OUTPUT_FILE"
    log_message "Cleared previous content of $DMESG_OUTPUT_FILE."

    local dmesg_commands=(
        "dmesg"
        "dmesg -r"
        "dmesg -k"
        "dmesg -u"
        "dmesg -T"
        "dmesg -x"
        "dmesg -l err"
        "dmesg -l warn"
    )

    start_spinner "Initializing..." # Start spinner once before the loop

    for cmd in "${dmesg_commands[@]}"; do
        CURRENT_ACTION="Running command: '$cmd'" # Update action message
        # start_spinner is called implicitly by the background subshell's loop
        log_message "Executing command: '$cmd'"

        printf "\n--- Output for: %s ---
" "$cmd" >> "$DMESG_OUTPUT_FILE"
        if output=$(eval "$cmd" 2>&1); then
            echo "$output" >> "$DMESG_OUTPUT_FILE"
            log_message "Successfully executed '$cmd'. Output appended to $DMESG_OUTPUT_FILE."
        else
            echo "Error executing '$cmd':" >> "$DMESG_OUTPUT_FILE"
            echo "$output" >> "$DMESG_OUTPUT_FILE"
            log_message "ERROR: Failed to execute '$cmd'. Error: $output"
            display_message "$RED" "WARNING: Failed to execute '$cmd'. Check $DMESG_OUTPUT_FILE for details."
        fi
        display_message "$GREEN" "Completed: '$cmd'"
    done

    stop_spinner # Stop spinner once after the loop

    display_message "$GREEN" "SUCCESS: All dmesg commands executed and logged to $DMESG_OUTPUT_FILE."
    log_message "SUCCESS: All dmesg commands executed and logged."
}


# --- Main Script Execution ---

display_message "$PURPLE" "Welcome to the dmesg Log Generator Script!"

# Initialize log file
echo "--- Script Start: $(date '+%Y-%m-%d %H:%M:%S') ---" > "$LOG_FILE"
log_message "Script started: dmesg_logger.sh"
display_message "$PURPLE" "This script will collect various dmesg outputs and save them to '$DMESG_OUTPUT_FILE'."
display_message "$PURPLE" "A detailed log of this script's execution will be saved to '$LOG_FILE'."

check_commands

display_message "$YELLOW" "Do you want to proceed? (yes/no): "
read -r user_response

if [[ "$user_response" =~ ^[Yy][Ee][Ss]$ ]]; then
    display_message "$GREEN" "Proceeding with dmesg log generation..."
    execute_dmesg_commands
    display_message "$GREEN" "Script finished successfully!"
    display_message "$GREEN" "You can find the dmesg output in: $(pwd)/$DMESG_OUTPUT_FILE"
    display_message "$GREEN" "And the script's execution log in: $(pwd)/$LOG_FILE"
    log_message "Script finished successfully."
else
    display_message "$RED" "Script aborted by user."
    log_message "Script aborted by user."
    exit 0
fi

log_message "--- Script End: $(date '+%Y-%m-%d %H:%M:%S') ---"
