#!/bin/bash

# Declare the global associative array for storing results
declare -A NETWORK_ANALYSIS_DATA

# --- Color Definitions ---
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_ITALIC='\033[3m'
C_UNDERLINE='\033[4m'

C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_MAGENTA='\033[0;35m'
C_CYAN='\033[0;36m'
C_LIGHT_GRAY='\033[0;37m'

C_LIGHT_RED='\033[1;31m'
C_LIGHT_GREEN='\033[1;32m'
C_LIGHT_YELLOW='\033[1;33m'
C_LIGHT_BLUE='\033[1;34m'
C_LIGHT_MAGENTA='\033[1;35m'
C_LIGHT_CYAN='\033[1;36m'
C_WHITE='\033[1;37m'

# Semantic colors
HEADER_COLOR="${C_BOLD}${C_LIGHT_BLUE}"
SUB_HEADER_COLOR="${C_BOLD}${C_BLUE}"
SECTION_TITLE_COLOR="${C_BOLD}${C_MAGENTA}"
INFO_COLOR="${C_GREEN}"
ACTION_INFO_COLOR="${C_LIGHT_GREEN}"
WARNING_COLOR="${C_YELLOW}"
ERROR_COLOR="${C_RED}"
COMMAND_COLOR="${C_LIGHT_CYAN}"
DATA_LABEL_COLOR="${C_BOLD}${C_WHITE}"
VALUE_COLOR="" # Default terminal color for values
IMPORTANT_VALUE_COLOR="${C_BOLD}${C_LIGHT_YELLOW}"
NOTE_COLOR="${C_DIM}"

# --- Helper Functions for Output and Data Storage ---
# ... (All helper functions from the previous version: _print_main_header, _print_section_header, etc.) ...
# (I will omit repeating all helper functions for brevity, assume they are here)
_print_main_header() { echo -e "\n${HEADER_COLOR}════════════════════════════════════════════════════════════════════════════════${C_RESET}"; echo -e "${HEADER_COLOR}║ ${C_BOLD}${C_WHITE}$1${HEADER_COLOR} ║${C_RESET}"; echo -e "${HEADER_COLOR}════════════════════════════════════════════════════════════════════════════════${C_RESET}\n"; }
_print_section_header() { echo -e "\n${SUB_HEADER_COLOR}▶ $1 ${C_RESET}"; }
_print_subsection_title() { echo -e "  ${SECTION_TITLE_COLOR}↳ $1${C_RESET}"; }

_print_info() { echo -e "  ${INFO_COLOR}ℹ INFO: ${C_RESET}$1"; }
_print_action_info() { echo -e "  ${ACTION_INFO_COLOR}✓ ACTION: ${C_RESET}$1";}
_print_warn() { echo -e "  ${WARNING_COLOR}⚠ WARN: ${C_RESET}$1"; }
_print_err() { echo -e "  ${ERROR_COLOR}✗ ERROR: ${C_RESET}$1"; }
_print_cmd_suggestion() { echo -e "    ${COMMAND_COLOR}  \$ ${C_ITALIC}$1${C_RESET}"; }
_print_cmd_run() { echo -e "    ${COMMAND_COLOR}  \$ ${C_ITALIC}$1${C_RESET}"; } # For commands actually run
_print_note() { echo -e "    ${NOTE_COLOR}Note: $1${C_RESET}"; }

_store_data() {
    NETWORK_ANALYSIS_DATA["$1"]="$2"
}

_print_and_store_data() {
    local key="$1"
    local label="$2"
    local value="$3"
    local is_multiline=false
    [[ "$value" == *$'\n'* ]] && is_multiline=true

    _store_data "$key" "$value"

    if [[ "$is_multiline" == true ]]; then
        echo -e "    ${DATA_LABEL_COLOR}${label}:${C_RESET}\n${VALUE_COLOR}$(echo "$value" | sed 's/^/      /') ${C_RESET}"
    else
        if [[ -z "$value" ]]; then
            echo -e "    ${DATA_LABEL_COLOR}${label}:${C_RESET} ${NOTE_COLOR}(empty/not found)${C_RESET}"
        else
            echo -e "    ${DATA_LABEL_COLOR}${label}:${C_RESET} ${VALUE_COLOR}${value}${C_RESET}"
        fi
    fi
}

_run_cmd_log_action() {
    local cmd_to_run="$1"
    local description="$2"
    echo -e "  ${ACTION_INFO_COLOR}EXECUTING:${C_RESET} ${COMMAND_COLOR}${cmd_to_run}${C_RESET} ($description)"
    eval "$cmd_to_run" # Use eval carefully; ensure commands are safe
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        _print_warn "Command finished with exit code $exit_code."
    fi
    return $exit_code
}

_run_and_store_cmd_output() {
    local key="$1"
    local label="$2"
    local cmd_to_run="$3"
    local result
    echo -e "    ${NOTE_COLOR}Executing: ${cmd_to_run}${C_RESET}"
    # shellcheck disable=SC2001
    result=$(eval "$cmd_to_run" 2>&1 | sed 's/\x1b\[[0-9;]*m//g') # Evaluate and strip ANSI codes from command output
    local exit_code=$?
    if [[ $exit_code -ne 0 && -z "$result" ]]; then
        result="Command failed (exit code $exit_code) or produced no output."
    elif [[ -z "$result" ]]; then
        result="(no output)"
    fi
    _print_and_store_data "$key" "$label" "$result"
}

_detect_primary_manager() {
    local detected_managers_arg="$1" # Pass as string "mgr1 mgr2"
    local primary_mgr="none"
    # Priority: NetworkManager > systemd-networkd > first detected
    if [[ " $detected_managers_arg " =~ " NetworkManager " ]]; then
        primary_mgr="NetworkManager"
    elif [[ " $detected_managers_arg " =~ " systemd-networkd " ]]; then
        primary_mgr="systemd-networkd"
    elif [[ -n "$detected_managers_arg" ]]; then
        primary_mgr=$(echo "$detected_managers_arg" | awk '{print $1}') # First one
    fi
    echo "$primary_mgr"
}


analyze_network_manager_deep_dive() {
    # ... (The entire analyze_network_manager_deep_dive function from the previous version) ...
    # (I will omit repeating the entire analysis function for brevity, assume it's here)
    # The definition from the previous answer should be pasted here.
    # For this example, let's just mock its output to make `attempt_reset_network_config` testable.
    # In a real scenario, analyze_network_manager_deep_dive would populate these correctly.

    if [[ -z "${NETWORK_ANALYSIS_DATA["identification_detected_running_managers"]}" ]]; then
        # This is a simplified version for demonstration if analyze_network_manager_deep_dive hasn't run or populated these.
        # In actual use, ensure analyze_network_manager_deep_dive populates these properly.
        local known_managers_local=("NetworkManager" "systemd-networkd" "wicd" "connman")
        local detected_running_managers_local=()
        for mgr_svc in "${known_managers_local[@]}"; do
            if systemctl is-active "${mgr_svc}.service" &>/dev/null; then
                detected_running_managers_local+=("$mgr_svc")
            fi
        done
        NETWORK_ANALYSIS_DATA["identification_detected_running_managers"]="${detected_running_managers_local[*]}"
        local primary_focus_manager_local
        primary_focus_manager_local=$(_detect_primary_manager "${detected_running_managers_local[*]}")
        NETWORK_ANALYSIS_DATA["analysis_primary_focus_manager"]="$primary_focus_manager_local"

        local target_interface_auto
        target_interface_auto=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
        if [[ -z "$target_interface_auto" ]]; then
            target_interface_auto=$(ip -o link show | awk -F': ' '$2 != "lo" && /state UP/ {print $2}' | head -n1)
        fi
        NETWORK_ANALYSIS_DATA["detected_target_interface"]="$target_interface_auto"
    fi

    _print_section_header "[X] Analysis Function Placeholder if not run previously"
    _print_info "Detected running managers from analysis: ${NETWORK_ANALYSIS_DATA["identification_detected_running_managers"]}"
    _print_info "Primary focus manager from analysis: ${NETWORK_ANALYSIS_DATA["analysis_primary_focus_manager"]}"
    _print_info "Detected target interface from analysis: ${NETWORK_ANALYSIS_DATA["detected_target_interface"]}"
}

# --- NEW FUNCTION ---
attempt_network_reset_to_dhcp() {
    local target_interfaces_str="$1" # Comma-separated string of interfaces, or "ALL"
    _print_main_header "Attempting Network Reset to DHCP"

    if [[ $EUID -ne 0 ]]; then
        _print_err "This function must be run as root (or with sudo)."
        return 1
    fi

    echo -e "${C_BOLD}${C_LIGHT_RED}"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! W A R N I N G !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "This operation will attempt to reset network configurations for specified"
    echo "interfaces to obtain IP addresses via DHCP. This may involve:"
    echo "  - Stopping network manager services."
    echo "  - Disconnecting current network connections."
    echo "  - Removing NetworkManager connection profiles for target interfaces."
    echo "  - Flushing IP addresses from interfaces."
    echo "  - Restarting network services."
    echo ""
    echo "THIS CAN POTENTIALLY DISRUPT YOUR NETWORK CONNECTIVITY."
    echo "IT IS NOT A GUARANTEED 'FACTORY RESET' AND MAY NOT WORK FOR ALL CONFIGURATIONS."
    echo "PROCEED WITH EXTREME CAUTION. ENSURE YOU HAVE CONSOLE ACCESS IF THIS IS A REMOTE MACHINE."
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo -e "${C_RESET}"

    read -r -p "$(echo -e "${C_BOLD}${C_YELLOW}Are you absolutely sure you want to proceed? (yes/NO): ${C_RESET}")" confirmation
    if [[ "${confirmation,,}" != "yes" ]]; then
        _print_info "Network reset aborted by user."
        return 1
    fi

    _print_section_header "[R1] Identifying Targets and Managers"

    # Run analysis if data isn't already populated from a prior call
    if [[ -z "${NETWORK_ANALYSIS_DATA["identification_detected_running_managers"]}" ]]; then
        _print_info "Running preliminary network analysis to gather system state..."
        analyze_network_manager_deep_dive # Call the main analysis function
        echo # Add a newline after analysis output
    fi

    local active_managers
    active_managers="${NETWORK_ANALYSIS_DATA["identification_detected_running_managers"]}"
    _print_info "Active network manager(s) detected: ${IMPORTANT_VALUE_COLOR}${active_managers:-None}${C_RESET}"

    local primary_manager
    primary_manager="${NETWORK_ANALYSIS_DATA["analysis_primary_focus_manager"]}"
    if [[ -z "$primary_manager" || "$primary_manager" == "none" ]]; then
        primary_manager=$(_detect_primary_manager "$active_managers")
    fi
    _print_info "Presumed primary network manager for restart: ${IMPORTANT_VALUE_COLOR}${primary_manager:-None, manual intervention may be needed}${C_RESET}"


    local interfaces_to_reset=()
    if [[ -z "$target_interfaces_str" || "${target_interfaces_str^^}" == "ALL" ]]; then
        _print_info "Targeting all non-loopback, non-bridge, non-bond physical interfaces."
        # Get physical interfaces (typically start with e, w, en, wl) and exclude common virtual ones.
        # This is a heuristic and might need adjustment for exotic interface names.
        mapfile -t interfaces_to_reset < <(ip -o link show | awk -F': ' '$2 != "lo" && $2 !~ /^docker|^veth|^br-|^bond|^dummy|^virbr/ && $3 !~ /NOARP/ {print $2}')
        if [[ ${#interfaces_to_reset[@]} -eq 0 ]]; then
             _print_warn "Could not automatically determine interfaces to reset. Please specify them."
             return 1
        fi
    else
        IFS=',' read -r -a interfaces_to_reset <<< "$target_interfaces_str"
    fi

    if [[ ${#interfaces_to_reset[@]} -eq 0 ]]; then
        _print_err "No interfaces specified or found for reset."
        return 1
    fi
    _print_info "Interfaces targeted for reset: ${IMPORTANT_VALUE_COLOR}${interfaces_to_reset[*]}${C_RESET}"


    _print_section_header "[R2] Performing Reset Actions"

    # Stop potentially conflicting managers if multiple are active (usually not a good state)
    # This is a simplification; proper handling of multiple managers is complex.
    # We prioritize NetworkManager or systemd-networkd if active.
    local managers_to_stop=()
    if [[ " $active_managers " =~ " NetworkManager " ]] && [[ " $active_managers " =~ " systemd-networkd " ]]; then
        _print_warn "Both NetworkManager and systemd-networkd appear active. This is often a misconfiguration."
        if [[ "$primary_manager" == "NetworkManager" ]]; then
            managers_to_stop+=("systemd-networkd")
        elif [[ "$primary_manager" == "systemd-networkd" ]]; then
            managers_to_stop+=("NetworkManager")
        else # Fallback, stop one
            managers_to_stop+=("systemd-networkd") # Arbitrary choice for now
            _print_warn "Could not definitively pick which of NM/systemd-networkd to prefer, will try to stop systemd-networkd."
        fi
    fi
    # Add other managers like wicd or connman if they are active and NOT the primary
    for mgr in wicd connman; do
        if [[ " $active_managers " =~ " $mgr " ]] && [[ "$primary_manager" != "$mgr" ]]; then
            managers_to_stop+=("$mgr")
        fi
    done

    for mgr_to_stop in "${managers_to_stop[@]}"; do
        _run_cmd_log_action "systemctl stop ${mgr_to_stop}.service" "Stopping potentially conflicting manager: $mgr_to_stop"
        _run_cmd_log_action "systemctl disable ${mgr_to_stop}.service" "Disabling potentially conflicting manager: $mgr_to_stop"
    done

    # For each targeted interface
    for iface in "${interfaces_to_reset[@]}"; do
        _print_subsection_title "Resetting interface: ${C_BOLD}${iface}${C_RESET}"
        
        # NetworkManager specific actions
        if [[ "$primary_manager" == "NetworkManager" ]] || [[ " $active_managers " =~ " NetworkManager " ]]; then
            if command -v nmcli &>/dev/null; then
                _print_info "Attempting NetworkManager actions for $iface..."
                # Find active connections on the device
                local connections
                mapfile -t connections < <(nmcli -g UUID,DEVICE connection show --active | grep "$iface" | cut -d':' -f1)
                if [[ ${#connections[@]} -gt 0 ]]; then
                    for conn_uuid in "${connections[@]}"; do
                        _run_cmd_log_action "nmcli connection down \"$conn_uuid\"" "Taking down active NM connection $conn_uuid on $iface"
                    done
                fi
                # Delete all profiles associated with this device (more aggressive)
                local profiles
                mapfile -t profiles < <(nmcli -g UUID,DEVICE connection show | grep "$iface" | cut -d':' -f1)
                if [[ ${#profiles[@]} -gt 0 ]]; then
                    _print_warn "The following NetworkManager connection profiles for $iface will be DELETED:"
                    for prof_uuid in "${profiles[@]}"; do
                        local prof_name
                        prof_name=$(nmcli -g NAME connection show uuid "$prof_uuid")
                        echo -e "    - UUID: $prof_uuid, Name: ${prof_name:-N/A}"
                    done
                     read -r -p "$(echo -e "    ${C_BOLD}${C_YELLOW}Confirm deletion of these profiles? (yes/NO): ${C_RESET}")" del_confirm
                    if [[ "${del_confirm,,}" == "yes" ]]; then
                        for prof_uuid in "${profiles[@]}"; do
                             _run_cmd_log_action "nmcli connection delete uuid \"$prof_uuid\"" "Deleting NM connection profile $prof_uuid for $iface"
                        done
                    else
                        _print_info "Skipped deletion of NetworkManager profiles for $iface."
                    fi
                else
                    _print_info "No specific NetworkManager connection profiles found for $iface to delete."
                fi
                _run_cmd_log_action "nmcli device disconnect \"$iface\"" "Ensuring $iface is disconnected via nmcli (errors are OK if not managed)"
            else
                _print_warn "nmcli not found, cannot perform NetworkManager specific connection reset for $iface."
            fi
        fi

        _run_cmd_log_action "ip addr flush dev \"$iface\"" "Flushing IP addresses from $iface"
        _run_cmd_log_action "ip link set dev \"$iface\" down" "Taking interface $iface down"
        sleep 1 # Brief pause
        _run_cmd_log_action "ip link set dev \"$iface\" up" "Bringing interface $iface up"
        _print_info "Interface $iface cycled down/up. Waiting for manager to reconfigure..."
    done

    _print_section_header "[R3] Restarting Primary Network Manager"
    if [[ -n "$primary_manager" && "$primary_manager" != "none" ]]; then
        _print_info "Attempting to restart the primary network manager: ${C_BOLD}$primary_manager${C_RESET}"
        # Ensure the primary manager is enabled before starting
        if ! systemctl is-enabled "${primary_manager}.service" &>/dev/null ; then
             _run_cmd_log_action "systemctl enable ${primary_manager}.service" "Enabling primary manager $primary_manager"
        fi
        _run_cmd_log_action "systemctl restart ${primary_manager}.service" "Restarting $primary_manager service"

        if [[ "$primary_manager" == "systemd-networkd" ]]; then
            if systemctl is-active systemd-resolved.service &>/dev/null; then
                 _run_cmd_log_action "systemctl restart systemd-resolved.service" "Restarting systemd-resolved service"
            fi
        fi
        sleep 3 # Give manager some time
        _print_info "Checking status of $primary_manager post-restart:"
        systemctl status --no-pager -l "${primary_manager}.service" | grep -E 'Active:|Loaded:|Main PID:'
    else
        _print_warn "No clear primary network manager identified to restart. Manual restart of networking services may be needed."
        _print_cmd_suggestion "sudo systemctl restart NetworkManager.service  # Or systemd-networkd.service, or networking.service"
    fi

    _print_section_header "[R4] Post-Reset Checks and Recommendations"
    echo ""
    for iface in "${interfaces_to_reset[@]}"; do
        _print_info "Current status for ${C_BOLD}${iface}${C_RESET} (wait a few moments for DHCP):"
        ip addr show dev "$iface" | grep 'inet ' || echo "    No IPv4 address found on $iface yet."
        ip route show dev "$iface" | grep 'default' || echo "    No default route via $iface yet."
    done
    echo ""
    _print_and_store_data "dns_resolv_conf_content_after_reset" "Current /etc/resolv.conf" "$(cat /etc/resolv.conf 2>/dev/null || echo 'Not found')"
    _print_info "Pinging a well-known host (e.g., 8.8.8.8) to test basic connectivity..."
    ping -c 3 8.8.8.8

    echo -e "\n${C_BOLD}${C_LIGHT_YELLOW}"
    echo "*********************************************************************************"
    echo "RECOMMENDATION: If networking is still not functioning as expected,"
    echo "a full system ${C_LIGHT_RED}REBOOT${C_LIGHT_YELLOW} is strongly recommended to ensure all services"
    echo "re-initialize their network state correctly."
    echo "  Command: ${C_BOLD}${C_WHITE}sudo reboot${C_RESET}"
    echo ""
    echo "Also, review logs for the active network manager:"
    _print_cmd_suggestion "journalctl -u ${primary_manager:-NetworkManager} -e"
    echo "*********************************************************************************"
    echo -e "${C_RESET}"

    _print_main_header "Network Reset Attempt Finished"
}

# --- Example Usage & Output (uncomment to run directly) ---
#
 if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then # Check if script is being executed directly
    if [[ $EUID -ne 0 ]]; then
        echo -e "\033[1;31mERROR: This script must be run as root (or with sudo).\033[0m"
        exit 1
    fi

    # First, optionally run the analysis function if you want its output displayed separately
    # analyze_network_manager_deep_dive "wlan0"

    # Then call the reset function.
    # Example 1: Target a specific interface
    # attempt_network_reset_to_dhcp "eth0"

    # Example 2: Target multiple specific interfaces
    # attempt_network_reset_to_dhcp "eth0,wlan0"

    # Example 3: Target all auto-detected physical interfaces (USE WITH EXTREME CAUTION)
    attempt_network_reset_to_dhcp "ALL"

    # === OPTIONALLY: Print the collected data from analyze_network_manager_deep_dive if it ran ===
    # echo -e "\n${C_BOLD}${C_LIGHT_MAGENTA}========================================================${C_RESET}"
    # echo -e "${C_BOLD}${C_LIGHT_MAGENTA}      Dumping Contents of NETWORK_ANALYSIS_DATA       ${C_RESET}"
    # echo -e "${C_BOLD}${C_LIGHT_MAGENTA}========================================================${C_RESET}"
    # for key in "${!NETWORK_ANALYSIS_DATA[@]}"; do
    #     echo -e "\n${C_BOLD}${C_YELLOW}--- KEY: $key ---${C_RESET}"
    #     if [[ "${NETWORK_ANALYSIS_DATA[$key]}" == *$'\n'* ]]; then
    #         echo -e "${NETWORK_ANALYSIS_DATA[$key]}"
    #     else
    #         echo -e "VALUE: ${NETWORK_ANALYSIS_DATA[$key]}"
    #     fi
    # done
    # echo -e "\n${C_BOLD}${C_LIGHT_MAGENTA}================ END OF DUMP =======================${C_RESET}"
 fi
