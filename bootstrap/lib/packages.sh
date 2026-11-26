#!/usr/bin/env bash

# ============================================================================
# Manifest Parsing
# ============================================================================
# Single place that reads the package manifests, so install.sh and
# update-tools.sh can never disagree about what belongs on a machine.
#
# Functions:
# - read_manifest()        - Emit the entries of a manifest, honouring
#                            [CONDITIONAL: ...] markers
# - formula_installed()    - Exact-match check for a brew formula
# - cask_installed()       - Exact-match check for a brew cask
# - detect_mise_mode()     - Recover the installation mode from state
#
# Manifest format: one entry per line. Blank lines and comments are ignored.
# A comment of the form `# [CONDITIONAL: USE_MISE]` or
# `# [CONDITIONAL: !USE_MISE]` applies to the next entry only.
# ============================================================================

# Emit every entry of a manifest that applies to the current mode.
#
# Usage: read_manifest <path> [use_mise]
#   use_mise: "true" or "false". Defaults to $USE_MISE, then "false".
read_manifest() {
    local manifest="$1"
    local use_mise="${2:-${USE_MISE:-false}}"

    if [ ! -f "$manifest" ]; then
        return 1
    fi

    local condition=""
    local line

    while IFS= read -r line || [ -n "$line" ]; do
        # Strip trailing whitespace and carriage returns
        line="${line%%[[:space:]]}"
        line="${line%$'\r'}"

        if [[ "$line" =~ \[CONDITIONAL:[[:space:]]*(!?)USE_MISE\] ]]; then
            condition="${BASH_REMATCH[1]}USE_MISE"
            continue
        fi

        # Comments and blank lines do not clear a pending condition, so a
        # marker may sit above an explanatory comment.
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue

        case "$condition" in
            USE_MISE)  [ "$use_mise" = true ] && echo "$line" ;;
            '!USE_MISE') [ "$use_mise" = true ] || echo "$line" ;;
            *)         echo "$line" ;;
        esac

        condition=""
    done < "$manifest"
}

# Entries a manifest defines that this mode deliberately skips.
read_manifest_skipped() {
    local manifest="$1"
    local use_mise="${2:-${USE_MISE:-false}}"
    local inverse

    if [ "$use_mise" = true ]; then inverse=false; else inverse=true; fi

    comm -13 \
        <(read_manifest "$manifest" "$use_mise" | sort) \
        <(read_manifest "$manifest" "$inverse" | sort)
}

# ============================================================================
# Installed-state checks
# ============================================================================
# `brew list --formula <name>` matches exactly and handles versioned
# formulas such as openjdk@17. Never grep the output of a bare `brew list`:
# "git" matches "git-filter-repo".

formula_installed() {
    brew list --formula "$1" &>/dev/null
}

cask_installed() {
    brew list --cask "$1" &>/dev/null
}

# ============================================================================
# Mode detection
# ============================================================================
# Recover whether this machine was set up with --use-mise. Prefers the state
# file written by install.sh and falls back to looking for mise itself.

detect_mise_mode() {
    local state_file="${STATE_FILE:-$HOME/.dev-env/state.json}"

    if [ -f "$state_file" ]; then
        local mode
        mode=$(grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$state_file" |
            sed 's/.*"\([^"]*\)".*/\1/' | head -1)
        case "$mode" in
            mise) echo true; return 0 ;;
            standard) echo false; return 0 ;;
        esac
    fi

    # No usable state: mise being active is the best available signal.
    if command -v mise &>/dev/null && [ -e "$HOME/.config/mise/config.toml" ]; then
        echo true
    else
        echo false
    fi
}
