#!/bin/bash

# --- Diagnostic Script for VSCode/GitHub User Mismatch ---
# Generates detailed log of environment, permissions, and configurations
# Output: diagnostic_log_<timestamp>.txt in current directory

# --- Initialize Log File ---
LOG_FILE="diagnostic_log_$(date +%Y%m%d_%H%M%S).txt"
{
echo "=== Diagnostic Report: $(date) ==="
echo "System: $(uname -a)"
echo "User: $USER (UID: $(id -u), GID: $(id -g))"
echo "Groups: $(groups)"
echo "--------------------------------------------"
} | tee "$LOG_FILE"

# --- Interactive Confirmation ---
read -p "Collect system/VSCode/Git configs? (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Diagnostics canceled by user" | tee -a "$LOG_FILE"
    exit 0
fi

# --- Core Diagnostics ---
{
echo "===== [1] VSCode Configurations ====="
echo "VSCode Install Path: $(which code 2>/dev/null || echo 'Not in PATH')"

# VSCode settings.json
find ~/.config -ipath '*Code*/User/settings.json' -exec echo -e "\nFound settings.json: {}\nContents:" \; \
    -exec grep -vE '//|^$' {} \; 2>/dev/null

echo -e "\n===== [2] Git Configurations ====="
echo "-- Global --"
git config --global --list 2>/dev/null
echo -e "\n-- Local (~/Development) --"
[ -d ~/Development ] && git -C ~/Development config --local --list 2>/dev/null || echo "No ~/Development directory"

echo -e "\n===== [3] SSH Configurations ====="
echo "SSH Keys:"
ls -l ~/.ssh/id_* 2>/dev/null
echo -e "\n~/.ssh/config:"
[ -f ~/.ssh/config ] && cat ~/.ssh/config || echo "No SSH config"

echo -e "\n===== [4] File Permissions ====="
echo "-- Project Directory Permissions --"
ls -ld ~/Development
echo -e "\n-- Contents Permissions --"
find ~/Development -maxdepth 1 -printf "%m %u %g %p\n" 2>/dev/null

echo -e "\n===== [5] GitHub Auth Status ====="
ssh -T git@github.com 2>&1
} | tee -a "$LOG_FILE"

# --- VSCode Extension Check ---
if command -v code &>/dev/null; then
    echo -e "\n===== [6] VSCode Extensions =====" | tee -a "$LOG_FILE"
    code --list-extensions | tee -a "$LOG_FILE"
else
    echo -e "\nVSCode CLI not found. Skipping extension check" | tee -a "$LOG_FILE"
fi

# --- Analysis Summary ---
{
echo -e "\n===== DIAGNOSTIC SUMMARY ====="
echo "Check these common mismatch points:"
echo "1. Git global.name/email vs GitHub username"
echo "2. SSH key used in ~/.ssh/config vs GitHub account"
echo "3. VSCode 'git.user.name' setting in settings.json"
echo "4. Project ownership (should be $USER)"
echo -e "\nFull log saved to: $PWD/$LOG_FILE"
} | tee -a "$LOG_FILE"
