#!/bin/bash

# --- Configuration ---
LOG_FILE="_sys_usr-groups.log"

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging Function ---
log_message() {
    local type="$1"
    local message="$2"
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') [${type}] ${message}" | tee -a "$LOG_FILE"
}

# --- Spinner Function ---
spinner() {
    local pid=$!
    local delay=0.1
    local spinstr='|/-\'
    local i=0
    local message="$1"
    echo -n -e "${BLUE}${message} ${NC}"
    while kill -0 $pid 2>/dev/null; do
        local temp=${spinstr:$i:1}
        echo -e -n "${BLUE}${temp}${NC}"
        i=$(( (i+1) % 4 ))
        sleep $delay
    done
    echo -e -n " " # Clear spinner
    wait $pid # Ensure the command finishes and capture its exit code
    return $?
}

# --- Dynamic Status Update ---
update_status() {
    echo -e -n "${YELLOW}STATUS: $1${NC}"
}

# --- User Management Functions ---

add_user() {
    log_message "INFO" "Starting user addition process."
    update_status "Adding new user..."

    read -p "$(echo -e "${GREEN}Enter username:${NC} ")" USERNAME
    if id "$USERNAME" &>/dev/null; then
        log_message "ERROR" "User '$USERNAME' already exists."
        echo -e "${RED}Error: User '$USERNAME' already exists.${NC}"
        return 1
    fi

    read -s -p "$(echo -e "${GREEN}Enter password for $USERNAME:${NC} ")" PASSWORD
    echo
    read -s -p "$(echo -e "${GREEN}Confirm password for $USERNAME:${NC} ")" PASSWORD_CONFIRM
    echo

    if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
        log_message "ERROR" "Passwords do not match."
        echo -e "${RED}Error: Passwords do not match.${NC}"
        return 1
    fi

    log_message "INFO" "Attempting to add user '$USERNAME'."
    update_status "Executing useradd..."
    sudo useradd -m "$USERNAME" &
    spinner "Adding user '$USERNAME'..."
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "User '$USERNAME' added successfully."
        update_status "Setting password for '$USERNAME'."
        echo "$USERNAME:$PASSWORD" | sudo chpasswd &
        spinner "Setting password..."
        if [ $? -eq 0 ]; then
            log_message "SUCCESS" "Password set for '$USERNAME'."
            echo -e "${GREEN}User '$USERNAME' created and password set successfully.${NC}"
        else
            log_message "ERROR" "Failed to set password for '$USERNAME'."
            echo -e "${RED}Error: Failed to set password for '$USERNAME'.${NC}"
        fi
    else
        log_message "ERROR" "Failed to add user '$USERNAME'."
        echo -e "${RED}Error: Failed to add user '$USERNAME'.${NC}"
    fi
    update_status "User addition process complete."
}

delete_user() {
    log_message "INFO" "Starting user deletion process."
    update_status "Deleting user..."

    read -p "$(echo -e "${GREEN}Enter username to delete:${NC} ")" USERNAME
    if ! id "$USERNAME" &>/dev/null; then
        log_message "ERROR" "User '$USERNAME' does not exist."
        echo -e "${RED}Error: User '$USERNAME' does not exist.${NC}"
        return 1
    fi

    read -p "$(echo -e "${YELLOW}Are you sure you want to delete user '$USERNAME' and their home directory? (y/N):${NC} ")" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        log_message "INFO" "User deletion cancelled by user."
        echo -e "${YELLOW}User deletion cancelled.${NC}"
        return 0
    fi

    log_message "INFO" "Attempting to delete user '$USERNAME' with home directory."
    update_status "Executing userdel..."
    sudo userdel -r "$USERNAME" &
    spinner "Deleting user '$USERNAME'..."
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "User '$USERNAME' deleted successfully."
        echo -e "${GREEN}User '$USERNAME' and their home directory deleted successfully.${NC}"
    else
        log_message "ERROR" "Failed to delete user '$USERNAME'."
        echo -e "${RED}Error: Failed to delete user '$USERNAME'.${NC}"
    fi
    update_status "User deletion process complete."
}

modify_user() {
    log_message "INFO" "Starting user modification process."
    update_status "Modifying user..."

    read -p "$(echo -e "${GREEN}Enter username to modify:${NC} ")" USERNAME
    if ! id "$USERNAME" &>/dev/null; then
        log_message "ERROR" "User '$USERNAME' does not exist."
        echo -e "${RED}Error: User '$USERNAME' does not exist.${NC}"
        return 1
    fi

    while true; do
        echo -e "\n${BLUE}--- Modify User '$USERNAME' ---${NC}"
        echo -e "1. Change Password"
        echo -e "2. Add to Group"
        echo -e "3. Remove from Group"
        echo -e "4. Change Shell"
        echo -e "5. Lock Account"
        echo -e "6. Unlock Account"
        echo -e "7. Back to Main Menu"
        read -p "$(echo -e "${GREEN}Choose an option:${NC} ")" MOD_CHOICE

        case $MOD_CHOICE in
            1)
                log_message "INFO" "Changing password for user '$USERNAME'."
                update_status "Changing password..."
                sudo passwd "$USERNAME" &
                spinner "Changing password..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "Password for '$USERNAME' changed successfully."
                    echo -e "${GREEN}Password for '$USERNAME' changed successfully.${NC}"
                else
                    log_message "ERROR" "Failed to change password for '$USERNAME'."
                    echo -e "${RED}Error: Failed to change password for '$USERNAME'.${NC}"
                fi
                ;;
            2)
                read -p "$(echo -e "${GREEN}Enter group name to add '$USERNAME' to:${NC} ")" GROUPNAME
                if ! getent group "$GROUPNAME" &>/dev/null; then
                    log_message "ERROR" "Group '$GROUPNAME' does not exist."
                    echo -e "${RED}Error: Group '$GROUPNAME' does not exist.${NC}"
                    continue
                fi
                log_message "INFO" "Adding user '$USERNAME' to group '$GROUPNAME'."
                update_status "Adding user to group..."
                sudo usermod -aG "$GROUPNAME" "$USERNAME" &
                spinner "Adding '$USERNAME' to '$GROUPNAME'..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "User '$USERNAME' added to group '$GROUPNAME' successfully."
                    echo -e "${GREEN}User '$USERNAME' added to group '$GROUPNAME' successfully.${NC}"
                else
                    log_message "ERROR" "Failed to add user '$USERNAME' to group '$GROUPNAME'."
                    echo -e "${RED}Error: Failed to add user '$USERNAME' to group '$GROUPNAME'.${NC}"
                fi
                ;;
            3)
                read -p "$(echo -e "${GREEN}Enter group name to remove '$USERNAME' from:${NC} ")" GROUPNAME
                if ! getent group "$GROUPNAME" &>/dev/null; then
                    log_message "ERROR" "Group '$GROUPNAME' does not exist."
                    echo -e "${RED}Error: Group '$GROUPNAME' does not exist.${NC}"
                    continue
                fi
                log_message "INFO" "Removing user '$USERNAME' from group '$GROUPNAME'."
                update_status "Removing user from group..."
                sudo gpasswd -d "$USERNAME" "$GROUPNAME" &
                spinner "Removing '$USERNAME' from '$GROUPNAME'..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "User '$USERNAME' removed from group '$GROUPNAME' successfully."
                    echo -e "${GREEN}User '$USERNAME' removed from group '$GROUPNAME' successfully.${NC}"
                else
                    log_message "ERROR" "Failed to remove user '$USERNAME' from group '$GROUPNAME'."
                    echo -e "${RED}Error: Failed to remove user '$USERNAME' from group '$GROUPNAME'.${NC}"
                fi
                ;;
            4)
                read -p "$(echo -e "${GREEN}Enter new shell for '$USERNAME' (e.g., /bin/bash):${NC} ")" NEWSHELL
                log_message "INFO" "Changing shell for user '$USERNAME' to '$NEWSHELL'."
                update_status "Changing shell..."
                sudo usermod -s "$NEWSHELL" "$USERNAME" &
                spinner "Changing shell for '$USERNAME'..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "Shell for '$USERNAME' changed to '$NEWSHELL' successfully."
                    echo -e "${GREEN}Shell for '$USERNAME' changed to '$NEWSHELL' successfully.${NC}"
                else
                    log_message "ERROR" "Failed to change shell for '$USERNAME'."
                    echo -e "${RED}Error: Failed to change shell for '$USERNAME'.${NC}"
                fi
                ;;
            5)
                log_message "INFO" "Locking account for user '$USERNAME'."
                update_status "Locking account..."
                sudo usermod -L "$USERNAME" &
                spinner "Locking '$USERNAME' account..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "Account for '$USERNAME' locked successfully."
                    echo -e "${GREEN}Account for '$USERNAME' locked successfully.${NC}"
                else
                    log_message "ERROR" "Failed to lock account for '$USERNAME'."
                    echo -e "${RED}Error: Failed to lock account for '$USERNAME'.${NC}"
                fi
                ;;
            6)
                log_message "INFO" "Unlocking account for user '$USERNAME'."
                update_status "Unlocking account..."
                sudo usermod -U "$USERNAME" &
                spinner "Unlocking '$USERNAME' account..."
                if [ $? -eq 0 ]; then
                    log_message "SUCCESS" "Account for '$USERNAME' unlocked successfully."
                    echo -e "${GREEN}Account for '$USERNAME' unlocked successfully.${NC}"
                else
                    log_message "ERROR" "Failed to unlock account for '$USERNAME'."
                    echo -e "${RED}Error: Failed to unlock account for '$USERNAME'.${NC}"
                fi
                ;;
            7)
                log_message "INFO" "Returning to main menu from user modification."
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        update_status "User modification process complete."
    done
}

list_users() {
    log_message "INFO" "Listing all system users."
    update_status "Retrieving user list..."
    echo -e "\n${BLUE}--- System Users ---${NC}"
    if command -v less >/dev/null; then
        getent passwd | cut -d: -f1,3,4,6,7 | column -t -s: | less -R
    else
        getent passwd | cut -d: -f1,3,4,6,7 | column -t -s:
        log_message "WARNING" "'less' command not found. Displaying full list without pagination."
        echo -e "${YELLOW}Warning: 'less' command not found. Displaying full list without pagination.${NC}"
    fi
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Successfully listed system users."
    else
        log_message "ERROR" "Failed to list system users."
        echo -e "${RED}Error: Failed to retrieve user list.${NC}"
    fi
    update_status "User listing complete."
}

# --- Group Management Functions ---

add_group() {
    log_message "INFO" "Starting group addition process."
    update_status "Adding new group..."

    read -p "$(echo -e "${GREEN}Enter group name:${NC} ")" GROUPNAME
    if getent group "$GROUPNAME" &>/dev/null; then
        log_message "ERROR" "Group '$GROUPNAME' already exists."
        echo -e "${RED}Error: Group '$GROUPNAME' already exists.${NC}"
        return 1
    fi

    log_message "INFO" "Attempting to add group '$GROUPNAME'."
    update_status "Executing groupadd..."
    sudo groupadd "$GROUPNAME" &
    spinner "Adding group '$GROUPNAME'..."
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Group '$GROUPNAME' added successfully."
        echo -e "${GREEN}Group '$GROUPNAME' created successfully.${NC}"
    else
        log_message "ERROR" "Failed to add group '$GROUPNAME'."
        echo -e "${RED}Error: Failed to add group '$GROUPNAME'.${NC}"
    fi
    update_status "Group addition process complete."
}

delete_group() {
    log_message "INFO" "Starting group deletion process."
    update_status "Deleting group..."

    read -p "$(echo -e "${GREEN}Enter group name to delete:${NC} ")" GROUPNAME
    if ! getent group "$GROUPNAME" &>/dev/null; then
        log_message "ERROR" "Group '$GROUPNAME' does not exist."
        echo -e "${RED}Error: Group '$GROUPNAME' does not exist.${NC}"
        return 1
    fi

    read -p "$(echo -e "${YELLOW}Are you sure you want to delete group '$GROUPNAME'? (y/N):${NC} ")" CONFIRM
    if [[ ! "$CONFIRM" =~ ^[yY]$ ]]; then
        log_message "INFO" "Group deletion cancelled by user."
        echo -e "${YELLOW}Group deletion cancelled.${NC}"
        return 0
    fi

    log_message "INFO" "Attempting to delete group '$GROUPNAME'."
    update_status "Executing groupdel..."
    sudo groupdel "$GROUPNAME" &
    spinner "Deleting group '$GROUPNAME'..."
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Group '$GROUPNAME' deleted successfully."
        echo -e "${GREEN}Group '$GROUPNAME' deleted successfully.${NC}"
    else
        log_message "ERROR" "Failed to delete group '$GROUPNAME'."
        echo -e "${RED}Error: Failed to delete group '$GROUPNAME'.${NC}"
    fi
    update_status "Group deletion process complete."
}

list_groups() {
    log_message "INFO" "Listing all system groups."
    update_status "Retrieving group list..."
    echo -e "\n${BLUE}--- System Groups ---${NC}"
    if command -v less >/dev/null; then
        getent group | cut -d: -f1,3 | column -t -s: | less -R
    else
        log_message "WARNING" "'less' command not found. Displaying full list without pagination."
        echo -e "${YELLOW}Warning: 'less' command not found. Displaying full list without pagination.${NC}"
    fi
    if [ $? -eq 0 ]; then
        log_message "SUCCESS" "Successfully listed system groups."
    else
        log_message "ERROR" "Failed to list system groups."
        echo -e "${RED}Error: Failed to retrieve group list.${NC}"
    fi
    update_status "Group listing complete."
}

# --- Main Menu ---
main_menu() {
    log_message "INFO" "Starting User and Group Management Script."
    while true; do
        echo -e "\n${BLUE}--- User and Group Management ---${NC}"
        echo -e "1. Add User"
        echo -e "2. Delete User"
        echo -e "3. Modify User"
        echo -e "4. List Users"
        echo -e "5. Add Group"
        echo -e "6. Delete Group"
        echo -e "7. List Groups"
        echo -e "8. Exit"
        read -p "$(echo -e "${GREEN}Choose an option:${NC} ")" CHOICE

        case $CHOICE in
            1) add_user ;;
            2) delete_user ;;
            3) modify_user ;;
            4) list_users ;;
            5) add_group ;;
            6) delete_group ;;
            7) list_groups ;;
            8)
                log_message "INFO" "Exiting User and Group Management Script."
                echo -e "${BLUE}Exiting. Goodbye!${NC}"
                break
                ;;
            *)
                echo -e "${RED}Invalid option. Please try again.${NC}"
                ;;
        esac
        echo -e "${NC}\n" # Clear status line
    done
}

# --- Script Execution ---
main_menu
