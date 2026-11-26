#!/usr/bin/env bash

# ============================================================================
# Drift Notifier
# ============================================================================
# Runs the checks that only a real machine can answer, and raises a macOS
# notification when something needs attention. Meant to be run on a schedule
# by launchd, not by hand; ./bootstrap/launchd/ holds the agent.
#
# It reports three things:
#   - drift between this machine and the repo (./scripts/doctor.sh)
#   - Homebrew formulas with a newer version available
#   - mise tools behind the versions pinned in mise/config.toml
#
# It changes nothing. Everything it finds is for you to act on.
#
# Usage: ./notify-drift.sh [OPTIONS]
#
# Options:
#   --stdout     Print the report instead of notifying. For testing.
#   --help       Show this message
#
# Exit codes:
#   0  nothing to report
#   1  something to report
# ============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# launchd gives a job almost no PATH, so Homebrew's bin has to be added
# before anything looks for brew, mise or git.
for prefix in /opt/homebrew /usr/local; do
    if [ -x "$prefix/bin/brew" ]; then
        export PATH="$prefix/bin:$prefix/sbin:$PATH"
        break
    fi
done

TO_STDOUT=false
for arg in "$@"; do
    case $arg in
        --stdout) TO_STDOUT=true ;;
        --help)
            echo "Usage: $0 [--stdout] [--help]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

LOG_DIR="$HOME/.dev-env"
LOG_FILE="$LOG_DIR/drift.log"
mkdir -p "$LOG_DIR"

HEADLINES=()
REPORT=""

add_section() {
    REPORT+="
── $1
$2
"
}

# ============================================================================
# 1. Drift against the repo
# ============================================================================

check_drift() {
    local output
    output=$("$REPO_ROOT/scripts/doctor.sh" --quiet 2>&1)
    local status=$?

    if [ "$status" -eq 0 ]; then
        return 0
    fi

    # Strip the colour codes; a notification and a log file want plain text.
    output=$(echo "$output" | sed $'s/\033\\[[0-9;]*m//g')

    local count
    count=$(echo "$output" | grep -cE '^[[:space:]]+✗' || true)
    HEADLINES+=("$count drift finding(s)")
    add_section "doctor" "$output"
}

# ============================================================================
# 2. Homebrew
# ============================================================================

check_brew() {
    command -v brew >/dev/null 2>&1 || return 0

    # Formulas only. Casks are left to their own updaters, which is why
    # --greedy is never used here. See bootstrap/cask-apps.txt.
    local outdated
    outdated=$(brew outdated --formula --quiet 2>/dev/null)

    [ -n "$outdated" ] || return 0

    local count
    count=$(echo "$outdated" | wc -l | tr -d ' ')
    HEADLINES+=("$count formula update(s)")
    add_section "brew outdated" "$(echo "$outdated" | sed 's/^/  /')"
}

# ============================================================================
# 3. mise
# ============================================================================

check_mise() {
    command -v mise >/dev/null 2>&1 || return 0

    local outdated
    outdated=$(mise outdated 2>/dev/null | tail -n +2)

    [ -n "$outdated" ] || return 0

    local count
    count=$(echo "$outdated" | wc -l | tr -d ' ')
    HEADLINES+=("$count tool(s) behind the pins")
    add_section "mise outdated" "$(echo "$outdated" | sed 's/^/  /')"
}

# ============================================================================
# Notification
# ============================================================================

notify() {
    local title="$1"
    local message="$2"

    # osascript keeps this dependency-free. A launchd *agent* runs in the
    # user's GUI session, which is what lets the notification appear at all;
    # a daemon has no session to post into.
    osascript -e "display notification \"$message\" with title \"$title\"" 2>/dev/null
}

# ============================================================================
# Main
# ============================================================================

main() {
    check_drift
    check_brew
    check_mise

    local stamp
    stamp=$(date "+%Y-%m-%d %H:%M:%S")

    if [ ${#HEADLINES[@]} -eq 0 ]; then
        echo "[$stamp] nothing to report" >> "$LOG_FILE"
        [ "$TO_STDOUT" = true ] && echo "Nothing to report."
        exit 0
    fi

    # "2 drift finding(s), 3 formula update(s)"
    local summary
    summary=$(printf '%s, ' "${HEADLINES[@]}")
    summary="${summary%, }"

    {
        echo "[$stamp] $summary"
        echo "$REPORT"
    } >> "$LOG_FILE"

    if [ "$TO_STDOUT" = true ]; then
        echo "dev-env: $summary"
        echo "$REPORT"
        exit 1
    fi

    notify "dev-env" "$summary — see ~/.dev-env/drift.log"
    exit 1
}

main
