#!/bin/bash

# Configuration
CONFIG_DIR="/etc/speech-dispatcher"
CONFIG_FILE="$CONFIG_DIR/speechd.conf"
MODULES_DIR="$CONFIG_DIR/modules"
BACKUP_DIR="$HOME/.speech-dispatcher-backup"
LOG_FILE="$BACKUP_DIR/speechd_config.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize
init_backup() {
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"
    echo "$(date) - Speech Dispatcher Config Tool started" >> "$LOG_FILE"
}

# Backup original config
backup_config() {
    local timestamp=$(date +%Y%m%d%H%M%S)
    local backup_file="$BACKUP_DIR/speechd.conf.$timestamp"

    if [ -f "$CONFIG_FILE" ]; then
        sudo cp "$CONFIG_FILE" "$backup_file"
        echo "$(date) - Config backed up to $backup_file" >> "$LOG_FILE"
        echo -e "${GREEN}Backup created:${NC} $backup_file"
    else
        echo -e "${RED}Error: Config file not found at $CONFIG_FILE${NC}"
        return 1
    fi
}

# List all available modules
list_modules() {
    echo -e "${BLUE}Available Speech Dispatcher Modules:${NC}"
    echo "---------------------------------"

    if [ -d "$MODULES_DIR" ]; then
        find "$MODULES_DIR" -name '*.conf' -exec basename {} \; | sed 's/\.conf$//' | sort | column
    else
        echo -e "${RED}Modules directory not found: $MODULES_DIR${NC}"
    fi

    echo -e "\n${YELLOW}Currently enabled modules:${NC}"
    grep -E '^AddModule' "$CONFIG_FILE" 2>/dev/null || echo "None configured"
}

# Show current configuration
show_config() {
    echo -e "${BLUE}Current Speech Dispatcher Configuration:${NC}"
    echo "----------------------------------------"

    echo -e "${YELLOW}Main Settings:${NC}"
    grep -E '^(Default|Language|Audio|Log)' "$CONFIG_FILE" 2>/dev/null

    echo -e "\n${YELLOW}Module Settings:${NC}"
    grep -E '^(AddModule|Module)' "$CONFIG_FILE" 2>/dev/null

    echo -e "\n${YELLOW}Output Modules:${NC}"
    speech-dispatcher -L 2>/dev/null || echo "Unable to list output modules"
}

# Change default module
set_default_module() {
    local modules=($(find "$MODULES_DIR" -name '*.conf' -exec basename {} \; | sed 's/\.conf$//'))

    echo -e "${BLUE}Select Default Module:${NC}"
    select module in "${modules[@]}" "Cancel"; do
        if [ "$module" == "Cancel" ]; then
            return
        elif [[ " ${modules[@]} " =~ " ${module} " ]]; then
            backup_config
            sudo sed -i "/^DefaultModule/c\DefaultModule $module" "$CONFIG_FILE"
            echo -e "${GREEN}Default module set to:${NC} $module"
            echo "$(date) - Default module changed to $module" >> "$LOG_FILE"
            break
        else
            echo -e "${RED}Invalid selection${NC}"
        fi
    done
}

# Toggle logging
toggle_logging() {
    local current_log=$(grep '^LogLevel' "$CONFIG_FILE" | awk '{print $2}')
    local new_log

    case "$current_log" in
        "NONE") new_log="DEBUG" ;;
        "DEBUG") new_log="NONE" ;;
        *) new_log="DEBUG" ;;
    esac

    backup_config
    sudo sed -i "/^LogLevel/c\LogLevel $new_log" "$CONFIG_FILE"
    echo -e "${GREEN}Logging set to:${NC} $new_log"
    echo "$(date) - Logging level changed to $new_log" >> "$LOG_FILE"
}

# Test speech output
test_speech() {
    echo -e "${BLUE}Speech Test Interface${NC}"
    echo "---------------------"

    while true; do
        read -p "Enter text to speak (or 'q' to quit): " text
        if [ "$text" == "q" ]; then
            break
        fi
        spd-say "$text"
    done
}

# Advanced module configuration
configure_module() {
    local modules=($(find "$MODULES_DIR" -name '*.conf' -exec basename {} \; | sed 's/\.conf$//'))

    echo -e "${BLUE}Select Module to Configure:${NC}"
    select module in "${modules[@]}" "Cancel"; do
        if [ "$module" == "Cancel" ]; then
            return
        elif [[ " ${modules[@]} " =~ " ${module} " ]]; then
            local module_conf="$MODULES_DIR/$module.conf"
            echo -e "\n${YELLOW}Current configuration for $module:${NC}"
            grep -v '^#' "$module_conf" | grep -v '^$'

            echo -e "\n${BLUE}Options:${NC}"
            select action in "Edit Config" "View Defaults" "Test Module" "Back"; do
                case $REPLY in
                    1)
                        if [ -w "$module_conf" ]; then
                            ${EDITOR:-nano} "$module_conf"
                        else
                            sudo ${EDITOR:-nano} "$module_conf"
                        fi
                        ;;
                    2)
                        echo -e "\n${YELLOW}Default configuration options:${NC}"
                        grep '^#' "$module_conf" | sed 's/^#//'
                        ;;
                    3)
                        echo -e "\n${YELLOW}Testing $module:${NC}"
                        spd-say -o "$module" "Testing the $module output module"
                        ;;
                    4)
                        break
                        ;;
                    *)
                        echo -e "${RED}Invalid option${NC}"
                        ;;
                esac
            done
            break
        else
            echo -e "${RED}Invalid selection${NC}"
        fi
    done
}

# Main menu
main_menu() {
    while true; do
        echo -e "\n${BLUE}Speech Dispatcher Configuration Tool${NC}"
        echo "----------------------------------"
        echo "1. Show Current Configuration"
        echo "2. List Available Modules"
        echo "3. Set Default Module"
        echo "4. Toggle Debug Logging"
        echo "5. Configure Specific Module"
        echo "6. Test Speech Output"
        echo "7. Restart Speech Dispatcher"
        echo "8. View Configuration Files"
        echo "9. Exit"
        echo -n "Select an option (1-9): "

        read choice
        case $choice in
            1) show_config ;;
            2) list_modules ;;
            3) set_default_module ;;
            4) toggle_logging ;;
            5) configure_module ;;
            6) test_speech ;;
            7)
                echo -e "${YELLOW}Restarting speech-dispatcher...${NC}"
                sudo systemctl restart speech-dispatcher
                ;;
            8)
                echo -e "${YELLOW}Configuration files in $CONFIG_DIR:${NC}"
                find "$CONFIG_DIR" -type f -name "*.conf" -exec ls -lh {} \;
                ;;
            9) exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

# Check if speech-dispatcher is installed
if ! command -v speech-dispatcher &> /dev/null; then
    echo -e "${RED}Error: speech-dispatcher is not installed${NC}"
    echo "Install it with: sudo apt install speech-dispatcher"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${YELLOW}Note: Some operations may require sudo privileges${NC}"
fi

init_backup
main_menu
