#!/bin/bash

# --- Configuration ---
COMMIT_MESSAGE="Initial commit"

# --- Global Variables ---
GUIDE_MODE=false
REMOTE_URL=""
DEFAULT_BRANCH=""
REPO_EXISTS_AND_CONTINUE=false # New global variable

# --- ANSI Color Codes ---
COLOR_RESET="\033[0m"
COLOR_GREEN="\033[0;32m"
COLOR_YELLOW="\033[0;33m"
COLOR_RED="\033[0;31m"
COLOR_BLUE="\033[0;34m"
COLOR_CYAN="\033[0;36m"
COLOR_MAGENTA="\033[0;35m"
COLOR_BOLD="\033[1m"

# --- Global Variables ---
USE_PAT=false # New global variable to indicate if PAT should be used for authentication

# --- Functions ---

# Function to check if an SSH key is present and loaded
check_ssh_key_exists() {
  echo -e "${COLOR_BLUE}Checking for existing SSH keys...${COLOR_RESET}"
  # Check for common SSH key files
  if [ -f "$HOME/.ssh/id_rsa" ] || [ -f "$HOME/.ssh/id_ed25519" ]; then
    echo -e "${COLOR_GREEN}✅ SSH key file found.${COLOR_RESET}"
    # Check if ssh-agent is running
    if pgrep -q "ssh-agent"; then
      echo -e "${COLOR_GREEN}✅ ssh-agent is running.${COLOR_RESET}"
      # Check if keys are added to ssh-agent
      if ssh-add -l &> /dev/null; then
        echo -e "${COLOR_GREEN}✅ SSH key loaded into ssh-agent.${COLOR_RESET}"
        return 0 # SSH key exists and is loaded
      else
        echo -e "${COLOR_YELLOW}⚠️ SSH key file found, but not loaded into ssh-agent. Attempting to add...${COLOR_RESET}"
        ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null
        if ssh-add -l &> /dev/null; then
          echo -e "${COLOR_GREEN}✅ SSH key successfully added to ssh-agent.${COLOR_RESET}"
          return 0
        else
          echo -e "${COLOR_RED}❌ Failed to add SSH key to ssh-agent. You may need to start ssh-agent or provide a passphrase.${COLOR_RESET}"
          return 1
        fi
      fi
    else
      echo -e "${COLOR_YELLOW}⚠️ ssh-agent is not running. Starting it...${COLOR_RESET}"
      eval "$(ssh-agent -s)" > /dev/null
      if pgrep -q "ssh-agent"; then
        echo -e "${COLOR_GREEN}✅ ssh-agent started.${COLOR_RESET}"
        echo -e "${COLOR_YELLOW}Attempting to add SSH key...${COLOR_RESET}"
        ssh-add "$HOME/.ssh/id_rsa" 2>/dev/null || ssh-add "$HOME/.ssh/id_ed25519" 2>/dev/null
        if ssh-add -l &> /dev/null; then
          echo -e "${COLOR_GREEN}✅ SSH key successfully added to ssh-agent.${COLOR_RESET}"
          return 0
        else
          echo -e "${COLOR_RED}❌ Failed to add SSH key to ssh-agent. You may need to provide a passphrase.${COLOR_RESET}"
          return 1
        fi
      else
        echo -e "${COLOR_RED}❌ Failed to start ssh-agent.${COLOR_RESET}"
        return 1
      fi
    fi
  else
    echo -e "${COLOR_YELLOW}⚠️ No SSH key file found in ~/.ssh/.${COLOR_RESET}"
    return 1 # No SSH key found
  fi
}

# Function to guide user through SSH key setup
setup_ssh_key() {
  echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Setting up SSH Key ---${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}It looks like you don't have an SSH key set up or loaded.${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}We will now guide you through creating one and adding it to your GitHub account.${COLOR_RESET}"
  continue_or_exit

  echo -e "${COLOR_BLUE}1. Generating a new SSH key...${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}When prompted, you can press Enter to accept the default file location and passphrase (though a passphrase is recommended for security).${COLOR_RESET}"
  ssh-keygen -t ed25519 -C "$(git config user.email)"
  if [ $? -ne 0 ]; then
    error_exit "Failed to generate SSH key."
  fi
  echo -e "${COLOR_GREEN}✅ SSH key generated.${COLOR_RESET}"
  continue_or_exit

  echo -e "${COLOR_BLUE}2. Starting the ssh-agent...${COLOR_RESET}"
  eval "$(ssh-agent -s)" > /dev/null
  if [ $? -ne 0 ]; then
    error_exit "Failed to start ssh-agent."
  fi
  echo -e "${COLOR_GREEN}✅ ssh-agent started.${COLOR_RESET}"
  continue_or_exit

  echo -e "${COLOR_BLUE}3. Adding your SSH key to the ssh-agent...${COLOR_RESET}"
  ssh-add "$HOME/.ssh/id_ed25519"
  if [ $? -ne 0 ]; then
    error_exit "Failed to add SSH key to ssh-agent. You may need to provide a passphrase."
  fi
  echo -e "${COLOR_GREEN}✅ SSH key added to ssh-agent.${COLOR_RESET}"
  continue_or_exit

  echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- IMPORTANT: Add your SSH Public Key to GitHub ---${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}To use SSH for GitHub, you need to add your public key to your GitHub account.${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}Your public key is located at: ${COLOR_BOLD}$HOME/.ssh/id_ed25519.pub${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}Copy the content of this file and add it to your GitHub SSH keys settings.${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}You can copy it using: ${COLOR_CYAN}cat ~/.ssh/id_ed25519.pub | xclip -selection clipboard${COLOR_RESET} (install xclip if needed)"
  echo -e "${COLOR_YELLOW}Or simply display it: ${COLOR_CYAN}cat ~/.ssh/id_ed25519.pub${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}Then go to: ${COLOR_CYAN}https://github.com/settings/keys${COLOR_RESET}"
  continue_or_exit
}

# Function to check and setup SSH or prompt for PAT
check_and_setup_ssh_or_pat() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step X: Configure Authentication Method ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}GitHub recommends using SSH keys or Personal Access Tokens (PATs) for authentication.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}We'll check your current setup and help you choose.${COLOR_RESET}"
    continue_or_exit
  fi

  if check_ssh_key_exists; then
    echo -e "${COLOR_GREEN}An SSH key is detected and loaded.${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to use a Personal Access Token (PAT) instead of SSH for this push? (y/N): ${COLOR_RESET}"
    read use_pat_choice
    use_pat_choice=${use_pat_choice:-n} # Default to 'n'
    if [[ "$use_pat_choice" =~ ^[Yy]$ ]]; then
      USE_PAT=true
      echo -e "${COLOR_YELLOW}Proceeding with Personal Access Token (PAT) authentication.${COLOR_RESET}"
    else
      USE_PAT=false
      echo -e "${COLOR_YELLOW}Proceeding with SSH key authentication.${COLOR_RESET}"
    fi
  else
    echo -e "${COLOR_YELLOW}No SSH key detected or loaded.${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to set up an SSH key now (recommended) or use a Personal Access Token (PAT)? (ssh/pat): ${COLOR_RESET}"
    read auth_method_choice
    auth_method_choice=${auth_method_choice:-ssh} # Default to 'ssh'

    if [[ "$auth_method_choice" =~ ^[Ss][Ss][Hh]$ ]]; then
      setup_ssh_key
      USE_PAT=false
    elif [[ "$auth_method_choice" =~ ^[Pp][Aa][Tt]$ ]]; then
      USE_PAT=true
      echo -e "${COLOR_YELLOW}Proceeding with Personal Access Token (PAT) authentication.${COLOR_RESET}"
      echo -e "${COLOR_YELLOW}Remember to generate a PAT from your GitHub settings and use it as your password when prompted.${COLOR_RESET}"
      echo -e "${COLOR_CYAN}GitHub PAT generation link: https://github.com/settings/tokens${COLOR_RESET}"
      continue_or_exit
    else
      error_exit "Invalid choice. Exiting script."
    fi
  fi
  continue_or_exit
}

# Function to check if a command exists

# Function to check if a command exists
command_exists () {
  type "$1" &> /dev/null ;
}

# Function to display error and exit
error_exit () {
  echo -e "${COLOR_RED}ERROR: $1${COLOR_RESET}" >&2
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_YELLOW}Please resolve the error and try again.${COLOR_RESET}"
  fi
  exit 1
}

# Function to pause and allow user to continue or quit in guide mode
continue_or_exit() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "\n${COLOR_CYAN}----------------------------------------------------${COLOR_RESET}"
    printf "Hint: Press ${COLOR_RED}Enter${COLOR_RESET} to continue, or '${COLOR_RED}q${COLOR_RESET}' to quit: " 
    read choice
    if [[ "$choice" == "q" ]]; then
      echo -e "${COLOR_YELLOW}Exiting guide mode. Goodbye!${COLOR_RESET}"
      exit 0
    fi
    echo -e "${COLOR_CYAN}----------------------------------------------------${COLOR_RESET}\n"
  fi
}

check_git_installed() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 1: Check Git Installation ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Git is a powerful version control system essential for managing your code.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}We-ll first check if Git is installed on your system.${COLOR_RESET}"
    continue_or_exit
  fi

  echo -e "${COLOR_BLUE}Checking for Git installation...${COLOR_RESET}"
  if ! command_exists git; then
    error_exit "Git is not installed. Please install Git and try again."
  fi
  echo -e "${COLOR_GREEN}✅ Git is installed.${COLOR_RESET}"
  continue_or_exit
}

check_existing_repo() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 2: Check for Existing Git Repository ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}We need to ensure that this directory is not already a Git repository.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}If it is, initializing a new one could cause conflicts.${COLOR_RESET}"
    continue_or_exit
  fi

  echo -e "${COLOR_BLUE}Checking if this is already a Git repository...${COLOR_RESET}"
  if git rev-parse --is-inside-work-tree &> /dev/null; then
    echo -e "${COLOR_YELLOW}⚠️ This directory is already a Git repository.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}What would you like to do?${COLOR_RESET}"
    echo -e "  ${COLOR_CYAN}1) Continue with the existing repository (add and push files).${COLOR_RESET}"
    echo -e "  ${COLOR_RED}2) Delete the existing .git directory and reinitialize (DANGEROUS - all history will be lost!).${COLOR_RESET}"
    echo -e "  ${COLOR_YELLOW}3) Exit the script.${COLOR_RESET}"

    printf "${COLOR_CYAN}Hint: Enter your choice (1, 2, or 3): ${COLOR_RESET}" 
    read repo_choice

    case $repo_choice in
      1)
        echo -e "${COLOR_GREEN}Continuing with the existing repository.${COLOR_RESET}"
        REPO_EXISTS_AND_CONTINUE=true
        ;;
      2)
        echo -e "${COLOR_RED}${COLOR_BOLD}WARNING: You are about to delete the .git directory.${COLOR_RESET}"
        echo -e "${COLOR_RED}${COLOR_BOLD}This will permanently erase all Git history for this project.${COLOR_RESET}"
        printf "${COLOR_RED}Type 'YES' (in uppercase) to confirm deletion: ${COLOR_RESET}"
        read confirm_delete
        if [ "$confirm_delete" == "YES" ]; then
          echo -e "${COLOR_YELLOW}Deleting .git directory...${COLOR_RESET}"
          rm -rf .git
          echo -e "${COLOR_GREEN}✅ .git directory deleted. Proceeding with reinitialization.${COLOR_RESET}"
        else
          error_exit "Deletion cancelled. Exiting script."
        fi
        ;;
      3)
        echo -e "${COLOR_YELLOW}Exiting script as requested.${COLOR_RESET}"
        exit 0
        ;;
      *)
        error_exit "Invalid choice. Exiting script."
        ;;
    esac
  else
    echo -e "${COLOR_GREEN}✅ Not an existing Git repository.${COLOR_RESET}"
  fi
  continue_or_exit
}

initialize_git() {
  if [ "$REPO_EXISTS_AND_CONTINUE" = true ]; then
    echo -e "${COLOR_YELLOW}ℹ️ Skipping Git initialization as you chose to continue with an existing repository.${COLOR_RESET}"
    continue_or_exit
    return # Exit function early
  fi

  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 3: Initialize Git Repository ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'git init' command creates a new, empty Git repository in the current directory.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}This is where Git will store all the version history of your project.${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to initialize a new Git repository here? (Y/n): ${COLOR_RESET}" 
    read confirm_init
    confirm_init=${confirm_init:-y} # Default to 'y'
    if ! [[ "$confirm_init" =~ ^[Yy]$ ]]; then
      error_exit "Git initialization cancelled by user."
    fi
  fi

  echo -e "${COLOR_BLUE}Initializing new Git repository...${COLOR_RESET}"
  if ! git init; then
    error_exit "Failed to initialize Git repository."
  fi
  echo -e "${COLOR_GREEN}✅ Git repository initialized.${COLOR_RESET}"
  continue_or_exit
}

get_default_branch() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 4: Determine Default Branch Name --- ${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Git repositories have a default branch, traditionally 'master' but increasingly 'main'.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}We'll determine which one your Git setup uses.${COLOR_RESET}"
    continue_or_exit
  fi

  echo -e "${COLOR_BLUE}Determining default branch name...${COLOR_RESET}"
  DEFAULT_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null)
  if [ -z "$DEFAULT_BRANCH" ]; then
    if git branch -m main &> /dev/null; then
      DEFAULT_BRANCH="main"
    else
      DEFAULT_BRANCH="master"
    fi
    echo -e "${COLOR_YELLOW}ℹ️  Default branch name determined as: ${COLOR_BOLD}$DEFAULT_BRANCH${COLOR_RESET}"
  else
    echo -e "${COLOR_YELLOW}ℹ️  Default branch name: ${COLOR_BOLD}$DEFAULT_BRANCH${COLOR_RESET}"
  fi
  continue_or_exit
}

add_files_to_staging() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 5: Add Files to Staging Area ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'git add .' command adds all current files and changes in your project to the staging area.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}The staging area is where you prepare changes before committing them.${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to add all files to the staging area? (Y/n): ${COLOR_RESET}" 
    read confirm_add
    confirm_add=${confirm_add:-y} # Default to 'y'
    if ! [[ "$confirm_add" =~ ^[Yy]$ ]]; then
      error_exit "Adding files cancelled by user."
    fi
  fi

  echo -e "${COLOR_BLUE}Adding all files to the staging area...${COLOR_RESET}"
  if ! git add .; then
    error_exit "Failed to add files to staging area."
  fi
  echo -e "${COLOR_GREEN}✅ All files added to staging area.${COLOR_RESET}"
  continue_or_exit
}

make_initial_commit() {
  if [ "$REPO_EXISTS_AND_CONTINUE" = true ]; then
    echo -e "${COLOR_YELLOW}ℹ️ Skipping initial commit as you chose to continue with an existing repository.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}Please ensure you have committed your changes manually if needed.${COLOR_RESET}"
    continue_or_exit
    return # Exit function early
  fi

  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 6: Make the Initial Commit ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'git commit' saves the changes from the staging area to your repository's history.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}The commit message describes the changes you've made.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}The default commit message will be: '${COLOR_BOLD}$COMMIT_MESSAGE${COLOR_RESET}${COLOR_YELLOW}'${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to make the initial commit? (Y/n): ${COLOR_RESET}" 
    read confirm_commit
    confirm_commit=${confirm_commit:-y} # Default to 'y'
    if ! [[ "$confirm_commit" =~ ^[Yy]$ ]]; then
      error_exit "Initial commit cancelled by user."
    fi
  fi

  echo -e "${COLOR_BLUE}Making the initial commit...${COLOR_RESET}"
  if ! git commit -m "$COMMIT_MESSAGE"; then
    error_exit "Failed to make the initial commit."
  fi
  echo -e "${COLOR_GREEN}✅ Initial commit created.${COLOR_RESET}"
  continue_or_exit
}

prompt_for_remote_url() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 7: Provide Remote Repository URL --- ${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}A remote repository is where your project's code will be stored online (e.g., GitHub, GitLab).${COLOR_RESET}"
    if [ "$USE_PAT" = true ]; then
      echo -e "${COLOR_YELLOW}You need to provide the HTTPS URL of your empty remote repository.${COLOR_RESET}"
      echo -e "${COLOR_YELLOW}Example: https://github.com/your-username/your-repo-name.git${COLOR_RESET}"
    else
      echo -e "${COLOR_YELLOW}You need to provide the SSH URL of your empty remote repository.${COLOR_RESET}"
      echo -e "${COLOR_YELLOW}Example: git@github.com:your-username/your-repo-name.git${COLOR_RESET}"
    fi
  fi

  # Try to automatically determine the remote URL if 'origin' already exists
  EXISTING_REMOTE=$(git remote get-url origin 2>/dev/null)
  if [ -n "$EXISTING_REMOTE" ]; then
    REMOTE_URL="$EXISTING_REMOTE"
    echo -e "${COLOR_GREEN}✅ Remote URL 'origin' already configured: ${COLOR_BOLD}$REMOTE_URL${COLOR_RESET}"
  else
    if [ "$USE_PAT" = true ]; then
      printf "${COLOR_CYAN}Hint: Enter the GitHub HTTPS repository URL: ${COLOR_RESET}" 
    else
      printf "${COLOR_CYAN}Hint: Enter the GitHub SSH repository URL: ${COLOR_RESET}" 
    fi
    read REMOTE_URL

    if [ -z "$REMOTE_URL" ]; then
      error_exit "No remote URL provided. Exiting."
    fi
  fi
  continue_or_exit
}

add_or_update_remote() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 8: Add or Update Remote Origin ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'git remote add origin' links your local repository to the remote one.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'origin' is the conventional name for the primary remote.${COLOR_RESET}"
  fi

  echo -e "${COLOR_BLUE}Adding remote origin: ${COLOR_BOLD}$REMOTE_URL${COLOR_RESET}"
  if git remote get-url origin &> /dev/null; then
    EXISTING_REMOTE_URL=$(git remote get-url origin)

    # Determine if existing remote is HTTPS or SSH
    if [[ "$EXISTING_REMOTE_URL" == git@* ]]; then
      EXISTING_REMOTE_TYPE="ssh"
    else
      EXISTING_REMOTE_TYPE="https"
    fi

    TARGET_REMOTE_URL="$REMOTE_URL"

    # Convert URL if necessary based on USE_PAT
    if [ "$USE_PAT" = true ] && [ "$EXISTING_REMOTE_TYPE" = "ssh" ]; then
      # Convert SSH to HTTPS
      TARGET_REMOTE_URL=$(echo "$REMOTE_URL" | sed -E 's/git@github.com:(.*)\.git/https:\/\/github.com\/\1.git/')
      echo -e "${COLOR_YELLOW}Converting SSH remote to HTTPS: ${COLOR_BOLD}$TARGET_REMOTE_URL${COLOR_RESET}"
    elif [ "$USE_PAT" = false ] && [ "$EXISTING_REMOTE_TYPE" = "https" ]; then
      # Convert HTTPS to SSH
      TARGET_REMOTE_URL=$(echo "$REMOTE_URL" | sed -E 's/https:\/\/github.com\/(.*)\.git/git@github.com:\1.git/')
      echo -e "${COLOR_YELLOW}Converting HTTPS remote to SSH: ${COLOR_BOLD}$TARGET_REMOTE_URL${COLOR_RESET}"
    fi

    if [ "$EXISTING_REMOTE_URL" == "$TARGET_REMOTE_URL" ]; then
      echo -e "${COLOR_YELLOW}ℹ️  Remote 'origin' already exists and points to the same URL. Skipping adding.${COLOR_RESET}"
    else
      if [ "$GUIDE_MODE" = true ]; then
        printf "${COLOR_CYAN}Hint: Remote 'origin' already exists and points to a different URL ($EXISTING_REMOTE_URL). Do you want to update it to $TARGET_REMOTE_URL? (y/N): ${COLOR_RESET}" 
        read UPDATE_REMOTE
        UPDATE_REMOTE=${UPDATE_REMOTE:-n} # Default to 'n'
      else
        UPDATE_REMOTE="n" # Default to No in automated mode
      fi

      if [[ "$UPDATE_REMOTE" =~ ^[Yy]$ ]]; then
        if ! git remote set-url origin "$TARGET_REMOTE_URL"; then
          error_exit "Failed to update remote 'origin' URL."
        fi
        echo -e "${COLOR_GREEN}✅ Remote 'origin' URL updated.${COLOR_RESET}"
      else
        error_exit "Remote 'origin' exists with a different URL. Exiting to prevent accidental changes."
      fi
    fi
  else
    # Add remote based on USE_PAT
    if [ "$USE_PAT" = true ]; then
      # Ensure HTTPS URL
      if [[ "$REMOTE_URL" == git@* ]]; then
        REMOTE_URL=$(echo "$REMOTE_URL" | sed -E 's/git@github.com:(.*)\.git/https:\/\/github.com\/\1.git/')
        echo -e "${COLOR_YELLOW}Converting SSH URL to HTTPS for PAT: ${COLOR_BOLD}$REMOTE_URL${COLOR_RESET}"
      fi
    else
      # Ensure SSH URL
      if [[ "$REMOTE_URL" == https://* ]]; then
        REMOTE_URL=$(echo "$REMOTE_URL" | sed -E 's/https:\/\/github.com\/(.*)\.git/git@github.com:\1.git/')
        echo -e "${COLOR_YELLOW}Converting HTTPS URL to SSH: ${COLOR_BOLD}$REMOTE_URL${COLOR_RESET}"
      fi
    fi

    if ! git remote add origin "$REMOTE_URL"; then
      error_exit "Failed to add remote origin. It might already exist or the URL is invalid."
    fi
    echo -e "${COLOR_GREEN}✅ Remote origin added.${COLOR_RESET}"
  fi
  continue_or_exit
}

push_to_remote() {
  if [ "$GUIDE_MODE" = true ]; then
    echo -e "${COLOR_BOLD}${COLOR_MAGENTA}--- Step 9: Push Changes to Remote Repository ---${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}'git push -u origin $DEFAULT_BRANCH' sends your local commits to the remote repository.${COLOR_RESET}"
    echo -e "${COLOR_YELLOW}The '-u' flag sets the upstream branch, so future 'git push' and 'git pull' commands are simpler.${COLOR_RESET}"
    printf "${COLOR_CYAN}Hint: Do you want to push your project to the remote repository now? (Y/n): ${COLOR_RESET}" 
    read confirm_push
    confirm_push=${confirm_push:-y} # Default to 'y'
    if ! [[ "$confirm_push" =~ ^[Yy]$ ]]; then
      error_exit "Push operation cancelled by user."
    fi
  fi

  echo -e "${COLOR_BLUE}Pushing changes to the remote repository (${COLOR_BOLD}$DEFAULT_BRANCH${COLOR_RESET}${COLOR_BLUE} branch)...${COLOR_RESET}"
  if ! git push -u origin "$DEFAULT_BRANCH"; then
    error_exit "Failed to push changes to the remote repository. Common reasons include:\n  - Authentication issues: GitHub no longer supports password authentication. Please use a Personal Access Token (PAT) or SSH keys. For PATs, generate one from GitHub settings and use it as your password.\n  - Network problems.\n  - Remote repository has changes you need to pull first (e.g., 'git pull origin $DEFAULT_BRANCH')."
  fi
  echo -e "${COLOR_GREEN}🎉 Project successfully pushed to GitHub! 🎉${COLOR_RESET}"
  continue_or_exit
}

# --- Main Script Execution ---

# Check for guide mode argument
if [[ "$1" == "--guide" ]]; then
  GUIDE_MODE=true
  echo -e "${COLOR_BOLD}${COLOR_MAGENTA}🚀 Welcome to the Git Repository Setup Guide! 🚀${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}This interactive guide will walk you through initializing a Git repository and pushing your project to a remote (e.g., GitHub).${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}We'll go step-by-step, explaining each action.${COLOR_RESET}"
  continue_or_exit
fi

echo -e "${COLOR_BOLD}${COLOR_MAGENTA}🚀 Git Repository Automation Script 🚀${COLOR_RESET}"
echo -e "${COLOR_BOLD}${COLOR_MAGENTA}-------------------------------------${COLOR_RESET}"

check_git_installed
check_existing_repo
initialize_git
get_default_branch
check_and_setup_ssh_or_pat # New function call
add_files_to_staging
make_initial_commit
prompt_for_remote_url
add_or_update_remote
push_to_remote

echo -e "${COLOR_BOLD}${COLOR_MAGENTA}-------------------------------------${COLOR_RESET}"
echo -e "${COLOR_GREEN}Script finished.${COLOR_RESET}"
