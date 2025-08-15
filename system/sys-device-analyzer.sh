#!/bin/bash

# --- Configuration ---
SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
LOG_FILE="${SCRIPT_DIR}/_${SCRIPT_NAME%.*}.log"

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

log_message "$BLUE" "--- Starting System Device Analysis Script ---"
log_message "$BLUE" "Log file for this run: $LOG_FILE"

# 1. Root Check
printf "${YELLOW}Checking for root privileges...${NC}"
if [[ $EUID -ne 0 ]]; then
   printf "\r${RED}Error: This script must be run as root to gather comprehensive device information. Please run with sudo.${NC}\n"
   log_message "$RED" "Script terminated: Insufficient privileges."
   exit 1
fi
printf "\r${GREEN}Root privileges confirmed.${NC}\n"
log_message "$GREEN" "Root privileges confirmed."

# 2. Phase 1: Gather System Device Information
log_message "$BLUE" "\nPhase 1: Gathering comprehensive system device information..."

printf "${YELLOW}  Collecting general system information (uname, lscpu, free, df)...${NC}"
start_spinner
log_message "$GREEN" "\n--- General System Information ---"
log_message "$NC" "$(uname -a)"
log_message "$NC" "$(lscpu)"
log_message "$NC" "$(free -h)"
log_message "$NC" "$(df -h)"
stop_spinner
log_message "$GREEN" "  General system information collected."

printf "${YELLOW}  Collecting detailed hardware information (lshw)...${NC}"
start_spinner
log_message "$GREEN" "\n--- Detailed Hardware Information (lshw) ---"
log_message "$NC" "$(lshw)"
stop_spinner
log_message "$GREEN" "  Detailed hardware information collected."

printf "${YELLOW}  Collecting PCI device information (lspci)...${NC}"
start_spinner
log_message "$GREEN" "\n--- PCI Devices (lspci -v) ---"
log_message "$NC" "$(lspci -v)"
log_message "$GREEN" "\n--- PCI Devices with Kernel Modules (lspci -k) ---"
log_message "$NC" "$(lspci -k)"
stop_spinner
log_message "$GREEN" "  PCI device information collected."

printf "${YELLOW}  Collecting USB device information (lsusb)...${NC}"
start_spinner
log_message "$GREEN" "\n--- USB Devices (lsusb -v) ---"
log_message "$NC" "$(lsusb -v)"
log_message "$GREEN" "\n--- USB Devices with Kernel Modules (lsusb -k) ---"
log_message "$NC" "$(lsusb -k)"
stop_spinner
log_message "$GREEN" "  USB device information collected."

printf "${YELLOW}  Collecting DMI/BIOS information (dmidecode)...${NC}"
start_spinner
log_message "$GREEN" "\n--- DMI/BIOS Information (dmidecode) ---"
log_message "$NC" "$(dmidecode)"
stop_spinner
log_message "$GREEN" "  DMI/BIOS information collected."

# 3. Phase 2: Driver Verification
log_message "$BLUE" "\nPhase 2: Verifying driver installation and checking for errors..."

printf "${YELLOW}  Searching kernel logs (dmesg) for driver-related errors...${NC}"
start_spinner
log_message "$GREEN" "\n--- Kernel Log (dmesg) for Driver Errors ---"
DMESG_ERRORS=$(dmesg | grep -Ei 'firmware|error|fail|driver|module')
if [ -n "$DMESG_ERRORS" ]; then
    log_message "$RED" "  Potential driver-related errors found in dmesg:"
    log_message "$NC" "$DMESG_ERRORS"
else
    log_message "$GREEN" "  No obvious driver-related errors found in dmesg."
fi
stop_spinner
log_message "$GREEN" "  Kernel log analysis complete."

printf "${YELLOW}  Listing loaded kernel modules (lsmod)...${NC}"
start_spinner
log_message "$GREEN" "\n--- Loaded Kernel Modules (lsmod) ---"
log_message "$NC" "$(lsmod)"
stop_spinner
log_message "$GREEN" "  Loaded kernel modules listed."

log_message "$BLUE" "\n--- Script Finished ---"
log_message "$BLUE" "Summary:"
log_message "$BLUE" "  Comprehensive device information and driver status collected."
log_message "$BLUE" "  Review the log file for detailed output: $LOG_FILE"

exit 0
