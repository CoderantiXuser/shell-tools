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

echo -e "${GREEN}=== Setting Up Qt5 Development Kits & Tools ===${NC}"

# Update system
sudo apt update

# -----------------------------------------------------------------------------
# 1. Install Compilers (Kits)
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking compilers...${NC}"
compilers=(
    "gcc"           # C compiler
    "g++"           # C++ compiler
    "clang"         # LLVM Clang (optional)
    "build-essential"
)
missing_compilers=()
for pkg in "${compilers[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_compilers+=("$pkg")
    fi
done

if [ ${#missing_compilers[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing compilers:${NC}"
    install_packages "${missing_compilers[@]}"
else
    echo -e "${GREEN}All compilers are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 2. Install Debuggers & Profilers
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking debuggers...${NC}"
debuggers=(
    "gdb"           # GNU Debugger
    "valgrind"      # Memory leak detector
    "cmake"         # Build system
)
missing_debuggers=()
for pkg in "${debuggers[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_debuggers+=("$pkg")
    fi
done

if [ ${#missing_debuggers[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing debug tools:${NC}"
    install_packages "${missing_debuggers[@]}"
else
    echo -e "${GREEN}All debug tools are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 3. Install Qt Creator Plugins (via apt)
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking Qt Creator plugins...${NC}"
qt_plugins=(
    "qtcreator-plugin-clang"     # Clang code model
    "qtcreator-plugin-cmake"     # CMake integration
    "qtcreator-plugin-valgrind"  # Valgrind support
    "qtcreator-plugin-ubuntu"    # Ubuntu-specific (useful for deployment)
)
missing_plugins=()
for pkg in "${qt_plugins[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_plugins+=("$pkg")
    fi
done

if [ ${#missing_plugins[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing Qt Creator plugins:${NC}"
    install_packages "${missing_plugins[@]}"
else
    echo -e "${GREEN}All Qt Creator plugins are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 4. Install External Tools
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking external tools...${NC}"
external_tools=(
    "git"               # Version control
    "doxygen"           # Documentation generator
    "graphviz"          # Diagrams for Doxygen
    "qmlscene"          # QML runtime
    "qv4l2"             # Video4Linux2 tool (Qt Multimedia)
    "qdbusviewer"       # D-Bus debugger
)
missing_tools=()
for pkg in "${external_tools[@]}"; do
    if ! is_pkg_installed "$pkg"; then
        missing_tools+=("$pkg")
    fi
done

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing external tools:${NC}"
    install_packages "${missing_tools[@]}"
else
    echo -e "${GREEN}All external tools are installed.${NC}"
fi

# -----------------------------------------------------------------------------
# 5. Verify Qt Kits in Qt Creator
# -----------------------------------------------------------------------------
echo -e "${GREEN}Checking Qt Kits...${NC}"
if ! command -v qtcreator &> /dev/null; then
    echo -e "${RED}Qt Creator is not installed! Run the Qt5 setup script first.${NC}"
else
    echo -e "${GREEN}Launch Qt Creator and check:${NC}"
    echo -e "  1. Go to: ${YELLOW}Tools → Options → Kits${NC}"
    echo -e "  2. Ensure a ${YELLOW}Desktop Kit${NC} is auto-detected."
    echo -e "  3. Verify:"
    echo -e "     - Compiler: ${YELLOW}GCC (g++)${NC}"
    echo -e "     - Debugger: ${YELLOW}GDB${NC}"
    echo -e "     - Qt Version: ${YELLOW}Qt5 (qmake)${NC}"
fi

# -----------------------------------------------------------------------------
# 6. Install Documentation (Optional)
# -----------------------------------------------------------------------------
read -p "Install Qt documentation? [y/N] " reply
if [[ "$reply" =~ ^[Yy]$ ]]; then
    sudo apt install -y qt5-doc qtbase5-doc qtcreator-doc
    echo -e "${GREEN}Qt docs installed. Access via Qt Creator's Help menu.${NC}"
else
    echo -e "${YELLOW}Skipping documentation.${NC}"
fi

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
echo -e "\n${GREEN}=== Qt Development Environment Ready ===${NC}"
echo -e "Installed:"
echo -e "  - ${GREEN}Compilers (GCC, Clang)${NC}"
echo -e "  - ${GREEN}Debuggers (GDB, Valgrind)${NC}"
echo -e "  - ${GREEN}Qt Creator plugins (Clang, CMake, Valgrind)${NC}"
echo -e "  - ${GREEN}External tools (Git, Doxygen, QML runtime)${NC}"
echo -e "\nNext steps:"
echo -e "  1. Open Qt Creator: ${YELLOW}qtcreator${NC}"
echo -e "  2. Configure Kits (if not auto-detected)."
echo -e "  3. Start coding! 🎉"
