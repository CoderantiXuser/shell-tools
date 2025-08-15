#!/bin/bash

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to check Python module
is_python_module_installed() {
    python3 -c "import $1" &> /dev/null
    return $?
}

# Function to install packages with confirmation
install_packages() {
    local packages=("$@")
    echo -e "${YELLOW}The following packages will be installed:${NC}"
    printf '  - %s\n' "${packages[@]}"
    read -p "Proceed? [Y/n] " reply
    if [[ -z "$reply" || "$reply" =~ ^[Yy]$ ]]; then
        pip3 install --user "${packages[@]}"
        return $?
    else
        echo -e "${RED}Installation skipped.${NC}"
        return 1
    fi
}

echo -e "${GREEN}=== Setting up Python Qt Development ===${NC}"

# Check if Python3 and pip are installed
if ! command -v python3 &> /dev/null; then
    echo -e "${RED}Python3 is not installed. Installing...${NC}"
    sudo apt install -y python3 python3-pip
fi

if ! command -v pip3 &> /dev/null; then
    echo -e "${RED}pip3 is not installed. Installing...${NC}"
    sudo apt install -y python3-pip
fi

# Update pip
echo -e "${GREEN}Upgrading pip...${NC}"
pip3 install --user --upgrade pip

# Required Python modules for Qt
required_modules=(
    "PyQt5"
    "PyQt5-sip"
    "PyQt5-Qt5"
    "PyQt5-tools"
)

# Optional modules (useful for development)
optional_modules=(
    "PySide6"       # Alternative to PyQt5 (Qt6)
    "matplotlib"    # Plotting (often used with Qt)
    "numpy"         # Numerical operations
    "pandas"        # Data handling (optional)
    "qdarkstyle"    # Dark theme for Qt apps
)

# Check and install required modules
echo -e "${GREEN}Checking required Python modules...${NC}"
missing_modules=()
for module in "${required_modules[@]}"; do
    if ! is_python_module_installed "${module%%-*}"; then
        missing_modules+=("$module")
    fi
done

if [ ${#missing_modules[@]} -gt 0 ]; then
    echo -e "${YELLOW}Missing required Python modules:${NC}"
    printf '  - %s\n' "${missing_modules[@]}"
    install_packages "${missing_modules[@]}"
else
    echo -e "${GREEN}All required Python modules are already installed.${NC}"
fi

# Check and install optional modules
echo -e "${GREEN}Checking optional Python modules...${NC}"
missing_optional=()
for module in "${optional_modules[@]}"; do
    if ! is_python_module_installed "${module%%-*}"; then
        missing_optional+=("$module")
    fi
done

if [ ${#missing_optional[@]} -gt 0 ]; then
    echo -e "${YELLOW}Optional Python modules available:${NC}"
    printf '  - %s\n' "${missing_optional[@]}"
    read -p "Install optional modules? [y/N] " reply
    if [[ "$reply" =~ ^[Yy]$ ]]; then
        install_packages "${missing_optional[@]}"
    else
        echo -e "${YELLOW}Skipping optional modules.${NC}"
    fi
else
    echo -e "${GREEN}All optional Python modules are already installed.${NC}"
fi

# Verify PyQt5 installation
echo -e "${GREEN}Verifying PyQt5 installation...${NC}"
if ! is_python_module_installed "PyQt5"; then
    echo -e "${RED}PyQt5 is not installed correctly!${NC}"
    echo -e "${YELLOW}Try reinstalling: 'pip3 install --user --force-reinstall PyQt5 PyQt5-sip'${NC}"
else
    echo -e "${GREEN}PyQt5 is installed correctly.${NC}"
fi

# Check if Qt Designer is available (from pyqt5-tools)
if ! command -v pyqt5-tools &> /dev/null; then
    echo -e "${YELLOW}Qt Designer (pyqt5-tools) is not in PATH. Add it manually if needed.${NC}"
else
    echo -e "${GREEN}Qt Designer is available at: $(which designer)${NC}"
fi

# Summary
echo -e "\n${GREEN}=== Python Qt Development Setup Complete ===${NC}"
echo -e "Installed:"
echo -e "  - PyQt5 (Python Qt5 bindings)"
echo -e "  - PyQt5-sip (required for PyQt5)"
echo -e "  - PyQt5-tools (Qt Designer, etc.)"
echo -e "\nTo start developing:"
echo -e "  1. Write a Python Qt app (e.g., using PyQt5)."
echo -e "  2. Use Qt Designer (run 'designer') for GUI design."
echo -e "  3. Convert .ui files to Python: 'pyuic5 -x file.ui -o file.py'"
echo -e "\n${GREEN}Happy coding with Python and Qt! 🚀${NC}"
