#!/usr/bin/env bash

# ============================================================================
# Section Definitions and Metadata
# ============================================================================
# Defines all installation sections with their properties and dependencies
#
# Sections:
# 1. homebrew - Homebrew package manager
# 2. brew_packages - Homebrew formula packages
# 3. brew_casks - Homebrew cask applications
# 4. oh_my_zsh - Oh-My-Zsh framework
# 5. nvm - Node Version Manager (standard mode)
# 6. pyenv - Python version manager (standard mode)
# 7. bun - Bun JavaScript runtime (standard mode)
# 8. mise - Mise unified version manager (mise mode)
# 9. rust - Rust toolchain
# 10. symlinks - Configuration symlinks
# 11. vscode_extensions - VS Code extensions
# 12. git_config - Git user configuration
# 13. shell_config - Shell configuration files
# 14. drift_agent - Weekly drift check (launchd agent)
#
# nvm, pyenv and bun remain as sections although nothing installs them any
# more: mise replaced them, and these are how a machine that still has them
# gets cleaned up.
#
# ============================================================================

# Source utils if not already loaded
if ! command -v info &>/dev/null; then
    # Its own variable: assigning SCRIPT_DIR here would overwrite the
    # caller's, which is how install.sh once failed to find its own lib.
    _SECTIONS_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$_SECTIONS_LIB_DIR/utils.sh"
fi

# ============================================================================
# Section Definitions
# ============================================================================

# Section names (in installation order)
SECTION_ORDER=(
    "homebrew"
    "brew_packages"
    "brew_casks"
    "oh_my_zsh"
    "nvm"
    "pyenv"
    "bun"
    "mise"
    "rust"
    "symlinks"
    "vscode_extensions"
    "git_config"
    "shell_config"
    "drift_agent"
)

# ============================================================================
# Helper Functions
# ============================================================================

# Get section display name
get_section_name() {
    local section="$1"
    case "$section" in
        homebrew)           echo "Homebrew Package Manager" ;;
        brew_packages)      echo "Homebrew Packages" ;;
        brew_casks)         echo "Homebrew Cask Apps" ;;
        oh_my_zsh)          echo "Oh-My-Zsh Framework" ;;
        nvm)                echo "Node Version Manager (nvm)" ;;
        pyenv)              echo "Python Version Manager (pyenv)" ;;
        bun)                echo "Bun JavaScript Runtime" ;;
        mise)               echo "Mise Version Manager" ;;
        rust)               echo "Rust Toolchain" ;;
        symlinks)           echo "Configuration Symlinks" ;;
        vscode_extensions)  echo "VS Code Extensions" ;;
        git_config)         echo "Git User Configuration" ;;
        shell_config)       echo "Shell Configuration Files" ;;
        drift_agent)        echo "Weekly Drift Check" ;;
        *)                  echo "$section" ;;
    esac
}

# Get section description
get_section_description() {
    local section="$1"
    case "$section" in
        homebrew)           echo "Package manager for macOS" ;;
        brew_packages)      echo "Formula packages from bootstrap/brew-packages.txt" ;;
        brew_casks)         echo "GUI applications (claude-code)" ;;
        oh_my_zsh)          echo "Zsh framework with themes and plugins" ;;
        nvm)                echo "Manages multiple Node.js versions" ;;
        pyenv)              echo "Manages multiple Python versions" ;;
        bun)                echo "Fast all-in-one JavaScript runtime" ;;
        mise)               echo "Unified tool version manager (Node, Python, Bun)" ;;
        rust)               echo "Rust programming language and Cargo" ;;
        symlinks)           echo ".zshrc, .gitconfig, .gitignore_global" ;;
        vscode_extensions)  echo "30+ VS Code extensions" ;;
        git_config)         echo "Global git user.name and user.email" ;;
        shell_config)       echo "Machine-specific shell configuration (~/.zshrc.local)" ;;
        drift_agent)        echo "launchd agent that reports drift once a week" ;;
        *)                  echo "" ;;
    esac
}

# Get section dependencies
get_section_deps() {
    local section="$1"
    case "$section" in
        brew_packages)      echo "homebrew" ;;
        brew_casks)         echo "homebrew" ;;
        nvm)                echo "brew_packages" ;;
        pyenv)              echo "brew_packages" ;;
        mise)               echo "brew_packages" ;;
        *)                  echo "" ;;
    esac
}

# Get section safety level
get_section_safety() {
    local section="$1"
    case "$section" in
        homebrew)           echo "critical" ;;
        brew_packages)      echo "medium" ;;
        nvm)                echo "medium" ;;
        pyenv)              echo "medium" ;;
        mise)               echo "medium" ;;
        *)                  echo "low" ;;
    esac
}

# Check if section exists
section_exists() {
    local section="$1"
    for s in "${SECTION_ORDER[@]}"; do
        if [ "$s" = "$section" ]; then
            return 0
        fi
    done
    return 1
}

# Validate section name
validate_section() {
    local section="$1"

    if ! section_exists "$section"; then
        error "Unknown section: $section"
        return 1
    fi

    return 0
}

# Expand group to sections
expand_group() {
    local group="$1"

    case "$group" in
        version_managers)  echo "nvm,pyenv,bun,mise,rust" ;;
        configs)           echo "symlinks,git_config,shell_config" ;;
        vscode)            echo "vscode_extensions" ;;
        homebrew_all)      echo "homebrew,brew_packages,brew_casks" ;;
        minimal)           echo "symlinks,git_config,shell_config" ;;
        all)               echo "homebrew,brew_packages,brew_casks,oh_my_zsh,nvm,pyenv,bun,mise,rust,symlinks,vscode_extensions,git_config,shell_config,drift_agent" ;;
        *)                 echo "$group" ;;
    esac
}

# Parse section list (comma-separated, supports groups)
parse_section_list() {
    local input="$1"
    local sections=()

    # Split by comma
    IFS=',' read -ra items <<< "$input"

    for item in "${items[@]}"; do
        # Trim whitespace
        item=$(echo "$item" | xargs)

        # Expand if it's a group
        local expanded
        expanded=$(expand_group "$item")
        if [ "$expanded" != "$item" ]; then
            IFS=',' read -ra group_sections <<< "$expanded"
            sections+=("${group_sections[@]}")
        else
            sections+=("$item")
        fi
    done

    # Remove duplicates and return
    printf '%s\n' "${sections[@]}" | sort -u | tr '\n' ' '
}

# Get all sections
get_all_sections() {
    echo "${SECTION_ORDER[@]}"
}

# Get reverse dependency order (for uninstall)
get_reverse_order() {
    local sections=("$@")

    if [ ${#sections[@]} -eq 0 ]; then
        sections=("${SECTION_ORDER[@]}")
    fi

    # Reverse the order
    for ((i=${#sections[@]}-1; i>=0; i--)); do
        echo "${sections[i]}"
    done
}

# Check reverse dependencies (what depends on this section)
get_reverse_deps() {
    local section="$1"
    local dependents=()

    for sec in "${SECTION_ORDER[@]}"; do
        local deps
        deps=$(get_section_deps "$sec")
        if [[ "$deps" == *"$section"* ]]; then
            dependents+=("$sec")
        fi
    done

    echo "${dependents[@]}"
}

# Build uninstall order (reverse dependency order)
build_uninstall_order() {
    local input_sections=("$@")
    local ordered=()
    local visited=()

    # Helper function for topological sort
    visit() {
        local section="$1"

        # Skip if already visited
        if array_contains "$section" "${visited[@]}"; then
            return
        fi

        visited+=("$section")

        # Visit dependencies first
        local deps
        deps=$(get_reverse_deps "$section")
        for dep in $deps; do
            # Only visit if in input list
            if array_contains "$dep" "${input_sections[@]}"; then
                visit "$dep"
            fi
        done

        # Add to ordered list
        ordered+=("$section")
    }

    # Visit all input sections
    for section in "${input_sections[@]}"; do
        visit "$section"
    done

    echo "${ordered[@]}"
}

# ============================================================================
# Section Display
# ============================================================================

# List all sections
list_sections() {
    echo "Available sections:"
    echo ""

    for section in "${SECTION_ORDER[@]}"; do
        local name
        name=$(get_section_name "$section")
        local desc
        desc=$(get_section_description "$section")
        local safety
        safety=$(get_section_safety "$section")

        # Color code by safety level
        local color=""
        case "$safety" in
            critical) color="$RED" ;;
            medium)   color="$YELLOW" ;;
            low)      color="$GREEN" ;;
        esac

        printf "  ${color}%-20s${NC} %s\n" "$section" "$desc"
    done

    echo ""
    echo "Available groups:"
    echo ""

    # List all groups manually (bash 3.2 compatible)
    local groups=("version_managers" "configs" "vscode" "homebrew_all" "minimal" "all")
    for group in "${groups[@]}"; do
        # Not named `sections`: that name is an array elsewhere in this file,
        # and reusing it here reads as a type change.
        local group_sections
        group_sections=$(expand_group "$group")
        printf "  %-20s %s\n" "$group" "$group_sections"
    done
}

# Show section status
show_section_status() {
    local section="$1"
    local installed="$2"  # true or false

    local name
    name=$(get_section_name "$section")
    local status_symbol=""
    local status_color=""

    if [ "$installed" = "true" ]; then
        status_symbol="✓"
        status_color="$GREEN"
    else
        status_symbol="✗"
        status_color="$RED"
    fi

    printf "  ${status_color}${status_symbol}${NC} %-20s %s\n" "$section" "$name"
}

# Show detailed section info
show_section_info() {
    local section="$1"

    if ! validate_section "$section"; then
        return 1
    fi

    local name
    name=$(get_section_name "$section")
    local desc
    desc=$(get_section_description "$section")
    local deps
    deps=$(get_section_deps "$section")
    local safety
    safety=$(get_section_safety "$section")
    local reverse_deps
    reverse_deps=$(get_reverse_deps "$section")

    echo "Section: $section"
    echo "Name: $name"
    echo "Description: $desc"
    echo "Safety Level: $safety"
    [ -n "$deps" ] && echo "Dependencies: $deps"
    [ -n "$reverse_deps" ] && echo "Required By: $reverse_deps"
}

# ============================================================================
# Section Filtering
# ============================================================================

# Filter sections by installation mode
filter_by_mode() {
    local mode="$1"
    shift
    local sections=("$@")
    local filtered=()

    for section in "${sections[@]}"; do
        case "$mode" in
            mise)
                # Skip nvm, pyenv, bun in mise mode
                if [[ "$section" != "nvm" && "$section" != "pyenv" && "$section" != "bun" ]]; then
                    filtered+=("$section")
                fi
                ;;
            standard)
                # Skip mise in standard mode
                if [[ "$section" != "mise" ]]; then
                    filtered+=("$section")
                fi
                ;;
            *)
                # Include all
                filtered+=("$section")
                ;;
        esac
    done

    echo "${filtered[@]}"
}

# Get mode-specific sections
get_mode_sections() {
    local mode="$1"

    case "$mode" in
        mise)
            echo "homebrew brew_packages brew_casks oh_my_zsh mise rust symlinks vscode_extensions git_config shell_config"
            ;;
        standard)
            echo "homebrew brew_packages brew_casks oh_my_zsh nvm pyenv bun rust symlinks vscode_extensions git_config shell_config"
            ;;
        *)
            echo "${SECTION_ORDER[@]}"
            ;;
    esac
}
