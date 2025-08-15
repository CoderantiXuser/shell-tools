#!/bin/bash

# Docblock: This script performs a comprehensive diagnostic of Bluetooth and Audio setup on a Linux system.
# It aims to identify potential issues, verify configurations, and provide a detailed report for troubleshooting or blueprinting.
#
# Usage Examples:
#   ./bt_check_v3.sh                    # Standard diagnostic
#   ./bt_check_v3.sh -d                 # Enable debug output
#   ./bt_check_v3.sh -v                 # Enable verbose output
#   ./bt_check_v3.sh -q                 # Quiet mode (errors only)
#   ./bt_check_v3.sh -o report.log      # Custom output file
#   ./bt_check_v3.sh -h                 # Show help
#   sudo ./bt_check_v3.sh -d -v         # Full privileges with debug+verbose
#
# Checks performed include:
# - [1] SYSTEM OVERVIEW: Basic system information (OS, Kernel, Hostname, User, Uptime, Memory).
# - [2] KERNEL MODULES: Verifies loaded Bluetooth-related kernel modules and checks for blacklisted modules.
# - [3] UDEV RULES: Inspects custom udev rules that might affect Bluetooth devices.
# - [4] POWER MANAGEMENT: Checks for power-saving features impacting Bluetooth, including TLP and USB autosuspend.
# - [5] BLUETOOTH SERVICE STATUS: Verifies the status of the Bluetooth service (systemd, SysVinit/Upstart) and `bluetoothd` process.
# - [6] INSTALLED BLUETOOTH PACKAGES: Lists installed Bluetooth-related packages and identifies missing recommended ones based on package manager.
# - [7] BLUETOOTH HARDWARE DETECTION: Detects USB and PCI Bluetooth devices, checks RFKill status (soft/hard blocked), and HCI configuration.
# - [8] BLUETOOTH ADAPTER CAPABILITIES: Provides detailed information about the Bluetooth controller's capabilities using `btmgmt` and `hcitool`.
# - [9] BLUETOOTH PROFILES & CODECS: Attempts to infer supported audio profiles (A2DP, HFP) and codecs via PulseAudio/PipeWire and BlueZ config.
# - [10] POTENTIAL SERVICE CONFLICTS: Identifies running processes that might conflict with Bluetooth (e.g., `connman`, `NetworkManager`).
# - [11] PULSEAUDIO/PIPEWIRE CONFIGURATION: Checks default audio sinks/sources, module loading, and user permissions for audio groups.
# - [12] ALSA CONFIGURATION: Lists ALSA sound cards and checks for custom ALSA configurations (`/etc/asound.conf`, `~/.asoundrc`).
# - [13] NETWORK MANAGER INTERACTION: Checks NetworkManager's status and its interaction with Bluetooth devices.
# - [14] FIREWALL RULES: Inspects firewall configurations (UFW/firewalld) for Bluetooth-related rules.
# - [15] SYSTEM LOGS (BLUETOOTH): Greps recent system logs (`syslog`, `journalctl`, `dmesg`) for Bluetooth-related messages.
# - [16] BLUETOOTH DAEMON LOGS: Checks for verbose logging settings for the BlueZ daemon in `main.conf`.
# - [17] BLUETOOTHCTL INTERACTIVE STATUS: Provides a snapshot of `bluetoothctl`'s current state (controller info, paired/connected devices, agent status).
# - [18] AUTO-START CONFIGURATIONS: Examines common autostart locations (`rc.local`, `~/.profile`, `~/.bashrc`, GUI autostart directories) for Bluetooth entries.
# - [19] DIAGNOSTIC SUMMARY: Provides a summary of potential issues found and suggests actions to resolve them, along with general troubleshooting steps.
#
# Enhanced Bluetooth & Audio Diagnostic Script
# Version 3.0 - Merged and Improved

#--- Robust header added by assistant: make script fault-tolerant ---#
# - keep undefined-variable checks, but avoid immediate exit on any command failure
# - provide helpers to check for required commands and run commands safely
set -uo pipefail


# Helper: print messages to stderr
_warn() { printf "%s\n" "$*" >&2; }
_info() { printf "%s\n" "$*"; }

# Check if a command exists (returns 0 if exists)
require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    _warn "WARNING: required command '$1' not found in PATH. The script will continue but features using it will be disabled."
    return 1
  fi
  return 0
}

# Safe executor: runs a command if it exists; returns 0 if skipped or successful
safe_run() {
  if command -v "$1" >/dev/null 2>&1; then
    "$@"
    return $?
  else
    _warn "SKIPPED: command '$1' not found; skipping: $*"
    return 0
  fi
}

# Trap to show where errors happen (does NOT exit)
_error_trace() {
  local rc=$?
  _warn "Notice: command failed with exit code $rc at line ${BASH_LINENO[0]} (in ${BASH_SOURCE[1]})"
  return $rc
}
trap _error_trace ERR
#--- end header ---
  # Exit on error, undefined vars, pipe failures
IFS=$'\n\t'       # Secure Internal Field Separator

# Global configuration
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="3.0"
readonly DEFAULT_REPORT_FILE="/tmp/bluetooth_audio_diagnostic_$(date +%Y%m%d_%H%M%S).log"

# Default settings - can be overridden by flags
DEBUG_MODE=false
VERBOSE_MODE=false
QUIET_MODE=false
REPORT_FILE="$DEFAULT_REPORT_FILE"
TIMEOUT_DEFAULT=30
NO_COLOR=false

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_CRITICAL_ISSUES=1
readonly EXIT_WARNINGS_ONLY=2
readonly EXIT_INVALID_ARGS=3

# Counters
ISSUES_FOUND=0
WARNINGS_FOUND=0

# Color codes (will be disabled if NO_COLOR=true or non-terminal)
if [[ -t 2 && "$NO_COLOR" != "true" ]]; then
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[1;33m'
    readonly GREEN='\033[0;32m'
    readonly BLUE='\033[0;34m'
    readonly CYAN='\033[0;36m'
    readonly NC='\033[0m' # No Color
else
    readonly RED=''
    readonly YELLOW=''
    readonly GREEN=''
    readonly BLUE=''
    readonly CYAN=''
    readonly NC=''
fi

# Temporary directory for safe cleanup
TEMP_DIR=""

# Show help
show_help() {
    cat << EOF
$SCRIPT_NAME v$SCRIPT_VERSION - Comprehensive Bluetooth & Audio Diagnostic Tool

USAGE:
    $SCRIPT_NAME [OPTIONS]

OPTIONS:
    -d, --debug         Enable debug output (shows command execution details)
    -v, --verbose       Enable verbose output (more detailed information)
    -q, --quiet         Quiet mode (only show errors and critical issues)
    -o, --output FILE   Specify custom output file (default: auto-generated in /tmp)
    -t, --timeout SEC   Set command timeout in seconds (default: $TIMEOUT_DEFAULT)
    -n, --no-color      Disable colored output
    -h, --help          Show this help message

EXAMPLES:
    $SCRIPT_NAME                          # Standard diagnostic
    $SCRIPT_NAME -d                       # With debug information
    $SCRIPT_NAME -v -o ~/bt_report.log    # Verbose with custom output
    sudo $SCRIPT_NAME -d -v               # Full privileges with maximum detail

EXIT CODES:
    0 - No issues found
    1 - Critical issues found
    2 - Only warnings found
    3 - Invalid arguments

NOTES:
    - Run with sudo for complete hardware and system diagnostics
    - Report file location is always shown at the end
    - Use -d flag to see why commands might be failing
EOF
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--debug)
                DEBUG_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -q|--quiet)
                QUIET_MODE=true
                shift
                ;;
            -o|--output)
                if [[ -n "$2" && "$2" != -* ]]; then
                    REPORT_FILE="$2"
                    shift 2
                else
                    echo "Error: --output requires a filename argument" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                ;;
            -t|--timeout)
                if [[ -n "$2" && "$2" =~ ^[0-9]+$ ]]; then
                    TIMEOUT_DEFAULT="$2"
                    shift 2
                else
                    echo "Error: --timeout requires a numeric argument" >&2
                    exit $EXIT_INVALID_ARGS
                fi
                ;;
            -n|--no-color)
                NO_COLOR=true
                shift
                ;;
            -h|--help)
                show_help
                exit $EXIT_SUCCESS
                ;;
            *)
                echo "Error: Unknown option '$1'" >&2
                echo "Use '$SCRIPT_NAME --help' for usage information." >&2
                exit $EXIT_INVALID_ARGS
                ;;
        esac
    done

    # Validate conflicting options
    if [[ "$QUIET_MODE" == "true" && ("$DEBUG_MODE" == "true" || "$VERBOSE_MODE" == "true") ]]; then
        echo "Warning: Quiet mode overrides debug and verbose modes" >&2
        DEBUG_MODE=false
        VERBOSE_MODE=false
    fi
}

# Improved logging functions with proper levels and formatting
log_debug() {
    [[ "$DEBUG_MODE" == "true" ]] || return 0
    echo -e "${BLUE}[DEBUG]${NC} $*" >&2
}

log_info() {
    [[ "$QUIET_MODE" == "true" ]] && return 0
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_verbose() {
    [[ "$VERBOSE_MODE" == "true" || "$DEBUG_MODE" == "true" ]] || return 0
    [[ "$QUIET_MODE" == "true" ]] && return 0
    echo -e "${CYAN}[VERBOSE]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
    ((WARNINGS_FOUND++))
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
    ((ISSUES_FOUND++))
}

# Enhanced safe command execution
safe_exec() {
    local cmd="$1"
    local timeout_val="${2:-$TIMEOUT_DEFAULT}"
    local ignore_errors="${3:-false}"
    local description="${4:-$cmd}"
    
    log_debug "Executing: $description (timeout: ${timeout_val}s)"
    
    local temp_file="$TEMP_DIR/cmd_output_$$_$(date +%s)"
    local exit_code=0
    
    # Execute command with timeout
    if timeout "$timeout_val" bash -c "$cmd" >"$temp_file" 2>&1; then
        cat "$temp_file"
        exit_code=0
    else
        exit_code=$?
        if [[ "$ignore_errors" != "true" ]]; then
            log_warn "Command failed: $description (exit code: $exit_code)"
            if [[ "$DEBUG_MODE" == "true" && -f "$temp_file" ]]; then
                echo "Command output:" >&2
                head -10 "$temp_file" >&2
            fi
        fi
    fi
    
    [[ -f "$temp_file" ]] && rm -f "$temp_file"
    return $exit_code
}

# Setup and cleanup functions
setup_environment() {
    # Create temporary directory
    TEMP_DIR="$(mktemp -d)"
    if [[ ! -d "$TEMP_DIR" ]]; then
        log_error "Failed to create temporary directory"
        exit $EXIT_CRITICAL_ISSUES
    fi
    
    # Set restrictive permissions on temp dir
    chmod 700 "$TEMP_DIR"
    
    # Verify report file can be created
    if ! touch "$REPORT_FILE" 2>/dev/null; then
        log_error "Cannot create report file: $REPORT_FILE"
        exit $EXIT_CRITICAL_ISSUES
    fi
    
    log_verbose "Environment setup complete"
    log_verbose "Temporary directory: $TEMP_DIR"
    log_verbose "Report file: $REPORT_FILE"
}

cleanup() {
    local exit_code=$?
    
    log_debug "Cleaning up (exit code: $exit_code)"
    
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
        log_debug "Removed temporary directory: $TEMP_DIR"
    fi
    
    exit $exit_code
}

# Set up signal handlers and error handling
setup_error_handling() {
    set -uo pipefail
    IFS=$'\n\t'
    trap cleanup EXIT INT TERM
}

# Enhanced tool checking
check_tool() {
    local tool="$1"
    local required="${2:-false}"
    
    if command -v "$tool" >/dev/null 2>&1; then
        local tool_path=$(command -v "$tool")
        log_debug "Tool '$tool' found at $tool_path"
        
        if [[ "$VERBOSE_MODE" == "true" && "$tool" != "echo" ]]; then
            local version_info=""
            case "$tool" in
                bluetoothctl|hciconfig|hcitool)
                    version_info="$($tool --version 2>/dev/null | head -1 || echo 'version unknown')"
                    ;;
                systemctl)
                    version_info="$(systemctl --version 2>/dev/null | head -1 || echo 'version unknown')"
                    ;;
                *)
                    # For other tools, try common version flags
                    version_info="$($tool --version 2>/dev/null | head -1 || $tool -v 2>/dev/null | head -1 || $tool -V 2>/dev/null | head -1 || echo 'version unknown')"
                    ;;
            esac
            [[ -n "$version_info" ]] && log_verbose "$tool: $version_info"
        fi
        return 0
    else
        if [[ "$required" == "true" ]]; then
            log_error "Required tool '$tool' not found"
            return 1
        else
            log_warn "Optional tool '$tool' not found - some checks may be limited"
            return 1
        fi
    fi
}

# System detection functions
detect_init_system() {
    if [[ -d /run/systemd/system ]] || [[ -f /sbin/init && "$(readlink -f /sbin/init 2>/dev/null)" == */systemd ]]; then
        echo "systemd"
    elif [[ -d /etc/init ]]; then
        echo "upstart"
    else
        echo "sysv"
    fi
}

detect_package_manager() {
    local managers=("apt" "yum" "dnf" "zypper" "pacman" "emerge" "apk")
    
    for manager in "${managers[@]}"; do
        if command -v "$manager" >/dev/null 2>&1; then
            echo "$manager"
            return 0
        fi
    done
    
    log_warn "No recognized package manager found"
    echo "unknown"
    return 1
}

# Enhanced header function
header() {
    local title="$1"
    local timestamp=$(date '+%H:%M:%S')
    local separator=$(printf '=%.0s' $(seq 1 ${#title}))
    
    {
        echo
        echo "[$timestamp] $title"
        echo "$separator"
    } | tee -a "$REPORT_FILE"
    
    log_verbose "Starting section: $title"
}

# Initialize report
init_report() {
    local start_time=$(date)
    local user_info="$(whoami) (UID: $(id -u))"
    local privilege_status="NO"
    [[ $EUID -eq 0 ]] && privilege_status="YES"
    
    cat > "$REPORT_FILE" << EOF
Bluetooth & Audio Diagnostic Report (Enhanced)
==============================================
Script Version: $SCRIPT_VERSION
Generated: $start_time
Hostname: $(hostname -f 2>/dev/null || hostname)
User: $user_info
Root Privileges: $privilege_status
Init System: $(detect_init_system)
Package Manager: $(detect_package_manager)

Command Line Options:
  Debug Mode: $DEBUG_MODE
  Verbose Mode: $VERBOSE_MODE
  Quiet Mode: $QUIET_MODE
  Timeout: ${TIMEOUT_DEFAULT}s

===============================================
EOF
}

# --- Diagnostic Check Functions ---

check_system_overview() {
    header "[1] SYSTEM OVERVIEW"
    
    {
        echo "Operating System: $(
            if [[ -f /etc/os-release ]]; then
                source /etc/os-release && echo "${PRETTY_NAME:-$ID}"
            elif command -v lsb_release >/dev/null 2>&1; then
                lsb_release -d 2>/dev/null | cut -f2 || echo "Unknown"
            else
                echo "Unknown"
            fi
        )"
        echo "Kernel Version: $(uname -r)"
        echo "Architecture: $(uname -m)"
        echo "Hostname: $(hostname -f 2>/dev/null || hostname)"
        echo "Current User: $(whoami) (UID: $(id -u))"
        echo "Load Average: $(cat /proc/loadavg 2>/dev/null || echo "N/A")"
        echo "Uptime: $(uptime -p 2>/dev/null || uptime | cut -d, -f1)"
        
        if [[ $EUID -eq 0 ]]; then
            echo "Running with root privileges: YES"
        else
            echo "Running with root privileges: NO (some checks may be limited)"
            log_warn "Script not running as root - some system checks may be incomplete"
        fi
        
        # Memory info for context
        if [[ -f /proc/meminfo ]]; then
            local mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            local mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            echo "Memory: $(( mem_total / 1024 ))MB total, $(( mem_available / 1024 ))MB available"
        fi
        
    } | tee -a "$REPORT_FILE"
}

check_kernel_modules() {
    header "[2] KERNEL MODULES"
    
    {
        echo "Bluetooth-related kernel modules status:"
        
        if ! check_tool lsmod; then
            log_error "lsmod command not available - cannot check kernel modules"
            echo "ERROR: Cannot check kernel modules"
            # return 1
        fi
        
        local bt_modules=(
            "bluetooth:Core Bluetooth support"
            "btusb:USB Bluetooth driver"
            "btrtl:Realtek Bluetooth driver" 
            "btintel:Intel Bluetooth driver"
            "btbcm:Broadcom Bluetooth driver"
            "btmtk:MediaTek Bluetooth driver"
            "bnep:Bluetooth Network Encapsulation Protocol"
            "rfcomm:RFCOMM protocol support"
            "hci_uart:HCI UART driver"
        )
        
        local lsmod_output modules_loaded=0
        lsmod_output=$(lsmod 2>/dev/null) || {
            log_error "Failed to get module list"
            return 1
        }
        
        for module_info in "${bt_modules[@]}"; do
            local module="${module_info%%:*}"
            local description="${module_info#*:}"
            
            if echo "$lsmod_output" | grep -q "^$module "; then
                local module_line=$(echo "$lsmod_output" | grep "^$module " || true)
                echo "✓ $module_line  # $description"
                ((modules_loaded++))
            else
                log_verbose "Module '$module' not loaded ($description)"
            fi
        done
        
        if [[ $modules_loaded -eq 0 ]]; then
            log_error "No Bluetooth kernel modules found loaded"
            echo "ERROR: No Bluetooth kernel modules detected"
        else
            echo
            echo "Summary: $modules_loaded Bluetooth-related modules loaded"
        fi
        
        # Check for blacklisted modules
        echo
        echo "Checking for blacklisted Bluetooth modules:"
        local blacklist_found=false
        
        for conf_file in /etc/modprobe.d/*.conf; do
            [[ -f "$conf_file" ]] || continue
            if grep -q "blacklist.*\(bluetooth\|btusb\|btrtl\|btintel\|btbcm\|btmtk\)" "$conf_file" 2>/dev/null; then
                echo "Found blacklist configuration in $(basename "$conf_file"):"
                grep -n "blacklist.*\(bluetooth\|btusb\|btrtl\|btintel\|btbcm\|btmtk\)" "$conf_file" 2>/dev/null || true
                blacklist_found=true
                log_warn "Bluetooth modules are blacklisted in $conf_file"
            fi
        done
        
        if [[ "$blacklist_found" == "false" ]]; then
            echo "No blacklisted Bluetooth modules found"
        fi
        
    }
}

check_udev_rules() {
    header "[3] UDEV RULES"
    
    {
        echo "Custom udev rules affecting Bluetooth:"
        local rules_found=false
        
        for rules_dir in /etc/udev/rules.d /usr/lib/udev/rules.d /lib/udev/rules.d; do
            [[ -d "$rules_dir" ]] || continue
            
            while IFS= read -r -d '' rule_file; do
                if [[ -f "$rule_file" ]] && grep -l -i bluetooth "$rule_file" >/dev/null 2>&1; then
                    echo "Found Bluetooth rules in $(basename "$rule_file"):"
                    grep -n -i bluetooth "$rule_file" | head -10
                    rules_found=true
                fi
            done < <(find "$rules_dir" -name "*.rules" -print0 2>/dev/null || true)
        done
        
        if [[ "$rules_found" == "false" ]]; then
            echo "No custom Bluetooth udev rules found"
        fi
    } | tee -a "$REPORT_FILE"
}

check_power_management() {
    header "[4] POWER MANAGEMENT"
    
    {
        # Check TLP
        if check_tool tlp-stat; then
            echo "TLP Power Management Status:"
            safe_exec "tlp-stat -b" 10 true "tlp-stat -b" | head -20
        else
            echo "TLP not installed/configured"
        fi
        
        echo
        echo "USB Power Management (autosuspend settings):"
        for usb_device in /sys/bus/usb/devices/*/; do
            [[ -d "$usb_device" ]] || continue
            local vendor_file="$usb_device/idVendor"
            local product_file="$usb_device/idProduct"
            local power_file="$usb_device/power/control"
            
            if [[ -f "$vendor_file" && -f "$product_file" ]]; then
                local vendor=$(cat "$vendor_file" 2>/dev/null)
                local product=$(cat "$product_file" 2>/dev/null)
                
                # Check for common Bluetooth vendor IDs
                if [[ "$vendor" =~ ^(8087|0a5c|413c|0cf3|04ca)$ ]]; then
                    local control_setting="N/A"
                    [[ -f "$power_file" ]] && control_setting=$(cat "$power_file" 2>/dev/null || echo "N/A")
                    echo "  USB Device $vendor:$product - Power Control: $control_setting"
                    
                    if [[ "$control_setting" == "auto" ]]; then
                        log_warn "USB Bluetooth device has autosuspend enabled - may cause connectivity issues"
                    fi
                fi
            fi
        done
        
        echo
        echo "Bluetooth adapter power settings:"
        local adapters_found=false
        for adapter in /sys/class/bluetooth/hci*; do
            if [[ -d "$adapter" ]]; then
                local adapter_name=$(basename "$adapter")
                local power_control="$adapter/power/control"
                local power_setting="N/A"
                
                [[ -f "$power_control" ]] && power_setting=$(cat "$power_control" 2>/dev/null || echo "N/A")
                echo "  $adapter_name: Power Control = $power_setting"
                adapters_found=true
                
                if [[ "$power_setting" == "auto" ]]; then
                    log_warn "Bluetooth adapter $adapter_name has power management enabled"
                fi
            fi
        done
        
        if [[ "$adapters_found" == "false" ]]; then
            echo "No Bluetooth adapters found in /sys/class/bluetooth/"
            log_error "No Bluetooth adapters detected in sysfs"
        fi
    } | tee -a "$REPORT_FILE"
}

check_bluetooth_service_status() { # Renamed from check_bluetooth_service to avoid conflict
    header "[5] BLUETOOTH SERVICE STATUS"
    
    local init_system=$(detect_init_system)
    
    {
        echo "Detected init system: $init_system"
        echo
        
        case "$init_system" in
            "systemd")
                if check_tool systemctl; then
                    echo "Systemd service status:"
                    safe_exec "systemctl status bluetooth.service" 10 true "systemctl status bluetooth.service"
                    echo
                    echo "Service enabled status:"
                    if systemctl is-enabled bluetooth.service >/dev/null 2>&1; then
                        echo "bluetooth.service is enabled"
                    else
                        log_warn "bluetooth.service is not enabled for auto-start"
                        echo "bluetooth.service is NOT enabled"
                    fi
                    
                    echo
                    echo "Service active status:"
                    if systemctl is-active bluetooth.service >/dev/null 2>&1; then
                        echo "bluetooth.service is active"
                    else
                        log_error "bluetooth.service is not active"
                        echo "bluetooth.service is NOT active"
                    fi
                fi
                ;;
            "sysv"|"upstart")
                if [[ -f /etc/init.d/bluetooth ]]; then
                    echo "SysV/Upstart init script found: /etc/init.d/bluetooth"
                    echo "Runlevel links:"
                    ls -la /etc/rc*.d/*bluetooth* 2>/dev/null || echo "No runlevel links found"
                    
                    echo
                    if check_tool service; then
                        echo "Service status:"
                        safe_exec "service bluetooth status" 10 true "service bluetooth status"
                    fi
                else
                    log_error "No Bluetooth init script found"
                    echo "No Bluetooth init script found"
                fi
                ;;
        esac
        
        # Check if bluetoothd process is running
        echo
        echo "Bluetooth daemon process status:"
        if pgrep -f bluetoothd >/dev/null; then
            echo "bluetoothd is running (PID: $(pgrep -f bluetoothd | tr '\n' ' '))"
        else
            log_error "bluetoothd process is not running"
            echo "bluetoothd is NOT running"
        fi
    } | tee -a "$REPORT_FILE"
}

check_bluetooth_packages() {
    header "[6] INSTALLED BLUETOOTH PACKAGES"
    
    local pkg_manager=$(detect_package_manager 2>/dev/null || echo "unknown")
    
    {
        echo "Package manager: $pkg_manager"
        echo
        
        case "$pkg_manager" in
            "apt")
                echo "Installed Bluetooth packages (dpkg):"
                dpkg -l 2>/dev/null | grep -E 'bluetooth|bluez|pulseaudio.*bluetooth|pipewire.*bluetooth' | grep '^ii' || echo "No Bluetooth packages found"
                
                echo
                echo "Package status check:"
                local essential_packages=("bluez" "bluetooth")
                local audio_packages=("pulseaudio-module-bluetooth" "pipewire-bluetooth" "bluez-alsa-utils")
                local tool_packages=("bluez-tools" "blueman")
                
                for pkg in "${essential_packages[@]}"; do
                    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
                        echo "✓ $pkg: installed"
                    else
                        log_error "Essential package '$pkg' is not installed"
                        echo "✗ $pkg: NOT installed (essential)"
                    fi
                done
                
                local audio_pkg_found=false
                for pkg in "${audio_packages[@]}"; do
                    if dpkg -l "$pkg" 2>/dev/null | grep -q '^ii'; then
                        echo "✓ $pkg: installed"
                        audio_pkg_found=true
                    fi
                done
                
                if [[ "$audio_pkg_found" == "false" ]]; then
                    log_warn "No Bluetooth audio packages found - audio functionality may be limited"
                    echo "⚠ No Bluetooth audio support packages installed"
                fi
                ;;
            "yum"|"dnf")
                echo "Installed Bluetooth packages (rpm):"
                rpm -qa 2>/dev/null | grep -E 'bluetooth|bluez|pulseaudio.*bluetooth|pipewire.*bluetooth' || echo "No Bluetooth packages found"
                
                echo
                echo "Package status check:"
                local essential_packages=("bluez" "bluetooth")
                local audio_packages=("pulseaudio-module-bluetooth" "pipewire-bluetooth" "bluez-alsa-utils")
                local tool_packages=("bluez-tools" "blueman")
                
                for pkg in "${essential_packages[@]}"; do
                    if rpm -q "$pkg" >/dev/null 2>&1; then
                        echo "✓ $pkg: installed"
                    else
                        log_error "Essential package '$pkg' is not installed"
                        echo "✗ $pkg: NOT installed (essential)"
                    fi
                done
                
                local audio_pkg_found=false
                for pkg in "${audio_packages[@]}"; do
                    if rpm -q "$pkg" >/dev/null 2>&1; then
                        echo "✓ $pkg: installed"
                        audio_pkg_found=true
                    fi
                    
                done
                
                if [[ "$audio_pkg_found" == "false" ]]; then
                    log_warn "No Bluetooth audio packages found - audio functionality may be limited"
                    echo "⚠ No Bluetooth audio support packages installed"
                fi
                ;;
            "pacman")
                echo "Installed Bluetooth packages (pacman):"
                pacman -Q 2>/dev/null | grep -E 'bluetooth|bluez|pulseaudio.*bluetooth|pipewire.*bluetooth' || echo "No Bluetooth packages found"
                
                echo
                echo "Package status check:"
                local essential_packages=("bluez" "bluez-utils") # bluez-utils for bluetoothctl
                local audio_packages=("pulseaudio-bluetooth" "pipewire-pulse" "pipewire-alsa" "pipewire-jack") # Common Arch audio packages
                
                for pkg in "${essential_packages[@]}"; do
                    if pacman -Q "$pkg" >/dev/null 2>&1; then
                        echo "✓ $pkg: installed"
                    else
                        log_error "Essential package '$pkg' is not installed"
                        echo "✗ $pkg: NOT installed (essential)"
                    fi
                done
                
                local audio_pkg_found=false
                for pkg in "${audio_packages[@]}"; do
                    if pacman -Q "$pkg" >/dev/null 2>&1; then
                        echo "✓ $pkg: installed"
                        audio_pkg_found=true
                    fi
                done
                
                if [[ "$audio_pkg_found" == "false" ]]; then
                    log_warn "No Bluetooth audio packages found - audio functionality may be limited"
                    echo "⚠ No Bluetooth audio support packages installed"
                fi
                ;;
            *)
                log_warn "Unknown package manager - cannot verify package installation"
                echo "Cannot check package status with unknown package manager"
                ;;
        esac
    } | tee -a "$REPORT_FILE"
}

check_bluetooth_hardware() {
    header "[7] BLUETOOTH HARDWARE DETECTION"
    
    {
        echo "Hardware Detection:"
        
        # USB Bluetooth devices
        echo "USB Bluetooth devices:"
        if check_tool lsusb; then
            local usb_bt_found=false
            while IFS= read -r line; do
                echo "  $line"
                usb_bt_found=true
            done < <(lsusb 2>/dev/null | grep -i bluetooth || true)
            
            if [[ "$usb_bt_found" == "false" ]]; then
                echo "  No USB Bluetooth devices found"
            fi
        else
            echo "  lsusb not available"
        fi
        
        # PCI Bluetooth devices
        echo
        echo "PCI Bluetooth devices:"
        if check_tool lspci; then
            local pci_bt_found=false
            while IFS= read -r line; do
                echo "  $line"
                pci_bt_found=true
            done < <(lspci 2>/dev/null | grep -i bluetooth || true)
            
            if [[ "$pci_bt_found" == "false" ]]; then
                echo "  No PCI Bluetooth devices found"
            fi
        else
            echo "  lspci not available"
        fi
        
        # RFKill status
        echo
        echo "RF Kill Status:"
        if check_tool rfkill; then
            rfkill list all 2>/dev/null | grep -A3 -B1 -i bluetooth || echo "No Bluetooth devices in rfkill"
            
            # Check for blocked devices
            if rfkill list bluetooth 2>/dev/null | grep -q "Soft blocked: yes"; then
                log_error "Bluetooth is soft-blocked by rfkill"
                echo "ERROR: Bluetooth is soft-blocked - run 'rfkill unblock bluetooth'"
            fi
            
            if rfkill list bluetooth 2>/dev/null | grep -q "Hard blocked: yes"; then
                log_error "Bluetooth is hard-blocked (hardware switch)"
                echo "ERROR: Bluetooth is hard-blocked - check hardware switch"
            fi
        else
            echo "  rfkill not available"
        fi
        
        # HCI Configuration
        echo
        echo "HCI Configuration:"
        if check_tool hciconfig; then
            if hciconfig 2>/dev/null | grep -q "hci"; then
                hciconfig -a 2>/dev/null || echo "hciconfig failed"
            else
                log_error "No HCI devices found"
                echo "No HCI devices detected"
            fi
        else
            echo "  hciconfig not available"
        fi
        
        # Check for firmware issues
        echo
        echo "Firmware and Driver Status:"
        if [[ -d /sys/class/bluetooth ]]; then
            local hci_count=$(find /sys/class/bluetooth -name "hci*" -type d | wc -l)
            echo "HCI interfaces found: $hci_count"
            
            if [[ $hci_count -eq 0 ]]; then
                log_error "No HCI interfaces found - driver or firmware issue likely"
            fi
        fi
    } | tee -a "$REPORT_FILE"
}

check_adapter_capabilities() {
    header "[8] BLUETOOTH ADAPTER CAPABILITIES"
    
    {
        if check_tool btmgmt; then
            echo "Bluetooth Management Interface (btmgmt info):"
            safe_exec "btmgmt info" 15 true "btmgmt info"
            
            echo
            echo "Available Controllers (btmgmt list):"
            safe_exec "btmgmt list" 10 true "btmgmt list"
        else
            echo "btmgmt not available - install bluez-tools for detailed adapter info"
            log_warn "btmgmt tool not available"
        fi
        
        # Alternative: use hcitool if available
        if check_tool hcitool; then
            echo
            echo "HCI Device Information (via hcitool dev):"
            safe_exec "hcitool dev" 10 true "hcitool dev"
        fi
    } | tee -a "$REPORT_FILE"
}

check_bluetooth_profiles_codecs() {
    header "[9] BLUETOOTH PROFILES & CODECS"
    echo "Attempting to infer supported audio profiles and codecs:" | tee -a "$REPORT_FILE"
    
    {
        local audio_system="unknown"
        if pgrep -f pipewire >/dev/null; then
            audio_system="pipewire"
        elif pgrep -f pulseaudio >/dev/null; then
            audio_system="pulseaudio"
        fi
        
        echo "Detected audio system: $audio_system"
        
        if [[ "$audio_system" == "pulseaudio" ]]; then
            if check_tool pactl;
            then
                echo -e "\nPulseAudio Bluetooth Sinks (A2DP/HFP):"
                safe_exec "pactl list sinks short | grep -i bluetooth" 5 true "pactl list sinks short (Bluetooth)" || echo "No Bluetooth sinks found."
                echo -e "\nPulseAudio Bluetooth Sources (HFP/HSP):"
                safe_exec "pactl list sources short | grep -i bluetooth" 5 true "pactl list sources short (Bluetooth)" || echo "No Bluetooth sources found."
                echo -e "\nPulseAudio Bluetooth Modules:"
                safe_exec "pactl list modules short | grep -E 'bluetooth|a2dp|hfp'" 5 true "pactl list modules short (Bluetooth)" || echo "No Bluetooth modules loaded."
            else
                echo "pactl not found. Cannot check PulseAudio profiles."
            fi
        elif [[ "$audio_system" == "pipewire" ]]; then
            if check_tool wpctl;
            then
                echo -e "\nPipeWire Bluetooth Sinks/Sources:"
                safe_exec "wpctl status | grep -E 'Bluetooth|A2DP|HFP'" 5 true "wpctl status (Bluetooth)" || echo "No Bluetooth devices found."
            else
                echo "wpctl not found. Cannot check PipeWire profiles."
            fi
        else
            echo "Neither pactl nor wpctl found. Cannot check audio profiles."
        fi
        
        echo -e "\nBlueZ configuration for A2DP/HFP (if available):"
        if [[ -f /etc/bluetooth/main.conf ]]; then
            echo "/etc/bluetooth/main.conf (relevant sections):"
            grep -E 'Enable=Source|Enable=Sink|AutoEnable=true|ControllerMode|Class' /etc/bluetooth/main.conf | tee -a "$REPORT_FILE" || echo "No relevant entries found."
        fi
        if [[ -f /etc/bluetooth/audio.conf ]]; then
            echo "/etc/bluetooth/audio.conf (relevant sections):"
            grep -E 'Enable=Source|Enable=Sink|AutoEnable=true|SBCAllocationMethod|MinBitpool|MaxBitpool' /etc/bluetooth/audio.conf | tee -a "$REPORT_FILE" || echo "No relevant entries found."
        fi
    } | tee -a "$REPORT_FILE"
}

check_potential_conflicts() {
    header "[10] POTENTIAL SERVICE CONFLICTS"
    
    {
        echo "Running processes using Bluetooth/BlueZ:"
        safe_exec "ps aux | grep -E 'bluetooth|bluez' | grep -v grep" 10 true "ps aux (Bluetooth processes)" || echo "No active Bluetooth-related processes found."
        
        echo -e "\nChecking for connman:"
        if check_tool service && [[ -f /etc/init.d/connman ]]; then
            echo "connman service exists and is:"
            safe_exec "service connman status" 10 true "service connman status"
            if safe_exec "service connman status" 5 true "service connman status (check running)" | grep -q "running"; then
                log_warn "connman service is running and may conflict with NetworkManager/Bluetooth."
                echo "WARNING: connman service is running and may conflict."
            fi
        else
            echo "No connman service found."
        fi
        
        echo -e "\nChecking for NetworkManager:"
        if check_tool service && [[ -f /etc/init.d/network-manager ]]; then
            echo "NetworkManager service exists and is:"
            safe_exec "service network-manager status" 10 true "service network-manager status"
        else
            echo "No NetworkManager init script found (likely systemd)."
        fi
        
        echo -e "\nChecking for PulseAudio (if not PipeWire):"
        if check_tool service && [[ -f /etc/init.d/pulseaudio ]]; then
            echo "PulseAudio service exists and is:"
            safe_exec "service pulseaudio status" 10 true "service pulseaudio status"
        else
            echo "No PulseAudio init script found (likely systemd or PipeWire)."
        fi
    } | tee -a "$REPORT_FILE"
}

check_pulseaudio_pipewire_config() {
    header "[11] PULSEAUDIO/PIPEWIRE CONFIGURATION"
    
    {
        echo "User in audio groups:"
        local current_user=$(whoami)
        local audio_groups=("audio" "pulse" "pulse-access" "pipewire")
        local in_audio_group=false
        
        for group in "${audio_groups[@]}"; do
            if groups "$current_user" 2>/dev/null | grep -q "\b$group\b"; then
                echo "✓ User '$current_user' is in group '$group'"
                in_audio_group=true
            fi
        done
        
        if [[ "$in_audio_group" == "false" ]]; then
            log_warn "User '$current_user' is not in any common audio groups. This may cause permission issues."
            echo "⚠ User not in audio groups - may cause permission issues."
        fi
        
        local audio_system="unknown"
        if pgrep -f pipewire >/dev/null; then
            audio_system="pipewire"
        elif pgrep -f pulseaudio >/dev/null; then
            audio_system="pulseaudio"
        fi
        
        echo -e "\nDetected audio system: $audio_system"
        
        if [[ "$audio_system" == "pulseaudio" ]]; then
            if check_tool pactl;
            then
                echo -e "\nPulseAudio Info:"
                safe_exec "pactl info" 10 true "pactl info"
                echo -e "\nPulseAudio Configuration Files (Bluetooth related):"
                grep -E 'load-module module-bluetooth|load-module module-bluez' /etc/pulse/*.pa 2>/dev/null | tee -a "$REPORT_FILE" || echo "No explicit Bluetooth module loading in PulseAudio config."
            else
                echo "pactl not found. Cannot check PulseAudio configuration."
            fi
        elif [[ "$audio_system" == "pipewire" ]]; then
            if check_tool wpctl;
            then
                echo -e "\nPipeWire Status (wpctl status):"
                safe_exec "wpctl status" 10 true "wpctl status"
                echo -e "\nPipeWire Configuration Files (Bluetooth related):"
                grep -r -E 'bluetooth|bluez' /etc/pipewire/ 2>/dev/null | tee -a "$REPORT_FILE" || echo "No explicit Bluetooth configuration in PipeWire config."
            else
                echo "wpctl not found. Cannot check PipeWire configuration."
            fi
        else
            echo "Neither PulseAudio (pactl) nor PipeWire (wpctl) tools found."
        fi
    } | tee -a "$REPORT_FILE"
}

check_alsa_config() {
    header "[12] ALSA CONFIGURATION"
    
    {
        if check_tool aplay;
        then
            echo "ALSA Playback Devices (aplay -l):"
            safe_exec "aplay -l" 5 true "aplay -l"
        fi
        if check_tool arecord;
        then
            echo -e "\nALSA Capture Devices (arecord -l):"
            safe_exec "arecord -l" 5 true "arecord -l"
        fi
        echo -e "\nCustom ALSA configuration files:"
        if [[ -f /etc/asound.conf ]]; then
            echo "/etc/asound.conf:"
            cat /etc/asound.conf | tee -a "$REPORT_FILE"
        fi
        if [[ -f ~/.asoundrc ]]; then
            echo "~/.asoundrc:"
            cat ~/.asoundrc | tee -a "$REPORT_FILE"
        fi
        if [[ ! -f /etc/asound.conf ]] && [[ ! -f ~/.asoundrc ]]; then
            echo "No custom ALSA configuration files found."
        fi
    } | tee -a "$REPORT_FILE"
}

check_network_manager_interaction() {
    header "[13] NETWORK MANAGER INTERACTION"
    
    {
        if check_tool nmcli;
        then
            echo "NetworkManager general status (nmcli general status):"
            safe_exec "nmcli general status" 10 true "nmcli general status"
            echo -e "\nNetworkManager Bluetooth devices (nmcli device show):"
            safe_exec "nmcli device show | grep -i bluetooth" 10 true "nmcli device show (Bluetooth)" || echo "No Bluetooth devices managed by NetworkManager."
        else
            echo "nmcli command not found. Cannot check NetworkManager status."
        fi
    } | tee -a "$REPORT_FILE"
}

check_firewall_rules() {
    header "[14] FIREWALL RULES"
    
    {
        echo "Checking UFW status:"
        if check_tool ufw;
        then
            safe_exec "sudo ufw status verbose" 10 true "ufw status verbose"
            if safe_exec "sudo ufw status" 5 true "ufw status (check active)" | grep -q "active"; then
                echo "UFW is active. Ensure no rules block Bluetooth services (e.g., port 1112 for SDP, 3333 for RFCOMM)."
            fi
        else
            echo "UFW not found."
        fi
        
        echo -e "\nChecking firewalld status:"
        if check_tool firewall-cmd;
        then
            safe_exec "sudo firewall-cmd --state" 10 true "firewall-cmd --state"
            if safe_exec "sudo firewall-cmd --state" 5 true "firewall-cmd --state (check running)" | grep -q "running"; then
                echo "firewalld is active. Check zones and services for Bluetooth."
                safe_exec "sudo firewall-cmd --list-all --zone=public | grep -i bluetooth" 10 true "firewall-cmd --list-all (Bluetooth)" || echo "No explicit Bluetooth rules in public zone."
            fi
        else
            echo "firewall-cmd not found."
        fi
    } | tee -a "$REPORT_FILE"
}

check_system_logs_bluetooth() { # Renamed from check_system_logs
    header "[15] SYSTEM LOGS (BLUETOOTH)"
    
    {
        echo "Recent Bluetooth-related log entries from syslog/messages:"
        local log_sources=("/var/log/syslog" "/var/log/messages" "/var/log/daemon.log")
        local logs_found_in_files=false
        
        for log_file in "${log_sources[@]}"; do
            if [[ -f "$log_file" && -r "$log_file" ]]; then
                echo "From $log_file (last 10 Bluetooth entries):"
                grep -i bluetooth "$log_file" 2>/dev/null | tail -10 || continue
                logs_found_in_files=true
                echo
                break
            fi
        done
        
        if [[ "$logs_found_in_files" == "false" ]]; then
            echo "No Bluetooth entries found in common log files."
        fi
        
        echo -e "\nJournalctl entries for bluetooth.service (if systemd exists):"
        if check_tool journalctl && [[ $(detect_init_system) == "systemd" ]]; then
            safe_exec "sudo journalctl -u bluetooth.service -n 20 --no-pager" 15 true "journalctl -u bluetooth.service"
            
            echo -e "\nRecent Bluetooth kernel messages (journalctl -k):"
            safe_exec "sudo journalctl -k --grep=bluetooth -n 10 --no-pager" 10 true "journalctl -k (Bluetooth)" || echo "No recent Bluetooth kernel messages in journal."
        else
            echo "journalctl not available or not a systemd system."
        fi
        
        echo -e "\nRecent kernel messages about Bluetooth hardware (dmesg):"
        if check_tool dmesg;
        then
            dmesg 2>/dev/null | grep -i bluetooth | tail -10 || echo "No recent Bluetooth kernel messages from dmesg."
        else
            echo "dmesg not available."
        fi
    } | tee -a "$REPORT_FILE"
}

check_bluetooth_daemon_logs() {
    header "[16] BLUETOOTH DAEMON LOGS"
    echo "BlueZ daemon configuration for verbose logging:" | tee -a "$REPORT_FILE"
    if [[ -f /etc/bluetooth/main.conf ]]; then
        grep -E '^#?LogLevel|^#?LogFile' /etc/bluetooth/main.conf | tee -a "$REPORT_FILE" || echo "No explicit LogLevel/LogFile settings found in main.conf."
    else
        echo "/etc/bluetooth/main.conf not found." | tee -a "$REPORT_FILE"
    fi
}

check_bluetoothctl_interactive_status() { # Renamed from check_bluetoothctl_status
    header "[17] BLUETOOTHCTL INTERACTIVE STATUS"
    
    {
        if check_tool bluetoothctl;
        then
            echo "Bluetoothctl info (controller, paired devices, connected devices):"
            
            echo "  Controller Information:"
            echo "show" | timeout 10 bluetoothctl 2>/dev/null | head -20 || {
                log_warn "Failed to get bluetoothctl controller info."
                echo "Could not retrieve controller information."
            }
            
            echo -e "\n  Paired Devices:"
            echo "paired-devices" | timeout 10 bluetoothctl 2>/dev/null | grep "Device" || echo "No paired devices."
            
            echo -e "\n  Connected Devices:"
            echo "info" | timeout 10 bluetoothctl 2>/dev/null | grep -E 'Device|Connected' || echo "No connected devices."
            
            echo -e "\n  Agent Status:"
            local agent_running=false
            if pgrep -f "bluetooth.*agent" >/dev/null; then
                echo "Bluetooth agent is running."
                agent_running=true
            else
                echo "No bluetooth agent detected."
            fi
            
            if [[ "$agent_running" == "false" ]]; then
                log_warn "No Bluetooth agent running - pairing may not work."
            fi
        else
            log_error "bluetoothctl not available. Cannot get interactive status."
            echo "bluetoothctl command not found."
        fi
    } | tee -a "$REPORT_FILE"
}

check_autostart_configurations() {
    header "[18] AUTO-START CONFIGURATIONS"
    
    {
        echo "Checking common autostart locations for Bluetooth entries:"
        
        # Check rc.local
        if [[ -f /etc/rc.local ]]; then
            echo -e "\n/etc/rc.local contents (Bluetooth related):"
            grep -i bluetooth /etc/rc.local | tee -a "$REPORT_FILE" || echo "No Bluetooth entries in /etc/rc.local."
        fi
        
        # Check profile scripts
        echo -e "\n~/.profile, ~/.bashrc contents (Bluetooth related):"
        grep -i bluetooth ~/.profile ~/.bashrc 2>/dev/null | tee -a "$REPORT_FILE" || echo "No Bluetooth entries in ~/.profile or ~/.bashrc."
        
        # Check autostart directories
        echo -e "\nChecking GUI autostart locations:"
        find ~/.config/autostart /etc/xdg/autostart -name "*bluetooth*" -ls 2>/dev/null | tee -a "$REPORT_FILE" || echo "No Bluetooth autostart files found in GUI locations."
    } | tee -a "$REPORT_FILE"
}

generate_summary() {
    header "[19] DIAGNOSTIC SUMMARY & RECOMMENDATIONS"
    
    {
        echo "Diagnostic Results Summary:"
        echo "  Total Critical Issues Found: $ISSUES_FOUND"
        echo "  Total Warnings: $WARNINGS_FOUND"
        echo
        
        if [[ $ISSUES_FOUND -eq 0 && $WARNINGS_FOUND -eq 0 ]]; then
            echo "✅ No major issues detected! Your Bluetooth and Audio setup appears to be in good shape."
        elif [[ $ISSUES_FOUND -eq 0 ]]; then
            echo "⚠️  Some warnings found, but no critical issues detected. Review the report for details."
        else
            echo "❌ Critical issues found that need attention. Please review the full report for details."
        fi
        
        echo
        echo "Recommended Actions:"
        
        if [[ $ISSUES_FOUND -gt 0 ]]; then
            echo "🔴 CRITICAL ISSUES TO FIX:"
            echo "   1. Review all ERROR messages in the report above."
            echo "   2. Ensure Bluetooth service is running and enabled: 'sudo systemctl start bluetooth' and 'sudo systemctl enable bluetooth'."
            echo "   3. Check if Bluetooth is blocked by rfkill: 'rfkill list bluetooth' and 'sudo rfkill unblock bluetooth'."
            echo "   4. Verify all essential Bluetooth and audio packages are installed for your distribution."
            echo "   5. If no hardware is detected, check physical adapter, drivers, and firmware."
        fi
        
        if [[ $WARNINGS_FOUND -gt 0 ]]; then
            echo "🟡 WARNINGS TO ADDRESS:"
            echo "   1. Review all WARN messages in the report above."
            echo "   2. Consider installing missing optional packages (e.g., 'bluez-tools', 'blueman')."
            echo "   3. Check power management settings (TLP, USB autosuspend) if experiencing connectivity or stability issues."
            echo "   4. Investigate conflicting services (e.g., 'connman') if present and causing issues."
        fi
        
        echo
        echo "General Troubleshooting Steps:"
        echo "   1. Restart Bluetooth service: 'sudo systemctl restart bluetooth'."
        echo "   2. Reset Bluetooth module (if USB adapter): 'sudo modprobe -r btusb && sudo modprobe btusb'."
        echo "   3. Clear PulseAudio/PipeWire cache (if audio issues persist): 'rm -rf ~/.config/pulse/' (then restart audio service)."
        echo "   4. Check hardware: ensure Bluetooth is enabled in BIOS/UEFI settings."
        echo "   5. Update system: ensure you have the latest kernel, drivers, and firmware."
        
        echo
        echo "For Audio Issues (if separate from Bluetooth connection):"
        echo "   1. Restart audio service (PulseAudio/PipeWire)."
        echo "   2. Verify user is in relevant audio groups ('audio', 'pulse', 'pulse-access', 'pipewire')."
        echo "   3. Check if Bluetooth audio modules are loaded in PulseAudio/PipeWire configuration."
        echo "   4. Test audio routing with 'pactl list sinks' or 'wpctl status'."
        
        echo
        echo "Report Information:"
        echo "   Full report saved to: $REPORT_FILE"
        echo "   Generated by: $SCRIPT_NAME v$SCRIPT_VERSION"
        echo "   Run with -d for more detailed debug output."
    } | tee -a "$REPORT_FILE"
}

# Main execution
main() {
    # Parse command line arguments first
    parse_arguments "$@"
    
    # Set up environment
    setup_error_handling
    setup_environment
    
    log_info "Starting $SCRIPT_NAME v$SCRIPT_VERSION"
    [[ "$DEBUG_MODE" == "true" ]] && log_debug "Debug mode enabled"
    [[ "$VERBOSE_MODE" == "true" ]] && log_verbose "Verbose mode enabled"
    [[ "$QUIET_MODE" == "true" ]] && log_info "Quiet mode enabled"
    
    # Check privileges
    if [[ $EUID -ne 0 ]]; then
        log_warn "Not running as root - some checks will be limited"
        log_info "For complete diagnostics, consider running: sudo $0 $*"
    fi
    
    # Initialize report
    init_report
    
    # Run diagnostic checks
    log_info "Running system diagnostics..."
    check_system_overview
    check_kernel_modules
    check_udev_rules
    check_power_management
    check_bluetooth_service_status # Renamed
    check_bluetooth_packages
    check_bluetooth_hardware
    check_adapter_capabilities
    check_bluetooth_profiles_codecs # Specific audio profiles/codecs
    check_potential_conflicts
    check_pulseaudio_pipewire_config # Detailed PA/PW config
    check_alsa_config
    check_network_manager_interaction
    check_firewall_rules
    check_system_logs_bluetooth # Renamed
    check_bluetooth_daemon_logs
    check_bluetoothctl_interactive_status # Renamed
    check_autostart_configurations
    
    # Generate final summary
    generate_summary
    
    # Final output
    echo
    log_info "Diagnostic complete!"
    log_info "Full report saved to: $REPORT_FILE"
    
    if [[ $ISSUES_FOUND -gt 0 ]]; then
        log_error "Found $ISSUES_FOUND critical issues requiring attention"
        exit $EXIT_CRITICAL_ISSUES
    elif [[ $WARNINGS_FOUND -gt 0 ]]; then
        log_warn "Found $WARNINGS_FOUND warnings - review recommended"
        exit $EXIT_WARNINGS_ONLY
    else
        log_info "No issues detected - Bluetooth configuration appears healthy"
        exit $EXIT_SUCCESS
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
