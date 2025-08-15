#!/bin/bash

# Configuration
LOG_FILE="talon_system_analysis_$(date +%Y%m%d_%H%M%S).log"
TALON_MIN_PYTHON="3.11"  # Minimum Python version required

# Create log file
exec > >(tee -a "$LOG_FILE") 2>&1

# Header
echo "=============================================="
echo " Talon Voice System Compatibility Analysis"
echo " Date: $(date)"
echo "=============================================="
echo ""

# Function to check command availability
check_command() {
    if command -v "$1" >/dev/null 2>&1; then
        echo "[✓] $1 found: $(command -v "$1")"
        return 0
    else
        echo "[✗] $1 not found"
        return 1
    fi
}

# Function to check package installation
check_package() {
    if dpkg -l | grep -q "$1"; then
        echo "[✓] Package installed: $1"
        return 0
    else
        echo "[✗] Package not found: $1"
        return 1
    fi
}

# Function to check audio device
check_audio_device() {
    echo ""
    echo "=== Audio Device Check ==="
    echo "ALSA Version: $(amixer --version | head -n1)"
    echo ""

    echo "Input Devices:"
    arecord -l | sed 's/^/  /'
    echo ""

    echo "Output Devices:"
    aplay -l | sed 's/^/  /'
    echo ""

    echo "Default Capture Device:"
    arecord -L default | head -n5 | sed 's/^/  /'
    echo ""

    echo "Default Playback Device:"
    aplay -L default | head -n5 | sed 's/^/  /'
    echo ""

    echo "Audio Groups:"
    grep -i audio /etc/group | sed 's/^/  /'
    echo ""

    echo "Current User in Audio Group:"
    if groups | grep -q '\baudio\b'; then
        echo "[✓] User $(whoami) is in 'audio' group"
    else
        echo "[✗] User $(whoami) is NOT in 'audio' group"
    fi
    echo ""
}

# Function to check Python
check_python() {
    echo ""
    echo "=== Python Check ==="
    if command -v python3 >/dev/null 2>&1; then
        python_version=$(python3 -c "import sys; print('.'.join(map(str, sys.version_info[:3])))")
        echo "Python Version: $python_version"

        if [ "$(printf '%s\n' "$TALON_MIN_PYTHON" "$python_version" | sort -V | head -n1)" = "$TALON_MIN_PYTHON" ]; then
            echo "[✓] Python version meets minimum requirement ($TALON_MIN_PYTHON)"
        else
            echo "[✗] Python version below minimum requirement ($TALON_MIN_PYTHON)"
        fi
    else
        echo "[✗] Python3 not found"
    fi
    echo ""
}

# Function to check display environment
check_display() {
    echo ""
    echo "=== Display Environment Check ==="
    echo "Display Manager: $(cat /etc/X11/default-display-manager 2>/dev/null || echo "Unknown")"
    echo "Current Desktop Session: $XDG_CURRENT_DESKTOP"
    echo "Window Manager:"
    wmctrl -m | sed 's/^/  /'
    echo ""

    echo "X11 Extensions:"
    xdpyinfo | grep "number of extensions" -A10 | sed 's/^/  /'
    echo ""

    echo "Input Devices:"
    xinput list | sed 's/^/  /'
    echo ""
}

# Function to check system info
check_system() {
    echo ""
    echo "=== System Information ==="
    echo "Distribution: $(lsb_release -d 2>/dev/null | cut -f2-)"
    echo "Kernel: $(uname -r)"
    echo "Architecture: $(uname -m)"
    echo "Available Memory: $(free -h | awk '/Mem:/ {print $2}')"
    echo ""
}

# Function to check Talon-specific dependencies
check_talon_deps() {
    echo ""
    echo "=== Talon Voice Dependencies Check ==="

    # Required libraries
    local required_libs=(
        "libx11" "libxext" "libxfixes" "libxrender" "libxcb"
        "libxkbcommon" "libasound2" "libpulse" "libdbus-1"
    )

    for lib in "${required_libs[@]}"; do
        if ldconfig -p | grep -q "$lib"; then
            echo "[✓] Library found: $lib"
        else
            echo "[✗] Library missing: $lib"
        fi
    done

    echo ""
    check_command "python3"
    check_command "pip3"
    check_command "arecord"
    check_command "aplay"
    check_command "wmctrl"
    check_command "xinput"
}

# Function to test microphone
test_microphone() {
    echo ""
    echo "=== Microphone Test ==="
    read -p "Would you like to test microphone recording? (y/n) " choice

    if [[ "$choice" =~ [yY] ]]; then
        TEST_FILE="talon_mic_test_$(date +%s).wav"
        echo "Recording for 3 seconds to $TEST_FILE..."
        arecord -d 3 -f cd "$TEST_FILE"

        read -p "Would you like to play back the recording? (y/n) " play_choice
        if [[ "$play_choice" =~ [yY] ]]; then
            aplay "$TEST_FILE"
            read -p "Did you hear the playback clearly? (y/n) " result
            if [[ "$result" =~ [yY] ]]; then
                echo "[✓] Microphone test successful"
            else
                echo "[✗] Microphone test failed - audio not clear"
            fi
            rm "$TEST_FILE"
        else
            echo "Recording saved to $TEST_FILE (not played back)"
        fi
    else
        echo "Skipped microphone test"
    fi
    echo ""
}

# Main execution
check_system
check_display
check_audio_device
check_python
check_talon_deps
test_microphone

echo ""
echo "Analysis complete. Full report saved to: $(pwd)/$LOG_FILE"
echo "You can review this file and share it for troubleshooting if needed."
