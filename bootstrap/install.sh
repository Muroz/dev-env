#!/usr/bin/env bash

# ============================================================================
# Dev Environment Bootstrap Script
# ============================================================================
# Sets up a fresh macOS system with all development tools and configurations
#
# Usage: ./install.sh [OPTIONS]
#
# Options:
#   --dry-run        Preview changes without making modifications
#   --skip-backups   Skip creating backups of existing configuration files
#   --use-mise       Use mise for unified version management (Node, Python, Bun)
#   --help           Display usage information and available options
#
# Examples:
#   ./install.sh                     # Standard installation (nvm, pyenv, bun)
#   ./install.sh --dry-run           # Preview what would be installed
#   ./install.sh --use-mise          # Install with mise for unified version management
#   ./install.sh --dry-run --use-mise  # Preview mise installation
#
# What this script does:
# 1. Validates macOS system and required dependencies (curl, git)
# 2. Installs Homebrew (if not present) for both Intel and Apple Silicon
# 3. Installs brew packages from brew-packages.txt (conditionally based on --use-mise)
# 4. Installs cask applications from cask-apps.txt
# 5. Installs oh-my-zsh (if not present)
# 6. Sets up version managers:
#    - Standard mode: nvm, pyenv, bun, rust, conda
#    - Mise mode (--use-mise): mise, rust, conda
# 7. Creates symlinks for shell and git configurations (with automatic backups)
# 8. Installs VS Code extensions and copies settings
# 9. Configures git with environment variables
# 10. Creates ~/.zshrc.local for machine-specific customizations
#
# Version Management Modes:
#
# Standard Mode (default):
#   - Installs: nvm, pyenv, poetry, tippecanoe, pmtiles
#   - Skips: mise
#   - Best for users familiar with traditional version managers
#
# Mise Mode (--use-mise):
#   - Installs: mise, poetry, tippecanoe, pmtiles
#   - Skips: nvm, pyenv (bun installed via mise)
#   - Automatically configures mise and installs tools from mise/config.toml
#   - Best for users wanting simplified, unified tooling
#
# IMPORTANT: Set these environment variables before running:
#   export GIT_USER_NAME="Your Name"
#   export GIT_USER_EMAIL="your.email@example.com"
#
# ============================================================================

set -o pipefail  # Catch errors in pipes
# Note: Not using 'set -e' to allow graceful handling of individual failures

# Source state tracking library
if [ -f "$SCRIPT_DIR/lib/state.sh" ]; then
    source "$SCRIPT_DIR/lib/state.sh"
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Flags
DRY_RUN=false
SKIP_BACKUPS=false
USE_MISE=false
ERROR_COUNT=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-backups)
            SKIP_BACKUPS=true
            ;;
        --use-mise)
            USE_MISE=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run        Preview changes without making modifications"
            echo "  --skip-backups   Skip creating backups of existing configuration files"
            echo "  --use-mise       Use mise for unified version management (Node, Python, Bun)"
            echo "                   This will skip installing nvm, pyenv, and standalone bun"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Standard installation (nvm, pyenv, bun)"
            echo "  $0 --dry-run          # Preview what would be installed"
            echo "  $0 --use-mise         # Install with mise for unified version management"
            echo "  $0 --dry-run --use-mise  # Preview mise installation"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--dry-run] [--skip-backups] [--use-mise] [--help]"
            exit 1
            ;;
    esac
done

# ============================================================================
# Helper Functions
# ============================================================================

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    ((ERROR_COUNT++))
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERROR_COUNT++))
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if running on macOS
check_macos() {
    if [[ "$OSTYPE" != "darwin"* ]]; then
        error "This script is designed for macOS only"
        exit 1
    fi
}

# Check for required dependencies
check_dependencies() {
    info "Checking required dependencies..."

    local missing_deps=()

    for dep in curl git; do
        if ! command_exists "$dep"; then
            missing_deps+=("$dep")
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        error "Missing required dependencies: ${missing_deps[*]}"
        info "Please install them first:"
        info "  xcode-select --install"
        exit 1
    fi

    success "All required dependencies present"
}

# ============================================================================
# 1. Homebrew Installation
# ============================================================================

install_homebrew() {
    info "Checking for Homebrew..."

    if command_exists brew; then
        success "Homebrew already installed ($(brew --version | head -n1))"

        if [ "$DRY_RUN" = false ]; then
            info "Updating Homebrew..."
            if ! brew update; then
                warning "Failed to update Homebrew"
            fi
        fi
    else
        info "Installing Homebrew..."

        if [ "$DRY_RUN" = false ]; then
            if ! /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
                error "Failed to install Homebrew"
                return 1
            fi

            # Add Homebrew to PATH based on architecture
            if [[ $(uname -m) == 'arm64' ]]; then
                # Apple Silicon
                if ! grep -q '/opt/homebrew/bin/brew' ~/.zprofile 2>/dev/null; then
                    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
                fi
                eval "$(/opt/homebrew/bin/brew shellenv)"
            else
                # Intel
                if ! grep -q '/usr/local/bin/brew' ~/.zprofile 2>/dev/null; then
                    echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
                fi
                eval "$(/usr/local/bin/brew shellenv)"
            fi

            success "Homebrew installed"
        else
            info "[DRY RUN] Would install Homebrew"
        fi
    fi
}

# ============================================================================
# 2. Brew Packages Installation
# ============================================================================

# Helper function to check if a package should be installed based on conditions
should_install_package() {
    local package="$1"
    local prev_line="$2"

    # Check for conditional markers in the previous comment line
    if [[ "$prev_line" =~ \[CONDITIONAL:\ USE_MISE\] ]]; then
        # Only install if USE_MISE is true
        [ "$USE_MISE" = true ] && return 0 || return 1
    elif [[ "$prev_line" =~ \[CONDITIONAL:\ !USE_MISE\] ]]; then
        # Only install if USE_MISE is false
        [ "$USE_MISE" = false ] && return 0 || return 1
    fi

    # No condition found, always install
    return 0
}

install_brew_packages() {
    info "Installing Homebrew packages..."

    if [ ! -f "$REPO_ROOT/bootstrap/brew-packages.txt" ]; then
        warning "brew-packages.txt not found"
        return 1
    fi

    local package_count=0
    local installed_count=0
    local skipped_count=0
    local failed_packages=()
    local prev_line=""

    while IFS= read -r line; do
        # Track previous line for conditional checking
        if [[ "$line" =~ ^# ]] || [[ -z "$line" ]]; then
            prev_line="$line"
            continue
        fi

        local package="$line"

        # Check if package should be installed based on conditions
        if ! should_install_package "$package" "$prev_line"; then
            if [[ "$prev_line" =~ \[CONDITIONAL:\ USE_MISE\] ]]; then
                info "  ⊘ $package (skipped - not using mise)"
            else
                info "  ⊘ $package (skipped - using mise instead)"
            fi
            ((skipped_count++))
            prev_line="$line"
            continue
        fi

        ((package_count++))

        if brew list --formula "$package" &>/dev/null; then
            info "  ✓ $package already installed"
            ((installed_count++))
        else
            if [ "$DRY_RUN" = false ]; then
                info "  Installing $package..."
                if brew install "$package" 2>&1 | tee /tmp/brew-install-$$.log; then
                    ((installed_count++))
                else
                    warning "Failed to install $package"
                    failed_packages+=("$package")
                fi
            else
                info "[DRY RUN] Would install $package"
            fi
        fi

        prev_line="$line"
    done < "$REPO_ROOT/bootstrap/brew-packages.txt"

    if [ ${#failed_packages[@]} -ne 0 ]; then
        warning "Failed to install: ${failed_packages[*]}"
    fi

    if [ $skipped_count -gt 0 ]; then
        if [ "$USE_MISE" = true ]; then
            info "Skipped $skipped_count package(s) (using mise for version management)"
        else
            info "Skipped $skipped_count package(s) (mise not enabled)"
        fi
    fi

    success "Brew packages: $installed_count/$package_count installed"
}

# ============================================================================
# 3. Brew Casks Installation
# ============================================================================

install_brew_casks() {
    info "Installing Homebrew casks..."

    if [ ! -f "$REPO_ROOT/bootstrap/cask-apps.txt" ]; then
        warning "cask-apps.txt not found"
        return 1
    fi

    local cask_count=0
    local installed_count=0
    local failed_casks=()

    while IFS= read -r cask; do
        # Skip empty lines and comments
        [[ -z "$cask" || "$cask" =~ ^# ]] && continue

        ((cask_count++))

        if brew list --cask "$cask" &>/dev/null; then
            info "  ✓ $cask already installed"
            ((installed_count++))
        else
            if [ "$DRY_RUN" = false ]; then
                info "  Installing $cask..."
                if brew install --cask "$cask"; then
                    ((installed_count++))
                else
                    warning "Failed to install $cask"
                    failed_casks+=("$cask")
                fi
            else
                info "[DRY RUN] Would install $cask"
            fi
        fi
    done < "$REPO_ROOT/bootstrap/cask-apps.txt"

    if [ ${#failed_casks[@]} -ne 0 ]; then
        warning "Failed to install casks: ${failed_casks[*]}"
    fi

    success "Brew casks: $installed_count/$cask_count installed"
}

# ============================================================================
# 4. Oh-My-Zsh Installation
# ============================================================================

install_oh_my_zsh() {
    info "Checking for Oh-My-Zsh..."

    if [ -d "$HOME/.oh-my-zsh" ]; then
        success "Oh-My-Zsh already installed"
    else
        if [ "$DRY_RUN" = false ]; then
            info "Installing Oh-My-Zsh..."

            # Download and verify installer
            if ! curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh -o /tmp/install-omz.sh; then
                error "Failed to download Oh-My-Zsh installer"
                return 1
            fi

            if sh /tmp/install-omz.sh --unattended; then
                rm -f /tmp/install-omz.sh
                success "Oh-My-Zsh installed"
            else
                error "Failed to install Oh-My-Zsh"
                rm -f /tmp/install-omz.sh
                return 1
            fi
        else
            info "[DRY RUN] Would install Oh-My-Zsh"
        fi
    fi
}

# ============================================================================
# 5. Version Managers & Language Tools
# ============================================================================

setup_mise_config() {
    # This function is called after mise is installed via brew packages
    # It handles configuration and tool installation

    info "Configuring mise..."

    local config_file="$REPO_ROOT/mise/config.toml"
    local global_config="$HOME/.config/mise/config.toml"

    if [ ! -f "$config_file" ]; then
        warning "mise config.toml not found at $config_file"
        return 1
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would uncomment tool versions in mise config"
        info "[DRY RUN] Would create symlink: $global_config → $config_file"
        info "[DRY RUN] Would run: mise install"
        return 0
    fi

    # At this point, we're not in dry-run mode, so mise should be installed
    if ! command_exists mise; then
        error "mise not found - this should have been installed via brew packages"
        info "Try running: brew install mise"
        return 1
    fi

    # Uncomment tool versions in the config file
    if grep -q "^# node = " "$config_file"; then
        info "Activating tool versions in mise config..."

        # Create a backup
        cp "$config_file" "$config_file.bak"

        # Uncomment the tool versions
        sed -i.tmp 's/^# node = /node = /' "$config_file"
        sed -i.tmp 's/^# python = /python = /' "$config_file"
        sed -i.tmp 's/^# bun = /bun = /' "$config_file"

        rm -f "$config_file.tmp"
        success "Tool versions activated in config"
    fi

    # Create mise config directory and symlink
    mkdir -p "$(dirname "$global_config")"

    if [ -e "$global_config" ] && [ ! -L "$global_config" ]; then
        # Backup existing config if it's not a symlink
        mv "$global_config" "$global_config.backup-$(date +%Y%m%d_%H%M%S)"
        info "Backed up existing mise config"
    fi

    # Create symlink to our config
    ln -sf "$config_file" "$global_config"
    success "Symlinked mise config: $global_config → $config_file"

    # Trust the config file (required by mise for security)
    info "Trusting mise config file..."
    if mise trust "$REPO_ROOT"; then
        success "mise config trusted"
    else
        warning "Failed to trust mise config - you may need to run: mise trust $REPO_ROOT"
    fi

    # Activate mise for current session
    eval "$(mise activate bash)"

    # Install configured tools
    info "Installing mise tools (this may take a few minutes)..."
    if mise install; then
        success "mise tools installed successfully"

        # Show what was installed
        info "Installed tools:"
        mise list 2>/dev/null | sed 's/^/  /'
    else
        warning "Some mise tools failed to install"
        return 1
    fi

    return 0
}

install_nvm() {
    # Skip if using mise
    if [ "$USE_MISE" = true ]; then
        info "Skipping nvm (using mise instead)"
        return 0
    fi

    info "Checking for nvm..."

    if [ -d "$HOME/.nvm" ]; then
        success "nvm already installed"
    else
        if [ "$DRY_RUN" = false ]; then
            info "Creating nvm directory (installed via Homebrew)..."
            mkdir -p "$HOME/.nvm"
            success "nvm ready"
        else
            info "[DRY RUN] Would create nvm directory"
        fi
    fi
}

install_pyenv() {
    # Skip if using mise
    if [ "$USE_MISE" = true ]; then
        info "Skipping pyenv (using mise instead)"
        return 0
    fi

    info "Checking for pyenv..."

    if command_exists pyenv; then
        success "pyenv already installed ($(pyenv --version))"
    else
        info "pyenv will be installed via Homebrew"
    fi
}

install_bun() {
    # Skip if using mise
    if [ "$USE_MISE" = true ]; then
        info "Skipping bun (using mise instead)"
        return 0
    fi

    info "Checking for Bun..."

    if command_exists bun; then
        success "Bun already installed ($(bun --version))"
    else
        if [ "$DRY_RUN" = false ]; then
            info "Installing Bun..."

            # Download installer
            if ! curl -fsSL https://bun.sh/install -o /tmp/install-bun.sh; then
                error "Failed to download Bun installer"
                return 1
            fi

            # Install Bun
            if bash /tmp/install-bun.sh; then
                rm -f /tmp/install-bun.sh
                success "Bun installed"
            else
                error "Failed to install Bun"
                rm -f /tmp/install-bun.sh
                return 1
            fi
        else
            info "[DRY RUN] Would install Bun"
        fi
    fi
}

install_rust() {
    info "Checking for Rust/Cargo..."

    if command_exists cargo; then
        success "Rust already installed ($(rustc --version 2>/dev/null || echo 'version unknown'))"
    else
        if [ "$DRY_RUN" = false ]; then
            info "Installing Rust..."

            # Download installer
            if ! curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o /tmp/install-rust.sh; then
                error "Failed to download Rust installer"
                return 1
            fi

            # Install Rust
            if sh /tmp/install-rust.sh -y; then
                rm -f /tmp/install-rust.sh
                # Source cargo env for current session
                [ -f "$HOME/.cargo/env" ] && source "$HOME/.cargo/env"
                success "Rust installed"
            else
                error "Failed to install Rust"
                rm -f /tmp/install-rust.sh
                return 1
            fi
        else
            info "[DRY RUN] Would install Rust"
        fi
    fi
}

install_conda() {
    info "Checking for Conda..."

    if command_exists conda; then
        success "Conda already installed"
    else
        warning "Conda not found. Install manually from https://www.anaconda.com/download if needed"
    fi
}

# ============================================================================
# 6. Configuration Symlinks
# ============================================================================

create_symlinks() {
    info "Creating configuration symlinks..."

    local backup_dir="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

    if [ "$SKIP_BACKUPS" = false ] && [ "$DRY_RUN" = false ]; then
        mkdir -p "$backup_dir"
    fi

    # Helper function to create symlink
    create_link() {
        local source="$1"
        local target="$2"
        local name="$3"

        if [ ! -f "$source" ]; then
            warning "Source file not found: $source"
            return 1
        fi

        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would link $target → $source"
            return 0
        fi

        # Handle existing file/symlink
        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ "$SKIP_BACKUPS" = false ]; then
                if [ -L "$target" ]; then
                    # Remove existing symlink
                    rm "$target"
                else
                    # Backup regular file
                    info "Backing up existing $name..."
                    mv "$target" "$backup_dir/$(basename "$target")"
                fi
            else
                rm -f "$target"
            fi
        fi

        if ln -sf "$source" "$target"; then
            success "Linked $name"
            return 0
        else
            error "Failed to link $name"
            return 1
        fi
    }

    # Create symlinks
    create_link "$REPO_ROOT/shell/zshrc" "$HOME/.zshrc" ".zshrc"
    create_link "$REPO_ROOT/git/gitconfig" "$HOME/.gitconfig" ".gitconfig"
    create_link "$REPO_ROOT/git/gitignore_global" "$HOME/.gitignore_global" ".gitignore_global"

    # Configure git to use global gitignore
    if [ "$DRY_RUN" = false ]; then
        git config --global core.excludesfile "$HOME/.gitignore_global"
    fi

    # Clean up empty backup directory
    if [ "$SKIP_BACKUPS" = false ] && [ "$DRY_RUN" = false ]; then
        if [ -d "$backup_dir" ] && [ -z "$(ls -A "$backup_dir")" ]; then
            rmdir "$backup_dir"
        elif [ -d "$backup_dir" ]; then
            info "Backups saved to: $backup_dir"
        fi
    fi
}

# ============================================================================
# 7. VS Code Extensions
# ============================================================================

install_vscode_extensions() {
    info "Checking for VS Code..."

    if ! command_exists code; then
        warning "VS Code CLI not found. Install VS Code and enable 'code' command in PATH"
        warning "To enable: Open VS Code → Cmd+Shift+P → 'Shell Command: Install code command in PATH'"
        return 0
    fi

    # Check if VS Code is currently running
    if pgrep -x "Code" >/dev/null 2>&1 || pgrep -x "Visual Studio Code" >/dev/null 2>&1; then
        warning "VS Code is currently running!"
        warning "Installing extensions while VS Code is running may cause it to crash or behave unexpectedly."
        echo ""
        if [ "$DRY_RUN" = false ]; then
            echo "Please close VS Code and press Enter to continue (or Ctrl+C to cancel)..."
            read -r
        else
            info "[DRY RUN] Would wait for user to close VS Code"
        fi
    fi

    info "Installing VS Code extensions..."

    if [ ! -f "$REPO_ROOT/editors/vscode/extensions.txt" ]; then
        warning "extensions.txt not found"
        return 1
    fi

    local ext_count=0
    local installed_count=0
    local failed_extensions=()
    local new_installs=0

    while IFS= read -r extension; do
        # Skip empty lines and comments
        [[ -z "$extension" || "$extension" =~ ^# ]] && continue

        ((ext_count++))

        if code --list-extensions 2>/dev/null | grep -qi "^${extension}\$"; then
            info "  ✓ $extension already installed"
            ((installed_count++))
        else
            if [ "$DRY_RUN" = false ]; then
                info "  Installing $extension..."
                if code --install-extension "$extension" --force 2>&1 | grep -v "Installing extensions..."; then
                    ((installed_count++))
                    ((new_installs++))
                    # Small delay to avoid overwhelming VS Code
                    sleep 0.5
                else
                    warning "Failed to install $extension"
                    failed_extensions+=("$extension")
                fi
            else
                info "[DRY RUN] Would install $extension"
            fi
        fi
    done < "$REPO_ROOT/editors/vscode/extensions.txt"

    if [ ${#failed_extensions[@]} -ne 0 ]; then
        warning "Failed to install extensions: ${failed_extensions[*]}"
    fi

    if [ "$DRY_RUN" = false ] && [ $new_installs -gt 0 ]; then
        success "VS Code extensions: $installed_count/$ext_count ready ($new_installs newly installed)"
        echo ""
        warning "IMPORTANT: $new_installs new extension(s) were installed."
        warning "VS Code may reload or restart when you next open it."
        warning "This is normal behavior and not a crash."
    else
        success "VS Code extensions: $installed_count/$ext_count installed"
    fi

    # Copy VS Code settings (with backup)
    local vscode_user_dir="$HOME/Library/Application Support/Code/User"
    if [ -d "$vscode_user_dir" ]; then
        if [ "$DRY_RUN" = false ]; then
            info "Copying VS Code settings..."

            # Backup existing settings
            local backup_dir="$HOME/.vscode-settings-backup-$(date +%Y%m%d_%H%M%S)"
            mkdir -p "$backup_dir"

            if [ -f "$vscode_user_dir/settings.json" ]; then
                cp "$vscode_user_dir/settings.json" "$backup_dir/settings.json"
                info "Backed up existing settings.json to $backup_dir"
            fi

            if [ -f "$vscode_user_dir/keybindings.json" ]; then
                cp "$vscode_user_dir/keybindings.json" "$backup_dir/keybindings.json"
                info "Backed up existing keybindings.json to $backup_dir"
            fi

            # Copy new settings
            cp "$REPO_ROOT/editors/vscode/settings.json" "$vscode_user_dir/settings.json"
            cp "$REPO_ROOT/editors/vscode/keybindings.json" "$vscode_user_dir/keybindings.json"
            success "VS Code settings copied"
        else
            info "[DRY RUN] Would backup and copy VS Code settings"
        fi
    else
        warning "VS Code user directory not found. Settings not copied."
    fi
}

# ============================================================================
# 8. Git Configuration with Environment Variables
# ============================================================================

configure_git() {
    info "Configuring Git..."

    if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
        warning "GIT_USER_NAME and GIT_USER_EMAIL environment variables not set"
        info "Git user identity not configured. Please run:"
        info "  export GIT_USER_NAME=\"Your Name\""
        info "  export GIT_USER_EMAIL=\"your.email@example.com\""
        info "  git config --global user.name \"\$GIT_USER_NAME\""
        info "  git config --global user.email \"\$GIT_USER_EMAIL\""
        return 0
    fi

    if [ "$DRY_RUN" = false ]; then
        git config --global user.name "$GIT_USER_NAME"
        git config --global user.email "$GIT_USER_EMAIL"
        success "Git user configured: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    else
        info "[DRY RUN] Would configure git user: $GIT_USER_NAME <$GIT_USER_EMAIL>"
    fi
}

# ============================================================================
# 9. Final Setup
# ============================================================================

final_setup() {
    info "Running final setup..."

    # Create a local shell config file for user-specific customizations
    local local_zshrc="$HOME/.zshrc.local"

    if [ "$DRY_RUN" = false ]; then
        if [ ! -f "$local_zshrc" ]; then
            cat > "$local_zshrc" << 'EOF'
# Local zsh configuration
# This file is for machine-specific settings and is not tracked in git

# Dev environment location
export DOTFILES_DIR="$HOME/dev-env"

# Add your local customizations below
# Example:
# export PATH="$HOME/custom/bin:$PATH"
# alias myalias="my command"

EOF
            success "Created $local_zshrc for local customizations"
        fi

        # Ensure local config is sourced in main zshrc if not already
        if [ -f "$HOME/.zshrc" ] && ! grep -q ".zshrc.local" "$HOME/.zshrc"; then
            echo "" >> "$HOME/.zshrc"
            echo "# Source local configuration" >> "$HOME/.zshrc"
            echo "[ -f ~/.zshrc.local ] && source ~/.zshrc.local" >> "$HOME/.zshrc"
        fi

        # Shell configuration is ready - both mise and traditional version managers
        # will work automatically based on conditional logic in zshrc
        if [ "$USE_MISE" = true ]; then
            info "mise is configured and will be used for version management"
        else
            info "Traditional version managers (nvm, pyenv, bun) are configured"
        fi
    else
        info "[DRY RUN] Would create $local_zshrc"
        if [ "$USE_MISE" = true ]; then
            info "[DRY RUN] Would activate mise in shell configuration"
        fi
    fi

    echo ""
    success "Bootstrap complete!"
    echo ""

    if [ $ERROR_COUNT -gt 0 ]; then
        warning "Completed with $ERROR_COUNT warnings/errors"
        info "Review the output above for any issues"
        echo ""
    fi

    info "Next steps:"
    echo ""

    if [ -z "$GIT_USER_NAME" ] || [ -z "$GIT_USER_EMAIL" ]; then
        echo "  1. Configure Git user identity:"
        echo "     export GIT_USER_NAME=\"Your Name\""
        echo "     export GIT_USER_EMAIL=\"your.email@example.com\""
        echo "     git config --global user.name \"\$GIT_USER_NAME\""
        echo "     git config --global user.email \"\$GIT_USER_EMAIL\""
        echo ""
    fi

    echo "  2. Restart your terminal or run:"
    echo "     source ~/.zshrc"
    echo ""
    echo "  3. Review local customizations:"
    echo "     code ~/.zshrc.local"
    echo ""

    if [ "$USE_MISE" = true ]; then
        info "Version management configured with mise"
        echo "  - To add more tools, edit: $REPO_ROOT/mise/config.toml"
        echo "  - Then run: mise install"
        echo ""
    else
        info "Optional enhancements:"
        echo "  - Migrate to mise for unified version management:"
        echo "      ./bootstrap/install.sh --use-mise"
        echo ""
    fi

    echo "  - Install git-delta for better diffs:"
    echo "      brew install git-delta"
    echo "      # Then uncomment delta section in git/gitconfig"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "================================================================"
    echo "  Dev Environment Bootstrap"
    echo "================================================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Pre-flight checks
    check_macos
    check_dependencies

    # Initialize state tracking
    if command -v init_state_file &>/dev/null; then
        init_state_file
        local mode="standard"
        [ "$USE_MISE" = true ] && mode="mise"
        record_installation_start "$mode"
    fi

    # Track installation results
    local -a NEWLY_INSTALLED_SECTIONS=()
    local -a ALREADY_PRESENT_SECTIONS=()
    local -a FAILED_SECTIONS=()
    local -a SKIPPED_SECTIONS=()

    # Pre-check: What's already installed?
    local -A PRECHECK_STATUS=(
        [homebrew]=$(command_exists brew && echo "present" || echo "absent")
        [brew_packages]="check_later"  # Too complex for pre-check
        [brew_casks]="check_later"
        [oh_my_zsh]=$([ -d "$HOME/.oh-my-zsh" ] && echo "present" || echo "absent")
        [mise]=$(command_exists mise && echo "present" || echo "absent")
        [nvm]=$([ -d "$HOME/.nvm" ] && echo "present" || echo "absent")
        [pyenv]=$(command_exists pyenv && echo "present" || echo "absent")
        [bun]=$(command_exists bun && echo "present" || echo "absent")
        [rust]=$(command_exists cargo && echo "present" || echo "absent")
        [symlinks]=$([ -L "$HOME/.zshrc" ] && echo "present" || echo "absent")
        [vscode_extensions]="check_later"
        [git_config]="check_later"
        [shell_config]=$([ -f "$HOME/.zshrc.local" ] && echo "present" || echo "absent")
    )

    # Helper function to track section status
    track_section() {
        local section_name="$1"
        local success="$2"  # true/false

        if [ "$success" = "true" ]; then
            if [ "${PRECHECK_STATUS[$section_name]}" = "present" ]; then
                ALREADY_PRESENT_SECTIONS+=("$section_name")
            elif [ "${PRECHECK_STATUS[$section_name]}" = "check_later" ]; then
                # For complex sections, default to already_present if DRY_RUN or if no errors
                ALREADY_PRESENT_SECTIONS+=("$section_name")
            else
                NEWLY_INSTALLED_SECTIONS+=("$section_name")
            fi
        else
            FAILED_SECTIONS+=("$section_name")
        fi
    }

    # Run installation steps
    if install_homebrew; then
        track_section "homebrew" "true"
        command -v record_section_installed &>/dev/null && \
            record_section_installed "homebrew" "{\"path\": \"$(brew --prefix 2>/dev/null || echo '')\"}"
    else
        track_section "homebrew" "false"
    fi

    if install_brew_packages; then
        track_section "brew_packages" "true"
        # Record installed packages
        if command -v record_section_installed &>/dev/null; then
            local packages="[]"
            if command -v jq &>/dev/null; then
                packages=$(brew leaves 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')
            fi
            record_section_installed "brew_packages" "{\"packages\": $packages}"
        fi
    else
        track_section "brew_packages" "false"
    fi

    if install_brew_casks; then
        track_section "brew_casks" "true"
        # Record installed casks
        if command -v record_section_installed &>/dev/null; then
            local casks="[]"
            if command -v jq &>/dev/null; then
                casks=$(brew list --cask 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')
            fi
            record_section_installed "brew_casks" "{\"casks\": $casks}"
        fi
    else
        FAILED_SECTIONS+=("brew_casks")
    fi

    if install_oh_my_zsh; then
        track_section "oh_my_zsh" "true"
        command -v record_section_installed &>/dev/null && \
            record_section_installed "oh_my_zsh" "{}"
    else
        FAILED_SECTIONS+=("oh_my_zsh")
    fi

    # Version management: either mise or individual tools
    if [ "$USE_MISE" = true ]; then
        # mise is already installed via brew packages
        # Now configure it and install tools
        if setup_mise_config; then
            track_section "mise" "true"
            if command -v record_section_installed &>/dev/null; then
                local tools="[]"
                if command -v jq &>/dev/null; then
                    tools=$(mise list 2>/dev/null | awk '{print $1"@"$2}' | jq -R -s -c 'split("\n") | map(select(length > 0))')
                fi
                record_section_installed "mise" "{\"tools\": $tools}"
            fi
        else
            FAILED_SECTIONS+=("mise")
        fi

        # Record skipped sections
        SKIPPED_SECTIONS+=("nvm" "pyenv" "bun")
        command -v record_section_skipped &>/dev/null && record_section_skipped "nvm" "using_mise"
        command -v record_section_skipped &>/dev/null && record_section_skipped "pyenv" "using_mise"
        command -v record_section_skipped &>/dev/null && record_section_skipped "bun" "using_mise"
    else
        # Install individual version managers
        if install_nvm; then
            track_section "nvm" "true"
            command -v record_section_installed &>/dev/null && \
                record_section_installed "nvm" "{}"
        else
            FAILED_SECTIONS+=("nvm")
        fi

        if install_pyenv; then
            track_section "pyenv" "true"
            command -v record_section_installed &>/dev/null && \
                record_section_installed "pyenv" "{}"
        else
            FAILED_SECTIONS+=("pyenv")
        fi

        if install_bun; then
            track_section "bun" "true"
            command -v record_section_installed &>/dev/null && \
                record_section_installed "bun" "{}"
        else
            FAILED_SECTIONS+=("bun")
        fi

        # Record skipped mise
        SKIPPED_SECTIONS+=("mise")
        command -v record_section_skipped &>/dev/null && record_section_skipped "mise" "using_standard_mode"
    fi

    if install_rust; then
        track_section "rust" "true"
        command -v record_section_installed &>/dev/null && \
            record_section_installed "rust" "{}"
    else
        FAILED_SECTIONS+=("rust")
    fi

    install_conda  # Conda is optional, don't track

    if create_symlinks; then
        track_section "symlinks" "true"
        # Record symlinks and backup location
        if command -v record_section_installed &>/dev/null; then
            local links="{}"
            if command -v jq &>/dev/null; then
                links=$(cat <<EOF
{
  ".zshrc": "$(readlink "$HOME/.zshrc" 2>/dev/null || echo '')",
  ".gitconfig": "$(readlink "$HOME/.gitconfig" 2>/dev/null || echo '')",
  ".gitignore_global": "$(readlink "$HOME/.gitignore_global" 2>/dev/null || echo '')"
}
EOF
)
            fi

            local backup_dir=$(ls -1d "$HOME/.dotfiles-backup-"* 2>/dev/null | tail -1)
            if [ -n "$backup_dir" ]; then
                record_section_installed "symlinks" "{\"links\": $links, \"backup_dir\": \"$backup_dir\"}"
                record_backup "$backup_dir"
            else
                record_section_installed "symlinks" "{\"links\": $links}"
            fi
        fi
    else
        FAILED_SECTIONS+=("symlinks")
    fi

    if install_vscode_extensions; then
        track_section "vscode_extensions" "true"
        if command -v record_section_installed &>/dev/null; then
            local count=$(code --list-extensions 2>/dev/null | wc -l | xargs)
            record_section_installed "vscode_extensions" "{\"count\": $count}"
        fi
    else
        FAILED_SECTIONS+=("vscode_extensions")
    fi

    if configure_git; then
        track_section "git_config" "true"
        if command -v record_section_installed &>/dev/null; then
            local user_name=$(git config --global user.name 2>/dev/null || echo '')
            local user_email=$(git config --global user.email 2>/dev/null || echo '')
            record_section_installed "git_config" "{\"user_name\": \"$user_name\", \"user_email\": \"$user_email\"}"
        fi
    else
        FAILED_SECTIONS+=("git_config")
    fi

    if final_setup; then
        track_section "shell_config" "true"
        command -v record_section_installed &>/dev/null && \
            record_section_installed "shell_config" "{}"
    else
        FAILED_SECTIONS+=("shell_config")
    fi

    echo ""
    echo "================================================================"
    if [ "$DRY_RUN" = true ]; then
        echo "  Dry Run Summary (No Changes Made)"
    else
        echo "  Installation Summary"
    fi
    echo "================================================================"
    echo ""

    # Display summary
    local total_successful=$((${#NEWLY_INSTALLED_SECTIONS[@]} + ${#ALREADY_PRESENT_SECTIONS[@]}))

    if [ ${#NEWLY_INSTALLED_SECTIONS[@]} -gt 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            success "Will install ${#NEWLY_INSTALLED_SECTIONS[@]} section(s):"
        else
            success "Newly installed ${#NEWLY_INSTALLED_SECTIONS[@]} section(s):"
        fi
        for section in "${NEWLY_INSTALLED_SECTIONS[@]}"; do
            echo "  ✓ $section"
        done
        echo ""
    fi

    if [ ${#ALREADY_PRESENT_SECTIONS[@]} -gt 0 ]; then
        if [ "$DRY_RUN" = false ]; then
            info "Already present ${#ALREADY_PRESENT_SECTIONS[@]} section(s):"
            for section in "${ALREADY_PRESENT_SECTIONS[@]}"; do
                echo "  ✓ $section"
            done
            echo ""
        fi
    fi

    if [ ${#SKIPPED_SECTIONS[@]} -gt 0 ]; then
        info "Skipped ${#SKIPPED_SECTIONS[@]} section(s):"
        for section in "${SKIPPED_SECTIONS[@]}"; do
            echo "  - $section"
        done
        echo ""
    fi

    if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        warning "Failed ${#FAILED_SECTIONS[@]} section(s):"
        for section in "${FAILED_SECTIONS[@]}"; do
            echo "  ✗ $section"
        done
        echo ""
    fi

    # Overall result
    if [ ${#FAILED_SECTIONS[@]} -eq 0 ]; then
        if [ "$DRY_RUN" = true ]; then
            success "Dry run completed successfully - no changes were made"
            echo ""
            info "To perform the actual installation, run without --dry-run:"
            if [ "$USE_MISE" = true ]; then
                info "  ./bootstrap/install.sh --use-mise"
            else
                info "  ./bootstrap/install.sh"
            fi
        else
            success "Installation completed successfully!"
        fi
    else
        if [ "$DRY_RUN" = true ]; then
            warning "Dry run completed with ${#FAILED_SECTIONS[@]} issue(s)"
            echo ""
            info "These issues would need to be resolved before installation"
        else
            warning "Installation completed with ${#FAILED_SECTIONS[@]} error(s)"
            echo ""
            info "You can try to fix the issues and re-run the installer"
            info "The installer is idempotent - it's safe to run multiple times"
        fi
    fi

    echo ""
    echo "================================================================"

    # Exit with error code if there were issues
    if [ $ERROR_COUNT -gt 0 ] || [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"
