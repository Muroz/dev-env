#!/usr/bin/env bash

# ============================================================================
# Uninstall Handlers for All Sections
# ============================================================================
# Contains uninstall logic for each of the 13 sections
#
# Each handler supports:
# - Dry-run mode (preview without making changes)
# - Data preservation (keep user data by default)
# - Force mode (skip confirmations)
# - Verbose output
#
# Handlers:
# 1. uninstall_homebrew - Remove Homebrew (only if safe)
# 2. uninstall_brew_packages - Uninstall tracked packages
# 3. uninstall_brew_casks - Uninstall tracked casks
# 4. uninstall_oh_my_zsh - Remove Oh-My-Zsh
# 5. uninstall_nvm - Remove nvm (preserve data)
# 6. uninstall_pyenv - Remove pyenv (preserve data)
# 7. uninstall_bun - Remove Bun
# 8. uninstall_mise - Remove mise (preserve data)
# 9. uninstall_rust - Remove Rust toolchain
# 10. uninstall_symlinks - Remove config symlinks
# 11. uninstall_vscode_extensions - Uninstall extensions
# 12. uninstall_git_config - Remove git user config
# 13. uninstall_shell_config - Remove local shell config
#
# ============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/utils.sh"
source "$SCRIPT_DIR/state.sh"
source "$SCRIPT_DIR/packages.sh"

# ============================================================================
# Shell config edits
# ============================================================================

# install.sh symlinks $HOME/.zshrc to the repo's shell/zshrc, and sed -i
# writes THROUGH a symlink. Stripping lines here would rewrite the tracked
# file, leave the checkout dirty, and delete config the repo deliberately
# ships — the nvm fallback among it. When the file is managed, say so and
# leave it; the repo decides what loads.
strip_from_zshrc() {
    local what="$1"
    shift

    [ -f "$HOME/.zshrc" ] || return 0

    if [ -L "$HOME/.zshrc" ]; then
        info "Shell config is symlinked to the repo; leaving its $what lines alone"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would strip $what lines from the shell config"
        return 0
    fi

    sed -i.bak "$@" "$HOME/.zshrc" 2>/dev/null
    rm -f "$HOME/.zshrc.bak"
}
source "$SCRIPT_DIR/sections.sh"

# ============================================================================
# 1. Homebrew
# ============================================================================

uninstall_homebrew() {
    local section="homebrew"

    info "Checking Homebrew..."

    if ! command_exists brew; then
        warning "Homebrew not found"
        return 0
    fi

    local brew_prefix
    brew_prefix=$(brew --prefix 2>/dev/null)

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would check if Homebrew can be safely removed"
        info "[DRY RUN] Would remove Homebrew from: $brew_prefix"
        return 0
    fi

    # CRITICAL: Check for non-bootstrap packages
    local state_packages
    state_packages=$(get_section_state "brew_packages" | jq -r '.packages[]? // empty' 2>/dev/null)
    local all_packages
    all_packages=$(brew leaves 2>/dev/null)

    local other_packages=()
    while IFS= read -r pkg; do
        if ! echo "$state_packages" | grep -q "^$pkg$"; then
            other_packages+=("$pkg")
        fi
    done <<< "$all_packages"

    if [ ${#other_packages[@]} -gt 0 ]; then
        error "Cannot remove Homebrew - other packages are installed:"
        printf '%s\n' "${other_packages[@]}" | sed 's/^/  - /'
        warning "Remove these packages first, or they will be lost"

        if ! confirm "Remove Homebrew anyway? (THIS WILL REMOVE ALL PACKAGES)"; then
            info "Skipping Homebrew uninstall"
            return 1
        fi
    fi

    warning "This will completely remove Homebrew and ALL installed packages"

    if ! confirm "Are you absolutely sure?"; then
        info "Skipping Homebrew uninstall"
        return 1
    fi

    info "Downloading Homebrew uninstaller..."

    # Use official Homebrew uninstaller
    if /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"; then
        # Clean up shell config
        if [ -f "$HOME/.zprofile" ]; then
            sed -i.bak '/brew shellenv/d' "$HOME/.zprofile" 2>/dev/null
            rm -f "$HOME/.zprofile.bak"
        fi

        record_section_uninstalled "$section"
        success "Homebrew removed"
        return 0
    else
        error "Failed to uninstall Homebrew"
        return 1
    fi
}

# ============================================================================
# 2. Brew Packages
# ============================================================================

uninstall_brew_packages() {
    local section="brew_packages"

    info "Uninstalling Homebrew packages..."

    if ! command_exists brew; then
        warning "Homebrew not found"
        return 0
    fi

    # Get packages from state
    local state_packages
    state_packages=$(get_section_state "$section" | jq -r '.packages[]? // empty' 2>/dev/null)

    if [ -z "$state_packages" ]; then
        warning "No tracked packages found in state"
        info "Detecting installed packages..."

        # Fallback: try common packages
        state_packages="mise nvm pyenv poetry tippecanoe pmtiles"
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uninstall packages:"
        echo "$state_packages" | sed 's/^/  - /'
        return 0
    fi

    local removed_count=0
    for package in $state_packages; do
        if brew list --formula "$package" &>/dev/null; then
            info "Uninstalling $package..."
            if brew uninstall "$package" 2>&1; then
                ((removed_count++))
            else
                warning "Failed to uninstall $package"
            fi
        fi
    done

    record_section_uninstalled "$section"
    success "Removed $removed_count package(s)"
    return 0
}

# ============================================================================
# 3. Brew Casks
# ============================================================================

uninstall_brew_casks() {
    local section="brew_casks"

    info "Uninstalling Homebrew casks..."

    if ! command_exists brew; then
        warning "Homebrew not found"
        return 0
    fi

    # Get casks from state
    local state_casks
    state_casks=$(get_section_state "$section" | jq -r '.casks[]? // empty' 2>/dev/null)

    if [ -z "$state_casks" ]; then
        # No state to go on: fall back to the manifest. Only casks brew
        # actually manages are touched, checked in the loop below, so an app
        # installed by hand is left alone.
        local manifest="${REPO_ROOT:-$(dirname "$(dirname "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")")}/bootstrap/cask-apps.txt"
        if [ -f "$manifest" ]; then
            state_casks=$(read_manifest "$manifest")
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uninstall casks:"
        echo "$state_casks" | sed 's/^/  - /'
        return 0
    fi

    local removed_count=0
    for cask in $state_casks; do
        if brew list --cask "$cask" &>/dev/null; then
            info "Uninstalling $cask..."
            if brew uninstall --cask "$cask" 2>&1; then
                ((removed_count++))
            else
                warning "Failed to uninstall $cask"
            fi
        fi
    done

    record_section_uninstalled "$section"
    success "Removed $removed_count cask(s)"
    return 0
}

# ============================================================================
# 4. Oh-My-Zsh
# ============================================================================

uninstall_oh_my_zsh() {
    local section="oh_my_zsh"

    info "Removing Oh-My-Zsh..."

    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        warning "Oh-My-Zsh not found"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would remove: $HOME/.oh-my-zsh"
        return 0
    fi

    # Use official uninstaller if available
    if [ -f "$HOME/.oh-my-zsh/tools/uninstall.sh" ]; then
        info "Using official Oh-My-Zsh uninstaller..."
        env ZSH="$HOME/.oh-my-zsh" sh "$HOME/.oh-my-zsh/tools/uninstall.sh" --unattended
    else
        info "Removing Oh-My-Zsh directory..."
        rm -rf "$HOME/.oh-my-zsh"
    fi

    record_section_uninstalled "$section"
    success "Oh-My-Zsh removed"
    return 0
}

# ============================================================================
# 5. NVM (Node Version Manager)
# ============================================================================

uninstall_nvm() {
    local section="nvm"

    info "Removing nvm..."

    if [ ! -d "$HOME/.nvm" ]; then
        warning "nvm not found"
        return 0
    fi

    # Check for installed Node versions
    local node_versions
    node_versions=$(ls -1 "$HOME/.nvm/versions/node" 2>/dev/null | wc -l | xargs)

    if [ "$node_versions" -gt 0 ]; then
        warning "$node_versions Node.js version(s) installed"

        if [ "$REMOVE_DATA" = true ]; then
            warning "All Node versions and global npm packages will be removed"
        else
            info "Node versions will be preserved (use --remove-data to remove)"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        if [ "$REMOVE_DATA" = false ] && [ "$node_versions" -gt 0 ]; then
            # The versions live inside .nvm, so "remove .nvm" would have been
            # a lie: only everything beside versions/ is removed.
            info "[DRY RUN] Would remove everything in $HOME/.nvm except versions/"
            info "[DRY RUN] Would keep $node_versions Node version(s) in $HOME/.nvm/versions"
        else
            info "[DRY RUN] Would remove: $HOME/.nvm, including every Node version"
        fi
        info "[DRY RUN] Would uninstall nvm via brew"
        return 0
    fi

    # nvm comes from Homebrew, same as pyenv did, so the formula goes too.
    # Removing only ~/.nvm left the formula installed, which then showed up as
    # an untracked formula in doctor.sh for ever.
    if command_exists brew && brew list --formula nvm &>/dev/null; then
        info "Uninstalling nvm via Homebrew..."
        brew uninstall nvm
    fi

    if [ "$REMOVE_DATA" = false ] && [ "$node_versions" -gt 0 ]; then
        # Preserve data: Only remove nvm installation, keep versions
        info "Removing nvm (preserving Node versions)..."

        # Remove nvm files but keep versions directory
        find "$HOME/.nvm" -mindepth 1 -maxdepth 1 ! -name 'versions' -exec rm -rf {} + 2>/dev/null
    else
        # Full removal
        info "Removing nvm and all data..."
        rm -rf "$HOME/.nvm"
    fi

    # Clean up shell config
    strip_from_zshrc "nvm" '/NVM_DIR/d; /nvm\.sh/d; /nvm bash_completion/d'

    record_section_uninstalled "$section"
    success "nvm removed"
    return 0
}

# ============================================================================
# 6. Pyenv (Python Version Manager)
# ============================================================================

uninstall_pyenv() {
    local section="pyenv"

    info "Removing pyenv..."

    if ! command_exists pyenv && [ ! -d "$HOME/.pyenv" ]; then
        warning "pyenv not found"
        return 0
    fi

    # Check for installed Python versions
    local python_versions
    python_versions=$(pyenv versions --bare 2>/dev/null | wc -l | xargs)

    if [ "$python_versions" -gt 0 ]; then
        warning "$python_versions Python version(s) installed"

        if [ "$REMOVE_DATA" = true ]; then
            warning "All Python versions and virtualenvs will be removed"
        else
            info "Python versions will be preserved (use --remove-data to remove)"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uninstall pyenv via brew"
        if [ "$REMOVE_DATA" = false ] && [ "$python_versions" -gt 0 ]; then
            # The versions live inside .pyenv, so naming the directory alone
            # would overstate what goes.
            info "[DRY RUN] Would remove everything in $HOME/.pyenv except versions/"
            info "[DRY RUN] Would keep $python_versions Python version(s) in $HOME/.pyenv/versions"
        else
            info "[DRY RUN] Would remove: $HOME/.pyenv, including every Python version"
        fi
        return 0
    fi

    # Uninstall via brew if installed that way
    if command_exists brew && brew list --formula pyenv &>/dev/null; then
        info "Uninstalling pyenv via Homebrew..."
        brew uninstall pyenv
    fi

    if [ "$REMOVE_DATA" = false ] && [ "$python_versions" -gt 0 ]; then
        # Preserve data: Keep versions directory
        info "Removing pyenv (preserving Python versions)..."

        if [ -d "$HOME/.pyenv" ]; then
            find "$HOME/.pyenv" -mindepth 1 -maxdepth 1 ! -name 'versions' -exec rm -rf {} + 2>/dev/null
        fi
    else
        # Full removal
        info "Removing pyenv and all data..."
        rm -rf "$HOME/.pyenv"
    fi

    # Clean up shell config
    strip_from_zshrc "pyenv" '/pyenv init/d; /PYENV_ROOT/d'

    record_section_uninstalled "$section"
    success "pyenv removed"
    return 0
}

# ============================================================================
# 7. Bun
# ============================================================================

uninstall_bun() {
    local section="bun"

    info "Removing Bun..."

    if [ ! -d "$HOME/.bun" ] && ! command_exists bun; then
        warning "Bun not found"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would remove: $HOME/.bun"
        return 0
    fi

    # Remove Bun directory
    if [ -d "$HOME/.bun" ]; then
        rm -rf "$HOME/.bun"
    fi

    # Clean up shell config
    strip_from_zshrc "bun" '/BUN_INSTALL/d; /_bun/d; /\.bun\/bin/d'

    record_section_uninstalled "$section"
    success "Bun removed"
    return 0
}

# ============================================================================
# 8. Mise
# ============================================================================

uninstall_mise() {
    local section="mise"

    info "Removing mise..."

    if ! command_exists mise; then
        warning "mise not found"
        return 0
    fi

    # Show installed tools
    local tools
    tools=$(mise list 2>/dev/null | wc -l | xargs)

    if [ "$tools" -gt 0 ]; then
        warning "$tools tool(s) installed via mise"

        if [ "$VERBOSE" = true ]; then
            mise list 2>/dev/null | sed 's/^/  /'
        fi

        if [ "$REMOVE_DATA" = true ]; then
            warning "All mise tools will be removed"
        else
            info "Tool installations will be preserved (use --remove-data to remove)"
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uninstall mise via brew"
        info "[DRY RUN] Would remove: $HOME/.config/mise"
        if [ "$REMOVE_DATA" = false ]; then
            info "[DRY RUN] Would preserve installed tools"
        else
            info "[DRY RUN] Would remove: $HOME/.local/share/mise"
        fi
        return 0
    fi

    # Uninstall via brew
    if command_exists brew && brew list --formula mise &>/dev/null; then
        info "Uninstalling mise via Homebrew..."
        brew uninstall mise
    fi

    # Remove config symlink
    if [ -L "$HOME/.config/mise/config.toml" ]; then
        rm "$HOME/.config/mise/config.toml"
    fi

    # Remove config directory if empty
    if [ -d "$HOME/.config/mise" ] && is_empty "$HOME/.config/mise"; then
        rmdir "$HOME/.config/mise"
    fi

    if [ "$REMOVE_DATA" = true ]; then
        # Full removal including tools
        info "Removing mise data and all tools..."
        rm -rf "$HOME/.local/share/mise"
        rm -rf "$HOME/.cache/mise"
    fi

    # Clean up shell config
    strip_from_zshrc "mise" '/mise activate/d; /command -v mise/d'

    record_section_uninstalled "$section"
    success "mise removed"
    return 0
}

# ============================================================================
# 9. Rust
# ============================================================================

uninstall_rust() {
    local section="rust"

    info "Removing Rust..."

    if [ ! -d "$HOME/.cargo" ] && [ ! -d "$HOME/.rustup" ]; then
        warning "Rust not found"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would run: rustup self uninstall"
        info "[DRY RUN] Would remove: $HOME/.cargo"
        info "[DRY RUN] Would remove: $HOME/.rustup"
        return 0
    fi

    # Use official uninstaller if rustup is available
    if command_exists rustup; then
        info "Using rustup self uninstall..."
        rustup self uninstall -y
    else
        # Manual cleanup
        info "Manually removing Rust directories..."
        rm -rf "$HOME/.cargo"
        rm -rf "$HOME/.rustup"
    fi

    record_section_uninstalled "$section"
    success "Rust removed"
    return 0
}

# ============================================================================
# 10. Configuration Symlinks
# ============================================================================

uninstall_symlinks() {
    local section="symlinks"

    info "Removing configuration symlinks..."

    # Get symlinks from state
    local state_links
    state_links=$(get_section_state "$section" | jq -r '.links | keys[]?' 2>/dev/null)

    if [ -z "$state_links" ]; then
        # Fallback to common symlinks
        state_links=".zshrc .gitconfig .gitignore_global"
    fi

    # Check for backups
    local backup_dir
    backup_dir=$(get_section_state "$section" | jq -r '.backup_dir // empty' 2>/dev/null)

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would remove symlinks:"
        for link in $state_links; do
            echo "  - $HOME/$link"
        done

        if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
            info "[DRY RUN] Backup available at: $backup_dir"
            info "[DRY RUN] Would ask about restoring backups"
        fi
        return 0
    fi

    # Remove symlinks
    local removed_count=0
    for link in $state_links; do
        local full_path="$HOME/$link"

        if [ -L "$full_path" ]; then
            info "Removing symlink: $full_path"
            rm "$full_path"
            ((removed_count++))
        elif [ -e "$full_path" ]; then
            warning "Not a symlink (skipping): $full_path"
        fi
    done

    # Ask about restoring backups
    if [ -n "$backup_dir" ] && [ -d "$backup_dir" ]; then
        info "Backup found: $backup_dir"

        if confirm "Restore original files from backup?"; then
            for file in "$backup_dir"/*; do
                local basename
                basename=$(basename "$file")
                info "Restoring: $basename"
                cp "$file" "$HOME/$basename"
            done
            success "Original files restored"
        fi
    fi

    # Remove git excludesfile config if it points to our gitignore
    if git config --global core.excludesfile | grep -q "gitignore_global"; then
        git config --global --unset core.excludesfile 2>/dev/null
    fi

    record_section_uninstalled "$section"
    success "Removed $removed_count symlink(s)"
    return 0
}

# ============================================================================
# 11. VS Code Extensions
# ============================================================================

uninstall_vscode_extensions() {
    local section="vscode_extensions"

    info "Uninstalling VS Code extensions..."

    if ! command_exists code; then
        warning "VS Code CLI not found"
        return 0
    fi

    # Get repo root
    local repo_root
    repo_root=$(dirname "$(dirname "$(dirname "${BASH_SOURCE[0]}")")")
    local extensions_file="$repo_root/editors/vscode/extensions.txt"

    if [ ! -f "$extensions_file" ]; then
        warning "Extensions list not found: $extensions_file"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uninstall extensions from: $extensions_file"
        return 0
    fi

    local removed_count=0
    while IFS= read -r extension; do
        # Skip empty lines and comments
        [[ -z "$extension" || "$extension" =~ ^# ]] && continue

        if code --list-extensions 2>/dev/null | grep -qi "^${extension}\$"; then
            info "Uninstalling: $extension"
            if code --uninstall-extension "$extension" &>/dev/null; then
                ((removed_count++))
            else
                warning "Failed to uninstall: $extension"
            fi
        fi
    done < "$extensions_file"

    record_section_uninstalled "$section"
    success "Removed $removed_count extension(s)"
    return 0
}

# ============================================================================
# 12. Git Configuration
# ============================================================================

uninstall_git_config() {
    local section="git_config"

    info "Removing git user configuration..."

    local current_name
    current_name=$(git config --global user.name 2>/dev/null)
    local current_email
    current_email=$(git config --global user.email 2>/dev/null)

    if [ -z "$current_name" ] && [ -z "$current_email" ]; then
        warning "No git user configuration found"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would remove git user configuration:"
        [ -n "$current_name" ] && info "[DRY RUN]   user.name: $current_name"
        [ -n "$current_email" ] && info "[DRY RUN]   user.email: $current_email"
        return 0
    fi

    if [ -n "$current_name" ]; then
        git config --global --unset user.name
        info "Removed user.name: $current_name"
    fi

    if [ -n "$current_email" ]; then
        git config --global --unset user.email
        info "Removed user.email: $current_email"
    fi

    record_section_uninstalled "$section"
    success "Git user configuration removed"
    return 0
}

# ============================================================================
# 13. Shell Configuration
# ============================================================================

uninstall_shell_config() {
    local section="shell_config"

    info "Removing shell configuration..."

    # shellcheck disable=SC2088  # literal ~ is intended in the message
    if [ ! -f "$HOME/.zshrc.local" ]; then
        warning "~/.zshrc.local not found"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would remove: $HOME/.zshrc.local"
        return 0
    fi

    # Offer to backup first
    if confirm "Backup .zshrc.local before removing?"; then
        local backup_path
        backup_path=$(backup_file "$HOME/.zshrc.local" "$HOME")
        info "Backup saved: $backup_path"
    fi

    rm -f "$HOME/.zshrc.local"

    # Remove sourcing line from .zshrc if it exists
    strip_from_zshrc "local-config" '/\.zshrc\.local/d'

    record_section_uninstalled "$section"
    success "Shell configuration removed"
    return 0
}

# ============================================================================
# 14. Weekly Drift Check
# ============================================================================

uninstall_drift_agent() {
    local section="drift_agent"
    local label="com.dev-env.drift"
    local plist="$HOME/Library/LaunchAgents/$label.plist"

    info "Removing the weekly drift check..."

    if [ ! -f "$plist" ]; then
        info "Drift check agent not installed"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would unload and remove $plist"
        return 0
    fi

    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    rm -f "$plist"

    record_section_uninstalled "$section"
    success "Drift check removed"
    info "Its log stays at ~/.dev-env/drift.log"
    return 0
}
