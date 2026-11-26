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
#   --help           Display usage information and available options
#
# Examples:
#   ./install.sh                     # Set this machine up
#   ./install.sh --dry-run           # Preview what would be installed
#
# What this script does:
# 1. Validates macOS system and required dependencies (curl, git)
# 2. Installs Homebrew (if not present) for both Intel and Apple Silicon
# 3. Installs brew packages from brew-packages.txt
# 4. Installs cask applications from cask-apps.txt
# 5. Installs oh-my-zsh (if not present)
# 6. Configures mise from mise/config.toml, plus rustup and conda
# 7. Creates symlinks for shell and git configurations (with automatic backups)
# 8. Installs VS Code extensions and copies settings
# 9. Configures git identity in ~/.gitconfig.local
# 10. Creates ~/.zshrc.local for machine-specific customizations
# 11. Installs the pre-commit hook and the weekly drift check
#
# Version management:
#   mise handles Node and Bun, from the versions pinned in mise/config.toml.
#   Rust stays with rustup, and Python stays with conda. There used to be a
#   --use-mise flag selecting between mise and nvm/pyenv; the second path is
#   gone, because one way of setting a machine up is the point of this repo.
#
# IMPORTANT: Set these environment variables before running:
#   export GIT_USER_NAME="Your Name"
#   export GIT_USER_EMAIL="your.email@example.com"
#
# ============================================================================

set -o pipefail  # Catch errors in pipes
# Note: Not using 'set -e' to allow graceful handling of individual failures

# Script directory. Must be resolved before anything that sources from it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Source state tracking library
if [ -f "$SCRIPT_DIR/lib/state.sh" ]; then
    source "$SCRIPT_DIR/lib/state.sh"
else
    echo "[ERROR] Missing $SCRIPT_DIR/lib/state.sh" >&2
    exit 1
fi

# Source manifest parsing, shared with scripts/update-tools.sh
if [ -f "$SCRIPT_DIR/lib/packages.sh" ]; then
    source "$SCRIPT_DIR/lib/packages.sh"
else
    echo "[ERROR] Missing $SCRIPT_DIR/lib/packages.sh" >&2
    exit 1
fi

# Re-assert, in case a sourced file assigned either name.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Flags
DRY_RUN=false
SKIP_BACKUPS=false
ERROR_COUNT=0
# Counted apart from errors: a warning means an optional tool is absent, not
# that the install failed, and only errors and failed sections decide the
# exit status.
WARNING_COUNT=0

# Parse arguments
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip-backups)
            SKIP_BACKUPS=true
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --dry-run        Preview changes without making modifications"
            echo "  --skip-backups   Skip creating backups of existing configuration files"
            echo "  --help           Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                    # Set this machine up"
            echo "  $0 --dry-run          # Preview what would be installed"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: $0 [--dry-run] [--skip-backups] [--help]"
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
    ((WARNING_COUNT++))
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

    local manifest="$REPO_ROOT/bootstrap/brew-packages.txt"

    if [ ! -f "$manifest" ]; then
        warning "brew-packages.txt not found"
        return 1
    fi

    local package_count=0
    local installed_count=0
    local failed_packages=()
    local package

    # read_manifest applies the [CONDITIONAL: ...] markers for this mode.
    while IFS= read -r package; do
        ((package_count++))

        if formula_installed "$package"; then
            info "  ✓ $package already installed"
            ((installed_count++))
        elif [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would install $package"
        else
            info "  Installing $package..."
            if brew install "$package"; then
                ((installed_count++))
            else
                warning "Failed to install $package"
                failed_packages+=("$package")
            fi
        fi
    done < <(read_manifest "$manifest")

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

    local manifest="$REPO_ROOT/bootstrap/cask-apps.txt"

    if [ ! -f "$manifest" ]; then
        warning "cask-apps.txt not found"
        return 0
    fi

    local cask_count=0
    local installed_count=0
    local failed_casks=()
    local cask

    while IFS= read -r cask; do
        ((cask_count++))

        if cask_installed "$cask"; then
            info "  ✓ $cask already installed"
            ((installed_count++))
            continue
        fi

        # Already on disk from a manual download. Adoption needs sudo and
        # only works while the installed version matches the cask exactly, so
        # attempting it here would re-download the app and then fail on the
        # password prompt. The app is present, which is what matters.
        if cask_app_present "$cask"; then
            info "  ✓ $cask present (not brew-managed)"
            ((installed_count++))
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would install $cask"
            continue
        fi

        # --adopt still goes on the install, for the case where the app does
        # appear mid-run or the versions happen to line up.
        info "  Installing $cask..."
        if brew install --cask --adopt "$cask"; then
            ((installed_count++))
        else
            warning "Failed to install $cask"
            failed_casks+=("$cask")
        fi
    done < <(read_manifest "$manifest")

    if [ ${#failed_casks[@]} -ne 0 ]; then
        warning "Failed to install casks: ${failed_casks[*]}"
    fi

    success "Brew casks: $installed_count/$cask_count installed"

    # Self-updating apps keep themselves current; brew only interferes if
    # asked to. Say so once, where someone setting up a machine will see it.
    info "Casks are bootstrap only: never run 'brew upgrade --cask --greedy'"
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

# mise has no Homebrew bottle on macOS 14 arm64, so brew would build it and
# its LLVM and Rust dependencies from source. Its own installer ships a
# prebuilt binary, checksum-verified, into ~/.local/bin — the same approach
# already used here for oh-my-zsh and rustup.
install_mise() {
    info "Checking for mise..."

    if command_exists mise; then
        success "mise already installed ($(mise --version 2>&1 | head -1))"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would install mise from https://mise.run"
        return 0
    fi

    local installer="/tmp/mise-install-$$.sh"

    if ! curl -fsSL https://mise.run -o "$installer"; then
        error "Could not download the mise installer"
        rm -f "$installer"
        return 1
    fi

    # Installs to ~/.local/bin/mise unless MISE_INSTALL_PATH says otherwise.
    if sh "$installer"; then
        rm -f "$installer"
        # Not yet on PATH in this shell: ~/.local/bin is added by zshrc, which
        # has not been re-sourced.
        export PATH="$HOME/.local/bin:$PATH"
        if command_exists mise; then
            success "mise installed ($(mise --version 2>&1 | head -1))"
            return 0
        fi
        error "mise installer finished but mise is not on PATH"
        return 1
    fi

    error "Failed to install mise"
    rm -f "$installer"
    return 1
}

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
        info "[DRY RUN] Would use tool versions from $config_file as committed"
        info "[DRY RUN] Would create symlink: $global_config → $config_file"
        info "[DRY RUN] Would run: mise trust $config_file"
        info "[DRY RUN] Would run: mise install"
        return 0
    fi

    # At this point, we're not in dry-run mode, so mise should be installed
    if ! command_exists mise; then
        error "mise not found"
        info "Try running: curl -fsSL https://mise.run | sh"
        return 1
    fi

    # The config carries live versions and is used as committed. Nothing here
    # rewrites it: editing a tracked file during install leaves the repo dirty,
    # which then breaks the `git pull` in scripts/update-tools.sh.
    if ! grep -qE '^[a-z]+ = ' "$config_file"; then
        warning "No tool versions set in $config_file"
        info "Add versions under [tools], then re-run"
        return 1
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

    # mise refuses a config file it has not been told to trust, so without
    # this `mise install` below fails on a fresh machine. Carried over from
    # 6c66255, which fixed it on the other laptop.
    info "Trusting the mise config..."
    if mise trust "$config_file"; then
        success "mise config trusted"
    else
        warning "Could not trust the mise config"
        info "Run: mise trust $config_file"
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

    local backup_dir
    backup_dir="$HOME/.dotfiles-backup-$(date +%Y%m%d_%H%M%S)"

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

    # Rescue the git identity before ~/.gitconfig is replaced. It is about to
    # become a symlink into the repo, and git writes through a symlink, so the
    # identity has to live in the untracked ~/.gitconfig.local instead. Doing
    # it here rather than in configure_git keeps it safe whatever the order.
    preserve_git_identity() {
        local local_config="$HOME/.gitconfig.local"
        local existing="$HOME/.gitconfig"

        # Already moved out, or nothing to move.
        [ -f "$local_config" ] && return 0
        [ -f "$existing" ] && [ ! -L "$existing" ] || return 0

        local name email
        name=$(git config --file "$existing" --get user.name 2>/dev/null)
        email=$(git config --file "$existing" --get user.email 2>/dev/null)

        [ -n "$name" ] || [ -n "$email" ] || return 0

        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would copy the git identity to $local_config"
            return 0
        fi

        [ -n "$name" ] && git config --file "$local_config" user.name "$name"
        [ -n "$email" ] && git config --file "$local_config" user.email "$email"
        success "Preserved git identity in $local_config"
    }

    preserve_git_identity

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
    done < <(read_manifest "$REPO_ROOT/editors/vscode/extensions.txt")

    if [ ${#failed_extensions[@]} -ne 0 ]; then
        warning "Failed to install extensions: ${failed_extensions[*]}"
    fi

    success "VS Code extensions: $installed_count/$ext_count installed"

    # Copy VS Code settings. Anything already there is backed up first: these
    # are hand-edited files and overwriting one without a copy loses work.
    local vscode_user_dir="$HOME/Library/Application Support/Code/User"

    if [ ! -d "$vscode_user_dir" ]; then
        warning "VS Code user directory not found. Settings not copied."
        return 0
    fi

    local file
    for file in settings.json keybindings.json; do
        local src="$REPO_ROOT/editors/vscode/$file"
        local dest="$vscode_user_dir/$file"

        [ -f "$src" ] || continue

        if [ -f "$dest" ] && diff -q "$src" "$dest" >/dev/null 2>&1; then
            info "  ✓ $file already matches the repo"
            continue
        fi

        if [ "$DRY_RUN" = true ]; then
            if [ -f "$dest" ]; then
                info "[DRY RUN] Would back up and replace $file"
            else
                info "[DRY RUN] Would install $file"
            fi
            continue
        fi

        if [ -f "$dest" ]; then
            cp "$dest" "$dest.backup-$(date +%Y%m%d_%H%M%S)"
            info "  Backed up existing $file"
        fi

        cp "$src" "$dest"
        info "  Installed $file"
    done

    success "VS Code settings in place"
}

# ============================================================================
# 8. Git Configuration with Environment Variables
# ============================================================================

configure_git() {
    info "Configuring Git..."

    # Identity lives in ~/.gitconfig.local, pulled in by the [include] at the
    # end of git/gitconfig. It must not be written with `git config --global`:
    # ~/.gitconfig is a symlink into the repo and git writes through it, so
    # the address would land in a tracked file.
    local local_config="$HOME/.gitconfig.local"

    # `git config --get` reads includes; the --global form does not.
    local existing_name existing_email
    existing_name=$(git config --get user.name 2>/dev/null)
    existing_email=$(git config --get user.email 2>/dev/null)

    if [ -z "$GIT_USER_NAME" ] && [ -z "$GIT_USER_EMAIL" ]; then
        if [ -n "$existing_name" ] && [ -n "$existing_email" ]; then
            if [ -f "$local_config" ]; then
                success "Git user already configured: $existing_name <$existing_email>"
                return 0
            fi

            # Identity is set, but in a file about to become a symlink into
            # the repo. Move it out before that can commit it.
            warning "Git identity is not yet in $local_config"
            if [ "$DRY_RUN" = true ]; then
                info "[DRY RUN] Would copy the identity to $local_config"
                return 0
            fi

            GIT_USER_NAME="$existing_name"
            GIT_USER_EMAIL="$existing_email"
            info "Moving the existing identity to $local_config"
        else
            warning "GIT_USER_NAME and GIT_USER_EMAIL environment variables not set"
            info "Git user identity not configured. Either:"
            info "  cp $REPO_ROOT/git/gitconfig.local.example $local_config"
            info "  \$EDITOR $local_config"
            info "or set the variables and re-run:"
            info "  export GIT_USER_NAME=\"Your Name\""
            info "  export GIT_USER_EMAIL=\"your.email@example.com\""
            return 0
        fi
    fi

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would write $local_config for $GIT_USER_NAME <$GIT_USER_EMAIL>"
        return 0
    fi

    if [ -f "$local_config" ]; then
        cp "$local_config" "$local_config.backup-$(date +%Y%m%d_%H%M%S)"
    fi

    # Written with git itself, against that file, so nothing touches
    # ~/.gitconfig.
    git config --file "$local_config" user.name "$GIT_USER_NAME"
    git config --file "$local_config" user.email "$GIT_USER_EMAIL"
    success "Git user configured in $local_config"
}

# ============================================================================
# 9. Final Setup
# ============================================================================

# Point this checkout's pre-commit hook at the version in the repo, so the
# quality gate runs before a commit here. Only affects the dev-env checkout.
install_git_hooks() {
    local hook_source="$REPO_ROOT/bootstrap/hooks/pre-commit"
    local hook_dir="$REPO_ROOT/.git/hooks"
    local hook_target="$hook_dir/pre-commit"

    [ -f "$hook_source" ] || return 0

    # Not a git checkout, or a worktree where .git is a file.
    [ -d "$hook_dir" ] || return 0

    if [ -L "$hook_target" ] || [ ! -e "$hook_target" ]; then
        if [ "$DRY_RUN" = true ]; then
            info "[DRY RUN] Would link the pre-commit hook"
            return 0
        fi
        ln -sfn "$hook_source" "$hook_target"
        success "Installed the pre-commit hook (skip once with --no-verify)"
    else
        # Someone wrote their own hook; leave it.
        info "Kept the existing pre-commit hook in this checkout"
    fi
}

# The weekly drift check. launchd cannot expand $HOME or any variable, so the
# template's placeholders are filled in with real paths on the way out.
install_drift_agent() {
    local template="$REPO_ROOT/bootstrap/launchd/com.dev-env.drift.plist.template"
    local label="com.dev-env.drift"
    local target="$HOME/Library/LaunchAgents/$label.plist"

    [ -f "$template" ] || return 0

    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] Would install the weekly drift check at $target"
        return 0
    fi

    mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.dev-env"

    sed -e "s|__REPO_ROOT__|$REPO_ROOT|g" \
        -e "s|__HOME__|$HOME|g" \
        "$template" > "$target"

    # Replace any previous registration, so a moved checkout takes effect.
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true

    if launchctl bootstrap "gui/$(id -u)" "$target" 2>/dev/null; then
        success "Weekly drift check scheduled (Mondays, 10:00)"
        info "Run it now with: ./scripts/notify-drift.sh --stdout"
    else
        warning "Could not load the drift check agent"
        info "Load it by hand: launchctl bootstrap gui/$(id -u) $target"
    fi
}

final_setup() {
    info "Running final setup..."

    # Create a local shell config file for user-specific customizations
    local local_zshrc="$HOME/.zshrc.local"

    install_git_hooks
    install_drift_agent

    # Nothing here edits ~/.zshrc. It is a symlink into the repo, so sed -i or
    # an append would rewrite the tracked file and leave the checkout dirty.
    # shell/zshrc already sources ~/.zshrc.local and already activates mise
    # whenever ~/.config/mise/config.toml exists, so no patching is needed.
    if [ "$DRY_RUN" = false ]; then
        if [ ! -f "$local_zshrc" ]; then
            if [ -f "$REPO_ROOT/shell/zshrc.local.example" ]; then
                cp "$REPO_ROOT/shell/zshrc.local.example" "$local_zshrc"
            else
                printf '%s\n' \
                    '#!/bin/zsh' \
                    '# Machine-specific shell configuration, sourced last by shell/zshrc.' \
                    '# Not tracked in git.' \
                    '' \
                    '# export PATH="$HOME/custom/bin:$PATH"' \
                    > "$local_zshrc"
            fi
            success "Created $local_zshrc for machine-specific settings"
        else
            info "Kept existing $local_zshrc"
        fi
    else
        info "[DRY RUN] Would create $local_zshrc"
    fi

    echo ""
    success "Bootstrap complete!"
    echo ""

    if [ $ERROR_COUNT -gt 0 ]; then
        echo -e "${RED}[SUMMARY]${NC} $ERROR_COUNT error(s), $WARNING_COUNT warning(s)"
        info "Review the output above"
        echo ""
    elif [ $WARNING_COUNT -gt 0 ]; then
        echo -e "${YELLOW}[SUMMARY]${NC} completed with $WARNING_COUNT warning(s)"
        info "Usually an optional tool that is not installed"
        echo ""
    fi

    info "Next steps:"
    echo ""

    if [ -z "$(git config --get user.name 2>/dev/null)" ] || \
       [ -z "$(git config --get user.email 2>/dev/null)" ]; then
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

    info "Version management runs through mise"
    echo "  - To change a version, edit: $REPO_ROOT/mise/config.toml"
    echo "  - Then run: mise install"
    echo ""
    info "Optional enhancements:"
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
        echo -e "${YELLOW}[DRY RUN]${NC} No changes will be made"
        echo ""
    fi

    # Pre-flight checks
    check_macos
    check_dependencies

    # Initialize state tracking
    if command -v init_state_file &>/dev/null; then
        init_state_file
        local mode="mise"
        record_installation_start "$mode"
    fi

    # Track installation results
    local -a SUCCESSFUL_SECTIONS=()
    local -a FAILED_SECTIONS=()
    local -a SKIPPED_SECTIONS=()

    # Run installation steps
    if install_homebrew; then
        SUCCESSFUL_SECTIONS+=("homebrew")
        command -v record_section_installed &>/dev/null && \
            record_section_installed "homebrew" "{\"path\": \"$(brew --prefix 2>/dev/null || echo '')\"}"
    else
        FAILED_SECTIONS+=("homebrew")
    fi

    if install_brew_packages; then
        SUCCESSFUL_SECTIONS+=("brew_packages")
        # Record installed packages
        if command -v record_section_installed &>/dev/null; then
            local packages="[]"
            if command -v jq &>/dev/null; then
                packages=$(brew leaves 2>/dev/null | jq -R -s -c 'split("\n") | map(select(length > 0))')
            fi
            record_section_installed "brew_packages" "{\"packages\": $packages}"
        fi
    else
        FAILED_SECTIONS+=("brew_packages")
    fi

    if install_brew_casks; then
        SUCCESSFUL_SECTIONS+=("brew_casks")
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
        SUCCESSFUL_SECTIONS+=("oh_my_zsh")
        command -v record_section_installed &>/dev/null && \
            record_section_installed "oh_my_zsh" "{}"
    else
        FAILED_SECTIONS+=("oh_my_zsh")
    fi

    # Version management. mise handles Node and Bun; rustup and conda keep
    # their own tools. There is no second path: a single way to set a machine
    # up is the whole reason the --use-mise flag is gone.
    if install_mise && setup_mise_config; then
        SUCCESSFUL_SECTIONS+=("mise")
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

    if install_rust; then
        SUCCESSFUL_SECTIONS+=("rust")
        command -v record_section_installed &>/dev/null && \
            record_section_installed "rust" "{}"
    else
        FAILED_SECTIONS+=("rust")
    fi

    install_conda  # Conda is optional, don't track

    if create_symlinks; then
        SUCCESSFUL_SECTIONS+=("symlinks")
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

            local backup_dir
            backup_dir=$(ls -1d "$HOME/.dotfiles-backup-"* 2>/dev/null | tail -1)
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
        SUCCESSFUL_SECTIONS+=("vscode_extensions")
        if command -v record_section_installed &>/dev/null; then
            local count
            count=$(code --list-extensions 2>/dev/null | wc -l | xargs)
            record_section_installed "vscode_extensions" "{\"count\": $count}"
        fi
    else
        FAILED_SECTIONS+=("vscode_extensions")
    fi

    if configure_git; then
        SUCCESSFUL_SECTIONS+=("git_config")
        if command -v record_section_installed &>/dev/null; then
            local user_name
            user_name=$(git config --global user.name 2>/dev/null || echo '')
            local user_email
            user_email=$(git config --global user.email 2>/dev/null || echo '')
            record_section_installed "git_config" "{\"user_name\": \"$user_name\", \"user_email\": \"$user_email\"}"
        fi
    else
        FAILED_SECTIONS+=("git_config")
    fi

    if final_setup; then
        SUCCESSFUL_SECTIONS+=("shell_config")
        command -v record_section_installed &>/dev/null && \
            record_section_installed "shell_config" "{}"
    else
        FAILED_SECTIONS+=("shell_config")
    fi

    echo ""
    echo "================================================================"
    echo "  Installation Summary"
    echo "================================================================"
    echo ""

    # Display summary
    if [ ${#SUCCESSFUL_SECTIONS[@]} -gt 0 ]; then
        success "Successfully installed ${#SUCCESSFUL_SECTIONS[@]} section(s):"
        for section in "${SUCCESSFUL_SECTIONS[@]}"; do
            echo "  ✓ $section"
        done
        echo ""
    fi

    if [ ${#SKIPPED_SECTIONS[@]} -gt 0 ]; then
        info "Skipped ${#SKIPPED_SECTIONS[@]} section(s):"
        for section in "${SKIPPED_SECTIONS[@]}"; do
            echo "  - $section"
        done
        echo ""
    fi

    if [ ${#FAILED_SECTIONS[@]} -gt 0 ]; then
        warning "Failed to install ${#FAILED_SECTIONS[@]} section(s):"
        for section in "${FAILED_SECTIONS[@]}"; do
            echo "  ✗ $section"
        done
        echo ""
    fi

    # Overall result
    if [ ${#FAILED_SECTIONS[@]} -eq 0 ]; then
        success "Installation completed successfully!"
    else
        warning "Installation completed with ${#FAILED_SECTIONS[@]} error(s)"
        echo ""
        info "You can try to fix the issues and re-run the installer"
        info "The installer is idempotent - it's safe to run multiple times"
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
