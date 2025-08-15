#!/bin/bash

# --- Script Settings ---
set -e # Exit immediately if a command exits with a non-zero status.

# --- Global Variables ---
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
LOG_FILE="$SCRIPT_DIR/performance_diag_$(date +%Y%m%d_%H%M%S).log"

# --- Global Variables for Raw Command Outputs (for scoring) ---
CPU_LSCPU_OUTPUT=""
CPU_MPSTAT_OUTPUT=""
CPU_TOP_OUTPUT=""

MEM_FREE_OUTPUT=""
MEM_VMSTAT_OUTPUT=""
MEM_MEMINFO_OUTPUT=""

DISK_DF_OUTPUT=""
DISK_IOSTAT_OUTPUT=""

NET_IP_OUTPUT=""
NET_NETSTAT_OUTPUT=""
NET_PING_OUTPUT=""

PROC_PS_MEM_OUTPUT=""
PROC_PS_CPU_OUTPUT=""

# --- Color and Icon Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

CHECK="✅"
CROSS="❌"
INFO="ℹ️"
WARN="⚠️"
GEAR="⚙️"

# --- Utility Functions ---

# spinner: Displays a spinning indicator while a command runs in the background.
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    printf " ${GEAR} "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf "\b%c" "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
    done
    printf "\b"
}

# normalize_score: Converts a raw metric value to a 0-10 score.
# Args: value, min_val, max_val, reverse_scale (1 for lower=better, 0 for higher=better)
normalize_score() {
    local value=$1
    local min_val=$2
    local max_val=$3
    local reverse_scale=$4

    # Ensure value is within bounds
    if [ $(echo "$value < $min_val" | bc -l) -eq 1 ]; then
        value=$min_val
    elif [ $(echo "$value > $max_val" | bc -l) -eq 1 ]; then
        value=$max_val
    fi

    local score=$(echo "scale=4; ( ( $value - $min_val ) / ( $max_val - $min_val ) ) * 10" | bc -l)

    if [ "$reverse_scale" -eq 1 ]; then
        score=$(echo "scale=4; 10 - $score" | bc -l)
    fi

    # Clamp score between 0 and 10
    if [ $(echo "$score < 0" | bc -l) -eq 1 ]; then
        score=0.0
    elif [ $(echo "$score > 10" | bc -l) -eq 1 ]; then
        score=10.0
    fi

    echo "$score"
}

# log_console: Prints messages to the console with appropriate colors and icons.
log_console() {
    local message="$1"
    local type="$2"
    case "$type" in
        "INFO") echo -e "${BLUE}${INFO} ${message}${NC}" >/dev/tty ;; 
        "SUCCESS") echo -e "${GREEN}${CHECK} ${message}${NC}" >/dev/tty ;; 
        "ERROR") echo -e "${RED}${CROSS} ${message}${NC}" >/dev/tty ;; 
        "WARN") echo -e "${YELLOW}${WARN} ${message}${NC}" >/dev/tty ;; 
        *) echo -e "${message}" >/dev/tty ;; 
    esac
}

# log_file: Appends verbose messages to the log file, optionally with a new section header and timestamp.
log_file() {
    local message="$1"
    local section_header="$2"
    if [ -n "$section_header" ]; then
        echo -e "\n--- ${section_header} ($(date '+%Y-%m-%d %H:%M:%S')) ---\n"
    fi
    echo -e "$message" >> "$LOG_FILE"
}

# start_logging: Initializes the log file.
start_logging() {
    touch "$LOG_FILE"
    log_console "Starting system performance diagnostics..." "INFO"
    log_file "Script started at $(date)" "SESSION START"
}

# stop_logging: Provides final log file location.
stop_logging() {
    log_console "Diagnostics complete. Log file saved to: ${LOG_FILE}" "SUCCESS"
    log_file "Script finished at $(date)" "SESSION END"
}

# check_dependencies: Verifies the presence of essential diagnostic tools.
check_dependencies() {
    local required_cmds=("iostat" "vmstat" "free" "top" "df" "lscpu" "netstat" "ping" "grep" "awk" "sed" "tput" "printf" "sleep")
    log_console "Checking for required system tools..." "INFO"
    local all_found=true
    for cmd in "${required_cmds[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            log_console "Missing tool: ${cmd}. Some diagnostics might be skipped." "WARN"
            all_found=false
        fi
    done
    if "$all_found"; then
        log_console "All required tools found." "SUCCESS"
    else
        log_console "Please consider installing missing tools for full functionality." "WARN"
    fi
}

# --- Diagnostic Modules ---

# run_cpu_diagnostics: Performs CPU-related performance checks.
run_cpu_diagnostics() {
    log_console "Running CPU diagnostics..." "INFO"
    (
        log_file "" "CPU Diagnostics"
        log_file "--- lscpu ---"
        CPU_LSCPU_OUTPUT=$(lscpu)
        log_file "$CPU_LSCPU_OUTPUT"

        log_file "\n--- mpstat -P ALL 1 1 ---"
        if command -v mpstat &> /dev/null; then
            CPU_MPSTAT_OUTPUT=$(mpstat -P ALL 1 1)
            log_file "$CPU_MPSTAT_OUTPUT"
        else
            log_file "mpstat not found, skipping."
        fi

        log_file "\n--- top -bn1 | head -n 10 ---"
        CPU_TOP_OUTPUT=$(top -bn1 | head -n 10)
        log_file "$CPU_TOP_OUTPUT"
    ) & spinner
    log_console "CPU diagnostics complete." "SUCCESS"
}

# run_memory_diagnostics: Performs memory-related performance checks.
run_memory_diagnostics() {
    log_console "Running Memory diagnostics..." "INFO"
    (
        log_file "" "Memory Diagnostics"
        log_file "--- free -h ---"
        MEM_FREE_OUTPUT=$(free -h)
        log_file "$MEM_FREE_OUTPUT"

        log_file "\n--- vmstat -s ---"
        if command -v vmstat &> /dev/null; then
            MEM_VMSTAT_OUTPUT=$(vmstat -s)
            log_file "$MEM_VMSTAT_OUTPUT"
        else
            log_file "vmstat not found, skipping."
        fi

        log_file "\n--- cat /proc/meminfo ---"
        MEM_MEMINFO_OUTPUT=$(cat /proc/meminfo)
        log_file "$MEM_MEMINFO_OUTPUT"
    ) & spinner
    log_console "Memory diagnostics complete." "SUCCESS"
}

# run_disk_diagnostics: Performs disk I/O and usage checks.
run_disk_diagnostics() {
    log_console "Running Disk I/O diagnostics..." "INFO"
    (
        log_file "" "Disk I/O Diagnostics"
        log_file "--- df -h ---"
        DISK_DF_OUTPUT=$(df -h)
        log_file "$DISK_DF_OUTPUT"

        log_file "\n--- iostat -xz 1 2 ---"
        if command -v iostat &> /dev/null; then
            DISK_IOSTAT_OUTPUT=$(iostat -xz 1 2)
            log_file "$DISK_IOSTAT_OUTPUT"
        else
            log_file "iostat not found, skipping."
        fi
    ) & spinner
    log_console "Disk I/O diagnostics complete." "SUCCESS"
}

# run_network_diagnostics: Performs network-related checks.
run_network_diagnostics() {
    log_console "Running Network diagnostics..." "INFO"
    (
        log_file "" "Network Diagnostics"
        log_file "--- ip a ---"
        NET_IP_OUTPUT=$(ip a)
        log_file "$NET_IP_OUTPUT"

        log_file "\n--- netstat -tulnp ---"
        if command -v netstat &> /dev/null; then
            NET_NETSTAT_OUTPUT=$(netstat -tulnp)
            log_file "$NET_NETSTAT_OUTPUT"
        else
            log_file "netstat not found, skipping."
        fi

        log_file "\n--- ping -c 4 google.com ---"
        NET_PING_OUTPUT=$(ping -c 4 google.com)
        log_file "$NET_PING_OUTPUT"
    ) & spinner
    log_console "Network diagnostics complete." "SUCCESS"
}

# run_process_diagnostics: Analyzes running processes for resource usage.
run_process_diagnostics() {
    log_console "Running Process analysis..." "INFO"
    (
        log_file "" "Process Analysis"
        log_file "--- ps aux --sort=-%mem | head -n 10 ---"
        PROC_PS_MEM_OUTPUT=$(ps aux --sort=-%mem | head -n 10)
        log_file "$PROC_PS_MEM_OUTPUT"

        log_file "\n--- ps aux --sort=-%cpu | head -n 10 ---"
        PROC_PS_CPU_OUTPUT=$(ps aux --sort=-%cpu | head -n 10)
        log_file "$PROC_PS_CPU_OUTPUT"
    ) & spinner
    log_console "Process analysis complete." "SUCCESS"
}

# calculate_performance_score: Calculates and displays the overall performance score.
calculate_performance_score() {
    log_console "Calculating performance score..." "INFO"
    log_file "" "Performance Score Calculation"

    local cpu_idle_score=0.0
    local cpu_load_score=0.0
    local mem_free_score=0.0
    local swap_used_score=0.0
    local disk_util_score=0.0
    local net_latency_score=0.0
    local net_packet_loss_score=0.0

    # --- CPU Scoring ---
    if [ -n "$CPU_MPSTAT_OUTPUT" ]; then
        local idle_percent=$(echo "$CPU_MPSTAT_OUTPUT" | awk '/Average:/{print $NF}' | head -n 1)
        if [ -n "$idle_percent" ]; then
            cpu_idle_score=$(normalize_score "$idle_percent" 10 90 0) # 10% idle = 0, 90% idle = 10 (higher is better)
        fi
    fi

    if [ -n "$CPU_TOP_OUTPUT" ]; then
        local load_avg_1min=$(echo "$CPU_TOP_OUTPUT" | head -n 1 | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}')
        local num_cores=$(echo "$CPU_LSCPU_OUTPUT" | grep "^CPU(s):" | awk '{print $2}')
        if [ -n "$load_avg_1min" ] && [ -n "$num_cores" ] && [ "$num_cores" -gt 0 ]; then
            local max_load=$(echo "scale=2; 2.0 * $num_cores" | bc -l)
            local min_load=$(echo "scale=2; 0.5 * $num_cores" | bc -l)
            cpu_load_score=$(normalize_score "$load_avg_1min" "$min_load" "$max_load" 1) # Lower load is better
        fi
    fi

    # --- Memory Scoring ---
    if [ -n "$MEM_MEMINFO_OUTPUT" ]; then
        local mem_total_kb=$(echo "$MEM_MEMINFO_OUTPUT" | grep "MemTotal:" | awk '{print $2}')
        local mem_free_kb=$(echo "$MEM_MEMINFO_OUTPUT" | grep "MemFree:" | awk '{print $2}')
        if [ -n "$mem_total_kb" ] && [ -n "$mem_free_kb" ] && [ "$mem_total_kb" -gt 0 ]; then
            local free_ratio=$(echo "scale=4; $mem_free_kb / $mem_total_kb" | bc -l)
            mem_free_score=$(normalize_score "$(echo "scale=2; $free_ratio * 100" | bc -l)" 10 80 0) # 10% free = 0, 80% free = 10
        fi

        local swap_total_kb=$(echo "$MEM_MEMINFO_OUTPUT" | grep "SwapTotal:" | awk '{print $2}')
        local swap_free_kb=$(echo "$MEM_MEMINFO_OUTPUT" | grep "SwapFree:" | awk '{print $2}')
        if [ -n "$swap_total_kb" ] && [ -n "$swap_free_kb" ] && [ "$swap_total_kb" -gt 0 ]; then
            local swap_used_kb=$(echo "$swap_total_kb - $swap_free_kb" | bc -l)
            local swap_used_ratio=$(echo "scale=4; $swap_used_kb / $swap_total_kb" | bc -l)
            swap_used_score=$(normalize_score "$(echo "scale=2; $swap_used_ratio * 100" | bc -l)" 0 10 1) # 0% used = 10, 10% used = 0
        elif [ "$swap_total_kb" -eq 0 ]; then
            swap_used_score=10.0 # No swap, so perfect score
        fi
    fi

    # --- Disk I/O Scoring ---
    if [ -n "$DISK_IOSTAT_OUTPUT" ]; then
        local avg_util=$(echo "$DISK_IOSTAT_OUTPUT" | awk '/Device/{p=1;next} p && NF>0{sum+=$NF; count++} END{if(count>0) print sum/count}')
        if [ -n "$avg_util" ]; then
            disk_util_score=$(normalize_score "$avg_util" 5 50 1) # 5% util = 10, 50% util = 0
        fi
    fi

    # --- Network Scoring ---
    if [ -n "$NET_PING_OUTPUT" ]; then
        local avg_latency=$(echo "$NET_PING_OUTPUT" | grep "rtt min/avg/max/mdev" | awk -F'/' '{print $5}')
        local packet_loss=$(echo "$NET_PING_OUTPUT" | grep "packet loss" | awk -F', ' '{print $3}' | awk '{print $1}' | sed 's/%//')

        if [ -n "$avg_latency" ]; then
            net_latency_score=$(normalize_score "$avg_latency" 20 200 1) # 20ms = 10, 200ms = 0
        fi
        if [ -n "$packet_loss" ]; then
            net_packet_loss_score=$(normalize_score "$packet_loss" 0 10 1) # 0% loss = 10, 10% loss = 0
        fi
    fi

    # --- Combine Scores ---
    local total_metrics=7 # Number of metrics being scored
    local sum_scores=$(echo "scale=2; $cpu_idle_score + $cpu_load_score + $mem_free_score + $swap_used_score + $disk_util_score + $net_latency_score + $net_packet_loss_score" | bc -l)
    local overall_score=$(echo "scale=2; $sum_scores / $total_metrics" | bc -l)

    log_file "\n--- Individual Metric Scores ---"
    log_file "CPU Idle Score: $(printf \"%.2f\" \"$cpu_idle_score\")"
    log_file "CPU Load Score: $(printf \"%.2f\" \"$cpu_load_score\")"
    log_file "Memory Free Score: $(printf \"%.2f\" \"$mem_free_score\")"
    log_file "Swap Used Score: $(printf \"%.2f\" \"$swap_used_score\")"
    log_file "Disk Utilization Score: $(printf \"%.2f\" \"$disk_util_score\")"
    log_file "Network Latency Score: $(printf \"%.2f\" \"$net_latency_score\")"
    log_file "Network Packet Loss Score: $(printf \"%.2f\" \"$net_packet_loss_score\")"
    log_file "\nOverall Performance Score: $(printf \"%.2f\" \"$overall_score\") / 10.0"

    log_console "Overall Performance Score: ${GREEN}$(printf \"%.2f\" \"$overall_score\")/10.0${NC}" "INFO"
}


# display_menu: Shows the main menu options to the user.
display_menu() {
    echo -e "
${BLUE}--- System Performance Diagnostics ---${NC}"
    echo -e "1. Run All Diagnostics"
    echo -e "2. CPU Diagnostics"
    echo -e "3. Memory Diagnostics"
    echo -e "4. Disk I/O Diagnostics"
    echo -e "5. Network Diagnostics"
    echo -e "6. Process Analysis"
    echo -e "0. Exit"
    echo -e "${BLUE}------------------------------------${NC}"
}

# get_user_choice: Prompts the user for their menu selection.
get_user_choice() {
    read -p "Enter your choice: " choice
}

# main: The main execution flow of the script.
main() {
    start_logging
    check_dependencies

    while true; do
        display_menu
        get_user_choice
        case "$choice" in
            1)
                log_console "Running all diagnostics..." "INFO"
                run_cpu_diagnostics
                run_memory_diagnostics
                run_disk_diagnostics
                run_network_diagnostics
                run_process_diagnostics
                calculate_performance_score
                # Add calls to other diagnostic functions here as they are implemented
                ;;
            2) run_cpu_diagnostics ;; 
            3) run_memory_diagnostics ;; 
            4) run_disk_diagnostics ;; 
            5) run_network_diagnostics ;; 
            6) run_process_diagnostics ;; 
            0) break ;; 
            *) log_console "Invalid choice. Please try again." "ERROR" ;; 
        esac
    done

    stop_logging
}

# Execute the main function
main
