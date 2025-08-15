#!/usr/bin/env bash
#
# ==============================================================================
# PyAnalyzer v3.4 - Single-File Python Codebase Analysis Tool
#
# A self-contained Bash script to perform deep analysis of Python projects.
# It generates a hierarchical report of file structures, dependencies, and
# detailed class/function signatures by parsing the Abstract Syntax Tree (AST).
# ==============================================================================

# --- Strict Mode ---
set -o errexit
set -o nounset
set -o pipefail

# ==============================================================================
# SECTION 1: CORE CONSTANTS & CONFIGURATION
# ==============================================================================
readonly VERSION="3.4"
readonly SCRIPT_NAME="${0##*/}"
readonly REQUIRED_TOOLS=(python3 jq find grep)

# --- Default File Filtering & Color Configuration ---
readonly DEFAULT_EXCLUDE_DIRS=( ".git" ".idea" ".vscode" "__pycache__" ".cache" "build" "dist" "*.egg-info" "node_modules" "target" "site" ".pytest_cache" ".mypy_cache" ".tox" ".nox" "htmlcov" )
readonly VENV_NAMES=("venv" ".venv" "env" ".env" "__pypackages__")
readonly DEFAULT_EXCLUDE_FILES=("*.pyc" "*.pyo" "*.pyd" "*.so" ".*.swp")
readonly DEFAULT_INCLUDE_FORMATS=("*.py")
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
log() { local level_code=$1 msg="$2" level_name color; [[ $level_code -gt $LOG_LEVEL ]] && return 0; case $level_code in 0) level_name="FATAL"; color=$'\033[0;31m';; 1) level_name="ERROR"; color=$'\033[0;31m';; 2) level_name="WARN"; color=$'\033[1;33m';; 3) level_name="INFO"; color=$'\033[0;32m';; 4) level_name="DEBUG"; color=$'\033[0;34m';; *) level_name="LOG"; color=$'\033[0m';; esac; local ts; ts=$(date "+%Y-%m-%d %H:%M:%S"); echo -e "${color}[${level_name}]${C_NC} ${msg}" >&2; echo "${ts} [${level_name}] ${msg}" >> "$LOG_FILE"; }
log_nn() { local level_code=$1 msg="$2" level_name color; [[ $level_code -gt $LOG_LEVEL ]] && return 0; case $level_code in 0) level_name="FATAL"; color=$'\033[0;31m';; 1) level_name="ERROR"; color=$'\033[0;31m';; 2) level_name="WARN"; color=$'\033[1;33m';; 3) level_name="INFO"; color=$'\033[0;32m';; 4) level_name="DEBUG"; color=$'\033[0;34m';; *) level_name="LOG"; color=$'\033[0m';; esac; echo -n -e "${color}[${level_name}]${C_NC} ${msg}"; }
fatal() { log 0 "$1"; exit 1; }
error() { log 1 "$1"; }
warn()  { log 2 "$1"; }
info()  { log 3 "$1"; }
info_nn() { log_nn 3 "$1"; }
debug() { log 4 "$1"; }
declare -A METRICS
init_monitoring() { METRICS=([start_time]=$(date +%s%N) [files_processed]=0 [errors_encountered]=0); trap 'generate_performance_report' EXIT; }
record_metric() { local key=$1 value=${2:-1}; ((METRICS[$key]+=value)); }
generate_performance_report() { local end_time duration_ms duration_s; end_time=$(date +%s%N); duration_ms=$(((end_time - METRICS[start_time]) / 1000000)); duration_s=$(printf "%.3f" "$(bc -l <<< "$duration_ms / 1000")"); debug "--- Performance Report ---"; debug "Total execution time: ${duration_s}s"; debug "Files processed: ${METRICS[files_processed]}"; debug "Errors encountered: ${METRICS[errors_encountered]}"; }

# ==============================================================================
# SECTION 3: SYSTEM & PROJECT VALIDATION MODULE
# ==============================================================================
playground_assessment() { info "Running system environment validation..."; local -i all_ok=1; for tool in "${REQUIRED_TOOLS[@]}"; do if ! command -v "$tool" &>/dev/null; then error "Required tool not found: '$tool'. Please install it."; all_ok=0; else debug "Verified tool: '$tool'"; fi; done; [[ $all_ok -eq 1 ]] || fatal "System validation failed. Aborting."; info "System environment is ready."; }

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

find_entry_points() {
    local files_to_check; mapfile -t files_to_check
    if [[ ${#files_to_check[@]} -eq 0 ]]; then echo ""; return; fi
    printf "%s\0" "${files_to_check[@]}" | xargs -0 grep -l "if __name__ *== *['\"]__main__['\"]" 2>/dev/null || true
}

prompt_for_entry_point() {
    local all_files_input; all_files_input=$(cat)
    mapfile -t all_files < <(echo "$all_files_input" | sed "s#^$TARGET_DIR/##")
    warn "No explicit entry points (if __name__ == '__main__') found."
    info "Please select the primary file(s) to consider as entry points."
    if [[ ${#all_files[@]} -eq 0 ]]; then error "No files found to select from. Cannot continue."; return 1; fi
    local i=0; for file in "${all_files[@]}"; do printf "  [%2d] %s\n" "$i" "$file"; ((i++)); done
    local selection; while true; do read -r -p "Enter number(s), comma-separated (e.g., 0,3): " selection < /dev/tty; if [[ "$selection" =~ ^[0-9]+(,[0-9]+)*$ ]]; then break; else error "Invalid input. Please enter numbers separated by commas."; fi; done
    local selected_paths=""; local IFS=','; for index in $selection; do if [[ "$index" -ge 0 && "$index" -lt ${#all_files[@]} ]]; then selected_paths+="${TARGET_DIR}/${all_files[$index]}\n"; else warn "Ignoring invalid index: $index"; fi; done
    echo -e "$selected_paths" | sed '/^$/d'
}

analyze_codebase_with_ast() {
    mapfile -t files_to_index < <(cat)
    if [[ ${#files_to_index[@]} -eq 0 ]]; then echo "{}"; return; fi
    python3 -c '
import ast, json, sys, re
from pathlib import Path

def get_source_segment(source_lines, node):
    try:
        return ast.get_source_segment(source="\n".join(source_lines), node=node)
    except Exception:
        return None

def parse_docstring(doc):
    if not doc: return {"purpose": "", "args": {}, "returns": ""}
    lines = [line.strip() for line in doc.strip().split("\n")]
    purpose = lines[0] if lines else ""
    args, returns = {}, ""
    current_section = None
    for line in lines[1:]:
        if line.lower().startswith("args:"): current_section = "args"
        elif line.lower().startswith("returns:"): current_section = "returns"
        elif line.strip() == "": current_section = None
        elif current_section == "args":
            match = re.match(r"(\w+)\s*(?:\((.*?)\))?:\s*(.*)", line)
            if match:
                name, type_hint, desc = match.groups()
                args[name] = {"type_hint": type_hint or "", "desc": desc.strip()}
        elif current_section == "returns":
            returns += line + " "
    return {"purpose": purpose, "args": args, "returns": returns.strip()}

def analyze_function(node, source_lines):
    name = node.name
    docstring = ast.get_docstring(node) or ""
    doc_details = parse_docstring(docstring)
    args = []
    all_args = node.args.posonlyargs + node.args.args
    defaults = node.args.defaults
    arg_offset = len(all_args) - len(defaults)
    for i, arg in enumerate(all_args):
        arg_info = {"name": arg.arg, "type_hint": "", "default": None}
        if arg.annotation:
            arg_info["type_hint"] = get_source_segment(source_lines, arg.annotation) or ""
        if i >= arg_offset:
            default_node = defaults[i - arg_offset]
            arg_info["default"] = get_source_segment(source_lines, default_node) or "..."
        args.append(arg_info)
    returns = {"type_hint": "", "doc": doc_details["returns"]}
    if node.returns:
        returns["type_hint"] = get_source_segment(source_lines, node.returns) or ""
    return {"type": "function", "name": name, "doc": doc_details["purpose"], "args": args, "returns": returns}

def analyze_file(filepath, base_dir, source_lines):
    tree = ast.parse("\n".join(source_lines), filename=str(filepath))
    imports, details = set(), {"classes": [], "functions": []}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names: imports.add(alias.name.split(".")[0])
        elif isinstance(node, ast.ImportFrom):
            if node.level == 0 and node.module: imports.add(node.module.split(".")[0])
    for node in tree.body:
        if isinstance(node, ast.FunctionDef):
            details["functions"].append(analyze_function(node, source_lines))
        elif isinstance(node, ast.ClassDef):
            doc = ast.get_docstring(node) or ""
            class_info = {"type": "class", "name": node.name, "doc": parse_docstring(doc)["purpose"], "methods": []}
            for sub_node in node.body:
                if isinstance(sub_node, ast.FunctionDef):
                    class_info["methods"].append(analyze_function(sub_node, source_lines))
            details["classes"].append(class_info)
    return {"imports": sorted(list(imports)), "details": details}

try:
    base_dir = Path(sys.argv[1]).resolve()
    all_files_data = {}
    filepaths_str = sys.argv[2:]
    for fp_str in filepaths_str:
        fp = Path(fp_str)
        relative_path = str(fp.relative_to(base_dir))
        print(f"FILE:{relative_path}", file=sys.stderr, flush=True)
        try:
            with open(fp, "r", encoding="utf-8", errors="ignore") as f:
                source_lines = f.read().splitlines()
            all_files_data[relative_path] = analyze_file(fp, base_dir, source_lines)
        except Exception as e:
            print(f"ERROR:Could not process {relative_path}: {e}", file=sys.stderr, flush=True)
            continue
    print(json.dumps(all_files_data, indent=2))
except Exception as e:
    print(f"FATAL:{e}", file=sys.stderr, flush=True)
    print("{}")
' "$TARGET_DIR" "${files_to_index[@]}"
}

render_text_report() {
    local json_report; json_report=$(cat)
    local target_dir files_processed entry_points_count
    target_dir=$(echo "$json_report" | jq -r '.metadata.target_directory')
    files_processed=$(echo "$json_report" | jq -r '.analysis_results | length')
    entry_points_count=$(echo "$json_report" | jq -r '.entry_points | length')
    echo -e "\n🌳 Analysis for: ${C_CYAN}$target_dir${C_NC}"
    echo "================================================="
    echo -e "Files Analyzed: ${C_YELLOW}${files_processed}${C_NC} | Entry Points Found: ${C_YELLOW}${entry_points_count}${C_NC}\n"
    echo -e "${C_GREEN}▶️ Entry Points:${C_NC}"
    echo "$json_report" | jq -r --arg td "$target_dir" 'if (.entry_points | length) > 0 then .entry_points[] | "  - \(. | ltrimstr($td + "/"))" else "  None specified." end'
    echo -e "\n${C_BLUE}🏗️ Codebase Structure & Dependencies:${C_NC}"
    echo -e "${C_DIM}Legend: ${C_MAGENTA}C${C_DIM} Class | ${C_BLUE}F${C_DIM} Function | ${C_BLUE}M${C_DIM} Method | ${C_YELLOW}→${C_DIM} Imports/Returns${C_NC}"
    echo "$json_report" | jq -r --arg C_BOLD "$C_BOLD" --arg C_MAGENTA "$C_MAGENTA" --arg C_BLUE "$C_BLUE" --arg C_YELLOW "$C_YELLOW" --arg C_DIM "$C_DIM" --arg C_NC "$C_NC" '
    .analysis_results | to_entries[] | .key as $path | .value as $file_data | (
        "\n▫︎ " + $C_BOLD + $path + $C_NC +
        ([$file_data.details.functions[]? | . as $func | "\n  " + $C_BLUE + "F " + $func.name + "(" + ($func.args | map(.name + (if .type_hint != "" then ":" + .type_hint else "" end) + (if .default then "=" + .default else "" end)) | join(", ")) + ")" + $C_NC + (if $func.doc and $func.doc != "" then "\n    " + $C_DIM + $func.doc + $C_NC else "" end) + (if $func.returns.type_hint and $func.returns.type_hint != "None" and $func.returns.type_hint != "" then "\n    " + $C_YELLOW + "→ Returns: " + $C_NC + $C_DIM + $func.returns.type_hint + $C_NC else "" end) ] | join("")) +
        ([$file_data.details.classes[]? | . as $class | "\n  " + $C_MAGENTA + "C " + $class.name + $C_NC + (if $class.doc and $class.doc != "" then "\n    " + $C_DIM + $class.doc + $C_NC else "" end) + ([$class.methods[]? | . as $method | "\n    " + $C_BLUE + "M " + $method.name + "(" + ($method.args | map(.name + (if .type_hint != "" then ":" + .type_hint else "" end) + (if .default then "=" + .default else "" end)) | join(", ")) + ")" + $C_NC + (if $method.doc and $method.doc != "" then "\n      " + $C_DIM + $method.doc + $C_NC else "" end) + (if $method.returns.type_hint and $method.returns.type_hint != "None" and $method.returns.type_hint != "" then "\n      " + $C_YELLOW + "→ Returns: " + $C_NC + $C_DIM + $method.returns.type_hint + $C_NC else "" end) ] | join("")) ] | join("")) +
        (if $file_data.imports and ($file_data.imports | length > 0) then "\n  " + $C_YELLOW + "→ Imports: " + $C_NC + ($file_data.imports | join(", ")) else "" end)
    )'
    echo -e "\n================================================="
}

analyze_project() {
    # --- Step 1: File Discovery ---
    info_nn "Step 1/3: Discovering project files..."
    local project_files; project_files=$(find_all_project_files)
    if [[ -z "$project_files" ]]; then echo -e " ${C_YELLOW}Found: 0${C_NC}"; warn "No files matching filters found in '$TARGET_DIR'."; return 0; fi
    local file_count; file_count=$(echo "$project_files" | wc -l | xargs); echo -e " ${C_GREEN}Found: $file_count${C_NC}"; record_metric "files_processed" "$file_count"

    # --- Step 2: Entry Point Identification ---
    info_nn "Step 2/3: Identifying entry points..."
    local entry_points; entry_points=$(echo "$project_files" | find_entry_points)
    local entry_point_count; entry_point_count=$(echo "$entry_points" | sed '/^\s*$/d' | wc -l | xargs)
    if [[ "$entry_point_count" -eq 0 ]]; then
        echo -e " ${C_YELLOW}None automatically.${C_NC}"; entry_points=$(echo "$project_files" | prompt_for_entry_point)
        [[ -z "$entry_points" ]] && fatal "No entry point selected. Aborting."; entry_point_count=$(echo "$entry_points" | sed '/^\s*$/d' | wc -l | xargs)
        info "User selected $entry_point_count entry point(s)."
    else echo -e " ${C_GREEN}Found: $entry_point_count${C_NC}"; fi
    debug "Using entry points:\n${entry_points}"

    # --- Step 3: AST Analysis with Progress Spinner ---
    info "Step 3/3: Analyzing codebase with AST..."
    local tmp_json progress_pipe; tmp_json=$(mktemp); progress_pipe=$(mktemp -u); mkfifo "$progress_pipe"
    trap 'rm -f -- "$tmp_json" "$progress_pipe"' EXIT SIGHUP SIGINT SIGTERM

    (echo "$project_files" | analyze_codebase_with_ast > "$tmp_json") 2>"$progress_pipe" &
    local pid=$!
    local spinner_chars='|/-\' current_file="Initializing..." i=0
    echo -ne "\033[?25l"; exec 3< "$progress_pipe" # Hide cursor, open pipe for reading
    while kill -0 "$pid" 2>/dev/null; do
        if read -r -t 0.1 -u 3 line; then if [[ "$line" == FILE:* ]]; then current_file="${line#FILE:}"; fi; fi
        local display_file; if ((${#current_file} > 50)); then display_file="..."${current_file: -47}; else display_file=$current_file; fi
        echo -ne "\r\033[K  ${C_CYAN}${spinner_chars:i++%${#spinner_chars}:1}${C_NC} Analyzing... ${C_DIM}${display_file}${C_NC}"
        sleep 0.1
    done
    exec 3<&-; echo -ne "\033[?25h" # Close pipe, restore cursor

    local exit_code=0; wait "$pid" || exit_code=$?
    echo -ne "\r\033[K"; if [[ $exit_code -ne 0 ]]; then echo -e "  ${C_YELLOW}✗ Analysis failed.${C_NC}"; error "AST analysis subprocess failed."; return 1; else echo -e "  ${C_GREEN}✔ Analysis complete.${C_NC}"; fi

    # --- Report Generation ---
    info "Consolidating report..."
    local final_json
    # FIXED: Read large analysis results from the temp file via stdin redirection (<).
    # This avoids the "Argument list too long" error. Note the removal of '-n'.
    final_json=$(jq \
        --argjson entries "$(echo "$entry_points" | jq -R . | jq -s .)" \
        --arg version "$VERSION" \
        --arg dir "$TARGET_DIR" \
        '{
            "metadata": {
                "tool_version": $version,
                "analysis_timestamp": (now|todate),
                "target_directory": $dir
            },
            "entry_points": $entries,
            "analysis_results": .
        }' < "$tmp_json")

    # Clean up temporary files now that we are done with them
    rm -f -- "$tmp_json" "$progress_pipe"
    trap - EXIT SIGHUP SIGINT SIGTERM

    # Verify the final JSON was created before proceeding
    if [[ -z "$final_json" ]]; then
        error "Failed to consolidate the final JSON report."
        return 1
    fi

    case "$OUTPUT_FORMAT" in
        json) echo "$final_json" | jq --color-output . ;;
        text|tree) echo "$final_json" | render_text_report ;;
        *) error "Unknown output format: '$OUTPUT_FORMAT'"; return 1 ;;
    esac
}

# ==============================================================================
# SECTION 5 & 6: ARGUMENT PARSING & MAIN WORKFLOW
# ==============================================================================
show_help() { cat <<EOF
PyAnalyzer v$VERSION - A self-contained Python codebase analysis tool.
Usage: $SCRIPT_NAME [OPTIONS] [TARGET_DIRECTORY]
Analyzes Python files in the target directory to map dependencies and extract
detailed information about classes and functions using AST parsing.
OPTIONS:
  -f, --format FMT   Output format. One of: tree (default), text, json.
  --include-formats FORMATS  Comma-separated list of additional file formats to analyze.
  --include-all-files        Disable all default file/directory exclusions.
  --venv                     Include virtual environment directories in analysis.
  -d, --dry-run              Perform checks but do not run the full analysis.
  -D, --debug                Enable verbose debug logging.
  -h, --help                 Display this help message and exit.
  -v, --version              Display script version and exit.
DEPENDENCIES: bash (v4+), python3, jq, find, grep
EOF
}
parse_arguments() { while [[ $# -gt 0 ]]; do case "$1" in -f|--format) OUTPUT_FORMAT="$2"; shift 2 ;; --include-formats) IFS=',' read -r -a ADDITIONAL_FORMATS <<< "$2"; shift 2 ;; --include-all-files) INCLUDE_ALL_FILES=true; shift ;; --venv) INCLUDE_VENV=true; shift ;; -d|--dry-run) DRY_RUN=true; shift ;; -D|--debug) DEBUG_MODE=true; LOG_LEVEL=4; shift ;; -h|--help) show_help; exit 0 ;; -v|--version) echo "$SCRIPT_NAME v$VERSION"; exit 0 ;; --) shift; break ;; -*) error "Unknown option: $1"; show_help; exit 1 ;; *) TARGET_DIR="$1"; shift ;; esac; done; }
main() {
    parse_arguments "$@"; init_monitoring
    info "PyAnalyzer v$VERSION starting..."; debug "Log file for this session: $LOG_FILE"
    playground_assessment
    TARGET_DIR=$(realpath "$TARGET_DIR" 2>/dev/null || realpath ".")
    if [[ "$INCLUDE_ALL_FILES" == "false" ]] && [[ "$INCLUDE_VENV" == "true" ]]; then warn "Including virtual environments in analysis (--venv)."; fi
    build_find_command
    if [[ "$DRY_RUN" == "true" ]]; then info "Dry-run mode enabled."; info "Effective find command:"; printf "%q " "${FIND_COMMAND_ARGS[@]}"; echo; exit 0; fi
    if ! analyze_project; then record_metric "errors_encountered"; fatal "Analysis failed. Please check logs for details."; fi
    info "Analysis completed successfully."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi