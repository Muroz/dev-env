#!/bin/zsh
# Custom shell aliases

# ============================================================================
# Navigation
# ============================================================================
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias ~="cd ~"

# ============================================================================
# Git Shortcuts
# ============================================================================
alias gs="git status"
alias ga="git add"
alias gc="git commit"
alias gp="git push"
alias gl="git pull"
alias gd="git diff"
alias gco="git checkout"
alias gb="git branch"
alias glog="git log --oneline --graph --decorate"

# ============================================================================
# Development
# ============================================================================
alias nr="npm run"
alias nrd="npm run dev"
alias nrb="npm run build"
alias nrt="npm run test"
alias ni="npm install"

# Python
alias py="python3"
alias pip="pip3"

# ============================================================================
# System
# ============================================================================
alias ll="ls -lah"
alias la="ls -A"
alias l="ls -CF"

# Show/hide hidden files in Finder
alias showfiles="defaults write com.apple.finder AppleShowAllFiles YES; killall Finder"
alias hidefiles="defaults write com.apple.finder AppleShowAllFiles NO; killall Finder"

# IP addresses
alias ip="curl -s https://api.ipify.org; echo"
alias localip="ipconfig getifaddr en0"

# ============================================================================
# Docker (if used)
# ============================================================================
alias d="docker"
alias dc="docker-compose"
alias dps="docker ps"
alias dimg="docker images"

# ============================================================================
# Dev Environment Management
# ============================================================================
alias reload="source ~/.zshrc"
alias edit-zsh="code ~/.zshrc"
alias update-dotfiles="cd ~/dev-env && git pull && reload"
