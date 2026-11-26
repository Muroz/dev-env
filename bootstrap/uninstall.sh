#!/usr/bin/env bash

# ============================================================================
# Dev Environment Uninstaller
# ============================================================================
# Removes components installed by the bootstrap script
#
# Usage: ./uninstall.sh [OPTIONS]
#
# Options:
#   --all                    Uninstall everything
#   --sections "id1,id2..."  Uninstall specific sections or groups (comma-separated)
#   --dry-run                Preview changes without making modifications
#   --remove-data            Remove user data: tool versions and virtualenvs
#   --force                  Skip confirmation prompts
#   --restore-backups        Restore original config files from backup
#   --status                 Show what's currently installed
#   --list-sections          Show all available sections and groups
#   --verbose                Detailed output
#   --help                   Show this help message
#
# Examples:
#   ./uninstall.sh --all                         # Full uninstall (interactive)
#   ./uninstall.sh --sections "nvm,pyenv"        # Remove specific sections
#   ./uninstall.sh --sections "version_managers" # Remove using group
#   ./uninstall.sh --all --dry-run               # Preview what would be removed
#   ./uninstall.sh --status                      # Show installation status
#
# Available Sections:
#   homebrew, brew_packages, brew_casks, oh_my_zsh, nvm, pyenv, bun,
#   mise, rust, symlinks, vscode_extensions, git_config, shell_config
#
# Available Groups:
#   version_managers, configs, vscode, homebrew_all, minimal, all
#
# ============================================================================

set -o pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Source library files
source "$SCRIPT_DIR/lib/utils.sh"
source "$SCRIPT_DIR/lib/state.sh"
source "$SCRIPT_DIR/lib/sections.sh"
source "$SCRIPT_DIR/lib/uninstall-handlers.sh"

# Global flags
UNINSTALL_ALL=false
UNINSTALL_SECTIONS=""
DRY_RUN=false
REMOVE_DATA=false
FORCE=false
SHOW_STATUS=false
RESTORE_BACKUPS=false
LIST_SECTIONS=false
VERBOSE=false

# ============================================================================
# Help Message
# ============================================================================

show_help() {
    cat << 'EOF'
Dev Environment Uninstaller

Usage: ./uninstall.sh [OPTIONS]

Options:
  --all                    Uninstall everything
  --sections "id1,id2..."  Uninstall specific sections (comma-separated)
  --dry-run                Preview changes without making modifications
  --remove-data            Remove user data: tool versions and virtualenvs
  --force                  Skip confirmation prompts
  --restore-backups        Restore original config files from backup
  --status                 Show what's currently installed
  --list-sections          Show all available sections
  --verbose                Detailed output
  --help                   Show this help message

Examples:
  # Full uninstall (interactive)
  ./uninstall.sh --all

  # Remove specific sections
  ./uninstall.sh --sections "nvm,pyenv,bun"

  # Remove using group
  ./uninstall.sh --sections "version_managers"

  # Remove multiple groups and sections
  ./uninstall.sh --sections "configs,vscode"

  # Preview what would be removed
  ./uninstall.sh --all --dry-run

  # Remove with user data
  ./uninstall.sh --all --remove-data

  # Force removal without prompts
  ./uninstall.sh --all --force

  # Show installation status
  ./uninstall.sh --status

  # List all sections and groups
  ./uninstall.sh --list-sections

  # Restore backups
  ./uninstall.sh --restore-backups

Available Sections:
  homebrew          - Homebrew package manager
  brew_packages     - Homebrew formula packages
  brew_casks        - Homebrew cask applications
  oh_my_zsh         - Oh-My-Zsh framework
  nvm               - Node Version Manager
  pyenv             - Python version manager
  bun               - Bun JavaScript runtime
  mise              - Mise unified version manager
  rust              - Rust toolchain
  symlinks          - Configuration symlinks
  vscode_extensions - VS Code extensions
  git_config        - Git user configuration
  shell_config      - Shell configuration files

Available Groups:
  version_managers  - nvm, pyenv, bun, mise, rust
  configs           - symlinks, git_config, shell_config
  vscode            - vscode_extensions
  homebrew_all      - homebrew, brew_packages, brew_casks
  minimal           - symlinks, git_config, shell_config
  all               - All sections (same as --all flag)

Safety Notes:
  - User data is preserved by default (use --remove-data to remove)
  - Homebrew only removed if no other packages depend on it
  - Backups can be restored with --restore-backups
  - Use --dry-run to preview changes before applying

EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    while [ $# -gt 0 ]; do
        case "$1" in
            --all)
                UNINSTALL_ALL=true
                shift
                ;;
            --sections)
                UNINSTALL_SECTIONS="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --remove-data)
                REMOVE_DATA=true
                shift
                ;;
            --force)
                FORCE=true
                shift
                ;;
            --restore-backups)
                RESTORE_BACKUPS=true
                shift
                ;;
            --status)
                SHOW_STATUS=true
                shift
                ;;
            --list-sections)
                LIST_SECTIONS=true
                shift
                ;;
            --verbose)
                VERBOSE=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1"
                echo ""
                show_help
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Status Display
# ============================================================================

show_installation_status() {
    echo ""
    echo "================================================================"
    echo "  Installation Status"
    echo "================================================================"
    echo ""

    # Load or rebuild state
    if [ ! -f "$STATE_FILE" ]; then
        warning "State file not found - scanning system..."
        rebuild_state_from_system
    fi

    # Installation info
    local mode
    mode=$(get_installation_mode)
    local date
    date=$(get_installation_date)

    echo "Mode: $mode"
    [ -n "$date" ] && echo "Installed: $date"
    echo ""

    echo "Sections:"
    echo ""

    # Show all sections with status
    for section in "${SECTION_ORDER[@]}"; do
        local installed=false

        if section_is_installed "$section"; then
            installed=true
        fi

        # Get additional info if verbose
        if [ "$VERBOSE" = true ] && [ "$installed" = true ]; then
            local state
            state=$(get_section_state "$section")

            show_section_status "$section" "true"

            # Show section-specific details
            if [ "$section" = "brew_packages" ]; then
                local packages
                packages=$(echo "$state" | jq -r '.packages[]?' 2>/dev/null | tr '\n' ' ')
                [ -n "$packages" ] && echo "    Packages: $packages"
            elif [ "$section" = "mise" ]; then
                local tools
                tools=$(echo "$state" | jq -r '.tools[]?' 2>/dev/null | tr '\n' ' ')
                [ -n "$tools" ] && echo "    Tools: $tools"
            fi
        else
            show_section_status "$section" "$installed"
        fi
    done

    echo ""

    # Show backups
    local backups
    backups=$(list_backups)
    if [ -n "$backups" ]; then
        echo "Backups:"
        echo ""
        echo "$backups" | while IFS=$'\t' read -r date path; do
            echo "  - $date  $path"
        done
        echo ""
    fi

    echo "================================================================"
    echo ""
}

# ============================================================================
# Backup Restoration
# ============================================================================

restore_backups_interactive() {
    echo ""
    echo "================================================================"
    echo "  Restore Backups"
    echo "================================================================"
    echo ""

    local backups
    backups=$(list_backups)

    if [ -z "$backups" ]; then
        warning "No backups found"
        return 0
    fi

    echo "Available backups:"
    echo ""

    local backup_dirs=()
    while IFS=$'\t' read -r date path; do
        echo "  - $date  $path"
        backup_dirs+=("$path")
    done <<< "$backups"

    echo ""

    if [ ${#backup_dirs[@]} -eq 1 ]; then
        # Only one backup
        local backup_dir="${backup_dirs[0]}"

        if confirm "Restore files from this backup?"; then
            info "Restoring files from: $backup_dir"

            for file in "$backup_dir"/*; do
                local basename
                basename=$(basename "$file")
                info "Restoring: $basename"
                cp "$file" "$HOME/$basename"
            done

            success "Backup restored"
        fi
    else
        # Multiple backups
        echo "Enter backup number to restore (1-${#backup_dirs[@]}), or 0 to cancel:"
        read -r selection

        if [ "$selection" -eq 0 ]; then
            info "Cancelled"
            return 0
        elif [ "$selection" -ge 1 ] && [ "$selection" -le "${#backup_dirs[@]}" ]; then
            local idx
            idx=$((selection - 1))
            local backup_dir="${backup_dirs[$idx]}"

            info "Restoring files from: $backup_dir"

            for file in "$backup_dir"/*; do
                local basename
                basename=$(basename "$file")
                info "Restoring: $basename"
                cp "$file" "$HOME/$basename"
            done

            success "Backup restored"
        else
            error "Invalid selection"
            return 1
        fi
    fi

    echo ""
}

# ============================================================================
# Uninstall Execution
# ============================================================================

execute_uninstall() {
    local sections_to_uninstall=("$@")

    echo ""
    echo "================================================================"
    echo "  Dev Environment Uninstaller"
    echo "================================================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        echo -e "${YELLOW}[DRY RUN]${NC} No changes will be made"
        echo ""
    fi

    # Show what will be removed
    echo "The following sections will be REMOVED:"
    echo ""

    for section in "${sections_to_uninstall[@]}"; do
        local name
        name=$(get_section_name "$section")
        local safety
        safety=$(get_section_safety "$section")

        # Color code by safety
        case "$safety" in
            critical) echo -e "  ${RED}[CRITICAL]${NC} $section - $name" ;;
            medium)   echo -e "  ${YELLOW}[CAUTION]${NC}  $section - $name" ;;
            low)      echo -e "  ${GREEN}[SAFE]${NC}     $section - $name" ;;
        esac
    done

    echo ""

    # Data preservation notice
    if [ "$REMOVE_DATA" = false ]; then
        info "User data will be preserved: Node versions and Python virtualenvs"
        info "Use --remove-data to remove all data"
        echo ""
    else
        warning "User data will be REMOVED: Node versions and Python virtualenvs"
        echo ""
    fi

    # Confirmation (unless force mode or dry-run)
    if [ "$DRY_RUN" = false ] && [ "$FORCE" = false ]; then
        warning "This action cannot be easily undone!"
        echo ""

        if ! confirm "Do you want to continue?"; then
            info "Uninstall cancelled"
            exit 0
        fi

        echo ""
    fi

    # Execute uninstall handlers
    local success_count=0
    local fail_count=0
    local -a successful_sections=()
    local -a failed_sections=()

    for section in "${sections_to_uninstall[@]}"; do
        echo "----------------------------------------------------------------"
        echo "Uninstalling: $section"
        echo "----------------------------------------------------------------"

        # Call uninstall handler
        local handler="uninstall_${section}"

        if command -v "$handler" &>/dev/null; then
            if $handler; then
                ((success_count++))
                successful_sections+=("$section")
            else
                ((fail_count++))
                failed_sections+=("$section")
                error "Failed to uninstall: $section"
            fi
        else
            warning "No uninstall handler found for: $section"
            ((fail_count++))
            failed_sections+=("$section")
        fi

        echo ""
    done

    # Summary
    echo "================================================================"
    echo "  Uninstall Summary"
    echo "================================================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        info "Dry run complete - no changes made"
        echo ""
        info "The following sections would be affected:"
        echo ""
        if [ ${#successful_sections[@]} -gt 0 ]; then
            echo "Would uninstall ${#successful_sections[@]} section(s):"
            for section in "${successful_sections[@]}"; do
                echo "  ○ $section"
            done
        fi
    else
        # Show successful uninstalls
        if [ ${#successful_sections[@]} -gt 0 ]; then
            success "Successfully uninstalled ${#successful_sections[@]} section(s):"
            for section in "${successful_sections[@]}"; do
                echo "  ✓ $section"
            done
            echo ""
        fi

        # Show failures if any
        if [ ${#failed_sections[@]} -gt 0 ]; then
            warning "Failed to uninstall ${#failed_sections[@]} section(s):"
            for section in "${failed_sections[@]}"; do
                echo "  ✗ $section"
            done
            echo ""
        fi

        # Overall result
        if [ $fail_count -eq 0 ]; then
            success "Uninstall completed successfully!"
        else
            warning "Uninstall completed with ${#failed_sections[@]} error(s)"
        fi

        echo ""
        info "Next steps:"
        echo "  - Restart your terminal to apply changes"
        echo "  - To reinstall, run: $REPO_ROOT/bootstrap/install.sh"

        # Mention backups if they exist
        local backups
        backups=$(list_backups)
        if [ -n "$backups" ]; then
            echo "  - To restore backups: ./uninstall.sh --restore-backups"
        fi
    fi

    echo ""
    echo "================================================================"
    echo ""

    # Return fail count
    return $fail_count
}

# ============================================================================
# Main Function
# ============================================================================

main() {
    # Parse arguments
    parse_arguments "$@"

    # Handle list sections
    if [ "$LIST_SECTIONS" = true ]; then
        list_sections
        exit 0
    fi

    # Handle status display
    if [ "$SHOW_STATUS" = true ]; then
        show_installation_status
        exit 0
    fi

    # Handle backup restoration
    if [ "$RESTORE_BACKUPS" = true ]; then
        restore_backups_interactive
        exit 0
    fi

    # Ensure we have something to uninstall
    if [ "$UNINSTALL_ALL" = false ] && [ -z "$UNINSTALL_SECTIONS" ]; then
        error "No sections specified for uninstall"
        echo ""
        echo "Use --all to uninstall everything, or --sections to specify sections"
        echo "Run --help for more information"
        exit 1
    fi

    # Load or rebuild state
    if [ ! -f "$STATE_FILE" ]; then
        if [ "$DRY_RUN" = false ]; then
            warning "State file not found - rebuilding from system..."
            rebuild_state_from_system
        else
            warning "State file not found - using system detection"
        fi
    fi

    # Determine sections to uninstall
    local sections_to_uninstall=()

    if [ "$UNINSTALL_ALL" = true ]; then
        # Get mode to filter sections
        local mode
        mode=$(get_installation_mode)

        if [ "$mode" = "mise" ]; then
            read -ra sections_to_uninstall <<< "$(get_mode_sections "mise")"
        elif [ "$mode" = "standard" ]; then
            read -ra sections_to_uninstall <<< "$(get_mode_sections "standard")"
        else
            # Unknown mode - include all
            sections_to_uninstall=("${SECTION_ORDER[@]}")
        fi
    else
        # Parse section list
        local parsed
        parsed=$(parse_section_list "$UNINSTALL_SECTIONS")
        IFS=' ' read -ra sections_to_uninstall <<< "$parsed"
    fi

    # Validate sections
    for section in "${sections_to_uninstall[@]}"; do
        if ! validate_section "$section"; then
            error "Invalid section: $section"
            info "Run --list-sections to see available sections"
            exit 1
        fi
    done

    # Build proper uninstall order (reverse dependencies)
    local ordered_sections
    ordered_sections=$(build_uninstall_order "${sections_to_uninstall[@]}")
    IFS=' ' read -ra sections_to_uninstall <<< "$ordered_sections"

    # Execute uninstall and capture exit code
    execute_uninstall "${sections_to_uninstall[@]}"
    local exit_code=$?

    # Exit with error code if any failures
    if [ $exit_code -gt 0 ]; then
        exit 1
    fi

    exit 0
}

# Run main function
main "$@"
