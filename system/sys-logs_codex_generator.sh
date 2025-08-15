#!/bin/bash

# This script is designed to collect, organize, and optionally compress system log files.
# It creates a structured directory containing copies of relevant logs and a codex file listing their original paths.
#
# Performed Actions:
#
# 1. Initial Setup:
#    - Verifies if the script is run with root privileges (required to access system logs).
#
# 2. Phase 1: Identify Log Files:
#    - Searches for common system-related log files within `/var/log`.
#    - Excludes known binary logs (e.g., wtmp, btmp, lastlog) and journald directories.
#
# 3. Phase 2: Create Output Directories:
#    - Creates a dedicated output directory (`_sys_logs_codex`) and a subdirectory (`codex`) within it.
#
# 4. Phase 3: Create Codex File:
#    - Generates a `codex.txt` file inside the output directory.
#    - This file lists the original absolute paths of all identified log files.
#
# 5. Phase 4: Copy Log Files:
#    - Prompts the user for confirmation before proceeding with copying.
#    - Copies the identified log files into the `codex` subdirectory.
#    - Dereferences symbolic links and preserves file permissions/timestamps during copying.
#    - Sets read/write/execute permissions (777) for the `codex` directory and its contents.
#
# 6. Extension: Offer to Compress:
#    - Prompts the user for confirmation to compress the copied logs.
#    - If confirmed, creates a `tar.gz` archive of the `codex` directory contents.
#
# 7. Summary:
#    - Provides a final summary of the operation, including counts of files found, successfully copied, and failed to copy.
#
# All script activities and progress are logged to a file named `_sys_logs_codex_generator.log`.

# --- Configuration ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
OUTPUT_DIR="${SCRIPT_DIR}/_sys_logs_codex"
CODEX_DIR="${OUTPUT_DIR}/codex"
CODEX_FILE="${OUTPUT_DIR}/codex.txt"
LOG_FILE="${SCRIPT_DIR}/_${SCRIPT_NAME%.*}.log" # e.g., _sys_logs_codex_generator.log

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging Function ---
log_message() {
    local color=$1
    local message=$2
    local timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo -e "${color}[${timestamp}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# --- Spinner Function ---
spinner_pid=""
_spinner_chars='|/-\'
_spinner_idx=0

start_spinner() {
    printf "  " # Initial space for spinner
    while true; do
        printf "\b\b[%c] " "${_spinner_chars: _spinner_idx++:1}"
        _spinner_idx=$((_spinner_idx % ${#_spinner_chars}))
        sleep 0.1
    done &
    spinner_pid=$!
}

stop_spinner() {
    if [ -n "$spinner_pid" ]; then
        kill "$spinner_pid" &> /dev/null
        printf "\b\b\b\b" # Clear spinner
        spinner_pid=""
    fi
}

# --- Trap for cleanup on exit ---
cleanup() {
    stop_spinner
    log_message "$YELLOW" "Script interrupted or finished. Cleaning up..."
    log_message "$YELLOW" "Cleanup complete."
}
trap cleanup EXIT

# --- Main Script Logic ---

log_message "$BLUE" "--- Starting System Log Codex Generator ---"
log_message "$BLUE" "Log file for this run: $LOG_FILE"

# 1. Root Check
printf "${YELLOW}Checking for root privileges...${NC}"
if [[ $EUID -ne 0 ]]; then
   printf "\r${RED}Error: This script must be run as root to access system log files. Please run with sudo.${NC}\n"
   log_message "$RED" "Script terminated: Insufficient privileges."
   exit 1
fi
printf "\r${GREEN}Root privileges confirmed.${NC}\n"
log_message "$GREEN" "Root privileges confirmed."

# 2. Phase 1: Identify Log Files
log_message "$BLUE" "Phase 1: Identifying system-related log files..."
printf "${YELLOW}  Searching for log files...${NC}"
start_spinner

# Find common log files, excluding known binary logs and journald directories
# Using -print0 and xargs for robustness with filenames containing spaces/newlines
# Filtering out common binary log files and journal directories by name/path
readarray -t LOG_FILES < <(find /var/log -type f \
    ! -path "/var/log/journal/*" \
    ! -path "/var/log/private/*" \
    ! -name "wtmp" \
    ! -name "btmp" \
    ! -name "lastlog" \
    2>/dev/null | grep -E '\.(log|txt|gz|[0-9])$|^syslog$|^auth\.log$|^kern\.log$|^dmesg$|^boot\.log$|^Xorg\.0\.log$|^messages$|^daemon\.log$|^user\.log$|^cron\.log$|^mail\.log$' \
    || true) # Allow grep to fail if no matches

stop_spinner
NUM_FOUND=${#LOG_FILES[@]}
log_message "$GREEN" "  Found $NUM_FOUND potential system log files."
if [ "$NUM_FOUND" -eq 0 ]; then
    log_message "$YELLOW" "  No system log files found matching common patterns. Exiting."
    exit 0
fi

# 3. Phase 2: Create Output Directories
log_message "$BLUE" "Phase 2: Creating output directories..."
printf "${YELLOW}  Creating directories...${NC}"
start_spinner

mkdir -p "$CODEX_DIR"
if [ $? -eq 0 ]; then
    log_message "$GREEN" "  Output directory created: $OUTPUT_DIR"
    log_message "$GREEN" "  Codex directory created: $CODEX_DIR"
else
    stop_spinner
    log_message "$RED" "  Error: Failed to create output directories. Exiting."
    exit 1
fi
stop_spinner

# 4. Phase 3: Create Codex File
log_message "$BLUE" "Phase 3: Creating codex.txt with log file paths..."
printf "${YELLOW}  Writing log file list...${NC}"
start_spinner

# Write the list of found log files to codex.txt
printf "%s\n" "${LOG_FILES[@]}" > "$CODEX_FILE"
if [ $? -eq 0 ]; then
    log_message "$GREEN" "  Codex file created: $CODEX_FILE"
    log_message "$GREEN" "  It contains a list of $NUM_FOUND log file paths."
else
    stop_spinner
    log_message "$RED" "  Error: Failed to create codex.txt. Exiting."
    exit 1
fi
stop_spinner

# 5. Phase 4: Copy Log Files
log_message "$BLUE" "Phase 4: Copying log files to codex directory..."

if [ "$NUM_FOUND" -gt 0 ]; then
    log_message "$YELLOW" "  About to copy $NUM_FOUND log files. This might take some time depending on file sizes."
    read -p "$(echo -e "${YELLOW}  Do you want to proceed with copying? (y/N): ${NC}")" -n 1 -r
    echo # Move to a new line
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message "$YELLOW" "  Copy operation cancelled by user."
        exit 0
    fi

    COPIED_COUNT=0
    FAILED_COUNT=0
    for (( i=0; i<${#LOG_FILES[@]}; i++ )); do
        FILE_PATH="${LOG_FILES[$i]}"
        FILE_NAME=$(basename "$FILE_PATH")
        printf "\r${YELLOW}  Copying file %d of %d: %s${NC}" $((i+1)) "$NUM_FOUND" "$FILE_NAME"
        start_spinner # Start spinner for each file copy

        # Use -L to dereference symbolic links, -p to preserve permissions/timestamps
        cp -Lp "$FILE_PATH" "$CODEX_DIR/" 2>/dev/null
        if [ $? -eq 0 ]; then
            ((COPIED_COUNT++))
        else
            ((FAILED_COUNT++))
            log_message "$RED" "    Failed to copy: $FILE_PATH"
        fi
        stop_spinner # Stop spinner after each file copy
    done
    printf "\r${GREEN}  Copying complete.                                       ${NC}\n" # Clear the line
    log_message "$GREEN" "  Successfully copied $COPIED_COUNT files."
    if [ "$FAILED_COUNT" -gt 0 ]; then
        log_message "$RED" "  Failed to copy $FAILED_COUNT files (check log for details)."
    fi

    # Set permissions for the codex directory and its contents
    log_message "$BLUE" "  Setting permissions for '$CODEX_DIR' and its contents..."
    printf "${YELLOW}  Applying permissions...${NC}"
    start_spinner
    chmod -R 777 "$CODEX_DIR"
    if [ $? -eq 0 ]; then
        stop_spinner
        log_message "$GREEN" "  Permissions set to 777 for '$CODEX_DIR' and all files within."
    else
        stop_spinner
        log_message "$RED" "  Error: Failed to set permissions for '$CODEX_DIR'."
    fi
else
    log_message "$YELLOW" "  No log files to copy."
fi

# 6. Extension: Offer to compress
log_message "$BLUE" "Extension: Offering to compress copied logs..."
if [ "$COPIED_COUNT" -gt 0 ]; then
    read -p "$(echo -e "${YELLOW}  Do you want to compress the copied logs in '$CODEX_DIR'? (y/N): ${NC}")" -n 1 -r
    echo # Move to a new line
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        printf "${YELLOW}  Compressing logs...${NC}"
        start_spinner
        tar -czf "${OUTPUT_DIR}/codex_logs_$(date +%Y%m%d_%H%M%S).tar.gz" -C "$CODEX_DIR" . 2>/dev/null
        if [ $? -eq 0 ]; then
            stop_spinner
            log_message "$GREEN" "  Logs compressed successfully to ${OUTPUT_DIR}/codex_logs_*.tar.gz"
        else
            stop_spinner
            log_message "$RED" "  Failed to compress logs."
        fi
    else
        log_message "$YELLOW" "  Compression skipped by user."
    fi
else
    log_message "$YELLOW" "  No files copied, skipping compression offer."
fi

# --- Summary ---
log_message "$BLUE" "--- Script Finished ---"
log_message "$BLUE" "Summary:"
log_message "$BLUE" "  Output directory: $OUTPUT_DIR"
log_message "$BLUE" "  Codex file: $CODEX_FILE"
log_message "$BLUE" "  Copied logs to: $CODEX_DIR"
log_message "$BLUE" "  Total files found: $NUM_FOUND"
log_message "$BLUE" "  Files successfully copied: $COPIED_COUNT"
log_message "$BLUE" "  Files failed to copy: $FAILED_COUNT"
log_message "$BLUE" "  Detailed log available at: $LOG_FILE"

exit 0
