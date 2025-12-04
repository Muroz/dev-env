#!/usr/bin/env bash

# ============================================================================
# Dev Environment Bootstrap Script
# ============================================================================
# Sets up a fresh macOS system with all development tools and configurations
#
# Usage: ./install.sh [--dry-run] [--skip-backups] [--use-mise]
#
# What this script does:
# 1. Installs Homebrew (if not present)
# 2. Installs all brew packages and casks
# 3. Installs oh-my-zsh (if not present)
# 4. Installs global development tools (nvm, pyenv, bun, rust)
# 5. Creates symlinks for configuration files
# 6. Sets up VS Code extensions
# 7. Configures git (with environment variables)
#
# IMPORTANT: Set these environment variables before running:
#   export GIT_USER_NAME="Your Name"
#   export GIT_USER_EMAIL="your.email@example.com"
#
# ============================================================================

set -o pipefail  # Catch errors in pipes
# Note: Not using 'set -e' to allow graceful handling of individual failures

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
            echo "  --use-mise       Use mise for version management instead of nvm/pyenv/bun"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Standard installation"
            echo "  $0 --dry-run          # Preview what would be installed"
            echo "  $0 --use-mise         # Install with mise for unified version management"
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

install_brew_packages() {
    info "Installing Homebrew packages..."

    if [ ! -f "$REPO_ROOT/bootstrap/brew-packages.txt" ]; then
        warning "brew-packages.txt not found"
        return 1
    fi

    local package_count=0
    local installed_count=0
    local failed_packages=()

    while IFS= read -r package; do
        # Skip empty lines and comments
        [[ -z "$package" || "$package" =~ ^# ]] && continue

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
    done < "$REPO_ROOT/bootstrap/brew-packages.txt"

    if [ ${#failed_packages[@]} -ne 0 ]; then
        warning "Failed to install: ${failed_packages[*]}"
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

install_mise() {
    info "Checking for mise..."

    if command_exists mise; then
        success "mise already installed ($(mise --version))"
    else
        if [ "$DRY_RUN" = false ]; then
            info "Installing mise via Homebrew..."
            if brew install mise; then
                success "mise installed"

                # Install tools from mise config if it exists
                if [ -f "$REPO_ROOT/mise/config.toml" ]; then
                    info "Installing tools from mise configuration..."

                    # Update mise config to uncomment tool versions
                    if grep -q "^# node = " "$REPO_ROOT/mise/config.toml"; then
                        info "Activating tool versions in mise config..."
                        # This will be handled by editing the config file below
                    fi

                    # Activate mise for current session
                    eval "$(mise activate bash)"

                    # Install configured tools
                    if mise install; then
                        success "mise tools installed"
                    else
                        warning "Some mise tools failed to install"
                    fi
                fi
            else
                error "Failed to install mise"
                return 1
            fi
        else
            info "[DRY RUN] Would install mise and configure tools"
        fi
    fi
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

    info "Installing VS Code extensions..."

    if [ ! -f "$REPO_ROOT/editors/vscode/extensions.txt" ]; then
        warning "extensions.txt not found"
        return 1
    fi

    local ext_count=0
    local installed_count=0
    local failed_extensions=()

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
                if code --install-extension "$extension" --force &>/dev/null; then
                    ((installed_count++))
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

    success "VS Code extensions: $installed_count/$ext_count installed"

    # Copy VS Code settings
    local vscode_user_dir="$HOME/Library/Application Support/Code/User"
    if [ -d "$vscode_user_dir" ]; then
        if [ "$DRY_RUN" = false ]; then
            info "Copying VS Code settings..."
            cp "$REPO_ROOT/editors/vscode/settings.json" "$vscode_user_dir/settings.json"
            cp "$REPO_ROOT/editors/vscode/keybindings.json" "$vscode_user_dir/keybindings.json"
            success "VS Code settings copied"
        else
            info "[DRY RUN] Would copy VS Code settings"
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

        # If using mise, activate it in zshrc
        if [ "$USE_MISE" = true ] && [ -f "$HOME/.zshrc" ]; then
            if ! grep -q "mise activate" "$HOME/.zshrc"; then
                info "Activating mise in shell configuration..."
                # Comment out individual version managers
                sed -i.bak 's/^export NVM_DIR=/# export NVM_DIR=/' "$HOME/.zshrc" 2>/dev/null || true
                sed -i.bak 's/^eval "$(pyenv init/# eval "$(pyenv init/' "$HOME/.zshrc" 2>/dev/null || true

                # Uncomment mise section
                sed -i.bak 's/^# if command -v mise/if command -v mise/' "$HOME/.zshrc" 2>/dev/null || true
                sed -i.bak 's/^#   eval "$(mise activate/  eval "$(mise activate/' "$HOME/.zshrc" 2>/dev/null || true
                sed -i.bak 's/^# fi  # mise/fi  # mise/' "$HOME/.zshrc" 2>/dev/null || true

                rm -f "$HOME/.zshrc.bak"
                success "mise activated in shell configuration"
            fi
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

    info "Optional enhancements:"
    echo "  - Install mise for unified version management:"
    echo "      brew install mise"
    echo "      # Then uncomment mise section in shell/zshrc"
    echo ""
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

    # Run installation steps
    install_homebrew
    install_brew_packages
    install_brew_casks
    install_oh_my_zsh

    # Version management: either mise or individual tools
    if [ "$USE_MISE" = true ]; then
        install_mise
    else
        install_nvm
        install_pyenv
        install_bun
    fi

    install_rust
    install_conda
    create_symlinks
    install_vscode_extensions
    configure_git
    final_setup

    echo ""
    echo "================================================================"

    # Exit with error code if there were issues
    if [ $ERROR_COUNT -gt 0 ]; then
        exit 1
    fi
}

# Run main function
main "$@"
