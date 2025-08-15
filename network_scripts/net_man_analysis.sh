#!/bin/bash

# Declare the global associative array
declare -A NETWORK_ANALYSIS_DATA

analyze_network_manager_deep_dive() {
    # --- Function Configuration & Pre-flight Checks ---
    local target_interface="$1"
    local focused_manager="$2" # Optional: NetworkManager, systemd-networkd, wicd
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")
    NETWORK_ANALYSIS_DATA=() # Clear previous results
    NETWORK_ANALYSIS_DATA["analysis_timestamp"]="$timestamp"
    NETWORK_ANALYSIS_DATA["script_version"]="1.0"
    NETWORK_ANALYSIS_DATA["function_call_args"]="Interface: '${target_interface:-auto}', Focused Manager: '${focused_manager:-auto}'"

    echo "Deep Network Analysis starting at $timestamp"
    echo "----------------------------------------------------"

    if [[ $EUID -ne 0 ]]; then
        echo "ERROR: This script must be run as root (or with sudo) to access system-level information."
        NETWORK_ANALYSIS_DATA["error_permission_denied"]="Script not run as root."
        return 1
    fi

    local tools_required=(
        "systemctl" "ps" "ip" "ls" "cat" "nmcli" "networkctl" "journalctl"
        "dmesg" "strace" "tcpdump" "dig" "iwconfig" "iw" "dbus-monitor" "pgrep"
    )
    local missing_tools=()
    for tool in "${tools_required[@]}"; do
        if ! command -v "$tool" &> /dev/null; then
            missing_tools+=("$tool")
        fi
    done
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        echo "WARNING: Missing required tools: ${missing_tools[*]}"
        NETWORK_ANALYSIS_DATA["warnings_missing_tools"]="${missing_tools[*]}"
    fi

    # --- Auto-detect primary interface if not specified ---
    if [[ -z "$target_interface" ]]; then
        # Try to find interface with default route
        target_interface=$(ip route | grep '^default' | awk '{print $5}' | head -n1)
        if [[ -z "$target_interface" ]]; then
            # Fallback: first non-loopback UP interface
            target_interface=$(ip -o link show | awk -F': ' '$2 != "lo" && /state UP/ {print $2}' | head -n1)
        fi
        if [[ -z "$target_interface" ]]; then
            echo "WARNING: Could not auto-detect an active network interface. Some tests will be skipped or may fail."
            NETWORK_ANALYSIS_DATA["warnings_interface_detection"]="Failed to auto-detect active interface."
        else
            echo "INFO: Auto-detected target interface: $target_interface"
            NETWORK_ANALYSIS_DATA["detected_target_interface"]="$target_interface"
        fi
    else
        echo "INFO: Using specified target interface: $target_interface"
        if ! ip link show "$target_interface" &>/dev/null; then
             echo "WARNING: Specified interface '$target_interface' does not exist. Some tests may fail."
             NETWORK_ANALYSIS_DATA["warnings_interface_validation"]="Specified interface '$target_interface' not found."
        fi
    fi
    local interface_for_keys="${target_interface//[^a-zA-Z0-9_]/_}" # Sanitize for map keys

    # --- 1. Identify the Active Network Manager ---
    echo "[1] Identifying Active Network Manager..."
    NETWORK_ANALYSIS_DATA["identification_active_services"]="$(systemctl list-units --type=service --state=running | grep -E 'NetworkManager|networkd|wicd|connman' || echo 'No common network manager services found running.')"
    NETWORK_ANALYSIS_DATA["identification_interface_processes"]="$(ps aux | grep -E 'NetworkManager|wpa_supplicant|dhclient|dhcpcd|systemd-networkd|connman|wicd' | grep -v 'grep' || echo 'No common network manager processes found.')"

    local nm_dir="/etc/NetworkManager/"
    local sd_net_dir="/etc/systemd/network/"
    local legacy_net_file="/etc/network/interfaces"
    NETWORK_ANALYSIS_DATA["identification_key_files_NetworkManager_dir_exists"]="$([ -d "$nm_dir" ] && echo "Exists" || echo "Not found")"
    NETWORK_ANALYSIS_DATA["identification_key_files_systemd_networkd_dir_exists"]="$([ -d "$sd_net_dir" ] && echo "Exists" || echo "Not found")"
    NETWORK_ANALYSIS_DATA["identification_key_files_legacy_interfaces_file_exists"]="$([ -f "$legacy_net_file" ] && echo "Exists" || echo "Not found")"

    # Determine probable active manager
    local probable_active_manager="unknown"
    if grep -q "NetworkManager.service" <<< "${NETWORK_ANALYSIS_DATA["identification_active_services"]}"; then
        probable_active_manager="NetworkManager"
    elif grep -q "systemd-networkd.service" <<< "${NETWORK_ANALYSIS_DATA["identification_active_services"]}"; then
        probable_active_manager="systemd-networkd"
    elif grep -q "wicd.service" <<< "${NETWORK_ANALYSIS_DATA["identification_active_services"]}"; then
        probable_active_manager="wicd"
    elif grep -q "connman.service" <<< "${NETWORK_ANALYSIS_DATA["identification_active_services"]}"; then
        probable_active_manager="connman"
    fi
    NETWORK_ANALYSIS_DATA["identification_probable_active_manager"]="$probable_active_manager"
    if [[ -n "$focused_manager" ]]; then
        echo "INFO: Focusing analysis on '$focused_manager' as requested."
    else
        focused_manager="$probable_active_manager" # Use auto-detected if not specified
        echo "INFO: Auto-focusing analysis on '$focused_manager'."
    fi
    NETWORK_ANALYSIS_DATA["analysis_focus_manager"]="$focused_manager"

    # --- 2. Trace Interface Ownership ---
    if [[ -n "$target_interface" ]]; then
        echo "[2] Tracing Ownership for Interface: $target_interface..."
        if command -v nmcli &> /dev/null; then
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_nmcli_device_show"]="$(nmcli device show "$target_interface" 2>/dev/null || echo "nmcli: Interface $target_interface not found or error.")"
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_nmcli_device_status"]="$(nmcli device status 2>/dev/null | grep "$target_interface" || echo "nmcli: Interface $target_interface not in status list or error.")"
        else
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_nmcli_device_status"]="nmcli command not found."
        fi

        if command -v networkctl &> /dev/null; then
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_networkctl_list"]="$(networkctl list "$target_interface" 2>/dev/null || echo "networkctl: Interface $target_interface not found or error.")"
        else
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_networkctl_list"]="networkctl command not found."
        fi

        NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_ip_link_show"]="$(ip link show "$target_interface" 2>/dev/null || echo "ip link: Interface $target_interface not found.")"
        local driver_path="/sys/class/net/${target_interface}/device/driver"
        if [[ -e "$driver_path" ]]; then
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_driver"]="$(ls -l "$driver_path" | awk '{print $NF}')"
        else
            NETWORK_ANALYSIS_DATA["ownership_${interface_for_keys}_driver"]="Driver path not found."
        fi
    else
        echo "INFO: Skipping Interface Ownership trace (no target interface)."
    fi


    # --- 3. Analyze Configuration Workflow ---
    echo "[3] Analyzing Configuration Workflow..."
    if [[ "$focused_manager" == "NetworkManager" ]] || [[ "$probable_active_manager" == "NetworkManager" ]]; then
        echo "  [3.A] NetworkManager Configuration:"
        NETWORK_ANALYSIS_DATA["config_NetworkManager_system_connections_path"]="/etc/NetworkManager/system-connections/"
        NETWORK_ANALYSIS_DATA["config_NetworkManager_system_connections_list"]="$(ls -1 /etc/NetworkManager/system-connections/ 2>/dev/null || echo 'No system connections found or directory inaccessible.')"
        # Optionally, cat a few files, but be mindful of sensitive data. For now, list only.
        NETWORK_ANALYSIS_DATA["config_NetworkManager_NetworkManager_conf"]="$(cat /etc/NetworkManager/NetworkManager.conf 2>/dev/null || echo 'File not found or unreadable.')"
        NETWORK_ANALYSIS_DATA["config_NetworkManager_notes"]="Uses wpa_supplicant for Wi-Fi, dhclient/dhcpcd for DHCP, modifies /etc/resolv.conf (or uses systemd-resolved)."
        NETWORK_ANALYSIS_DATA["config_NetworkManager_resolv_conf_link"]="$(ls -l /etc/resolv.conf 2>/dev/null || echo '/etc/resolv.conf not found')"
    fi

    if [[ "$focused_manager" == "systemd-networkd" ]] || [[ "$probable_active_manager" == "systemd-networkd" ]]; then
        echo "  [3.B] systemd-networkd Configuration:"
        NETWORK_ANALYSIS_DATA["config_systemd_networkd_path"]="/etc/systemd/network/"
        NETWORK_ANALYSIS_DATA["config_systemd_networkd_files_content"]=""
        if compgen -G "/etc/systemd/network/*.network" > /dev/null; then
            for conf_file in /etc/systemd/network/*.network; do
                NETWORK_ANALYSIS_DATA["config_systemd_networkd_files_content"]+="\n--- $conf_file ---\n$(cat "$conf_file" 2>/dev/null)\n"
            done
        else
             NETWORK_ANALYSIS_DATA["config_systemd_networkd_files_content"]="No .network files found in /etc/systemd/network/."
        fi
        if [[ -z "${NETWORK_ANALYSIS_DATA["config_systemd_networkd_files_content"]}" ]]; then # Handle case where loop doesn't run but directory exists
            NETWORK_ANALYSIS_DATA["config_systemd_networkd_files_content"]="No .network files found or unreadable."
        fi
        NETWORK_ANALYSIS_DATA["config_systemd_networkd_notes"]="Directly configures kernel via netlink, integrates with systemd-resolved for DNS."
    fi

    if [[ "$focused_manager" == "wicd" ]] || [[ "$probable_active_manager" == "wicd" ]]; then
        echo "  [3.C] wicd Configuration:"
        NETWORK_ANALYSIS_DATA["config_wicd_path"]="/etc/wicd/"
        NETWORK_ANALYSIS_DATA["config_wicd_settings_conf"]="$(cat /etc/wicd/manager-settings.conf 2>/dev/null || echo 'File not found or unreadable.')"
        NETWORK_ANALYSIS_DATA["config_wicd_wired_settings_conf"]="$(cat /etc/wicd/wired-settings.conf 2>/dev/null || echo 'File not found or unreadable.')"
        NETWORK_ANALYSIS_DATA["config_wicd_wireless_settings_conf"]="$(cat /etc/wicd/wireless-settings.conf 2>/dev/null || echo 'File not found or unreadable.')"
        NETWORK_ANALYSIS_DATA["config_wicd_notes"]="Configuration typically in /etc/wicd/. Uses its own backend or external tools for DHCP/WPA."
    fi

    if [[ -f "$legacy_net_file" ]]; then
        echo "  [3.D] Legacy /etc/network/interfaces:"
        NETWORK_ANALYSIS_DATA["config_legacy_interfaces_content"]="$(cat "$legacy_net_file" 2>/dev/null || echo 'File not found or unreadable')"
    fi


    # --- 4. Monitor Runtime Behavior ---
    echo "[4] Monitoring Runtime Behavior (Recent Data & Commands)..."
    # Logs (recent entries)
    if command -v journalctl &> /dev/null; then
        if [[ "$focused_manager" == "NetworkManager" ]] || [[ "$probable_active_manager" == "NetworkManager" ]]; then
            NETWORK_ANALYSIS_DATA["logs_NetworkManager_recent"]="$(journalctl -u NetworkManager --no-pager -n 50 || echo 'Failed to get NetworkManager logs.')"
        fi
        if [[ "$focused_manager" == "systemd-networkd" ]] || [[ "$probable_active_manager" == "systemd-networkd" ]]; then
            NETWORK_ANALYSIS_DATA["logs_systemd_networkd_recent"]="$(journalctl -u systemd-networkd --no-pager -n 50 || echo 'Failed to get systemd-networkd logs.')"
        fi
         if [[ "$focused_manager" == "wicd" ]] || [[ "$probable_active_manager" == "wicd" ]]; then
            NETWORK_ANALYSIS_DATA["logs_wicd_recent"]="$(journalctl -u wicd --no-pager -n 50 || echo 'Failed to get wicd logs.')" # Or check /var/log/wicd/
            NETWORK_ANALYSIS_DATA["logs_wicd_file_path_note"]="Also check /var/log/wicd/wicd.log"
        fi
    else
        NETWORK_ANALYSIS_DATA["logs_journalctl_status"]="journalctl command not found."
    fi
    if command -v dmesg &> /dev/null; then
        NETWORK_ANALYSIS_DATA["logs_kernel_recent_dmesg"]="$(dmesg -T | tail -n 50 || echo 'Failed to get dmesg output.')"
    else
        NETWORK_ANALYSIS_DATA["logs_kernel_recent_dmesg"]="dmesg command not found."
    fi

    # Process Tracing (provide commands and PIDs)
    NETWORK_ANALYSIS_DATA["process_tracing_commands_note"]="Use strace on PIDs. e.g., sudo strace -p PID -e network,ioctl -f -tt"
    if command -v pgrep &>/dev/null; then
        local nm_pid systemd_networkd_pid wicd_pid
        nm_pid=$(pgrep NetworkManager)
        systemd_networkd_pid=$(pgrep systemd-networkd)
        wicd_pid=$(pgrep wicd)
        
        if [[ -n "$nm_pid" ]]; then NETWORK_ANALYSIS_DATA["process_tracing_NetworkManager_PIDs"]="$nm_pid"; fi
        if [[ -n "$systemd_networkd_pid" ]]; then NETWORK_ANALYSIS_DATA["process_tracing_systemd_networkd_PIDs"]="$systemd_networkd_pid"; fi
        if [[ -n "$wicd_pid" ]]; then NETWORK_ANALYSIS_DATA["process_tracing_wicd_PIDs"]="$wicd_pid"; fi
    else
        NETWORK_ANALYSIS_DATA["process_tracing_pgrep_status"]="pgrep command not found."
    fi


    # Network Traffic (provide commands)
    if [[ -n "$target_interface" ]]; then
        NETWORK_ANALYSIS_DATA["network_traffic_capture_commands_note"]="Use tcpdump. e.g.:"
        NETWORK_ANALYSIS_DATA["network_traffic_DHCP_command"]="sudo tcpdump -i $target_interface -envv port 67 or port 68"
        NETWORK_ANALYSIS_DATA["network_traffic_full_capture_command"]="sudo tcpdump -i $target_interface -w ${interface_for_keys}_capture.pcap"
    else
        NETWORK_ANALYSIS_DATA["network_traffic_capture_commands_note"]="Target interface not determined, tcpdump commands would require an interface."
    fi

    # --- 5. Test for Conflicts (Provide Commands, DO NOT EXECUTE) ---
    echo "[5] Test for Conflicts (Commands to run manually - NOT EXECUTED):"
    NETWORK_ANALYSIS_DATA["conflict_test_note"]="These commands would modify system state and are NOT executed by this script."
    NETWORK_ANALYSIS_DATA["conflict_test_A_disable_NM_start_networkd"]="sudo systemctl stop NetworkManager; sudo systemctl disable NetworkManager; sudo systemctl enable systemd-networkd; sudo systemctl start systemd-networkd"
    NETWORK_ANALYSIS_DATA["conflict_test_A_disable_networkd_start_NM"]="sudo systemctl stop systemd-networkd; sudo systemctl disable systemd-networkd; sudo systemctl enable NetworkManager; sudo systemctl start NetworkManager"
    if [[ -n "$target_interface" ]]; then
        NETWORK_ANALYSIS_DATA["conflict_test_A_check_interface_command"]="ip addr show $target_interface; ip route show dev $target_interface"
        NETWORK_ANALYSIS_DATA["conflict_test_B_current_ip_config_note"]="Current IP/route/DNS for $target_interface:"
        NETWORK_ANALYSIS_DATA["conflict_test_B_current_ip_addr"]="$(ip addr show "$target_interface" 2>/dev/null || echo 'Not available')"
        NETWORK_ANALYSIS_DATA["conflict_test_B_current_ip_route"]="$(ip route show dev "$target_interface" 2>/dev/null || echo 'Not available')"
        NETWORK_ANALYSIS_DATA["conflict_test_B_current_dns_resolv_conf"]="$(cat /etc/resolv.conf 2>/dev/null || echo 'Not available')"
        
        local example_manual_ip="192.168.1.200/24" # Placeholder
        local example_manual_gw="192.168.1.1"    # Placeholder
        NETWORK_ANALYSIS_DATA["conflict_test_B_manual_config_commands"]="sudo ip addr add $example_manual_ip dev $target_interface; sudo ip link set $target_interface up; sudo ip route add default via $example_manual_gw dev $target_interface"
        NETWORK_ANALYSIS_DATA["conflict_test_B_manual_config_cleanup_commands"]="sudo ip addr del $example_manual_ip dev $target_interface; sudo ip route del default via $example_manual_gw dev $target_interface; # May need to restart manager"
        NETWORK_ANALYSIS_DATA["conflict_test_B_observe_note"]="Observe if manager overwrites manual settings."
    else
        NETWORK_ANALYSIS_DATA["conflict_test_A_B_note"]="Target interface not determined, specific conflict tests cannot be fully detailed."
    fi

    # --- 6. Key Metrics to Investigate ---
    echo "[6] Key Metrics to Investigate (Commands and Data Points)..."
    if [[ -n "$target_interface" ]]; then
        NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_bring_up_time_command_NM"]="time nmcli device connect $target_interface (If using NM and interface is disconnected)"
    fi

    local dhclient_leases="/var/lib/dhcp/dhclient.leases" # Common path
    local dhcpcd_leases_dir="/var/lib/dhcpcd/"            # Common path for dhcpcd
    NETWORK_ANALYSIS_DATA["metrics_dhcp_lease_stability_dhclient_path"]="$dhclient_leases"
    NETWORK_ANALYSIS_DATA["metrics_dhcp_lease_stability_dhcpcd_path_note"]="Check $dhcpcd_leases_dir for per-interface leases if dhcpcd is used."
    if [[ -f "$dhclient_leases" ]]; then
        NETWORK_ANALYSIS_DATA["metrics_dhcp_lease_stability_dhclient_content_tail"]="$(tail -n 30 "$dhclient_leases" 2>/dev/null || echo 'Lease file unreadable or empty')"
    else
        NETWORK_ANALYSIS_DATA["metrics_dhcp_lease_stability_dhclient_content_tail"]="dhclient.leases file not found at $dhclient_leases"
    fi
    
    local dns_test_domain="example.com"
    NETWORK_ANALYSIS_DATA["metrics_dns_resolution_dig_command"]="dig $dns_test_domain"
    if command -v dig &>/dev/null; then
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_dig_output"]="$(dig +short $dns_test_domain @8.8.8.8 A)" # Test against public DNS
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_dig_local_output"]="$(dig +short $dns_test_domain A)" # Test against system configured DNS
    else
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_dig_status"]="dig command not found."
    fi

    if command -v systemd-resolve &>/dev/null && systemctl is-active systemd-resolved &>/dev/null; then
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_systemd_resolve_command"]="systemd-resolve $dns_test_domain"
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_systemd_resolve_output"]="$(systemd-resolve $dns_test_domain 2>/dev/null | grep 'Current scope' -A 2 || echo 'systemd-resolve query failed or no result')"
    else
        NETWORK_ANALYSIS_DATA["metrics_dns_resolution_systemd_resolve_status"]="systemd-resolve not found or systemd-resolved not active."
    fi

    if [[ -n "$target_interface" ]] && [[ "$target_interface" == wlan* || "$target_interface" == ath* || "$target_interface" == ra* ]]; then # Common wireless prefixes
        NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_roaming_iwconfig_command"]="iwconfig $target_interface"
        if command -v iwconfig &>/dev/null; then
            NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_roaming_iwconfig_output"]="$(iwconfig "$target_interface" 2>/dev/null || echo 'iwconfig failed or interface not wireless.')"
        else
            NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_roaming_iwconfig_status"]="iwconfig command not found."
        fi
        
        NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_power_management_iw_command"]="iw dev $target_interface get power_save"
        if command -v iw &>/dev/null; then
            NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_power_management_iw_output"]="$(iw dev "$target_interface" get power_save 2>/dev/null || echo 'iw get power_save failed.')"
        else
             NETWORK_ANALYSIS_DATA["metrics_${interface_for_keys}_power_management_iw_status"]="iw command not found."
        fi
    fi

    # --- 7. Advanced: Hook into D-Bus (NetworkManager) ---
    echo "[7] Advanced: D-Bus Monitoring (Command for NetworkManager)..."
    if [[ "$focused_manager" == "NetworkManager" ]] || [[ "$probable_active_manager" == "NetworkManager" ]]; then
        if command -v dbus-monitor &>/dev/null; then
            NETWORK_ANALYSIS_DATA["dbus_NetworkManager_monitor_command"]="dbus-monitor --system \"interface='org.freedesktop.NetworkManager'\""
            NETWORK_ANALYSIS_DATA["dbus_NetworkManager_monitor_note"]="Run this command manually to observe D-Bus events in real-time."
        else
            NETWORK_ANALYSIS_DATA["dbus_NetworkManager_monitor_status"]="dbus-monitor command not found."
        fi
    else
        NETWORK_ANALYSIS_DATA["dbus_NetworkManager_monitor_note"]="D-Bus monitoring typically relevant for NetworkManager."
    fi


    # --- 8. Document Findings (already done via NETWORK_ANALYSIS_DATA map) ---
    echo "[8] Document Findings: All data collected in NETWORK_ANALYSIS_DATA associative array."
    NETWORK_ANALYSIS_DATA["documentation_comparison_table_template"]="
| Scenario               | NetworkManager | systemd-networkd | Manual | Wicd   |
|------------------------|----------------|------------------|--------|--------|
| Interface auto-up      | (e.g., Yes)    | (e.g., No)       | N/A    | (e.g., Yes) |
| DHCP Reliability       |                |                  |        |        |
| Wi-Fi Reconnect Speed  |                |                  |        |        |
| DNS Config Method      |                |                  |        |        |
Fill this based on observations from logs, tests, and metrics."

    echo "----------------------------------------------------"
    echo "Deep Network Analysis completed."
    echo "Results stored in NETWORK_ANALYSIS_DATA array."
}

# --- Example Usage & Output ---
#
# Make sure to run this script with sudo:
# sudo ./your_script_name.sh
#
# if [[ $EUID -ne 0 ]]; then
#    echo "Please run as root or with sudo."
#    exit 1
# fi
#
# # Example 1: Auto-detect interface, auto-focus manager
# # analyze_network_manager_deep_dive
#
# # Example 2: Specify interface (e.g., wlan0), auto-focus manager
# # analyze_network_manager_deep_dive "wlan0"
#
# # Example 3: Specify interface and focus on NetworkManager
# # analyze_network_manager_deep_dive "eth0" "NetworkManager"
#
# # After running, you can print the results:
# #
# # echo "========================================"
# # echo "NETWORK ANALYSIS RESULTS DUMP:"
# # echo "========================================"
# # for key in "${!NETWORK_ANALYSIS_DATA[@]}"; do
# #     printf "\n--- %s ---\n" "$key"
# #     printf "%s\n" "${NETWORK_ANALYSIS_DATA[$key]}"
# # done
# # echo "========================================"

# --- Call the function (CHOOSE ONE EXAMPLE) ---
# analyze_network_manager_deep_dive # Auto-detect interface and manager focus
analyze_network_manager_deep_dive "wlan0" "NetworkManager" # Specific interface and manager

# --- Print the results ---
echo ""
echo "========================================"
echo "NETWORK ANALYSIS RESULTS DUMP:"
echo "========================================"
# Sort keys for more consistent output (optional, bash 4+)
# IFS=$'\n' sorted_keys=($(sort <<<"${!NETWORK_ANALYSIS_DATA[*]}"))
# unset IFS
# for key in "${sorted_keys[@]}"; do
for key in "${!NETWORK_ANALYSIS_DATA[@]}"; do # Original order
    printf "\n--- %s ---\n" "$key"
    # For multiline values, it's often better to just echo, but printf handles special chars better.
    # For complex strings, 'echo' might be visually cleaner.
    # Using printf for safety against arbitrary characters in values.
    printf "%s\n" "${NETWORK_ANALYSIS_DATA[$key]}"
done
echo "========================================"
