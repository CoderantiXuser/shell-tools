#!/usr/bin/env bash
#
# ==============================================================================
# PyAnalyzer v2.7 - Single-File Python Codebase Analysis Tool
#
# A self-contained Bash script to perform deep analysis of Python projects.
# It generates a hierarchical report of file structures, dependencies, and
# entry points, adhering to modern documentation and analysis blueprints.
# ==============================================================================

# --- Strict Mode ---
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# SECTION 1: CORE CONSTANTS & CONFIGURATION
# ==============================================================================
readonly VERSION="2.7" # Updated version
readonly SCRIPT_NAME="${0##*/}"
readonly REQUIRED_TOOLS=(python3 jq find ctags grep)

# --- Default File Filtering & Color Configuration ---
readonly DEFAULT_EXCLUDE_DIRS=( ".git" ".idea" ".vscode" "__pycache__" ".cache" "build" "dist" "*.egg-info" "node_modules" "target" "site" ".pytest_cache" ".mypy_cache" ".tox" ".nox" "htmlcov" )
readonly VENV_NAMES=("venv" ".venv" "env" ".env" "__pypackages__")
readonly DEFAULT_EXCLUDE_FILES=("*.pyc" "*.pyo" "*.pyd" "*.so" ".*.swp")
readonly DEFAULT_INCLUDE_FORMATS=("*.py")

# FIX: Use ANSI C-quoted strings ($'...') to store raw escape characters.
# This ensures they are correctly interpreted by all tools, not just `echo -e`.
readonly C_BOLD=$'\033[1m' C_CYAN=$'\033[1;36m' C_GREEN=$'\033[1;32m' C_YELLOW=$'\033[1;33m' C_MAGENTA=$'\033[0;35m' C_BLUE=$'\033[0;36m' C_DIM=$'\033[2m' C_NC=$'\033[0m'

# --- Global State Variables ---
DRY_RUN=false
DEBUG_MODE=false
INCLUDE_VENV=false
INCLUDE_ALL_FILES=false
ADDITIONAL_FORMATS=()
TARGET_DIR="."
OUTPUT_FORMAT="tree"
LOG_LEVEL=3 # INFO
LOG_FILE="/tmp/pyanalyzer_$(date +%Y%m%d).log"
declare -a FIND_COMMAND_ARGS

# ==============================================================================
# SECTION 2: LOGGING & MONITORING MODULE
# ==============================================================================
log() { local level_code=$1 message="$2" level_name color; [[ $level_code -gt $LOG_LEVEL ]] && return 0; case $level_code in 0) level_name="FATAL"; color=$'\033[0;31m';; 1) level_name="ERROR"; color=$'\033[0;31m';; 2) level_name="WARN"; color=$'\033[1;33m';; 3) level_name="INFO"; color=$'\033[0;32m';; 4) level_name="DEBUG"; color=$'\033[0;34m';; *) level_name="LOG"; color=$'\033[0m';; esac; local timestamp; timestamp=$(date "+%Y-%m-%d %H:%M:%S"); echo -e "${color}[${level_name}]${C_NC} ${message}" >&2; echo "${timestamp} [${level_name}] ${message}" >> "$LOG_FILE"; }
fatal() { log 0 "$1"; exit 1; }
error() { log 1 "$1"; }
warn()  { log 2 "$1"; }
info()  { log 3 "$1"; }
debug() { log 4 "$1"; }
declare -A METRICS
init_monitoring() { METRICS=([start_time]=$(date +%s%N) [files_processed]=0 [errors_encountered]=0); trap 'generate_performance_report' EXIT; }
record_metric() { local key=$1 value=${2:-1}; ((METRICS[$key]+=value)); }
generate_performance_report() { local end_time duration_ms duration_s; end_time=$(date +%s%N); duration_ms=$(((end_time - METRICS[start_time]) / 1000000)); duration_s=$(printf "%.3f" "$(bc -l <<< "$duration_ms / 1000")"); debug "--- Performance Report ---"; debug "Total execution time: ${duration_s}s"; debug "Files processed: ${METRICS[files_processed]}"; debug "Errors encountered: ${METRICS[errors_encountered]}"; }

# ==============================================================================
# SECTION 3: SYSTEM & PROJECT VALIDATION MODULE
# ==============================================================================
playground_assessment() { info "Running system environment validation..."; local -i all_ok=1; for tool in "${REQUIRED_TOOLS[@]}"; do if ! command -v "$tool" &>/dev/null; then error "Required tool not found: '$tool'. Please install it."; all_ok=0; else debug "Verified tool: '$tool'"; fi; done; if command -v "ctags" &>/dev/null && ! ctags --version | grep -qi "Universal"; then warn "'ctags' found, but it may not be Universal Ctags. Code indexing might be incomplete."; fi; [[ $all_ok -eq 1 ]] || fatal "System validation failed. Aborting."; info "System environment is ready."; }

# ==============================================================================
# SECTION 4: PYTHON ANALYSIS ENGINE
# ==============================================================================
build_find_command() {
    FIND_COMMAND_ARGS=("find" "$TARGET_DIR" -type d)
    local prune_clauses=()
    if [[ "$INCLUDE_ALL_FILES" == "false" ]]; then
        local exclude_dirs=("${DEFAULT_EXCLUDE_DIRS[@]}")
        if [[ "$INCLUDE_VENV" == "false" ]]; then exclude_dirs+=("${VENV_NAMES[@]}"); fi
        for dir in "${exclude_dirs[@]}"; do prune_clauses+=(-o -name "$dir"); done
        if [[ ${#prune_clauses[@]} -gt 0 ]]; then FIND_COMMAND_ARGS+=(\( "${prune_clauses[@]:1}" \)); FIND_COMMAND_ARGS+=(-prune); fi
    fi
    FIND_COMMAND_ARGS+=(-o -type f)
    local include_clauses=()
    local formats_to_include=("${DEFAULT_INCLUDE_FORMATS[@]}")
    if [[ ${#ADDITIONAL_FORMATS[@]} -gt 0 ]]; then formats_to_include+=("${ADDITIONAL_FORMATS[@]}"); fi
    for fmt in "${formats_to_include[@]}"; do include_clauses+=(-o -name "$fmt"); done
    if [[ ${#include_clauses[@]} -gt 0 ]]; then FIND_COMMAND_ARGS+=(\( "${include_clauses[@]:1}" \)); fi
    if [[ "$INCLUDE_ALL_FILES" == "false" ]]; then
        for file_pattern in "${DEFAULT_EXCLUDE_FILES[@]}"; do FIND_COMMAND_ARGS+=(-a -not -name "$file_pattern"); done
    fi
    FIND_COMMAND_ARGS+=(-print)
    debug "Constructed find command args:"; debug "$(printf "'%s' " "${FIND_COMMAND_ARGS[@]}")"
}
find_all_project_files() { "${FIND_COMMAND_ARGS[@]}"; }
find_entry_points() { local files_to_check; mapfile -t files_to_check; if [[ ${#files_to_check[@]} -eq 0 ]]; then echo ""; return; fi; printf "%s\0" "${files_to_check[@]}" | xargs -0 grep -l "if __name__ *== *['\"]__main__['\"]" 2>/dev/null || true; }
prompt_for_entry_point() {
    warn "No explicit entry points (if __name__ == '__main__') found."
    info "Please select the primary file(s) to consider as entry points."
    mapfile -t all_files < <(sed "s#^$TARGET_DIR/##") # Read from stdin provided by pipe
    if [[ ${#all_files[@]} -eq 0 ]]; then error "No files found to select from. Cannot continue."; return 1; fi
    local i=0; for file in "${all_files[@]}"; do printf "  [%2d] %s\n" "$i" "$file"; ((i++)); done
    local selection; while true; do read -r -p "Enter number(s), comma-separated (e.g., 0,3): " selection; if [[ "$selection" =~ ^[0-9]+(,[0-9]+)*$ ]]; then break; else error "Invalid input. Please enter numbers separated by commas."; fi; done
    local selected_paths=""; local IFS=','; for index in $selection; do if [[ "$index" -ge 0 && "$index" -lt ${#all_files[@]} ]]; then selected_paths+="${TARGET_DIR}/${all_files[$index]}\n"; else warn "Ignoring invalid index: $index"; fi; done
    echo -e "$selected_paths" | sed '/^$/d'
}
generate_dependency_graph() { python3 -c "
import ast, json, os, sys
from pathlib import Path
def get_imports(fp):
    i=set()
    try:
        with open(fp, 'r', encoding='utf-8', errors='ignore') as f: t=ast.parse(f.read(),filename=str(fp))
        for n in ast.walk(t):
            if isinstance(n,ast.Import):
                for a in n.names: i.add(a.name.split('.')[0])
            elif isinstance(n,ast.ImportFrom):
                if n.level>0: continue
                if n.module: i.add(n.module.split('.')[0])
    except Exception: pass
    return sorted(list(i))
try:
    td=Path(sys.argv[1]).resolve()
    fps=[Path(l.strip()).resolve() for l in sys.stdin if l.strip()]
    g={str(p.relative_to(td)):get_imports(p) for p in fps}
    print(json.dumps(g,indent=2))
except Exception as e: print(f'Error: {e}',file=sys.stderr); sys.exit(1)
" "$TARGET_DIR"; }
index_code_structures() { if ! command -v "ctags" &>/dev/null; then warn "ctags not found, skipping code structure indexing."; echo "{}"; return; fi; mapfile -t files_to_index < <(cat); if [[ ${#files_to_index[@]} -eq 0 ]]; then echo "{}"; return; fi; ctags --fields=+S --output-format=json "${files_to_index[@]}" 2>/dev/null | jq -s 'group_by(.path)|map({(.[0].path|ltrimstr("'$TARGET_DIR'/")): {classes:([.[]|select(.kind=="class")|.name]|unique),functions:([.[]|select(.kind=="function")|.name]|unique)}})|add'; }

render_text_report() {
    local json_report; json_report=$(cat)
    local target_dir files_processed entry_points_count
    target_dir=$(echo "$json_report" | jq -r '.metadata.target_directory')
    files_processed=$(echo "$json_report" | jq -r '.dependency_graph | length')
    entry_points_count=$(echo "$json_report" | jq -r '.entry_points | length')

    echo -e "\n🌳 Analysis for: ${C_CYAN}$target_dir${C_NC}"
    echo "================================================="
    echo -e "Files Analyzed: ${C_YELLOW}${files_processed}${C_NC} | Entry Points Found: ${C_YELLOW}${entry_points_count}${C_NC}"
    echo ""

    echo -e "${C_GREEN}▶️ Entry Points:${C_NC}"
    echo "$json_report" | jq -r --arg td "$target_dir" \
        'if (.entry_points | length) > 0 then .entry_points[] | "  - \(. | ltrimstr($td + "/"))" else "  None specified." end'
    echo ""

    echo -e "${C_BLUE}🏗️ Codebase Structure & Index:${C_NC}"
    # The jq -r command now correctly outputs raw ANSI escape codes which the terminal can interpret directly.
    echo "$json_report" | jq -r \
        --arg C_BOLD "$C_BOLD" --arg C_MAGENTA "$C_MAGENTA" --arg C_BLUE "$C_BLUE" \
        --arg C_YELLOW "$C_YELLOW" --arg C_DIM "$C_DIM" --arg C_NC "$C_NC" \
        '
        .code_index as $idx | .dependency_graph as $deps | ($idx | keys_unsorted) as $all_files |
        $all_files[] | . as $path |
        "\n📄 " + $C_BOLD + $path + $C_NC +
        (if $idx[$path].classes and ($idx[$path].classes | length > 0) then "\n    " + $C_MAGENTA + "C" + $C_NC + " " + ($idx[$path].classes | join(", ")) else "" end) +
        (if $idx[$path].functions and ($idx[$path].functions | length > 0) then "\n    " + $C_BLUE + "F" + $C_NC + " " + ($idx[$path].functions | join(", ")) else "" end) +
        (if $deps[$path] and ($deps[$path] | length > 0) then "\n    " + $C_YELLOW + "→" + $C_NC + " " + ($deps[$path] | join(", ")) else "\n    " + $C_DIM + "(No external dependencies)" + $C_NC end)
        '
    echo -e "\n================================================="
}

analyze_project() {
    info "Starting analysis of target: '$TARGET_DIR'"
    info "Step 1/4: Discovering project files..."
    local project_files; project_files=$(find_all_project_files)
    if [[ -z "$project_files" ]]; then warn "No files matching filters found in '$TARGET_DIR'."; return 0; fi
    record_metric "files_processed" "$(echo "$project_files" | wc -l)"
    info "Step 2/4: Identifying entry points..."
    local entry_points; entry_points=$(echo "$project_files" | find_entry_points)
    if [[ -z "$entry_points" ]]; then entry_points=$(echo "$project_files" | prompt_for_entry_point); [[ -z "$entry_points" ]] && fatal "No entry point selected. Aborting."; fi
    debug "Using entry points:\n${entry_points}"
    info "Step 3/4: Building dependency graph..."
    local dep_graph; dep_graph=$(echo "$project_files" | generate_dependency_graph)
    [[ -z "$dep_graph" ]] && { error "Failed to generate dependency graph."; return 1; }
    info "Step 4/4: Indexing code structures..."
    local code_index; code_index=$(echo "$project_files" | index_code_structures)
    info "Analysis complete. Consolidating report..."
    local final_json; final_json=$(jq -n --argjson deps "$dep_graph" --argjson index "$code_index" --argjson entries "$(echo "$entry_points"|jq -R .|jq -s .)" '{"metadata":{"tool_version":"'$VERSION'","analysis_timestamp":(now|todate),"target_directory":"'$TARGET_DIR'"},"entry_points":$entries,"dependency_graph":$deps,"code_index":$index}');
    case "$OUTPUT_FORMAT" in
        json) echo "$final_json" | jq . ;;
        text|tree) echo "$final_json" | render_text_report ;;
        *) error "Unknown output format: '$OUTPUT_FORMAT'"; return 1 ;;
    esac
}

# ==============================================================================
# SECTION 5 & 6: ARGUMENT PARSING & MAIN WORKFLOW
# ==============================================================================
show_help() {
    cat <<EOF
PyAnalyzer v$VERSION - A self-contained Python codebase analysis tool.

Usage: $SCRIPT_NAME [OPTIONS] [TARGET_DIRECTORY]

Analyzes Python files in the target directory to map dependencies, index code
structures, and identify entry points. By default, it excludes common virtual
environment, IDE, and build directories.

OPTIONS:
  -f, --format FMT   Output format. One of: tree (default), text, json.
  --include-formats FORMATS
                     Comma-separated list of additional file formats to analyze
                     (e.g., "*.robot,*.resource").
  --include-all-files
                     Disable all default file/directory exclusions. Analyzes every file.
  --venv             Include default virtual environment directories in analysis.
  -d, --dry-run      Perform checks but do not run the full analysis.
  -D, --debug        Enable verbose debug logging.
  -h, --help         Display this help message and exit.
  -v, --version      Display script version and exit.

DEPENDENCIES:
  - bash (v4+), python3, jq, find, grep
  - universal-ctags (required for code indexing)
EOF
}
parse_arguments() { while [[ $# -gt 0 ]]; do case "$1" in -f|--format) OUTPUT_FORMAT="$2"; shift 2 ;; --include-formats) IFS=',' read -r -a ADDITIONAL_FORMATS <<< "$2"; shift 2 ;; --include-all-files) INCLUDE_ALL_FILES=true; shift ;; --venv) INCLUDE_VENV=true; shift ;; -d|--dry-run) DRY_RUN=true; shift ;; -D|--debug) DEBUG_MODE=true; LOG_LEVEL=4; shift ;; -h|--help) show_help; exit 0 ;; -v|--version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;; --) shift; break ;; -*) error "Unknown option: $1"; show_help; exit 1 ;; *) TARGET_DIR="$1"; shift ;; esac; done; }
main() {
    parse_arguments "$@"; init_monitoring
    info "PyAnalyzer v$VERSION starting..."; debug "Log file for this session: $LOG_FILE"
    playground_assessment
    TARGET_DIR=$(realpath "$TARGET_DIR")
    if [[ "$INCLUDE_ALL_FILES" == "false" ]] && [[ "$INCLUDE_VENV" == "true" ]]; then warn "Including virtual environments in analysis (--venv)."; fi
    build_find_command
    if [[ "$DRY_RUN" == "true" ]]; then info "Dry-run mode enabled."; info "Effective find command:"; printf "%q " "${FIND_COMMAND_ARGS[@]}"; echo; exit 0; fi
    if ! analyze_project; then record_metric "errors_encountered"; fatal "Analysis failed. Please check logs for details."; fi
    info "Analysis completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi