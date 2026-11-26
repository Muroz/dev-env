#!/usr/bin/env bash

# ============================================================================
# Dev Environment Update Script
# ============================================================================
# Run on each machine to bring it back in line with the repo.
#
# Usage: ./update-tools.sh [OPTIONS]
#
# Options:
#   --dry-run    Report what would change without changing anything
#   --no-pull    Skip the git pull (use the working tree as it stands)
#   --help       Show this message
#
# What this script does:
# 1. Pulls the repo, then re-executes itself so the new version runs
# 2. Updates Homebrew and its packages
# 3. Installs anything added to the manifests since last time
# 4. Updates VS Code extensions and settings
# 5. Updates mise tools, rustup and conda
# 6. Refreshes symlinks
#
# It never upgrades casks. Every tracked app self-updates, and forcing brew to
# upgrade them reinstalls an older pinned version over the top. See
# bootstrap/cask-apps.txt.
# ============================================================================

set -o pipefail
# No 'set -e': a single tool failing should not abandon the rest of the update.

# Script directory. Resolved before anything sources from it.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/bootstrap/lib/utils.sh"
source "$REPO_ROOT/bootstrap/lib/packages.sh"

# Flags
NO_PULL=false
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true; NO_PULL=true ;;
        --no-pull) NO_PULL=true ;;
        --help)
            echo "Usage: $0 [--dry-run] [--no-pull] [--help]"
            exit 0
            ;;
        *)
            error "Unknown option: $arg"
            echo "Usage: $0 [--dry-run] [--no-pull] [--help]"
            exit 1
            ;;
    esac
done

# Run a command, or say what it would have been.
run() {
    if [ "$DRY_RUN" = true ]; then
        info "[DRY RUN] $*"
        return 0
    fi
    "$@"
}

# ============================================================================
# Repository
# ============================================================================

update_repo() {
    info "Updating dev-env repository..."

    cd "$REPO_ROOT" || return 1

    if [ ! -d ".git" ]; then
        warning "Not a git repository, skipping pull"
        return 0
    fi

    if [ -n "$(git status --porcelain)" ]; then
        warning "Working tree has local changes, skipping pull"
        info "Commit or stash them, then re-run"
        return 0
    fi

    local before
    before=$(git rev-parse HEAD)

    if ! git pull --ff-only; then
        warning "Could not pull, continuing with the current checkout"
        return 0
    fi

    local after
    after=$(git rev-parse HEAD)

    if [ "$before" != "$after" ]; then
        success "Repository updated: ${before:0:7} → ${after:0:7}"
        # Bash reads a script as it runs, so carrying on after the file
        # changed underneath us runs a mix of both versions. Start again.
        info "Re-running the updated script..."
        export DEV_ENV_UPDATE_REEXEC=1
        exec "$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")" --no-pull
    fi

    success "Repository already up to date"
}

# ============================================================================
# Homebrew
# ============================================================================

update_homebrew() {
    info "Updating Homebrew..."

    if ! command_exists brew; then
        warning "Homebrew not installed"
        return 0
    fi

    run brew update

    # Formulas only. Casks are deliberately left to their own updaters.
    run brew upgrade --formula
    run brew cleanup
    success "Homebrew formulas updated"
}

update_brew_packages() {
    info "Checking for new Homebrew packages..."

    local manifest="$REPO_ROOT/bootstrap/brew-packages.txt"
    [ -f "$manifest" ] || { warning "brew-packages.txt not found"; return 0; }

    local added=0
    local package

    while IFS= read -r package; do
        # formula_installed matches exactly, so openjdk@17 is found and "git"
        # is not satisfied by "git-filter-repo".
        if ! formula_installed "$package"; then
            info "Installing new package: $package"
            if run brew install "$package"; then
                ((added++))
            else
                warning "Failed to install $package"
            fi
        fi
    done < <(read_manifest "$manifest")

    if [ "$added" -eq 0 ]; then
        success "Brew packages already in sync"
    else
        success "Installed $added new package(s)"
    fi
}

update_brew_casks() {
    info "Checking for new cask applications..."

    local manifest="$REPO_ROOT/bootstrap/cask-apps.txt"
    [ -f "$manifest" ] || return 0

    local added=0
    local cask

    while IFS= read -r cask; do
        if ! cask_installed "$cask"; then
            info "Installing new cask: $cask"
            # --adopt takes over an app already in /Applications rather than
            # overwriting it.
            if run brew install --cask --adopt "$cask"; then
                ((added++))
            else
                warning "Failed to install $cask"
            fi
        fi
    done < <(read_manifest "$manifest")

    if [ "$added" -eq 0 ]; then
        success "Cask applications already in sync"
    else
        success "Installed $added new cask(s)"
    fi

    info "Tracked apps update themselves; no cask upgrade is run here"
}

# ============================================================================
# VS Code
# ============================================================================

update_vscode_extensions() {
    info "Updating VS Code extensions..."

    if ! command_exists code; then
        warning "VS Code CLI not found"
        return 0
    fi

    run code --update-extensions || warning "Could not auto-update extensions"

    local manifest="$REPO_ROOT/editors/vscode/extensions.txt"
    [ -f "$manifest" ] || return 0

    # One listing, compared case-insensitively: marketplace ids are
    # case-insensitive but `code --list-extensions` preserves their casing.
    local installed
    installed=$(code --list-extensions | tr '[:upper:]' '[:lower:]')

    local extension
    while IFS= read -r extension; do
        if ! grep -qx "$(echo "$extension" | tr '[:upper:]' '[:lower:]')" <<< "$installed"; then
            info "Installing new extension: $extension"
            run code --install-extension "$extension" --force
        fi
    done < <(read_manifest "$manifest")

    success "VS Code extensions synced"
}

update_vscode_settings() {
    info "Updating VS Code settings..."

    local vscode_user_dir="$HOME/Library/Application Support/Code/User"

    if [ ! -d "$vscode_user_dir" ]; then
        warning "VS Code user directory not found"
        return 0
    fi

    local file
    for file in settings.json keybindings.json; do
        local src="$REPO_ROOT/editors/vscode/$file"
        local dest="$vscode_user_dir/$file"

        [ -f "$src" ] || continue

        if [ -f "$dest" ] && diff -q "$src" "$dest" >/dev/null 2>&1; then
            continue
        fi

        if [ -f "$dest" ]; then
            run cp "$dest" "$dest.backup-$(date +%Y%m%d_%H%M%S)"
            info "Backed up existing $file"
        fi

        run cp "$src" "$dest"
    done

    success "VS Code settings updated"
}

# ============================================================================
# Version managers
# ============================================================================

update_version_managers() {
    update_mise
    update_rust
    update_conda
}

update_mise() {
    if ! command_exists mise; then
        warning "mise is not installed"
        info "Run: brew install mise, or ./bootstrap/install.sh"
        return 0
    fi

    # Installed from mise's own installer, not brew, so it updates itself.
    run mise self-update --yes || warning "Could not self-update mise"

    info "Installing tools from mise config..."
    if run mise install; then
        success "mise tools synchronized"
        mise current 2>/dev/null | sed 's/^/  /'
    else
        warning "Some mise tools failed to install"
    fi
}

update_rust() {
    if ! command_exists rustup; then
        info "rustup not installed (optional)"
        return 0
    fi

    run rustup update && success "Rust is at $(rustc --version)"
}

update_conda() {
    if ! command_exists conda; then
        info "Conda not installed (optional)"
        return 0
    fi

    run conda update -n base -c defaults conda -y && success "Conda updated"
}

# ============================================================================
# Symlinks
# ============================================================================

refresh_symlinks() {
    info "Refreshing configuration symlinks..."

    local pair
    for pair in \
        "shell/zshrc:$HOME/.zshrc" \
        "git/gitconfig:$HOME/.gitconfig" \
        "git/gitignore_global:$HOME/.gitignore_global"; do

        local src="$REPO_ROOT/${pair%%:*}"
        local dest="${pair##*:}"

        [ -f "$src" ] || continue

        # A real file here is the user's own config, not ours to discard.
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            warning "$dest is a regular file, not a symlink - leaving it alone"
            info "Run ./bootstrap/install.sh to back it up and link it"
            continue
        fi

        run ln -sfn "$src" "$dest"
    done

    if [ -f "$REPO_ROOT/mise/config.toml" ]; then
        run mkdir -p "$HOME/.config/mise"
        run ln -sfn "$REPO_ROOT/mise/config.toml" "$HOME/.config/mise/config.toml"
    fi

    success "Symlinks refreshed"
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "================================================================"
    echo "  Dev Environment Update"
    echo "================================================================"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        warning "DRY RUN - nothing will be changed"
        echo ""
    fi

    if [ "$NO_PULL" = false ]; then
        update_repo
    elif [ -n "$DEV_ENV_UPDATE_REEXEC" ]; then
        info "Running the freshly pulled script"
    else
        info "Skipping git pull (--no-pull)"
    fi

    update_homebrew
    update_brew_packages
    update_brew_casks
    update_vscode_extensions
    update_vscode_settings
    update_version_managers
    refresh_symlinks

    echo ""
    success "Update complete"
    info "Check for drift at any time with: ./scripts/doctor.sh"
    info "Restart your terminal or run: source ~/.zshrc"
    echo ""
}

main
