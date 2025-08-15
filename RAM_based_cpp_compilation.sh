#!/bin/bash

# ===================================================================================
#
#           GGUF Transcriber Enabler - The Ultimate Archival Installer
#                (Definitive Edition - Hardened & Optimized)
#
# ===================================================================================
#
# PURPOSE:
# This script provides a hyper-robust, automated solution for installing the
# `whisper-cpp-python` library, specifically designed to overcome known compilation
# issues while adhering to the strictest hardware protection and performance principles.
#
# KEY FEATURES & IMPERATIVES (DEFINITIVE):
#
# 1. ULTIMATE HARDWARE PROTECTION (Source & Build in RAM):
#    The source code is downloaded and patched in RAM. The compilation process itself
#    (which can be I/O intensive) is also encouraged to happen in RAM.
#
# 2. MAXIMIZED CPU PERFORMANCE (Parallel & Native Compilation):
#    - High-Priority Execution: `nice` and `ionice` give the build maximum OS priority.
#    - Optimization Flags: Uses environment variables to instruct the build system
#      to use all CPU threads, enable GPU support, and optimize for the native CPU.
#
# 3. ROBUST BUILD PROCESS:
#    - Lets `pip` handle its own build-time dependency resolution (PEP 517), which is
#      more robust than manually specifying them.
#    - Archives the final, optimized .whl package for instant re-use.
#
# 4. BULLETPROOF VERIFICATION:
#    - Correctly tests the final installed package from a neutral directory.
#
# ===================================================================================

# --- Script Configuration ---
TARGET_VENV_PYTHON="/usr/share/piper-tts-vosk-asr-models/_voice_dev/voice_venv/bin/python"
PERSISTENT_WHEEL_DIR="$HOME/compiled_python_wheels"
RAMDISK_MOUNT_POINT="/mnt/ramdisk_build"
RAMDISK_SIZE="4G"

# --- Helper Functions ---
function print_step { echo -e "\n\e[1;34m============================================================\n  STEP: $1\n============================================================\e[0m"; }
function print_info { echo "  [INFO] $1"; }
function print_success {
    local message=$1
    local duration=$2
    if [ -n "$duration" ]; then
        echo -e "  \e[1;32m[SUCCESS]\e[0m $message (Took: $(format_duration "$duration"))"
    else
        echo -e "  \e[1;32m[SUCCESS]\e[0m $message"
    fi
}
function print_error { echo -e "  \e[1;31m[ERROR]\e[0m $1" >&2; exit 1; }
function cleanup {
    cd /tmp
    print_step "Performing Cleanup"
    if mountpoint -q "$RAMDISK_MOUNT_POINT"; then
        sudo umount -l "$RAMDISK_MOUNT_POINT" || print_info "Lazy unmount may have had issues."
    fi
    if [ -d "$RAMDISK_MOUNT_POINT" ]; then
        sudo rmdir "$RAMDISK_MOUNT_POINT" 2>/dev/null || true
    fi
    print_success "Cleanup complete."
}
function format_duration {
    local seconds=$1
    if (( seconds < 0 )); then seconds=0; fi
    local minutes=$((seconds / 60))
    local remaining_seconds=$((seconds % 60))
    printf "%dm %ds" "$minutes" "$remaining_seconds"
}


# --- Script Execution ---
set -e
trap cleanup EXIT
SCRIPT_START_TIME=$(date +%s)

print_step "Starting the Ultimate Reinforced Installer"
if ! sudo -v; then print_error "Sudo password entry failed. Aborting."; fi

# --- Phase 0: Prerequisite & Cache Cleaning ---
print_step "Checking Dependencies & Purging Caches"
PACKAGES_TO_CHECK="build-essential cmake opencl-headers ocl-icd-opencl-dev ninja-build"
MISSING_PACKAGES=""
for pkg in $PACKAGES_TO_CHECK; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        MISSING_PACKAGES="$MISSING_PACKAGES $pkg"
    fi
done
if [ -n "$MISSING_PACKAGES" ]; then
    print_error "Missing required packages:$MISSING_PACKAGES."
else
    print_success "All build dependencies are present."
fi
print_info "Purging pip cache to ensure a true from-scratch build..."
"$TARGET_VENV_PYTHON" -m pip cache purge >/dev/null
print_success "Pip cache purged."

# --- Phase 1: Check for Pre-Built Archived Wheel ---
print_step "Checking for a Pre-Built, Reusable Package"
mkdir -p "$PERSISTENT_WHEEL_DIR"
FOUND_WHEEL=$(find "$PERSISTENT_WHEEL_DIR" -name "whisper_cpp_python-*.whl" -print -quit)

if [ -n "$FOUND_WHEEL" ]; then
    print_success "Found an archived package: $(basename "$FOUND_WHEEL")"
    read -p "Do you want to (I)nstall this package, (R)ebuild from scratch, or (A)bort? [I/r/a] " choice
    case "$choice" in
        i|I|"" )
            print_step "Installing from Archived Package (Fast Path)"
            INSTALL_START_TIME=$(date +%s)
            "$TARGET_VENV_PYTHON" -m pip install "$FOUND_WHEEL" --no-cache-dir --force-reinstall --progress-bar off
            INSTALL_DURATION=$(( $(date +%s) - INSTALL_START_TIME ))
            print_success "Installation from archive complete!" "$INSTALL_DURATION"
            print_step "Verifying Installation"
            cd /tmp
            VERIFICATION_CMD="import whisper_cpp_python; info = whisper_cpp_python.get_system_info(); assert info.get('opencl') == True, 'OpenCL support is not True in system info'; print(f'Verification successful: {info}')"
            if ! "$TARGET_VENV_PYTHON" -c "$VERIFICATION_CMD"; then
                 print_error "VERIFICATION FAILED! The archived library does not report OpenCL support. Please rebuild."
            fi
            print_success "VERIFICATION PASSED! Archived package is GPU-ready."
            exit 0
            ;;
        r|R ) print_info "User selected to rebuild. Proceeding with a full, reinforced build...";;
        * ) print_info "Aborting script."; exit 1;;
    esac
else
    print_info "No pre-built package found. A one-time full compilation is required."
fi

# --- Phase 2: Setup In-Memory Source Directory ---
print_step "Setting up In-Memory Source Directory"
PHASE_START_TIME=$(date +%s)
sudo mkdir -p "$RAMDISK_MOUNT_POINT"
if ! mountpoint -q "$RAMDISK_MOUNT_POINT"; then
    sudo mount -t tmpfs -o size=$RAMDISK_SIZE,noatime tmpfs "$RAMDISK_MOUNT_POINT"
fi
PHASE_DURATION=$(( $(date +%s) - PHASE_START_TIME ))
print_success "RAM disk for source code is active." "$PHASE_DURATION"

# --- Phase 3: Download and Patch Source in RAM ---
print_step "Downloading and Patching Source Code (in RAM)"
PHASE_START_TIME=$(date +%s)
cd "$RAMDISK_MOUNT_POINT"
# We only use pip from the TARGET VENV now. It will handle its own build dependencies.
"$TARGET_VENV_PYTHON" -m pip download --no-deps --no-binary :all: whisper-cpp-python --no-cache-dir --progress-bar off
PACKAGE_ARCHIVE=$(ls whisper_cpp_python-*.tar.gz)
tar -xvf "$PACKAGE_ARCHIVE" > /dev/null
SOURCE_DIR=$(ls -d whisper_cpp_python-*/)
BROKEN_CMAKE_FILE="${SOURCE_DIR}vendor/whisper.cpp/CMakeLists.txt"
NEW_CMAKE_VERSION="3.13"
sed -i "/^cmake_minimum_required/c\cmake_minimum_required(VERSION ${NEW_CMAKE_VERSION})" "$BROKEN_CMAKE_FILE"
if ! grep -q "cmake_minimum_required(VERSION ${NEW_CMAKE_VERSION})" "$BROKEN_CMAKE_FILE"; then
    print_error "PATCH FAILED! The CMakeLists.txt file could not be updated. Aborting."
fi
PHASE_DURATION=$(( $(date +%s) - PHASE_START_TIME ))
print_success "Source code is patched and ready." "$PHASE_DURATION"

# --- Phase 4: Build the Wheel with ALL Reinforcements ---
print_step "STAGE 1/2: Building the Python Wheel from Patched Source"
cd "$SOURCE_DIR"
PHASE_START_TIME=$(date +%s)
export CFLAGS="-O3 -march=native -flto"
export CXXFLAGS="-O3 -march=native -flto"
export CMAKE_ARGS="-DWHISPER_OPENCL=ON -DWHISPER_LTO=ON"
export MAX_JOBS=$(nproc)
print_info "Applying build reinforcements:"
print_info "  - CPU Threads: $MAX_JOBS, GPU Backend: OpenCL, CPU Arch: native"
print_info "Launching build... Pip will now download build tools to a temporary location."
print_info "This may take a moment, then the main compilation will start."
# Use the TARGET VENV pip. It will create its own isolated build environment.
# Our environment variables will be passed to it automatically.
sudo nice -n -10 ionice -c 1 -n 0 "$TARGET_VENV_PYTHON" -m pip wheel . --no-deps -w . --no-cache-dir --progress-bar off
unset CFLAGS CXXFLAGS CMAKE_ARGS MAX_JOBS
BUILT_WHEEL=$(find . -maxdepth 1 -name "whisper_cpp_python-*.whl")
if [ -z "$BUILT_WHEEL" ]; then
    print_error "Build succeeded but could not find the compiled .whl file."
fi
PHASE_DURATION=$(( $(date +%s) - PHASE_START_TIME ))
print_success "Successfully built the reinforced package: $(basename "$BUILT_WHEEL")" "$PHASE_DURATION"

# --- Phase 5: Secure the Compilation Product ---
print_step "Archiving the Compiled Product for Future Use"
cp "$BUILT_WHEEL" "$PERSISTENT_WHEEL_DIR/"
print_success "Package secured: $(basename "$BUILT_WHEEL")"

# --- Phase 6: Install the Custom-Built Wheel into Target VENV ---
print_step "STAGE 2/2: Installing the Custom-Built, GPU-Enabled Wheel"
PHASE_START_TIME=$(date +%s)
"$TARGET_VENV_PYTHON" -m pip install "$PERSISTENT_WHEEL_DIR/$(basename "$BUILT_WHEEL")" --no-cache-dir --force-reinstall --progress-bar off
PHASE_DURATION=$(( $(date +%s) - PHASE_START_TIME ))
print_success "The final package and its dependencies are installed." "$PHASE_DURATION"

# --- Phase 7: Verification ---
print_step "Final Verification"
print_info "Changing to a neutral directory for testing..."
cd /tmp
print_info "Ensuring the library can be imported and reports OpenCL support..."
VERIFICATION_CMD="import whisper_cpp_python; info = whisper_cpp_python.get_system_info(); assert info.get('opencl') == True, 'OpenCL support is not True in system info'; print(f'Verification successful: {info}')"
if ! "$TARGET_VENV_PYTHON" -c "$VERIFICATION_CMD"; then
    print_error "VERIFICATION FAILED! The library was installed, but could not be imported or does not report OpenCL support."
fi
print_success "VERIFICATION PASSED! The library is correctly installed and GPU-ready."

# --- Done ---
TOTAL_DURATION=$(( $(date +%s) - SCRIPT_START_TIME ))
echo ""
echo -e "\e[1;32m============================================================\e[0m"
echo -e "\e[1;32m                 MISSION ACCOMPLISHED - DEFINITIVE               \e[0m"
echo -e "\e[1;32m============================================================\e[0m"
echo "The GGUF enabler 'whisper-cpp-python' has been successfully compiled and installed."
echo ""
echo -e "Total script execution time: \e[1;32m$(format_duration "$TOTAL_DURATION")\e[0m"
echo ""

exit 0
