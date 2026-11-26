#!/bin/zsh
# Custom shell functions

# ============================================================================
# Clear clashing aliases
# ============================================================================
# zsh expands an alias when it reads `name()`, so an alias of the same name
# makes the function definition a parse error, and that error stops the rest
# of this file loading. Oh My Zsh plugins load before this file and define
# plenty of short aliases, so clear any that match a function defined below.
#
# The one that actually collides today is gcm: the git plugin defines it as
# `git checkout <main branch>`, and the gcm() below is a conventional-commit
# helper. The function wins. Oh My Zsh's own `gcmsg` is still `git commit -m`,
# and `gco` is still checkout.
for _fn in mkcd groot serve killport gcm gacp venv sysinfo; do
    unalias "$_fn" 2>/dev/null
done
unset _fn

# ============================================================================
# Directory Management
# ============================================================================

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Go to project root (finds nearest git root)
groot() {
    cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
}

# ============================================================================
# Development Helpers
# ============================================================================

# Quick server for current directory
serve() {
    local port="${1:-8000}"
    python3 -m http.server "$port"
}

# Find and kill process on port
killport() {
    if [ -z "$1" ]; then
        echo "Usage: killport <port>"
        return 1
    fi
    lsof -ti:"$1" | xargs kill -9
}

# ============================================================================
# Git Helpers
# ============================================================================

# Git commit with conventional commit format
gcm() {
    if [ -z "$1" ] || [ -z "$2" ]; then
        echo "Usage: gcm <type> <message>"
        echo "Types: feat, fix, docs, style, refactor, test, chore"
        return 1
    fi
    git commit -m "$1: $2"
}

# Quick git add, commit, push
gacp() {
    if [ -z "$1" ]; then
        echo "Usage: gacp <commit message>"
        return 1
    fi
    git add . && git commit -m "$1" && git push
}

# ============================================================================
# Node/NPM Helpers
# ============================================================================

# Clean install (remove node_modules and reinstall)
clean-install() {
    echo "Removing node_modules and package-lock.json..."
    rm -rf node_modules package-lock.json
    echo "Running npm install..."
    npm install
}

# Update all npm global packages
npm-update-global() {
    npm update -g
}

# ============================================================================
# Python Helpers
# ============================================================================

# Create and activate virtual environment
venv-create() {
    python3 -m venv .venv
    source .venv/bin/activate
    pip install --upgrade pip
}

# Activate virtual environment
venv() {
    if [ -d ".venv" ]; then
        source .venv/bin/activate
    elif [ -d "venv" ]; then
        source venv/bin/activate
    else
        echo "No virtual environment found"
        return 1
    fi
}

# ============================================================================
# System Information
# ============================================================================

# Show system info summary
sysinfo() {
    echo "=== System Information ==="
    echo "OS: $(sw_vers -productName) $(sw_vers -productVersion)"
    echo "Hostname: $(hostname)"
    echo "User: $(whoami)"
    echo ""
    echo "=== Development Tools ==="
    echo "Node: $(node --version 2>/dev/null || echo 'not installed')"
    echo "npm: $(npm --version 2>/dev/null || echo 'not installed')"
    echo "Python: $(python3 --version 2>/dev/null || echo 'not installed')"
    echo "Bun: $(bun --version 2>/dev/null || echo 'not installed')"
    echo "Git: $(git --version 2>/dev/null || echo 'not installed')"
}
