#!/usr/bin/env bash

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
declare -a PY_FILES
declare -A FILE_MAP

# Progress logging
log() {
    local type=$1; shift
    local color=""
    local prefix=""

    case "$type" in
        success) color=$GREEN; prefix="[✓]" ;;
        info) color=$BLUE; prefix="[i]" ;;
        warn) color=$YELLOW; prefix="[!]" ;;
        error) color=$RED; prefix="[✗]" ;;
        *) color=$NC; prefix="[ ]" ;;
    esac

    echo -e "${color}${prefix} $*${NC}"
}

# Find main.py
find_main_py() {
    log info "Searching for main.py..."
    if [[ -f "main.py" ]]; then
        log success "Found main.py in working directory"
        realpath "main.py"
        return 0
    fi

    local mains=()
    while IFS= read -r -d $'\0' file; do
        [[ $file =~ /main.py$ ]] && mains+=("$file")
    done < <(find . -type f -name "*.py" -print0)

    case ${#mains[@]} in
        0) log error "No main.py found"; return 1 ;;
        1) log success "Found main.py: ${mains[0]}"; echo "${mains[0]}"; return 0 ;;
        *) log warn "Multiple main.py files found";
           PS3="Select main.py: "
           select opt in "${mains[@]}"; do
               [[ -n $opt ]] && { echo "$opt"; return 0; }
           done ;;
    esac
}

# Extract imports from Python file
extract_imports() {
    local file=$1
    local imports=()
    local dir base module_path

    dir=$(dirname "$file")
    base=$(basename "$file")

    # Skip standard library imports and relative imports
    while IFS= read -r line; do
        # Skip empty lines and comments
        [[ -z $line || $line == \#* ]] && continue

        # Extract module names
        if [[ $line =~ ^(import|from)\ +([a-zA-Z_][a-zA-Z0-9_.]*) ]]; then
            local module=${BASH_REMATCH[2]}

            # Skip standard libraries and relative imports
            [[ $module =~ ^\. ]] && continue

            # Convert module to path
            module_path="${module//.//}"

            # Check possible file paths
            local candidate="${dir}/${module_path}.py"
            [[ -f "$candidate" ]] && imports+=("$candidate")

            candidate="${dir}/${module_path}/__init__.py"
            [[ -f "$candidate" ]] && imports+=("$candidate")
        fi
    done < "$file"

    echo "${imports[@]}"
}

# Recursive file collection
collect_related() {
    local file=$1
    [[ -n "${FILE_MAP[$file]}" ]] && return

    log info "Processing: $(basename "$file")"
    FILE_MAP["$file"]=1
    PY_FILES+=("$file")

    # Get imports and process recursively
    while IFS= read -r -d ' ' imp; do
        [[ -n $imp ]] && collect_related "$imp"
    done <<< "$(extract_imports "$file") "
}

# Generate ASCII tree view
generate_tree() {
    log info "Generating file tree..."
    declare -A dir_map

    # Create directory structure mapping
    for file in "${PY_FILES[@]}"; do
        local dir=$(dirname "$file")
        local base=$(basename "$file")
        dir_map["$dir"]+="$base"$'\n'
    done

    # Print tree structure
    local indent=""
    for dir in $(echo "${!dir_map[@]}" | tr ' ' $'\n' | sort -t'/' -k1,1n); do
        local parts=($(echo "$dir" | tr '/' '\n'))
        indent=""

        # Build indentation structure
        for ((i=0; i<${#parts[@]}-1; i++)); do
            [[ $i > 0 ]] && indent+="    "
        done

        [[ ${#parts[@]} > 0 ]] && indent+="├── "

        echo "${indent}${parts[${#parts[@]}-1]}/"
        indent+="    "

        # Print files in directory
        while IFS= read -r file; do
            [[ -n $file ]] && echo "${indent}└── ${file}"
        done <<< "${dir_map[$dir]}"
    done
}

# Main process
main() {
    log info "Starting Python file analyzer"

    # Step 1: Find main.py
    local main_py
    if ! main_py=$(find_main_py); then
        log error "Aborting: No valid main.py found"
        exit 1
    fi

    # Step 2: Collect related files
    log info "Analyzing imports..."
    collect_related "$main_py"

    # Step 3: Display results
    echo -e "\n${YELLOW}Identified Python Files:${NC}"
    generate_tree

    # Step 4: User confirmation
    echo -e "\n${GREEN}Collection complete!${NC}"
    read -rp "Confirm these files? (y/n) " confirm
    [[ $confirm != "y" ]] && { log warn "Aborted by user"; exit 1; }

    log success "Files stored for further processing"

    # Display collected files in global variable
    echo -e "\n${BLUE}Global PY_FILES content:${NC}"
    printf '%s\n' "${PY_FILES[@]}"
}

main "$@"
