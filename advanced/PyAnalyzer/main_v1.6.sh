#!/usr/bin/env bash
#
# ==============================================================================
# PyAnalyzer v1.6 - Single-File Python Codebase Analysis Tool
#
# A self-contained Bash script to perform deep analysis of Python projects.
# By default, it analyzes user-created files and excludes virtual environments.
# ==============================================================================

# --- Strict Mode ---
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# SECTION 1: CORE CONSTANTS & CONFIGURATION
# ==============================================================================
readonly VERSION="1.6"
readonly SCRIPT_NAME="${0##*/}"
readonly REQUIRED_TOOLS=(python3 jq find ctags)
readonly OPTIONAL_TOOLS=(tree)
readonly VENV_NAMES=("venv" ".venv" "env" ".env" "__pypackages__")

# Global state variables, populated by argument parser
DRY_RUN=false
DEBUG_MODE=false
INCLUDE_VENV=false
TARGET_DIR="."
OUTPUT_FORMAT="text"
LOG_LEVEL=3 # Default: INFO (3=INFO, 4=DEBUG)
LOG_FILE="/tmp/pyanalyzer_$(date +%Y%m%d).log"

# ==============================================================================
# SECTION 2: LOGGING & MONITORING MODULE
# ==============================================================================
# Provides color-coded logging, progress updates, and performance metrics.

# --- Tiered Logging System ---
log() {
    local level_code=$1
    local message="$2"
    local level_name color

    # Skip logging if level is too low
    [[ $level_code -gt $LOG_LEVEL ]] && return 0

    case $level_code in
        0) level_name="FATAL"; color="\033[0;31m";;
        1) level_name="ERROR"; color="\033[0;31m";;
        2) level_name="WARN";  color="\033[1;33m";;
        3) level_name="INFO";  color="\033[0;32m";;
        4) level_name="DEBUG"; color="\033[0;34m";;
        *) level_name="LOG";   color="\033[0m";;
    esac

    # Log to console and file
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    echo -e "${color}[${level_name}]${NC} ${message}" >&2
    echo "${timestamp} [${level_name}] ${message}" >> "$LOG_FILE"
}

fatal() { log 0 "$1"; exit 1; }
error() { log 1 "$1"; }
warn()  { log 2 "$1"; }
info()  { log 3 "$1"; }
debug() { log 4 "$1"; }

# --- Performance Metrics ---
declare -A METRICS
init_monitoring() {
    METRICS=(
        [start_time]=$(date +%s%N)
        [files_processed]=0
        [errors_encountered]=0
    )
    # Setup automatic report generation on script exit
    trap 'generate_performance_report' EXIT
}

record_metric() {
    local key=$1
    local value=${2:-1}
    ((METRICS[$key]+=$value))
}

generate_performance_report() {
    local end_time
    end_time=$(date +%s%N)
    local duration_ms=$(((end_time - METRICS[start_time]) / 1000000))
    local duration_s
    duration_s=$(printf "%.3f" "$(bc -l <<< "$duration_ms / 1000")")

    debug "--- Performance Report ---"
    debug "Total execution time: ${duration_s}s"
    debug "Python files processed: ${METRICS[files_processed]}"
    debug "Errors encountered: ${METRICS[errors_encountered]}"
}

# ==============================================================================
# SECTION 3: SYSTEM VALIDATION MODULE
# ==============================================================================
# Checks for required system dependencies before execution.

playground_assessment() {
    info "Running system environment validation..."
    local -i all_ok=1

    # Check for required tools
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if ! command -v "$tool" &>/dev/null; then
            error "Required tool not found: '$tool'. Please install it."
            all_ok=0
        else
            debug "Verified tool: '$tool'"
        fi
    done

    # Special check for universal-ctags
    if command -v "ctags" &>/dev/null && ! ctags --version | grep -q "Universal"; then
        warn "'ctags' found, but it may not be Universal Ctags. Code indexing might be incomplete."
    fi

    [[ $all_ok -eq 1 ]] || fatal "System validation failed. Aborting."
    info "System environment is ready."
}

# ==============================================================================
# SECTION 4: PYTHON ANALYSIS ENGINE
# ==============================================================================
# The core logic for discovering and analyzing Python files.

filter_venv_paths() {
    # This function uses grep to filter out paths containing venv directory names.
    # It's used as a pipe to process file lists from `find`.
    if [[ "$INCLUDE_VENV" == "false" ]]; then
        local pattern
        pattern=$(IFS="|"; echo "${VENV_NAMES[*]}")
        debug "Excluding virtual environment paths matching: /$pattern/"
        grep -vE "/($pattern)/"
    else
        # If including venv, just pass the input through
        cat
    fi
}

find_entry_points() {
    # Find files named main.py or any file containing the __main__ execution block.
    find "$1" -type f \( -name "main.py" -o -name "*.py" \) -print0 | \
        xargs -0 grep -l "if __name__ *== *['\"]__main__['\"]" 2>/dev/null | \
        filter_venv_paths || true
}

generate_dependency_graph() {
    # Passes the exclusion configuration to a Python script that leverages
    # the AST module for accurate import parsing.
    local venv_names_csv
    venv_names_csv=$(IFS=","; echo "${VENV_NAMES[*]}")

    python3 -c "
import ast, json, os, sys
from pathlib import Path

def get_imports(file_path):
    '''Extracts top-level imports from a Python file.'''
    imports = set()
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            tree = ast.parse(f.read(), filename=str(file_path))
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for alias in node.names:
                    imports.add(alias.name.split('.')[0])
            elif isinstance(node, ast.ImportFrom):
                if node.module:
                    imports.add(node.module.split('.')[0])
    except Exception:
        pass # Silently ignore files that can't be parsed
    return sorted(list(imports))

try:
    target_dir = sys.argv[1]
    include_venv = sys.argv[2] == 'true'
    venv_names = set(sys.argv[3].split(','))

    all_files = list(Path(target_dir).rglob('*.py'))

    if not include_venv:
        filtered_files = [
            p for p in all_files
            if not any(part in venv_names for part in p.parts)
        ]
        all_files = filtered_files

    graph = {
        str(p.relative_to(target_dir)): get_imports(p)
        for p in all_files
    }
    print(json.dumps(graph, indent=2))
except Exception:
    sys.exit(1)
" "$1" "$INCLUDE_VENV" "$venv_names_csv"
}

index_code_structures() {
    # Uses universal-ctags' --exclude flag for efficient directory skipping.
    if ! command -v "ctags" &>/dev/null; then
        warn "ctags not found, skipping code structure indexing."
        echo "{}"
        return
    fi

    local ctags_exclude_args=()
    if [[ "$INCLUDE_VENV" == "false" ]]; then
        for venv_name in "${VENV_NAMES[@]}"; do
            ctags_exclude_args+=(--exclude="$venv_name")
        done
        debug "ctags excluding: ${ctags_exclude_args[*]}"
    fi

    ctags "${ctags_exclude_args[@]}" --fields=+S --output-format=json -R "$1" 2>/dev/null | \
    jq -s 'group_by(.path) | map({(.[0].path | ltrimstr("'$1'/")) : {
        classes: [.[] | select(.kind == "class") | .name],
        functions: [.[] | select(.kind == "function") | .name]
    }}) | add'
}

analyze_project() {
    info "Starting analysis of target: '$TARGET_DIR'"
    TARGET_DIR=$(realpath "$TARGET_DIR")

    if [[ ! -d "$TARGET_DIR" ]]; then
        error "Target directory not found: $TARGET_DIR"
        return 1
    fi

    if [[ "$INCLUDE_VENV" == "true" ]]; then
        warn "Including virtual environments in analysis (--venv)."
    fi

    # --- Data Collection ---
    info "Step 1/3: Identifying entry points..."
    local entry_points
    entry_points=$(find_entry_points "$TARGET_DIR")
    debug "Found entry points:\n${entry_points:-None}"

    info "Step 2/3: Building dependency graph..."
    local dep_graph
    dep_graph=$(generate_dependency_graph "$TARGET_DIR")
    [[ -z "$dep_graph" ]] && { error "Failed to generate dependency graph."; return 1; }
    record_metric "files_processed" "$(echo "$dep_graph" | jq 'length')"

    info "Step 3/3: Indexing code structures..."
    local code_index
    code_index=$(index_code_structures "$TARGET_DIR")

    # --- Consolidated Reporting ---
    info "Analysis complete. Consolidating report..."

    # Use temporary files for large JSON data
    local temp_deps=$(mktemp)
    local temp_index=$(mktemp)
    echo "$dep_graph" > "$temp_deps"
    echo "$code_index" > "$temp_index"

    # Generate final report using file references
    case "$OUTPUT_FORMAT" in
        json)
            jq -n \
                --slurpfile deps "$temp_deps" \
                --slurpfile index "$temp_index" \
                --arg entries "$(echo "$entry_points" | jq -R . | jq -s .)" \
                '{
                    metadata: {
                        target_directory: "'"$TARGET_DIR"'",
                        analysis_timestamp: (now | todate),
                        version: "'"$VERSION"'"
                    },
                    entry_points: $entries,
                    dependency_graph: $deps[0],
                    code_index: $index[0]
                }'
            ;;
        text | tree)
            # Human-readable summary
            echo -e "\n--- Analysis Summary for: $TARGET_DIR ---\n"
            echo "Entry Points:"
            echo "$entry_points" | while read -r ep; do echo "  - $ep"; done || echo "  None found"
            echo -e "\nFiles Processed: $(jq 'length' "$temp_deps")"
            echo -e "\nCode Index Summary:"
            jq -r 'to_entries[] | "  - \(.key): \(.value.classes | length) classes, \(.value.functions | length) functions"' "$temp_index"
            ;;
        *)
            error "Unknown output format: '$OUTPUT_FORMAT'"
            return 1
            ;;
    esac

    # Cleanup
    rm -f "$temp_deps" "$temp_index"
}

# ==============================================================================
# SECTION 5: HELP & ARGUMENT PARSING
# ==============================================================================
show_help() {
    cat <<EOF
PyAnalyzer v$VERSION - A self-contained Python codebase analysis tool.

Usage: $SCRIPT_NAME [OPTIONS] [TARGET_DIRECTORY]

Analyzes user-created Python files in the target directory to map dependencies
and index code structures. Virtual environment directories are excluded by default.

OPTIONS:
  -f, --format FMT   Output format. One of: text (default), json, tree.
  --venv             Include virtual environment directories in the analysis.
  -d, --dry-run      Perform checks but do not run the full analysis.
  -D, --debug        Enable verbose debug logging.
  -h, --help         Display this help message and exit.
  -v, --version      Display script version and exit.

DEPENDENCIES:
  - bash (v4+), python3, jq, find, realpath, grep, xargs
  - universal-ctags (required for code indexing)
EOF
}

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--format)
                OUTPUT_FORMAT="$2"
                shift 2
                ;;
            --venv)
                INCLUDE_VENV=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -D|--debug)
                DEBUG_MODE=true
                LOG_LEVEL=4
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                echo "$SCRIPT_NAME v$VERSION"
                exit 0
                ;;
            --)
                shift
                break
                ;;
            -*)
                error "Unknown option: $1"
                show_help
                exit 1
                ;;
            *)
                TARGET_DIR="$1"
                shift
                ;;
        esac
    done
}

# ==============================================================================
# SECTION 6: MAIN EXECUTION WORKFLOW
# ==============================================================================
main() {
    # Initialize color codes for logging
    NC='\033[0m'

    parse_arguments "$@"
    init_monitoring

    info "PyAnalyzer v$VERSION starting..."
    debug "Log file for this session: $LOG_FILE"

    playground_assessment

    if [[ "$DRY_RUN" == "true" ]]; then
        info "Dry-run mode enabled. Halting before analysis."
        exit 0
    fi

    if ! analyze_project; then
        record_metric "errors_encountered"
        fatal "Analysis failed. Please check logs for details."
    fi

    info "Analysis completed successfully."
}

# --- Script Entry Point ---
main "$@"