#!/usr/bin/env bash

# ============================================================================
# Shared Utility Functions
# ============================================================================
# Common helper functions used across install and uninstall scripts
#
# Functions:
# - Color output (info, success, warning, error)
# - confirm() - Interactive yes/no prompts
# - command_exists() - Check if command is available
# - JSON helpers - Parse and manipulate JSON data
#
# ============================================================================

# Colors for output (reuse from install.sh)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Output Functions
# ============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# ============================================================================
# Interactive Prompts
# ============================================================================

confirm() {
    local message="$1"
    local default="${2:-n}"  # Default to 'no'

    # Skip prompt if FORCE mode
    if [ "${FORCE:-false}" = true ]; then
        return 0
    fi

    local prompt
    if [ "$default" = "y" ]; then
        prompt="$message [Y/n] "
    else
        prompt="$message [y/N] "
    fi

    read -p "$prompt" -n 1 -r
    echo # New line after input

    if [ "$default" = "y" ]; then
        # Default yes: return false only if explicitly 'n' or 'N'
        [[ $REPLY =~ ^[Nn]$ ]] && return 1 || return 0
    else
        # Default no: return true only if explicitly 'y' or 'Y'
        [[ $REPLY =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

# ============================================================================
# Command Availability
# ============================================================================

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# JSON Helpers
# ============================================================================

# Check if jq is available
has_jq() {
    command_exists jq
}

# Parse JSON using jq (preferred) or fallback to manual parsing
json_get() {
    local file="$1"
    local key="$2"

    if [ ! -f "$file" ]; then
        echo ""
        return 1
    fi

    if has_jq; then
        # Use jq for robust JSON parsing
        jq -r "$key // empty" "$file" 2>/dev/null
    else
        # Fallback: Simple grep-based parsing (less robust)
        # This is a basic implementation - jq is recommended
        grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | \
            sed 's/.*:\s*"\([^"]*\)".*/\1/' | head -1
    fi
}

# Get array values from JSON
json_get_array() {
    local file="$1"
    local key="$2"

    if [ ! -f "$file" ]; then
        echo ""
        return 1
    fi

    if has_jq; then
        jq -r "$key[]? // empty" "$file" 2>/dev/null
    else
        # Fallback: Basic array parsing
        warning "jq not installed - array parsing may be inaccurate"
        return 1
    fi
}

# Check if JSON key exists
json_has_key() {
    local file="$1"
    local key="$2"

    if [ ! -f "$file" ]; then
        return 1
    fi

    if has_jq; then
        jq -e "$key" "$file" >/dev/null 2>&1
    else
        grep -q "\"$key\"" "$file" 2>/dev/null
    fi
}

# Update JSON value (requires jq)
json_set() {
    local file="$1"
    local key="$2"
    local value="$3"

    if [ ! -f "$file" ]; then
        error "JSON file not found: $file"
        return 1
    fi

    if ! has_jq; then
        error "jq is required for JSON updates"
        error "Install: brew install jq"
        return 1
    fi

    # Create temporary file
    local temp_file="${file}.tmp"

    # Update JSON
    jq "$key = $value" "$file" > "$temp_file" && mv "$temp_file" "$file"
}

# ============================================================================
# Path Helpers
# ============================================================================

# Get absolute path
get_absolute_path() {
    local path="$1"

    if [ -d "$path" ]; then
        (cd "$path" && pwd)
    elif [ -f "$path" ]; then
        local dir=$(dirname "$path")
        local file=$(basename "$path")
        echo "$(cd "$dir" && pwd)/$file"
    else
        echo "$path"
    fi
}

# Check if path is a symlink
is_symlink() {
    [ -L "$1" ]
}

# Get symlink target
get_symlink_target() {
    if is_symlink "$1"; then
        readlink "$1"
    else
        echo ""
    fi
}

# ============================================================================
# Array Helpers
# ============================================================================

# Check if array contains value
array_contains() {
    local needle="$1"
    shift
    local haystack=("$@")

    for item in "${haystack[@]}"; do
        if [ "$item" = "$needle" ]; then
            return 0
        fi
    done

    return 1
}

# Remove duplicates from array
array_unique() {
    local arr=("$@")
    local unique=()

    for item in "${arr[@]}"; do
        if ! array_contains "$item" "${unique[@]}"; then
            unique+=("$item")
        fi
    done

    echo "${unique[@]}"
}

# ============================================================================
# File Helpers
# ============================================================================

# Backup file with timestamp
backup_file() {
    local file="$1"
    local backup_dir="${2:-$HOME}"

    if [ ! -f "$file" ]; then
        return 1
    fi

    local basename=$(basename "$file")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_path="$backup_dir/${basename}.backup-${timestamp}"

    cp "$file" "$backup_path"
    echo "$backup_path"
}

# Check if file or directory is empty
is_empty() {
    local path="$1"

    if [ -f "$path" ]; then
        [ ! -s "$path" ]
    elif [ -d "$path" ]; then
        [ -z "$(ls -A "$path" 2>/dev/null)" ]
    else
        return 1
    fi
}

# ============================================================================
# String Helpers
# ============================================================================

# Trim whitespace
trim() {
    local str="$1"
    # Remove leading/trailing whitespace
    echo "$str" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# Join array with delimiter
join_by() {
    local delimiter="$1"
    shift
    local first="$1"
    shift
    printf "%s" "$first" "${@/#/$delimiter}"
}

# ============================================================================
# Validation
# ============================================================================

# Validate section name
is_valid_section() {
    local section="$1"

    # Check if section matches expected format (alphanumeric with underscores)
    [[ "$section" =~ ^[a-z_]+$ ]]
}

# Validate file path
is_valid_path() {
    local path="$1"

    # Check if path doesn't contain dangerous characters
    case "$path" in
        *";"*|*'$'*|*'`'*) return 1 ;;
        *) return 0 ;;
    esac
}

# ============================================================================
# Error Handling
# ============================================================================

# Exit with error message
die() {
    error "$1"
    exit "${2:-1}"
}

# Check command exit status
check_status() {
    local status=$?
    local message="$1"

    if [ $status -ne 0 ]; then
        error "$message"
        return $status
    fi

    return 0
}

# ============================================================================
# Logging
# ============================================================================

# Log to file if LOG_FILE is set
log() {
    local message="$1"

    if [ -n "${LOG_FILE:-}" ]; then
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $message" >> "$LOG_FILE"
    fi
}

# ============================================================================
# Version Comparison
# ============================================================================

# Compare version strings (returns 0 if v1 >= v2)
version_gte() {
    local v1="$1"
    local v2="$2"

    # Use sort -V for version comparison
    printf '%s\n%s' "$v2" "$v1" | sort -V -C
}
