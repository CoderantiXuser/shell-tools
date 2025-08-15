#!/usr/bin/env bash

# This script is designed to analyze and repair common issues in Linux APT repository configurations.
# It performs a series of checks to identify problems and offers automated repair options.
#
# Performed Checks and Actions:
#
# 1. Initial Checks:
#    - Verifies if the script is run with root privileges.
#
# 2. Backup Creation:
#    - Creates a timestamped backup of `/etc/apt/sources.list` and `/etc/apt/sources.list.d/`.
#
# 3. Repository Analysis (`analyze_repos` function):
#    - Duplicate Entries Check: Scans for and reports any duplicate repository entries.
#    - Invalid Repositories Check: Attempts to validate each repository by performing a simulated update.
#    - Mixed Release Repositories Check: Identifies if repositories from different distribution releases are configured.
#    - Missing GPG Keys Check: Detects and reports missing GPG public keys required for repository authentication.
#
# 4. Repair Actions (Interactive or Non-Interactive):
#    - Remove Duplicates: Consolidates and reorganizes repository entries to eliminate duplicates.
#    - Fix Invalid Repositories: Attempts common fixes for invalid repositories (e.g., changing http to https, adjusting mirror URLs).
#    - Add Missing GPG Keys: Fetches and adds missing GPG keys from public key servers.
#
# 5. Final Verification:
#    - Runs a final `apt-get update` to confirm the repository configuration is functional after repairs.
#
# All actions and their outcomes are logged to a file in `/var/log/`.

# Color definitions
RED='\033[1;31m'
GREEN='\033[1;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
NC='\033[0m' # No Color

# Log file
LOG_FILE="/var/log/repo_repair_$(date +%Y%m%d_%H%M%S).log"
touch "$LOG_FILE"

# Spinner function
spinner() {
    local pid=$1
    local msg=$2
    local delay=0.15
    local spinstr='|/-\'

    printf "${CYAN}${msg}... ${NC}"
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "[%c] " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b"
    done
    printf "\b\b\b\b"
}

# Function for colored logging
log() {
    local color=$1
    local message=$2
    local log_level=$3
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [$log_level] $message${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$log_level] $message" >> "$LOG_FILE"
}

# Header
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Repository Configuration Repair Script    ${NC}"
echo -e "${CYAN}============================================${NC}"
log $BLUE "Script started" "INFO"
log $BLUE "Log file: $LOG_FILE" "INFO"

# Check root privileges
if [[ $EUID -ne 0 ]]; then
    log $RED "This script must be run as root" "ERROR"
    exit 1
fi

# Backup original files
backup_files() {
    log $YELLOW "Creating backups..." "BACKUP"
    local timestamp=$(date +%Y%m%d_%H%M%S)

    (mkdir -p "/etc/apt/backups_$timestamp" &&
     cp -v /etc/apt/sources.list "/etc/apt/backups_$timestamp/sources.list.bak" &&
     if [ -d "/etc/apt/sources.list.d" ]; then
         cp -rv /etc/apt/sources.list.d "/etc/apt/backups_$timestamp/"
     fi) >> "$LOG_FILE" 2>&1 &

    spinner $! "Creating backups"
    echo ""

    log $GREEN "Backups created in /etc/apt/backups_$timestamp" "BACKUP"
}

# Analyze current state
analyze_repos() {
    log $YELLOW "Analyzing current repository configuration..." "ANALYSIS"

    # Check for duplicate entries
    (duplicates=$(grep -rhE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | sort | uniq -d)) &
    spinner $! "Checking for duplicate entries"
    echo ""

    if [ -n "$duplicates" ]; then
        log $RED "Found duplicate repository entries:" "ANALYSIS"
        echo "$duplicates" | while read -r line; do
            log $RED "$line" "ANALYSIS"
        done
    else
        log $GREEN "No duplicate entries found" "ANALYSIS"
    fi

    # Check for invalid repositories
    (invalid_repos=0
    while read -r repo; do
        if ! apt-get update -o Dir::Etc::sourcelist="$repo" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" &>/dev/null; then
            ((invalid_repos++))
        fi
    done < <(grep -rlE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/)) &
    spinner $! "Checking for invalid repositories"
    echo ""

    if [ $invalid_repos -eq 0 ]; then
        log $GREEN "No invalid repositories found" "ANALYSIS"
    else
        log $RED "Found $invalid_repos invalid repositories" "ANALYSIS"
    fi

    # Check for mixed release repositories
    (releases=$(grep -rhE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | awk '{print $3}' | sort | uniq)) &
    spinner $! "Checking for mixed releases"
    echo ""

    if [ $(echo "$releases" | wc -l) -gt 1 ]; then
        log $YELLOW "Multiple distribution releases detected:" "ANALYSIS"
        echo "$releases" | while read -r rel; do
            log $YELLOW "$rel" "ANALYSIS"
        done
    else
        log $GREEN "Consistent distribution release: $releases" "ANALYSIS"
    fi

    # Check for missing GPG keys
    (missing_keys=$(apt-get update 2>&1 | grep 'NO_PUBKEY' | awk '{print $NF}' | sort | uniq)) &
    spinner $! "Checking for missing GPG keys"
    echo ""

    if [ -n "$missing_keys" ]; then
        log $RED "Missing GPG keys detected:" "ANALYSIS"
        echo "$missing_keys" | while read -r key; do
            log $RED "$key" "ANALYSIS"
        done
    else
        log $GREEN "No missing GPG keys found" "ANALYSIS"
    fi
}

# Repair functions
remove_duplicates() {
    log $YELLOW "Removing duplicate entries..." "REPAIR"

    (grep -rhE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | sort -u > /tmp/unique_repos.list &&
     > /etc/apt/sources.list &&
     if [ -d "/etc/apt/sources.list.d" ]; then
         rm -f /etc/apt/sources.list.d/*.list
     else
         mkdir -p /etc/apt/sources.list.d
     fi &&
     local main_repo="/etc/apt/sources.list"
     local other_count=0
     while read -r line; do
         if [[ $line == *"main"* ]] && [ $(wc -l < "$main_repo") -eq 0 ]; then
             echo "$line" >> "$main_repo"
         else
             let other_count++
             echo "$line" > "/etc/apt/sources.list.d/repo_${other_count}.list"
         fi
     done < /tmp/unique_repos.list) >> "$LOG_FILE" 2>&1 &

    spinner $! "Removing duplicates"
    echo ""

    log $GREEN "Duplicates removed and repositories reorganized" "REPAIR"
}

fix_invalid_repos() {
    log $YELLOW "Attempting to fix invalid repositories..." "REPAIR"

    (grep -rlE '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | while read -r repo; do
        if ! apt-get update -o Dir::Etc::sourcelist="$repo" -o Dir::Etc::sourceparts="-" -o APT::Get::List-Cleanup="0" &>/dev/null; then
            sed -i 's/http:/https:/g' "$repo"
            sed -i 's/ftp:/https:/g' "$repo"
            sed -i 's/archive.ubuntu.com/deb.debian.org/g' "$repo"
            sed -i 's/security.ubuntu.com/security.debian.org/g' "$repo"
        fi
    done) >> "$LOG_FILE" 2>&1 &

    spinner $! "Fixing invalid repositories"
    echo ""

    log $GREEN "Invalid repository fixes attempted" "REPAIR"
}

add_missing_keys() {
    log $YELLOW "Adding missing GPG keys..." "REPAIR"
    local keys_added=0

    (apt-get update 2>&1 | grep 'NO_PUBKEY' | awk '{print $NF}' | sort | uniq | while read -r key; do
        if apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$key" >> "$LOG_FILE" 2>&1; then
            ((keys_added++))
        else
            apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys "$key" >> "$LOG_FILE" 2>&1 && ((keys_added++))
        fi
    done) &

    spinner $! "Adding missing GPG keys"
    echo ""

    log $GREEN "Added $keys_added missing GPG keys" "REPAIR"
}

# Main execution
INTERACTIVE="true"

if [[ $1 == "--non-interactive" ]]; then
    INTERACTIVE="false"
    log $BLUE "Running in non-interactive mode" "INFO"
fi

# Start the process
backup_files
analyze_repos

if [[ $INTERACTIVE == "true" ]]; then
    read -p "Do you want to proceed with repairs? [Y/n] " choice
    if [[ $choice =~ ^[Nn] ]]; then
        log $BLUE "Aborting as requested by user" "INFO"
        exit 0
    fi
fi

remove_duplicates
fix_invalid_repos
add_missing_keys

# Final update check
log $YELLOW "Running final update check..." "VERIFICATION"
(apt-get update >> "$LOG_FILE" 2>&1) &
spinner $! "Running final update check"
echo ""

if [ $? -eq 0 ]; then
    log $GREEN "Repository configuration successfully repaired!" "SUCCESS"
else
    log $RED "Some issues remain. Please check the log file: $LOG_FILE" "WARNING"
fi

log $BLUE "Script completed" "INFO"
echo -e "${CYAN}============================================${NC}"
echo -e "${CYAN}  Repair process complete                   ${NC}"
echo -e "${CYAN}  Detailed log available at: $LOG_FILE     ${NC}"
echo -e "${CYAN}============================================${NC}"

exit 0