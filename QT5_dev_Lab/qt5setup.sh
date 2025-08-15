#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check if a package is installed
is_pkg_installed() {
    dpkg -l "$1" &> /dev/null
    return $?
}

# Function to install packages with confirmation
install_packages() {
    local packages=("$@")
    echo -e "${YELLOW}The following packages will be installed:${NC}"
    printf '  - %s\n' "${packages[@]}"
    read -p "Proceed? [Y/n] " reply
    if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then
        sudo apt install -y "${packages[@]}"
        return $?
    else
        echo -e "${RED}Installation skipped.${NC}"
        return 1
    fi
}

# Update system
echo -e "${GREEN}Updating package lists...${NC}"
sudo apt update

# Check and install build essentials (gcc, g++, make, etc.)
echo -e "${GREEN}Checking for build tools...${NC}"
build_tools=("build-essential" "cmake" "g++" "gdb" "git")
missing_build_tools=()
for pkg in "${build_tools[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_build_tools+=("$pkg")
    fi
done

if [ ${#missing_build_tools[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing build tools detected.${NC}"
    install_packages "${missing_build_tools[@]}"
else
    echo -e "${GREEN}All required build tools are already installed.${NC}"
fi

# Check and install Qt5 packages
echo -e "${GREEN}Checking for Qt5 development packages...${NC}"
qt5_packages=(
    "qt5-default"
    "qtbase5-dev"
    "qttools5-dev"
    "qtdeclarative5-dev"
    "qtmultimedia5-dev"
    "libqt5svg5-dev"
    "libqt5websockets5-dev"
    "qtcreator"
)
missing_qt5_packages=()
for pkg in "${qt5_packages[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_qt5_packages+=("$pkg")
    fi
done

if [ ${#missing_qt5_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing Qt5 packages detected.${NC}"
    install_packages "${missing_qt5_packages[@]}"
else
    echo -e "${GREEN}All required Qt5 packages are already installed.${NC}"
fi

# Optional: Install additional Qt modules
echo -e "${GREEN}Would you like to install optional Qt5 modules?${NC}"
optional_packages=(
    "libqt5serialport5-dev"
    "qtconnectivity5-dev"
    "qtpositioning5-dev"
    "qtscript5-dev"
    "qtwebengine5-dev"
)
missing_optional_packages=()
for pkg in "${optional_packages[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_optional_packages+=("$pkg")
    fi
done

if [ ${#missing_optional_packages[@]} -gt 0 ]; then
    echo -e "${YELLOW}The following optional Qt5 modules are available:${NC}"
    printf '  - %s\n' "${missing_optional_packages[@]}"
    read -p "Install optional modules? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        install_packages "${missing_optional_packages[@]}"
    else
        echo -e "${YELLOW}Skipping optional modules.${NC}"
    fi
else
    echo -e "${GREEN}All optional Qt5 modules are already installed.${NC}"
fi

# Verify Qt Creator setup
echo -e "${GREEN}Checking Qt Creator installation...${NC}"
if ! command -v qtcreator &> /dev/null; then
    echo -e "${RED}Qt Creator is not installed correctly.${NC}"
    echo -e "${YELLOW}Try reinstalling it manually: 'sudo apt install --reinstall qtcreator'${NC}"
else
    echo -e "${GREEN}Qt Creator is installed.${NC}"
fi

# Final check: Test qmake
echo -e "${GREEN}Checking qmake...${NC}"
if ! command -v qmake &> /dev/null; then
    echo -e "${RED}qmake is missing! Qt development may not work properly.${NC}"
    echo -e "${YELLOW}Try reinstalling qt5-default: 'sudo apt install --reinstall qt5-default'${NC}"
else
    echo -e "${GREEN}qmake is available at: $(which qmake)${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Qt5 Development Setup Complete ===${NC}"
echo -e "Installed:"
echo -e "  - Qt5 libraries & tools"
echo -e "  - Qt Creator IDE"
echo -e "  - Build essentials (gcc, g++, make, etc.)"
echo -e "\nTo start developing:"
echo -e "  1. Launch Qt Creator: ${YELLOW}qtcreator${NC}"
echo -e "  2. Create a new Qt Widgets project."
echo -e "  3. Build & run to test your setup."
echo -e "\n${GREEN}Happy coding with Qt5! 🚀${NC}"
