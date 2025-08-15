#!/bin/bash

# Configuration
BACKUP_DIR="$HOME/llm_optimizer_backup_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="$BACKUP_DIR/optimization.log"
ROLLBACK_SCRIPT="$BACKUP_DIR/rollback.sh"

# Initialize
mkdir -p "$BACKUP_DIR"
touch "$LOG_FILE" "$ROLLBACK_SCRIPT"
chmod +x "$ROLLBACK_SCRIPT"

echo -e "\033[1;36mLocal LLM Optimization Wizard\033[0m"
echo -e "System Assessment Mode\n"

# --- Phase 1: System Assessment ---
function assess_system() {
    echo -e "\n\033[1;34m[SYSTEM ASSESSMENT]\033[0m" | tee -a "$LOG_FILE"

    # CPU
    CPU_FLAGS=$(grep -m1 "flags" /proc/cpuinfo)
    echo -e "\n\033[1;33mCPU Features:\033[0m" | tee -a "$LOG_FILE"
    echo "AVX:    $(grep -q "avx" <<< "$CPU_FLAGS" && echo "✅" || echo "❌")" | tee -a "$LOG_FILE"
    echo "AVX2:   $(grep -q "avx2" <<< "$CPU_FLAGS" && echo "✅" || echo "❌")" | tee -a "$LOG_FILE"
    echo "FMA:    $(grep -q "fma" <<< "$CPU_FLAGS" && echo "✅" || echo "❌")" | tee -a "$LOG_FILE"

    # Memory
    MEM_TOTAL=$(free -h | awk '/Mem/{print $2}')
    echo -e "\n\033[1;33mMemory:\033[0m $MEM_TOTAL" | tee -a "$LOG_FILE"

    # GPU
    echo -e "\n\033[1;33mGPU Detection:\033[0m" | tee -a "$LOG_FILE"
    if command -v nvidia-smi &>/dev/null; then
        nvidia-smi --query-gpu=name,memory.total --format=csv | tee -a "$LOG_FILE"
    else
        echo "No dedicated GPU detected" | tee -a "$LOG_FILE"
    fi

    # Storage
    echo -e "\n\033[1;33mStorage:\033[0m" | tee -a "$LOG_FILE"
    df -h --output=source,fstype,size,avail /home | tee -a "$LOG_FILE"
}

# --- Phase 2: Backup Current Config ---
function backup_config() {
    echo -e "\n\033[1;34m[BACKUP CURRENT CONFIG]\033[0m" | tee -a "$LOG_FILE"

    # Generate rollback script header
    echo '#!/bin/bash' > "$ROLLBACK_SCRIPT"
    echo 'echo "Restoring original system configuration..."' >> "$ROLLBACK_SCRIPT"

    # Backup kernel parameters
    sysctl -a > "$BACKUP_DIR/sysctl_backup.conf"
    echo 'sysctl --system >/dev/null 2>&1' >> "$ROLLBACK_SCRIPT"

    # Backup environment variables
    printenv > "$BACKUP_DIR/env_backup.txt"

    # Backup CPU governor
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > "$BACKUP_DIR/cpu_governor_backup.txt"
    fi

    echo -e "\n\033[1;32m✓ Backup created in $BACKUP_DIR\033[0m" | tee -a "$LOG_FILE"
}

# --- Phase 3: Optimization Menu ---
function optimization_menu() {
    while true; do
        echo -e "\n\033[1;34m[OPTIMIZATION OPTIONS]\033[0m"
        echo "1. Install Essential Packages"
        echo "2. Configure CPU Performance"
        echo "3. Setup RAM Disk"
        echo "4. Optimize Swappiness"
        echo "5. Install llama.cpp (AVX2 optimized)"
        echo "6. Apply All Optimizations"
        echo "7. View Current Recommendations"
        echo "8. Rollback Changes"
        echo "9. Exit"

        read -p "Select an option (1-9): " choice

        case $choice in
            1) install_packages ;;
            2) configure_cpu ;;
            3) setup_ramdisk ;;
            4) optimize_swappiness ;;
            5) install_llamacpp ;;
            6) apply_all_optimizations ;;
            7) show_recommendations ;;
            8) rollback_changes ;;
            9) exit 0 ;;
            *) echo "Invalid option" ;;
        esac
    done
}

# --- Optimization Functions ---
function install_packages() {
    echo -e "\n\033[1;34m[INSTALLING PACKAGES]\033[0m" | tee -a "$LOG_FILE"

    # Backup current packages
    dpkg --get-selections > "$BACKUP_DIR/package_backup.txt"

    # Install essential packages
    sudo apt update | tee -a "$LOG_FILE"
    sudo apt install -y build-essential python3-pip cmake libopenblas-dev \
                        git python3-virtualenv htop glances | tee -a "$LOG_FILE"

    # Add to rollback script
    echo 'sudo apt remove --purge -y build-essential python3-pip cmake libopenblas-dev git python3-virtualenv htop glances' >> "$ROLLBACK_SCRIPT"

    echo -e "\n\033[1;32m✓ Essential packages installed\033[0m" | tee -a "$LOG_FILE"
}

function configure_cpu() {
    echo -e "\n\033[1;34m[CONFIGURING CPU]\033[0m" | tee -a "$LOG_FILE"

    # Set performance governor
    if [ -f /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor ]; then
        echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | tee -a "$LOG_FILE"
        echo 'echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor' >> "$ROLLBACK_SCRIPT"
    fi

    # Set environment variables
    echo 'export OMP_NUM_THREADS=$(nproc)' >> ~/.bashrc
    echo 'export GGML_NUM_THREADS=$(nproc)' >> ~/.bashrc
    echo 'unset OMP_NUM_THREADS' >> "$ROLLBACK_SCRIPT"
    echo 'unset GGML_NUM_THREADS' >> "$ROLLBACK_SCRIPT"

    echo -e "\n\033[1;32m✓ CPU configured for performance\033[0m" | tee -a "$LOG_FILE"
}

function install_llamacpp() {
    echo -e "\n\033[1;34m[INSTALLING LLAMA.CPP]\033[0m" | tee -a "$LOG_FILE"

    # Clone and build based on CPU capabilities
    git clone https://github.com/ggerganov/llama.cpp || { echo "Clone failed" | tee -a "$LOG_FILE"; return 1; }
    cd llama.cpp

    # Determine optimal compile flags
    COMPILE_FLAGS=""
    grep -q "avx2" /proc/cpuinfo && COMPILE_FLAGS+="LLAMA_AVX2=1 "
    grep -q "fma" /proc/cpuinfo && COMPILE_FLAGS+="LLAMA_FMA=1 "

    echo "Building with flags: $COMPILE_FLAGS" | tee -a "$LOG_FILE"
    make clean && make $COMPILE_FLAGS -j$(nproc) | tee -a "$LOG_FILE"

    # Add to PATH
    echo "export PATH=\$PATH:$(pwd)" >> ~/.bashrc
    echo "cd $(pwd)" >> "$BACKUP_DIR/llamacpp_install_path.txt"

    echo -e "\n\033[1;32m✓ llama.cpp installed\033[0m" | tee -a "$LOG_FILE"
}

function show_recommendations() {
    echo -e "\n\033[1;34m[CURRENT RECOMMENDATIONS]\033[0m" | tee -a "$LOG_FILE"

    # CPU-based recommendations
    grep -q "avx2" /proc/cpuinfo && \
    echo "- Use AVX2 optimized builds (llama.cpp compiled with LLAMA_AVX2=1)" | tee -a "$LOG_FILE"

    # Memory recommendations
    MEM_AVAIL=$(free -m | awk '/Mem/{print $7}')
    if [ "$MEM_AVAIL" -lt 8000 ]; then
        echo "- Use quantized models (q4_0, q5_K_M) for <8GB available RAM" | tee -a "$LOG_FILE"
    fi

    # GPU check
    if ! command -v nvidia-smi &>/dev/null; then
        echo "- No NVIDIA GPU detected: Use CPU-only inference" | tee -a "$LOG_FILE"
        echo "- Consider GGUF format models for better CPU performance" | tee -a "$LOG_FILE"
    fi

    # Storage recommendations
    DISK_SPEED=$(dd if=/dev/zero of=/tmp/test bs=1M count=512 2>&1 | awk '/copied/{print $8 $9}')
    echo "- Disk speed: $DISK_SPEED (consider RAM disk for models)" | tee -a "$LOG_FILE"

    echo -e "\nFor best performance:" | tee -a "$LOG_FILE"
    echo "1. Use models matching your CPU capabilities" | tee -a "$LOG_FILE"
    echo "2. Quantize models to 4-bit or 5-bit" | tee -a "$LOG_FILE"
    echo "3. Limit context size based on available RAM" | tee -a "$LOG_FILE"
}

function setup_ramdisk() {
    echo -e "\n\033[1;34m[SETUP RAMDISK]\033[0m" | tee -a "$LOG_FILE"

    RAM_SIZE=$(free -m | awk '/Mem/{print int($2*0.7)}')
    echo "Creating RAM disk of ${RAM_SIZE}MB at /mnt/llm_ramdisk" | tee -a "$LOG_FILE"

    sudo mkdir -p /mnt/llm_ramdisk
    sudo mount -t tmpfs -o size=${RAM_SIZE}M tmpfs /mnt/llm_ramdisk

    # Add to fstab for persistence
    echo "tmpfs /mnt/llm_ramdisk tmpfs defaults,size=${RAM_SIZE}M 0 0" | sudo tee -a /etc/fstab

    # Add to rollback
    echo 'sudo sed -i "/llm_ramdisk/d" /etc/fstab' >> "$ROLLBACK_SCRIPT"
    echo 'sudo umount /mnt/llm_ramdisk' >> "$ROLLBACK_SCRIPT"

    echo -e "\n\033[1;32m✓ RAM disk created at /mnt/llm_ramdisk\033[0m" | tee -a "$LOG_FILE"
}

function optimize_swappiness() {
    echo -e "\n\033[1;34m[OPTIMIZE SWAPPINESS]\033[0m" | tee -a "$LOG_FILE"

    echo "Current swappiness: $(cat /proc/sys/vm/swappiness)" | tee -a "$LOG_FILE"
    echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
    sudo sysctl -p

    # Rollback entry
    echo 'sudo sed -i "/vm.swappiness/d" /etc/sysctl.conf' >> "$ROLLBACK_SCRIPT"
    echo 'sudo sysctl -p' >> "$ROLLBACK_SCRIPT"

    echo -e "\n\033[1;32m✓ Swappiness optimized (set to 10)\033[0m" | tee -a "$LOG_FILE"
}

function apply_all_optimizations() {
    install_packages
    configure_cpu
    setup_ramdisk
    optimize_swappiness
    install_llamacpp
}

function rollback_changes() {
    echo -e "\n\033[1;31m[ROLLING BACK CHANGES]\033[0m" | tee -a "$LOG_FILE"
    "$ROLLBACK_SCRIPT"
    echo -e "\n\033[1;32m✓ System restored from backup\033[0m" | tee -a "$LOG_FILE"
    exit 0
}
# ... (similar functions for other optimizations)

# --- Main Execution ---
assess_system
backup_config
optimization_menu
