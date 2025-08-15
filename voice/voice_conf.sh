#!/bin/bash

# Global Configuration
BACKUP_DIR="$HOME/.speech_synth_backup"
LOG_FILE="$BACKUP_DIR/configuration_changes.log"
declare -A ORIGINAL_CONFIGS
declare -A MODIFIED_CONFIGS

# Required Packages
REQUIRED_PKGS=(
    "rhvoice"
    "rhvoice-english"
    "speech-dispatcher"
    "speech-dispatcher-rhvoice"
    "espeak-ng"
    "festival"
)

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Helper Functions
init_backup_dir() {
    mkdir -p "$BACKUP_DIR"
    touch "$LOG_FILE"
}

log_action() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

backup_file() {
    local src=$1
    local backup="$BACKUP_DIR/$(basename "$src").bak.$(date +%s)"

    if [ -f "$src" ]; then
        sudo cp "$src" "$backup"
        ORIGINAL_CONFIGS["$src"]="$backup"
        log_action "Backed up: $src → $backup"
        echo "$backup"
    else
        log_action "Backup failed: $src not found"
        echo ""
    fi
}

# Dependency Management
verify_dependencies() {
    echo -e "${BLUE}=== Verifying Dependencies ===${NC}"
    local missing=()

    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! dpkg -l | grep -q " $pkg "; then
            missing+=("$pkg")
            echo -e "${RED}Missing: $pkg${NC}"
        else
            echo -e "${GREEN}Installed: $pkg${NC}"
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "\n${YELLOW}Missing packages detected!${NC}"
        read -p "Install missing packages? (y/N) " choice
        if [[ $choice =~ [Yy] ]]; then
            sudo apt update && sudo apt install -y "${missing[@]}"
            return $?
        else
            echo -e "${RED}Aborting: Required packages missing${NC}"
            exit 1
        fi
    fi
    return 0
}

# System Detection
detect_tts_systems() {
    echo -e "${BLUE}=== Detected TTS Systems ===${NC}"

    declare -A systems=(
        ["speech-dispatcher"]="/etc/speech-dispatcher"
        ["RHVoice"]="/usr/share/RHVoice"
        ["espeak-ng"]="/usr/share/espeak-ng"
        ["festival"]="/usr/share/festival"
    )

    for sys in "${!systems[@]}"; do
        if [ -d "${systems[$sys]}" ]; then
            echo -e "${GREEN}$sys:${NC}"
            echo "  Path: ${systems[$sys]}"

            case $sys in
                "speech-dispatcher")
                    echo "  Voices: $(spd-voices | grep -c 'Name:') available"
                    ;;
                "RHVoice")
                    echo "  Voices: $(RHVoice-list-voices | grep -c 'Voice:') available"
                    ;;
                "espeak-ng")
                    echo "  Voices: $(espeak-ng --voices | wc -l) available"
                    ;;
                "festival")
                    echo "  Voices: $(find /usr/share/festival/voices/ -mindepth 1 -maxdepth 1 -type d | wc -l) available"
                    ;;
            esac
        fi
    done
    echo ""
}

# Configuration Management
configure_speech_dispatcher() {
    local conf_file="/etc/speech-dispatcher/speechd.conf"
    local backup=$(backup_file "$conf_file")

    echo -e "${BLUE}Configuring Speech Dispatcher...${NC}"

    sudo sed -i '/^DefaultModule/c\DefaultModule rhvoice' "$conf_file"
    sudo sed -i '/^AddModule "rhvoice"/d' "$conf_file"
    sudo sed -i '/^#RHVoice module/a AddModule "rhvoice" "sd_rhvoice" "rhvoice.conf"' "$conf_file"

    MODIFIED_CONFIGS["$conf_file"]=1
    log_action "Configured speech-dispatcher for RHVoice"
    echo -e "${GREEN}Speech Dispatcher configured successfully${NC}\n"
}

configure_festival() {
    local conf_file="$HOME/.festivalrc"
    [ -f "$conf_file" ] && backup_file "$conf_file"

    echo -e "${BLUE}Configuring Festival...${NC}"

    cat > "$conf_file" << 'EOL'
;; Festival configuration for RHVoice integration
(Parameter.set 'Audio_Command "spd-say -o rhvoice -r $rate -p $pitch -y $vol '($file)")
(Parameter.set 'Audio_Required_Format 'snd)
(Parameter.set 'Audio_Method 'Audio_Command)
(set! voice_default 'voice_rab_diphone)
EOL

    MODIFIED_CONFIGS["$conf_file"]=1
    log_action "Created Festival configuration"
    echo -e "${GREEN}Festival configured successfully${NC}\n"
}

# Fixed Validation Checks
validate_installation() {
    echo -e "${BLUE}=== Validation Checks ===${NC}"

    # Test RHVoice
    if command -v RHVoice-test &> /dev/null; then
        echo -n "Testing RHVoice... "
        if RHVoice-test -t "RHVoice test successful" &> /dev/null; then
            echo -e "${GREEN}Success${NC}"
        else
            echo -e "${RED}Failed${NC}"
        fi
    else
        echo -e "${YELLOW}RHVoice-test not found${NC}"
    fi

    # Test Speech Dispatcher
    if command -v spd-say &> /dev/null; then
        echo -n "Testing Speech Dispatcher... "
        if spd-say -o rhvoice "Speech Dispatcher test successful" &> /dev/null; then
            echo -e "${GREEN}Success${NC}"
        else
            echo -e "${RED}Failed${NC}"
        fi
    else
        echo -e "${YELLOW}spd-say not found${NC}"
    fi

    # Test Festival
    if command -v festival &> /dev/null; then
        echo -n "Testing Festival... "
        if echo "(SayText \"Festival test successful\")" | festival --batch &> /dev/null; then
            echo -e "${GREEN}Success${NC}"
        else
            echo -e "${RED}Failed${NC}"
        fi
    else
        echo -e "${YELLOW}festival not found${NC}"
    fi

    echo -e "\n${GREEN}Validation complete. Check audio output.${NC}\n"
}

# Main Interface
main_menu() {
    while true; do
        echo -e "${BLUE}=== TTS Configuration Menu ===${NC}"
        echo "1. Install Dependencies"
        echo "2. Configure TTS System"
        echo "3. Validate Installation"
        echo "4. Revert Changes"
        echo "5. Exit"
        echo -n "Select an option (1-5): "

        read choice
        case $choice in
            1) verify_dependencies ;;
            2)
                init_backup_dir
                configure_speech_dispatcher
                configure_festival
                ;;
            3) validate_installation ;;
            4) revert_changes ;;
            5) exit 0 ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

# Initialization
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${RED}Warning: Running as root may cause permission issues with user configs${NC}"
    read -p "Continue anyway? (y/N) " choice
    [[ ! $choice =~ [Yy] ]] && exit 1
fi

main_menu
