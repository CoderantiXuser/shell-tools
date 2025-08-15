#!/bin/bash

# Colors
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

echo -e "${GREEN}=== Setting Up Qt Development Environment ===${NC}"

# Update system (skip problematic repos)
sudo apt update --allow-insecure-repositories

# -----------------------------------------------------------------------------
# 1. Install Compilers & Debuggers
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking compilers and debuggers...${NC}"
tools=(
    "gcc"
    "g++"
    "clang"
    "build-essential"
    "gdb"
    "valgrind"
    "cmake"
)
missing_tools=()
for pkg in "${tools[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_tools+=("$pkg")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    install_packages "${missing_tools[@]}"
else
    echo -e "${GREEN}All compilers/debuggers are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Install Qt Creator (Debian's version)
# -----------------------------------------------------------------------------
if ! command -v qtcreator &> /dev/null; then
    echo -e "${YELLOW}Installing Qt Creator...${NC}"
    sudo apt install -y qtcreator
else
    echo -e "${GREEN}Qt Creator is already installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 3. Install External Tools
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking external tools...${NC}"
external_tools=(
    "git"
    "doxygen"
    "graphviz"
    "qmlscene"
)
missing_tools=()
for pkg in "${external_tools[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_tools+=("$pkg")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    install_packages "${missing_tools[@]}"
else
    echo -e "${GREEN}All external tools are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 4. Verify Qt Kits
# -----------------------------------------------------------------------------
echo -e "${GREEN}Verifying Qt Kits...${NC}"
if ! command -v qmake &> /dev/null; then
    echo -e "${RED}qmake is missing! Installing qt5-default...${NC}"
    sudo apt install -y qt5-default
fi

echo -e "${GREEN}Open Qt Creator and check:${NC}"
echo -e "  1. Go to: ${YELLOW}Tools → Options → Kits${NC}"
echo -e "  2. Ensure a ${YELLOW}Desktop Kit${NC} is detected."
echo -e "  3. Manually add plugins (Clang, CMake) if needed."

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}=== Setup Complete ===${NC}"
echo -e "Run Qt Creator: ${YELLOW}qtcreator${NC}"
