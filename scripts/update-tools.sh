#!/usr/bin/env bash

# ============================================================================
# Dev Environment Update Script
# ============================================================================
# Run this script on each machine after updating dev-env repository
# to sync tool versions and configurations
#
# Usage: ./update-tools.sh
#
# What this script does:
# 1. Pulls latest changes from dev-env repo
# 2. Updates Homebrew and packages
# 3. Updates version managers (nvm, pyenv, bun, rust)
# 4. Updates VS Code extensions
# 5. Refreshes symlinks
# 6. Optionally runs mise install (if using mise)
#
# ============================================================================

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

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
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================================
# Update Functions
# ============================================================================

update_repo() {
    info "Updating dev-env repository..."

    cd "$REPO_ROOT"

    if [ -d ".git" ]; then
        git pull
        success "Repository updated"
    else
        warning "Not a git repository"
    fi
}

update_homebrew() {
    info "Updating Homebrew..."

    if command_exists brew; then
        brew update
        brew upgrade
        brew cleanup
        success "Homebrew updated"
    else
        warning "Homebrew not installed"
    fi
}

update_brew_packages() {
    info "Checking for new Homebrew packages..."

    if [ -f "$REPO_ROOT/bootstrap/brew-packages.txt" ]; then
        while IFS= read -r package; do
            [[ -z "$package" || "$package" =~ ^# ]] && continue

            if ! brew list --formula | grep -q "^${package}\$"; then
                info "Installing new package: $package"
                brew install "$package"
            fi
        done < "$REPO_ROOT/bootstrap/brew-packages.txt"
        success "Brew packages synced"
    fi
}

update_vscode_extensions() {
    info "Updating VS Code extensions..."

    if ! command_exists code; then
        warning "VS Code CLI not found"
        return 0
    fi

    # Update existing extensions
    info "Updating existing extensions..."
    code --update-extensions || warning "Could not auto-update extensions"

    # Install new extensions from list
    if [ -f "$REPO_ROOT/editors/vscode/extensions.txt" ]; then
        while IFS= read -r extension; do
            [[ -z "$extension" || "$extension" =~ ^# ]] && continue

            if ! code --list-extensions | grep -qi "^${extension}\$"; then
                info "Installing new extension: $extension"
                code --install-extension "$extension" --force
            fi
        done < "$REPO_ROOT/editors/vscode/extensions.txt"
        success "VS Code extensions updated"
    fi
}

update_nvm() {
    info "Checking nvm..."

    if [ -d "$HOME/.nvm" ]; then
        # Source nvm
        export NVM_DIR="$HOME/.nvm"
        [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"

        if command_exists nvm; then
            info "Current node version: $(nvm current)"
            info "Run 'nvm install <version>' to update Node.js"
        fi
    else
        warning "nvm not installed"
    fi
}

update_pyenv() {
    info "Checking pyenv..."

    if command_exists pyenv; then
        # Update pyenv via Homebrew
        brew upgrade pyenv 2>/dev/null || true

        info "Current python version: $(pyenv version 2>/dev/null || echo 'not set')"
        info "Run 'pyenv install <version>' to update Python"
        success "pyenv checked"
    else
        warning "pyenv not installed"
    fi
}

update_bun() {
    info "Updating Bun..."

    if command_exists bun; then
        bun upgrade
        success "Bun updated to $(bun --version)"
    else
        warning "Bun not installed"
    fi
}

update_rust() {
    info "Updating Rust..."

    if command_exists rustup; then
        rustup update
        success "Rust updated to $(rustc --version)"
    else
        warning "Rust not installed"
    fi
}

update_conda() {
    info "Checking Conda..."

    if command_exists conda; then
        conda update -n base -c defaults conda -y
        success "Conda updated"
    else
        info "Conda not installed (optional)"
    fi
}

update_mise() {
    info "Checking for mise..."

    if command_exists mise; then
        info "Updating mise..."
        brew upgrade mise 2>/dev/null || true

        info "Installing tools from mise config..."
        mise install

        success "Mise updated and tools synchronized"
    else
        info "mise not installed (optional)"
        info "To migrate to mise, run: brew install mise"
    fi
}

refresh_symlinks() {
    info "Refreshing configuration symlinks..."

    # Re-link zshrc
    ln -sf "$REPO_ROOT/shell/zshrc" "$HOME/.zshrc"

    # Re-link git configs
    ln -sf "$REPO_ROOT/git/gitconfig" "$HOME/.gitconfig"
    ln -sf "$REPO_ROOT/git/gitignore_global" "$HOME/.gitignore_global"

    success "Symlinks refreshed"
}

update_vscode_settings() {
    info "Updating VS Code settings..."

    vscode_user_dir="$HOME/Library/Application Support/Code/User"
    if [ -d "$vscode_user_dir" ]; then
        cp "$REPO_ROOT/editors/vscode/settings.json" "$vscode_user_dir/settings.json"
        cp "$REPO_ROOT/editors/vscode/keybindings.json" "$vscode_user_dir/keybindings.json"
        success "VS Code settings updated"
    else
        warning "VS Code user directory not found"
    fi
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo "  Dev Environment Update"
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
    echo ""

    update_repo
    update_homebrew
    update_brew_packages
    update_vscode_extensions
    update_vscode_settings
    update_nvm
    update_pyenv
    update_bun
    update_rust
    update_conda
    update_mise
    refresh_symlinks

    echo ""
    success "Update complete!"
    echo ""
    info "Restart your terminal or run: source ~/.zshrc"
    echo ""
    echo "PPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPPP"
}

# Run main function
main
