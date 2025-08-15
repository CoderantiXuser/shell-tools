#!/bin/bash
echo "Restoring original system configuration..."
sudo apt remove --purge -y build-essential python3-pip cmake...
echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
unset OMP_NUM_THREADS
unset GGML_NUM_THREADS
