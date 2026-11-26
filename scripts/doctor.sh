#!/usr/bin/env bash

# ============================================================================
# Dev Environment Doctor
# ============================================================================
# Compares this machine against the repo and reports every difference. Reads
# only: it changes nothing, and prints the command that would fix each finding.
#
# Run it on both laptops. Matching output means matching environments.
#
# Usage: ./doctor.sh [OPTIONS]
#
# Options:
#   --quiet      Only report problems, not the checks that passed
#   --help       Show this message
#
# Exit codes:
#   0  no drift
#   1  drift found
#   2  the check could not run
# ============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

source "$REPO_ROOT/bootstrap/lib/utils.sh"
source "$REPO_ROOT/bootstrap/lib/packages.sh"

QUIET=false
for arg in "$@"; do
    case $arg in
        --quiet) QUIET=true ;;
        --help)
            echo "Usage: $0 [--quiet] [--help]"
            exit 0
            ;;
        *)
            error "Unknown option: $arg"
            exit 2
            ;;
    esac
done

USE_MISE=$(detect_mise_mode)

DRIFT_COUNT=0
FIXES=()

# ============================================================================
# Reporting helpers
# ============================================================================

section() {
    echo ""
    echo "── $1"
}

ok() {
    [ "$QUIET" = true ] && return 0
    echo -e "   ${GREEN}✓${NC} $1"
}

drift() {
    echo -e "   ${YELLOW}✗${NC} $1"
    ((DRIFT_COUNT++))
}

# Worth seeing, but not a problem: does not affect the exit status.
note() {
    [ "$QUIET" = true ] && return 0
    echo -e "   ${BLUE}·${NC} $1"
}

fix() {
    FIXES+=("$1")
}

# ============================================================================
# 1. Configuration symlinks
# ============================================================================

check_symlinks() {
    section "Configuration symlinks"

    local pair
    for pair in \
        "shell/zshrc:$HOME/.zshrc" \
        "git/gitconfig:$HOME/.gitconfig" \
        "git/gitignore_global:$HOME/.gitignore_global"; do

        local rel="${pair%%:*}"
        local dest="${pair##*:}"
        local src="$REPO_ROOT/$rel"
        local name="${dest#"$HOME"/}"

        if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then
            drift "$name is missing"
            fix "./bootstrap/install.sh    # creates $name"
        elif [ -L "$dest" ]; then
            local target
            target=$(cd "$(dirname "$dest")" && cd "$(dirname "$(readlink "$dest")")" 2>/dev/null && pwd)/$(basename "$(readlink "$dest")")
            if [ "$target" = "$src" ]; then
                ok "$name → $rel"
            else
                drift "$name points at $target, not $rel"
                fix "ln -sfn $src $dest"
            fi
        else
            drift "$name is a regular file, so the repo's version is not in use"
            fix "./bootstrap/install.sh    # backs up $name, then links it"
        fi
    done

    if [ "$USE_MISE" = true ]; then
        local mise_cfg="$HOME/.config/mise/config.toml"
        if [ -L "$mise_cfg" ]; then
            ok ".config/mise/config.toml → mise/config.toml"
        else
            drift ".config/mise/config.toml is not linked to the repo"
            fix "ln -sfn $REPO_ROOT/mise/config.toml $mise_cfg"
        fi
    fi
}

# ============================================================================
# 2. Homebrew formulas
# ============================================================================

check_formulas() {
    section "Homebrew formulas"

    if ! command_exists brew; then
        drift "Homebrew is not installed"
        fix "./bootstrap/install.sh"
        return
    fi

    local manifest="$REPO_ROOT/bootstrap/brew-packages.txt"
    local missing=()
    local package

    while IFS= read -r package; do
        formula_installed "$package" || missing+=("$package")
    done < <(read_manifest "$manifest" "$USE_MISE")

    if [ ${#missing[@]} -eq 0 ]; then
        ok "all tracked formulas installed"
    else
        drift "not installed: ${missing[*]}"
        fix "./scripts/update-tools.sh    # installs ${#missing[@]} missing formula(s)"
    fi

    # Explicitly installed formulas the repo does not know about. `brew leaves`
    # lists only what was asked for, so dependencies do not show up as drift.
    local untracked
    untracked=$(comm -23 \
        <(brew leaves | sort) \
        <(read_manifest "$manifest" "$USE_MISE" | sort))

    if [ -z "$untracked" ]; then
        ok "no untracked formulas"
    else
        local count
        count=$(echo "$untracked" | wc -l | tr -d ' ')
        drift "installed but not in the repo ($count): $(echo "$untracked" | tr '\n' ' ')"
        fix "Add to bootstrap/brew-packages.txt, or 'brew uninstall' what you do not want:"
        fix "$(echo "$untracked" | sed 's/^/    /')"
    fi
}

# ============================================================================
# 3. Cask applications
# ============================================================================

# What a cask puts on disk, so a hand-installed copy can be told apart from a
# missing one. Prints one line per app bundle, then "PKG" if the cask installs
# a pkg rather than an app: --adopt cannot take over a pkg install.
cask_artifacts() {
    brew info --cask --json=v2 "$1" 2>/dev/null | python3 -I -c '
import json, os, sys
try:
    cask = json.load(sys.stdin)["casks"][0]
except Exception:
    sys.exit(0)

apps, is_pkg = [], False
for artifact in cask.get("artifacts", []):
    for app in artifact.get("app", []) or []:
        if isinstance(app, str):
            apps.append(app)
    if artifact.get("pkg"):
        is_pkg = True
    # A pkg cask names the app it drops in its uninstall stanza.
    for stanza in artifact.get("uninstall", []) or []:
        if not isinstance(stanza, dict):
            continue
        for path in stanza.get("delete", []) or []:
            if isinstance(path, str) and path.endswith(".app"):
                apps.append(os.path.basename(path))

for app in dict.fromkeys(apps):
    print(app)
if is_pkg:
    print("PKG")
'
}

check_casks() {
    section "Cask applications"

    command_exists brew || return

    local manifest="$REPO_ROOT/bootstrap/cask-apps.txt"
    local missing=()
    local adoptable=()
    local pkg_conflict=()
    local cask

    while IFS= read -r cask; do
        cask_installed "$cask" && continue

        # Not brew-managed. Is the app nonetheless already on disk?
        local found=false
        local is_pkg=false
        local app
        while IFS= read -r app; do
            [ -n "$app" ] || continue
            if [ "$app" = "PKG" ]; then
                is_pkg=true
                continue
            fi
            if [ -d "/Applications/$app" ] || [ -d "$HOME/Applications/$app" ]; then
                found=true
            fi
        done < <(cask_artifacts "$cask")

        if [ "$found" = true ] && [ "$is_pkg" = true ]; then
            pkg_conflict+=("$cask")
        elif [ "$found" = true ]; then
            adoptable+=("$cask")
        else
            missing+=("$cask")
        fi
    done < <(read_manifest "$manifest" "$USE_MISE")

    # An app that is present is not a parity problem, whoever installed it.
    # Only a missing app makes the two machines differ, so that is the only
    # case counted as drift.
    if [ ${#missing[@]} -eq 0 ]; then
        ok "every tracked app is installed"
    else
        drift "not installed (${#missing[@]}): ${missing[*]}"
        fix "./scripts/update-tools.sh    # installs ${#missing[@]} missing app(s)"
    fi

    local unmanaged=("${adoptable[@]}" "${pkg_conflict[@]}")

    if [ ${#unmanaged[@]} -gt 0 ]; then
        note "present but not brew-managed (${#unmanaged[@]}): ${unmanaged[*]}"
        note "  brew can take over an app only while the installed version"
        note "  matches the cask exactly, and these update themselves, so that"
        note "  window is narrow. Nothing is wrong; brew would just reinstall."
    fi

    local untracked
    untracked=$(brew list --cask 2>/dev/null | comm -23 - <(read_manifest "$manifest" "$USE_MISE" | sort))

    if [ -n "$untracked" ]; then
        note "brew-managed but not tracked: $(echo "$untracked" | tr '\n' ' ')"
    fi
}

# ============================================================================
# 4. VS Code
# ============================================================================

check_vscode() {
    section "VS Code"

    if ! command_exists code; then
        drift "the 'code' CLI is not on PATH"
        fix "In VS Code: Shell Command: Install 'code' command in PATH"
        return
    fi

    local manifest="$REPO_ROOT/editors/vscode/extensions.txt"
    local installed tracked
    installed=$(code --list-extensions | tr '[:upper:]' '[:lower:]' | sort)
    tracked=$(read_manifest "$manifest" "$USE_MISE" | tr '[:upper:]' '[:lower:]' | sort)

    local missing extra
    missing=$(comm -13 <(echo "$installed") <(echo "$tracked"))
    extra=$(comm -23 <(echo "$installed") <(echo "$tracked"))

    if [ -z "$missing" ]; then
        ok "all tracked extensions installed"
    else
        drift "not installed: $(echo "$missing" | tr '\n' ' ')"
        fix "./scripts/update-tools.sh    # installs missing extensions"
    fi

    if [ -z "$extra" ]; then
        ok "no untracked extensions"
    else
        drift "installed but not in the repo: $(echo "$extra" | tr '\n' ' ')"
        fix "Add to editors/vscode/extensions.txt:"
        fix "$(echo "$extra" | sed 's/^/    /')"
    fi

    local user_dir="$HOME/Library/Application Support/Code/User"
    local file
    for file in settings.json keybindings.json; do
        local src="$REPO_ROOT/editors/vscode/$file"
        local dest="$user_dir/$file"

        [ -f "$src" ] || continue

        if [ ! -f "$dest" ]; then
            drift "$file is not installed"
            fix "cp $src '$dest'"
        elif diff -q "$src" "$dest" >/dev/null 2>&1; then
            ok "$file matches the repo"
        else
            drift "$file differs from the repo"
            fix "diff '$dest' $src    # then copy whichever is right"
        fi
    done
}

# ============================================================================
# 5. Tool versions
# ============================================================================

check_versions() {
    section "Tool versions"

    local tool
    for tool in node npm python3 bun rustc git gh docker; do
        if command_exists "$tool"; then
            local version
            version=$("$tool" --version 2>&1 | head -1)
            ok "$tool: $version"
        else
            # Only Node and Python are promised by either mode.
            case "$tool" in
                node|python3) drift "$tool is not installed" ;;
                *) ok "$tool: not installed (optional)" ;;
            esac
        fi
    done

    if [ "$USE_MISE" = true ]; then
        if command_exists mise; then
            local outdated
            outdated=$(mise outdated 2>/dev/null | tail -n +2)
            if [ -z "$outdated" ]; then
                ok "mise tools match mise/config.toml"
            else
                drift "mise tools behind the config:"
                echo "$outdated" | sed 's/^/       /'
                fix "mise install"
            fi
        else
            drift "mise mode recorded but mise is not installed"
            fix "brew install mise"
        fi
    fi
}

# ============================================================================
# 6. Git identity
# ============================================================================

check_git_identity() {
    section "Git identity"

    # `git config --get` follows the [include] in git/gitconfig; the --global
    # form does not.
    local name email
    name=$(git config --get user.name 2>/dev/null)
    email=$(git config --get user.email 2>/dev/null)

    if [ -n "$name" ] && [ -n "$email" ]; then
        ok "$name <$email>"
    else
        drift "user.name or user.email is not set"
        fix "cp $REPO_ROOT/git/gitconfig.local.example ~/.gitconfig.local"
        fix "\$EDITOR ~/.gitconfig.local"
    fi

    # Identity written into the tracked file would be committed.
    if grep -qE '^[[:space:]]*(name|email)[[:space:]]*=' "$REPO_ROOT/git/gitconfig" 2>/dev/null; then
        drift "an identity is set in the tracked git/gitconfig"
        fix "Move it to ~/.gitconfig.local before committing"
    else
        ok "no identity in the tracked gitconfig"
    fi

    # shellcheck disable=SC2088  # literal ~ is intended: this is text shown
    # to the user, and a command for them to paste into a shell.
    if [ -f "$HOME/.gitconfig.local" ]; then
        ok "~/.gitconfig.local present"
    elif [ -L "$HOME/.gitconfig" ]; then
        drift "~/.gitconfig.local is missing, so git has nowhere local to write"
        fix "cp $REPO_ROOT/git/gitconfig.local.example ~/.gitconfig.local"
    fi
}

# ============================================================================
# 7. Repo and state
# ============================================================================

check_repo_state() {
    section "Repository and state"

    cd "$REPO_ROOT" || return

    if [ -n "$(git status --porcelain)" ]; then
        drift "the dev-env checkout has uncommitted changes"
        fix "cd $REPO_ROOT && git status"
    else
        ok "checkout is clean"
    fi

    git fetch --quiet 2>/dev/null
    local behind
    behind=$(git rev-list --count 'HEAD..@{upstream}' 2>/dev/null || echo 0)
    if [ "$behind" -gt 0 ] 2>/dev/null; then
        drift "$behind commit(s) behind the remote"
        fix "./scripts/update-tools.sh"
    else
        ok "up to date with the remote"
    fi

    # The global gitignore applies to every repo, this one included. A bare
    # directory name in it can hide real source with no error and nothing in
    # `git status`, which is how bootstrap/lib/packages.sh once went missing.
    # Scoped to the directories that hold this repo's own source, so a local
    # settings file that is meant to be ignored is not reported.
    local hidden
    hidden=$(git ls-files --others --ignored --exclude-standard \
        -- bootstrap scripts shell git editors mise '*.md' 2>/dev/null)

    if [ -z "$hidden" ]; then
        ok "no repo source files hidden by a gitignore"
    else
        drift "source files in this repo are ignored by git:"
        echo "$hidden" | sed 's/^/       /'
        fix "git check-ignore -v <path>    # shows which pattern hides it"
    fi

    local state_file="$HOME/.dev-env/state.json"
    if [ -f "$state_file" ]; then
        ok "install state recorded (mode: $([ "$USE_MISE" = true ] && echo mise || echo standard))"
    else
        drift "no install state at ~/.dev-env/state.json, so the mode is a guess"
        fix "./bootstrap/install.sh    # records what it installs"
    fi

    # shellcheck disable=SC2088  # literal ~ is intended in the message
    if [ -f "$HOME/.zshrc.local" ]; then
        ok "~/.zshrc.local present for machine-specific settings"
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "================================================================"
    echo "  Dev Environment Doctor"
    echo "================================================================"
    echo "  repo: $REPO_ROOT"
    echo "  mode: $([ "$USE_MISE" = true ] && echo mise || echo standard)"

    check_symlinks
    check_formulas
    check_casks
    check_vscode
    check_versions
    check_git_identity
    check_repo_state

    echo ""
    echo "================================================================"

    if [ "$DRIFT_COUNT" -eq 0 ]; then
        success "No drift: this machine matches the repo"
        echo ""
        exit 0
    fi

    warning "$DRIFT_COUNT difference(s) between this machine and the repo"

    if [ ${#FIXES[@]} -gt 0 ]; then
        echo ""
        echo "Suggested fixes:"
        local f
        for f in "${FIXES[@]}"; do
            echo "  $f"
        done
    fi

    echo ""
    exit 1
}

main
