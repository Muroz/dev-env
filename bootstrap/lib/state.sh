#!/usr/bin/env bash

# ============================================================================
# State Management Functions
# ============================================================================
# Handles installation state tracking via JSON file
#
# State file location: ~/.dev-env/state.json
#
# Functions:
# - init_state_file() - Create state file if missing
# - get_section_state() - Read section data
# - update_section_state() - Update section data
# - section_is_installed() - Check if section is installed
# - record_installation_start() - Mark installation beginning
# - record_section_installed() - Mark section as installed
# - record_backup() - Record backup location
# - rebuild_state_from_system() - Detect installations from system
#
# ============================================================================

# State file location
STATE_DIR="$HOME/.dev-env"
STATE_FILE="$STATE_DIR/state.json"
STATE_VERSION="1.0.0"

# Source utils if not already loaded
if ! command -v info &>/dev/null; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/utils.sh"
fi

# ============================================================================
# State File Initialization
# ============================================================================

init_state_file() {
    # Create state directory
    if [ ! -d "$STATE_DIR" ]; then
        mkdir -p "$STATE_DIR" || {
            error "Failed to create state directory: $STATE_DIR"
            return 1
        }
    fi

    # Create state file if it doesn't exist
    if [ ! -f "$STATE_FILE" ]; then
        info "Initializing state file: $STATE_FILE"

        cat > "$STATE_FILE" << EOF
{
  "version": "$STATE_VERSION",
  "installation": {
    "date": "",
    "mode": ""
  },
  "sections": {},
  "backups": []
}
EOF
        return $?
    fi

    return 0
}

# ============================================================================
# Installation Tracking
# ============================================================================

record_installation_start() {
    local mode="${1:-standard}"  # "standard" or "mise"

    if [ ! -f "$STATE_FILE" ]; then
        init_state_file
    fi

    if ! has_jq; then
        warning "jq not available - state tracking limited"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    jq ".installation.date = \"$timestamp\" | .installation.mode = \"$mode\"" \
        "$STATE_FILE" > "$STATE_FILE.tmp" && \
        mv "$STATE_FILE.tmp" "$STATE_FILE"
}

record_section_installed() {
    local section="$1"
    local metadata="${2:-{}}"  # JSON object with section-specific data

    if [ ! -f "$STATE_FILE" ]; then
        init_state_file
    fi

    if ! has_jq; then
        warning "jq not available - cannot record section: $section"
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Merge metadata with installed flag and timestamp
    local section_data=$(echo "$metadata" | jq ". + {installed: true, date: \"$timestamp\"}")

    # Update state file
    jq ".sections.\"$section\" = $section_data" \
        "$STATE_FILE" > "$STATE_FILE.tmp" && \
        mv "$STATE_FILE.tmp" "$STATE_FILE"
}

record_section_skipped() {
    local section="$1"
    local reason="${2:-}"

    if [ ! -f "$STATE_FILE" ]; then
        init_state_file
    fi

    if ! has_jq; then
        return 1
    fi

    local data="{\"installed\": false, \"skipped_reason\": \"$reason\"}"

    jq ".sections.\"$section\" = $data" \
        "$STATE_FILE" > "$STATE_FILE.tmp" && \
        mv "$STATE_FILE.tmp" "$STATE_FILE"
}

record_section_uninstalled() {
    local section="$1"

    if [ ! -f "$STATE_FILE" ]; then
        return 0
    fi

    if ! has_jq; then
        return 1
    fi

    # Mark as not installed
    jq ".sections.\"$section\".installed = false" \
        "$STATE_FILE" > "$STATE_FILE.tmp" && \
        mv "$STATE_FILE.tmp" "$STATE_FILE"
}

# ============================================================================
# Backup Tracking
# ============================================================================

record_backup() {
    local backup_dir="$1"

    if [ ! -f "$STATE_FILE" ]; then
        init_state_file
    fi

    if ! has_jq; then
        return 1
    fi

    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Get list of files in backup
    local files=$(ls -1 "$backup_dir" 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')

    local backup_entry="{\"date\": \"$timestamp\", \"path\": \"$backup_dir\", \"files\": $files}"

    # Add to backups array
    jq ".backups += [$backup_entry]" \
        "$STATE_FILE" > "$STATE_FILE.tmp" && \
        mv "$STATE_FILE.tmp" "$STATE_FILE"
}

list_backups() {
    if [ ! -f "$STATE_FILE" ]; then
        return 0
    fi

    if ! has_jq; then
        # Fallback: list backup directories manually
        find "$HOME" -maxdepth 1 -name ".dotfiles-backup-*" -type d 2>/dev/null
        return $?
    fi

    jq -r '.backups[]? | "\(.date)\t\(.path)"' "$STATE_FILE"
}

# ============================================================================
# State Queries
# ============================================================================

section_is_installed() {
    local section="$1"

    if [ ! -f "$STATE_FILE" ]; then
        return 1
    fi

    if has_jq; then
        jq -e ".sections.\"$section\".installed == true" "$STATE_FILE" >/dev/null 2>&1
    else
        grep -q "\"$section\".*\"installed\"[[:space:]]*:[[:space:]]*true" "$STATE_FILE" 2>/dev/null
    fi
}

get_section_state() {
    local section="$1"

    if [ ! -f "$STATE_FILE" ]; then
        echo "{}"
        return 1
    fi

    if has_jq; then
        jq -r ".sections.\"$section\" // {}" "$STATE_FILE"
    else
        echo "{}"
        return 1
    fi
}

get_installation_mode() {
    if [ ! -f "$STATE_FILE" ]; then
        echo "unknown"
        return 1
    fi

    if has_jq; then
        jq -r '.installation.mode // "unknown"' "$STATE_FILE"
    else
        grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$STATE_FILE" | \
            sed 's/.*"\([^"]*\)".*/\1/' | head -1
    fi
}

get_installation_date() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return 1
    fi

    if has_jq; then
        jq -r '.installation.date // ""' "$STATE_FILE"
    else
        echo ""
    fi
}

list_installed_sections() {
    if [ ! -f "$STATE_FILE" ]; then
        echo ""
        return 1
    fi

    if has_jq; then
        jq -r '.sections | to_entries[] | select(.value.installed == true) | .key' "$STATE_FILE"
    else
        echo ""
        return 1
    fi
}

# ============================================================================
# State Verification
# ============================================================================

verify_section_state() {
    local section="$1"

    case "$section" in
        homebrew)
            command_exists brew
            ;;
        oh_my_zsh)
            [ -d "$HOME/.oh-my-zsh" ]
            ;;
        nvm)
            [ -d "$HOME/.nvm" ]
            ;;
        pyenv)
            command_exists pyenv
            ;;
        bun)
            [ -d "$HOME/.bun" ] || command_exists bun
            ;;
        mise)
            command_exists mise
            ;;
        rust)
            [ -d "$HOME/.cargo" ] && command_exists cargo
            ;;
        symlinks)
            [ -L "$HOME/.zshrc" ] || [ -L "$HOME/.gitconfig" ] || [ -L "$HOME/.gitignore_global" ]
            ;;
        vscode_extensions)
            command_exists code
            ;;
        git_config)
            [ -n "$(git config --global user.name 2>/dev/null)" ]
            ;;
        shell_config)
            [ -f "$HOME/.zshrc.local" ]
            ;;
        brew_packages|brew_casks)
            command_exists brew
            ;;
        *)
            return 1
            ;;
    esac
}

# ============================================================================
# System Detection (State Recovery)
# ============================================================================

detect_installed_sections() {
    local sections=()

    # Check each section on the system
    if command_exists brew; then
        sections+=("homebrew")
        sections+=("brew_packages")

        # Check for specific version managers
        if brew list --formula nvm &>/dev/null || [ -d "$HOME/.nvm" ]; then
            sections+=("nvm")
        fi

        if brew list --formula pyenv &>/dev/null || command_exists pyenv; then
            sections+=("pyenv")
        fi

        if brew list --formula mise &>/dev/null || command_exists mise; then
            sections+=("mise")
        fi

        # Check for casks
        if brew list --cask claude-code &>/dev/null; then
            sections+=("brew_casks")
        fi
    fi

    [ -d "$HOME/.oh-my-zsh" ] && sections+=("oh_my_zsh")
    [ -d "$HOME/.bun" ] && sections+=("bun")
    [ -d "$HOME/.cargo" ] && sections+=("rust")
    [ -L "$HOME/.zshrc" ] && sections+=("symlinks")
    [ -f "$HOME/.zshrc.local" ] && sections+=("shell_config")
    [ -n "$(git config --global user.name 2>/dev/null)" ] && sections+=("git_config")
    command_exists code && sections+=("vscode_extensions")

    # Remove duplicates
    echo "${sections[@]}" | tr ' ' '\n' | sort -u
}

rebuild_state_from_system() {
    info "Rebuilding state from system detection..."

    init_state_file

    local detected_sections=$(detect_installed_sections)
    local mode="unknown"

    # Determine installation mode
    if echo "$detected_sections" | grep -q "mise"; then
        mode="mise"
    elif echo "$detected_sections" | grep -q "nvm\|pyenv"; then
        mode="standard"
    fi

    # Record installation start (with detected mode)
    if has_jq; then
        local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
        jq ".installation.date = \"$timestamp\" | .installation.mode = \"$mode\"" \
            "$STATE_FILE" > "$STATE_FILE.tmp" && \
            mv "$STATE_FILE.tmp" "$STATE_FILE"
    fi

    # Record each detected section
    for section in $detected_sections; do
        record_section_installed "$section" "{\"detected\": true}"
    done

    success "State rebuilt from system (detected $mode mode)"
}

# ============================================================================
# State Export/Import
# ============================================================================

export_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo "{}"
    fi
}

import_state() {
    local state_json="$1"

    if [ -z "$state_json" ]; then
        error "No state data provided"
        return 1
    fi

    # Validate JSON
    if has_jq; then
        if ! echo "$state_json" | jq empty 2>/dev/null; then
            error "Invalid JSON data"
            return 1
        fi
    fi

    # Write to state file
    echo "$state_json" > "$STATE_FILE"
    success "State imported successfully"
}

reset_state() {
    if [ -f "$STATE_FILE" ]; then
        local backup="${STATE_FILE}.backup-$(date +%Y%m%d_%H%M%S)"
        mv "$STATE_FILE" "$backup"
        info "Previous state backed up to: $backup"
    fi

    init_state_file
    success "State reset"
}

# ============================================================================
# State Diff (Compare State vs System)
# ============================================================================

check_state_drift() {
    if [ ! -f "$STATE_FILE" ]; then
        warning "State file not found"
        return 1
    fi

    local drifted=false
    local installed_sections=$(list_installed_sections)

    echo "Checking for drift between state file and actual system..."
    echo ""

    for section in $installed_sections; do
        if ! verify_section_state "$section"; then
            warning "State says installed but not found on system: $section"
            drifted=true
        fi
    done

    local detected_sections=$(detect_installed_sections)
    for section in $detected_sections; do
        if ! section_is_installed "$section"; then
            warning "Found on system but not in state: $section"
            drifted=true
        fi
    done

    if [ "$drifted" = false ]; then
        success "No drift detected - state matches system"
        return 0
    else
        warning "Drift detected - state and system are out of sync"
        info "Run: ./uninstall.sh --rebuild-state to fix"
        return 1
    fi
}
