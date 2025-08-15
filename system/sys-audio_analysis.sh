#!/bin/bash

# This script performs a deep analysis of the audio system on a Linux machine.
# It gathers comprehensive information from various sources to help diagnose audio-related issues.
#
# Performed Tests and Information Gathered:
#
# 1. System Information:
#    - Hostname
#    - Kernel Version
#    - OS Distribution Details
#
# 2. ALSA (Advanced Linux Sound Architecture) Information:
#    - Available Playback Devices (aplay -l)
#    - Available Recording Devices (arecord -l)
#    - Sound Cards (cat /proc/asound/cards)
#    - ALSA Devices (cat /proc/asound/devices)
#    - ALSA Mixer Controls (amixer scontrols)
#    - ALSA Mixer Contents (amixer contents - detailed settings)
#
# 3. PulseAudio Information (if running):
#    - PulseAudio Server Information (pactl info)
#    - PulseAudio Sinks (Output Devices - pactl list sinks)
#    - PulseAudio Sources (Input Devices - pactl list sources)
#    - PulseAudio Sink Inputs (Application Playback Streams - pactl list sink-inputs)
#    - PulseAudio Source Outputs (Application Recording Streams - pactl list source-outputs)
#
# 4. Kernel Modules (Sound Related):
#    - Loaded Sound Modules (lsmod | grep snd)
#
# 5. /sys Filesystem Information (Sound Cards):
#    - Contents of /sys/class/sound
#    - Detailed information for each sound card in /sys/class/sound/card*
#    - Detailed information for sound-related modules in /sys/module/snd*
#
# 6. Hardware Information (Multimedia Devices):
#    - Multimedia Hardware details (lshw -C multimedia - requires 'lshw' to be installed)
#
# 7. Environment Variables (Relevant to Audio):
#    - Environment variables related to ALSA, PulseAudio, and general audio settings.
#
# All output is redirected to a log file named 'audio_analysis_YYYYMMDD_HHMMSS.log' in the current directory.

# Define the log file name with a timestamp
LOG_FILE="audio_analysis_$(date +%Y%m%d_%H%M%S).log"

echo "Starting deep audio analysis..."
echo "Log file: $LOG_FILE"
echo ""

# Redirect all subsequent output to the log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=========================================="
echo "Audio System Analysis - $(date)"
echo "=========================================="
echo ""

echo "--- System Information ---"
echo "Hostname: $(hostname)"
echo "Kernel: $(uname -a)"
if command -v lsb_release &> /dev/null; then
    echo "OS Distribution:"
    lsb_release -a
elif [ -f /etc/os-release ]; then
    echo "OS Distribution:"
    cat /etc/os-release
fi
echo ""

echo "--- ALSA (Advanced Linux Sound Architecture) Information ---"
echo "Available Playback Devices (aplay -l):"
aplay -l
echo ""

echo "Available Recording Devices (arecord -l):"
arecord -l
echo ""

echo "Sound Cards (cat /proc/asound/cards):"
cat /proc/asound/cards
echo ""

echo "ALSA Devices (cat /proc/asound/devices):"
cat /proc/asound/devices
echo ""

echo "ALSA Mixer Controls (amixer scontrols):"
amixer scontrols
echo ""

echo "ALSA Mixer Contents (amixer contents - detailed settings):"
# This can be very verbose, but provides all current ALSA settings
amixer contents
echo ""

echo "--- PulseAudio Information (if running) ---"
if command -v pactl &> /dev/null; then
    echo "PulseAudio Server Information (pactl info):"
    pactl info
    echo ""

    echo "PulseAudio Sinks (Output Devices - pactl list sinks):"
    pactl list sinks
    echo ""

    echo "PulseAudio Sources (Input Devices - pactl list sources):"
    pactl list sources
    echo ""

    echo "PulseAudio Sink Inputs (Application Playback Streams - pactl list sink-inputs):"
    pactl list sink-inputs
    echo ""

    echo "PulseAudio Source Outputs (Application Recording Streams - pactl list source-outputs):"
    pactl list source-outputs
    echo ""
else
    echo "PulseAudio not detected or 'pactl' command not found."
fi
echo ""

echo "--- Kernel Modules (Sound Related) ---"
echo "Loaded Sound Modules (lsmod | grep snd):"
lsmod | grep snd
echo ""

echo "--- /sys Filesystem Information (Sound Cards) ---"
if [ -d "/sys/class/sound" ]; then
    echo "Contents of /sys/class/sound:"
    ls -l /sys/class/sound
    echo ""

    for card_path in /sys/class/sound/card*; do
        if [ -d "$card_path" ]; then
            card_name=$(basename "$card_path")
            echo "Details for $card_name ($card_path):"
            find "$card_path" -maxdepth 2 -type f -print -exec cat {} \; 2>/dev/null
            echo "---"
        fi
    done
    echo ""
else
    echo "/sys/class/sound not found or accessible."
fi

if [ -d "/sys/module" ]; then
    echo "Sound-related modules in /sys/module:"
    for module_path in /sys/module/snd*; do
        if [ -d "$module_path" ]; then
            module_name=$(basename "$module_path")
            echo "Details for module $module_name ($module_path):"
            find "$module_path" -maxdepth 2 -type f -print -exec cat {} \; 2>/dev/null
            echo "---"
        fi
    done
    echo ""
else
    echo "/sys/module not found or accessible."
fi
echo ""

echo "--- Hardware Information (Multimedia Devices) ---"
if command -v lshw &> /dev/null; then
    echo "Multimedia Hardware (lshw -C multimedia):"
    sudo lshw -C multimedia
    echo ""
else
    echo "'lshw' command not found. Install 'lshw' for detailed hardware information (e.g., sudo apt install lshw)."
fi
echo ""

echo "--- Environment Variables (Relevant to Audio) ---"
echo "Relevant Environment Variables:"
env | grep -E "ALSA|PULSE|AUDIO|XDG_RUNTIME_DIR"
echo ""

echo "=========================================="
echo "Analysis Complete - $(date)"
echo "=========================================="
echo ""
echo "Output also saved to $LOG_FILE"
