#!/usr/bin/env bash

# ============================================================================
# Dev Environment Quality Gate
# ============================================================================
# Checks the repository itself: shell syntax, shellcheck, manifest parsing,
# and that no secret or identity has crept into a tracked file. It touches
# nothing on the machine, so it is safe to run anywhere, and it is what the
# CI workflow and the pre-commit hook both run.
#
# This is about the repo. `./scripts/doctor.sh` is about the machine.
#
# Usage: ./check.sh [OPTIONS]
#
# Options:
#   --fast    Skip the installer dry runs, which are the slow part
#   --help    Show this message
#
# Exit codes:
#   0  everything passed
#   1  a check failed
# ============================================================================

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT" || exit 1

FAST=false
for arg in "$@"; do
    case $arg in
        --fast) FAST=true ;;
        --help)
            echo "Usage: $0 [--fast] [--help]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg" >&2
            exit 1
            ;;
    esac
done

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

FAILED=0

pass() { echo -e "   ${GREEN}✓${NC} $1"; }
fail() { echo -e "   ${RED}✗${NC} $1"; FAILED=$((FAILED + 1)); }
skip() { echo -e "   ${YELLOW}−${NC} $1"; }
step() { echo ""; echo "── $1"; }

# Every bash script in the repo. Kept in one place so each check covers the
# same set.
BASH_SCRIPTS=(
    bootstrap/install.sh
    bootstrap/uninstall.sh
    bootstrap/lib/packages.sh
    bootstrap/lib/sections.sh
    bootstrap/lib/state.sh
    bootstrap/lib/uninstall-handlers.sh
    bootstrap/lib/utils.sh
    bootstrap/hooks/pre-commit
    scripts/check.sh
    scripts/doctor.sh
    scripts/notify-drift.sh
    scripts/update-tools.sh
)

# Sourced by zsh, not bash, so they are parsed with zsh instead.
ZSH_FILES=(
    shell/zshrc
    shell/zshrc.local.example
    shell/zsh_aliases.sh
    shell/zsh_functions.sh
)

# ============================================================================
# 1. Every script listed still exists
# ============================================================================

check_inventory() {
    step "Script inventory"

    local missing=0
    local f
    for f in "${BASH_SCRIPTS[@]}" "${ZSH_FILES[@]}"; do
        if [ ! -f "$f" ]; then
            fail "listed in check.sh but missing: $f"
            missing=$((missing + 1))
        fi
    done

    # A script added to the repo but not to the lists above would go
    # unchecked, which is the failure mode this guards against.
    local found
    while IFS= read -r found; do
        local known=false
        for f in "${BASH_SCRIPTS[@]}" "${ZSH_FILES[@]}"; do
            [ "$f" = "$found" ] && known=true && break
        done
        if [ "$known" = false ]; then
            fail "not covered by check.sh: $found"
            missing=$((missing + 1))
        fi
    done < <(git ls-files '*.sh' 'shell/zshrc' 'bootstrap/hooks/*' 2>/dev/null)

    [ "$missing" -eq 0 ] && pass "all ${#BASH_SCRIPTS[@]} bash and ${#ZSH_FILES[@]} zsh files accounted for"
}

# ============================================================================
# 2. Syntax
# ============================================================================

check_syntax() {
    step "Syntax"

    local bad=0
    local f
    for f in "${BASH_SCRIPTS[@]}"; do
        [ -f "$f" ] || continue
        if ! bash -n "$f" 2>/dev/null; then
            fail "bash -n failed: $f"
            bash -n "$f" 2>&1 | sed 's/^/       /'
            bad=$((bad + 1))
        fi
    done
    [ "$bad" -eq 0 ] && pass "bash scripts parse"

    if ! command -v zsh >/dev/null 2>&1; then
        skip "zsh not available, shell config not parsed"
        return
    fi

    bad=0
    for f in "${ZSH_FILES[@]}"; do
        [ -f "$f" ] || continue
        if ! zsh -n "$f" 2>/dev/null; then
            fail "zsh -n failed: $f"
            zsh -n "$f" 2>&1 | sed 's/^/       /'
            bad=$((bad + 1))
        fi
    done
    [ "$bad" -eq 0 ] && pass "zsh config parses"
}

# ============================================================================
# 3. shellcheck
# ============================================================================

check_shellcheck() {
    step "shellcheck"

    if ! command -v shellcheck >/dev/null 2>&1; then
        fail "shellcheck is not installed"
        echo "       brew install shellcheck"
        return
    fi

    # -x follows sourced files, which is what makes the lib/ helpers visible
    # and clears the SC1091 noise.
    #
    # The bar is --severity=warning. Info-level notes are left alone on
    # purpose: they are style preferences (sed over parameter expansion, ls
    # over find, deliberate single quotes) and holding the gate to them would
    # mean churn without a bug fixed.
    if shellcheck -x --severity=warning "${BASH_SCRIPTS[@]}"; then
        pass "clean at warning level ($(shellcheck --version | awk '/version:/ {print $2}'))"
    else
        fail "shellcheck reported problems"
    fi
}

# ============================================================================
# 4. Manifests parse, and say something
# ============================================================================

check_manifests() {
    step "Manifests"

    # shellcheck source=bootstrap/lib/packages.sh
    source "$REPO_ROOT/bootstrap/lib/packages.sh"

    local manifest
    for manifest in bootstrap/brew-packages.txt bootstrap/cask-apps.txt editors/vscode/extensions.txt; do
        if [ ! -f "$manifest" ]; then
            fail "missing: $manifest"
            continue
        fi

        local count
        count=$(read_manifest "$manifest" | wc -l | tr -d ' ')

        if [ "$count" -eq 0 ]; then
            fail "$manifest parses to nothing"
        else
            pass "$manifest: $count entries"
        fi
    done

    # mise is how Node and Bun arrive, and nothing else should be competing
    # to provide them.
    #
    # Captured first rather than piped into `grep -q`: with `set -o pipefail`,
    # grep -q closes the pipe as soon as it matches, read_manifest dies of
    # SIGPIPE, and the pipeline reports failure on success.
    local formulas
    formulas=$(read_manifest bootstrap/brew-packages.txt)

    # mise is deliberately NOT a tracked formula: no bottle exists for this
    # platform, so install.sh uses mise's own installer. Catch a well-meaning
    # re-add, which would start an hours-long source build.
    if grep -qx "mise" <<< "$formulas"; then
        fail "mise is in brew-packages.txt; brew has no bottle for it here and would build from source"
    else
        pass "mise is not tracked as a formula"
    fi

    if grep -q "mise.run" bootstrap/install.sh; then
        pass "install.sh installs mise from its own installer"
    else
        fail "install.sh has no way to install mise"
    fi

    local superseded
    superseded=$(grep -xE "nvm|pyenv" <<< "$formulas" || true)
    if [ -n "$superseded" ]; then
        fail "superseded version manager(s) still tracked: $(echo "$superseded" | tr '\n' ' ')"
    else
        pass "no superseded version managers tracked"
    fi

    if grep -qE '^node = ' mise/config.toml; then
        pass "mise/config.toml pins node"
    else
        fail "mise/config.toml does not pin node"
    fi

    # An entry with whitespace or an inline comment would be passed to brew
    # verbatim and fail there instead of here.
    local entry
    while IFS= read -r entry; do
        case "$entry" in
            *[[:space:]]*|*"#"*)
                fail "malformed manifest entry: '$entry'"
                ;;
        esac
    done < <(
        read_manifest bootstrap/brew-packages.txt
        read_manifest bootstrap/cask-apps.txt
        read_manifest editors/vscode/extensions.txt
    )
}

# ============================================================================
# 4b. Machine-readable files parse
# ============================================================================

check_data_files() {
    step "Data files"

    local template="bootstrap/launchd/com.dev-env.drift.plist.template"
    if [ -f "$template" ]; then
        # A template, so the placeholders are substituted before parsing.
        if python3 -I -c "
import plistlib, sys, pathlib
raw = pathlib.Path('$template').read_bytes()
raw = raw.replace(b'__REPO_ROOT__', b'/repo').replace(b'__HOME__', b'/home')
d = plistlib.loads(raw)
assert d['Label'] == 'com.dev-env.drift', 'unexpected label'
assert d['ProgramArguments'][0].endswith('scripts/notify-drift.sh'), 'unexpected program'
" 2>/dev/null; then
            pass "launchd template parses, with the expected label and program"
        else
            fail "launchd template is not a valid plist"
        fi

        # Every placeholder must be substituted, or launchd gets a literal
        # path and the agent silently never runs.
        local unfilled
        unfilled=$(grep -oE '__[A-Z_]+__' "$template" | sort -u | tr '\n' ' ')
        if [ "$unfilled" = "__HOME__ __REPO_ROOT__ " ]; then
            pass "template placeholders are the two install.sh substitutes"
        else
            fail "unexpected placeholders in the template: $unfilled"
        fi
    fi

    if [ -f renovate.json ]; then
        if python3 -I -c "import json; json.load(open('renovate.json'))" 2>/dev/null; then
            pass "renovate.json is valid JSON"
        else
            fail "renovate.json is not valid JSON"
        fi
    fi

    # Two bots on the same ecosystem means duplicate pull requests.
    if [ -f renovate.json ] && [ -f .github/dependabot.yml ]; then
        if grep -q "github-actions" .github/dependabot.yml 2>/dev/null; then
            fail "Renovate and Dependabot both cover github-actions"
        fi
    fi
}

# ============================================================================
# 5. Nothing private in a tracked file
# ============================================================================

check_no_secrets() {
    step "Tracked files carry no identity or secrets"

    # ~/.gitconfig is a symlink to git/gitconfig and git writes through a
    # symlink, so `git config --global user.email ...` lands here. Identity
    # belongs in the untracked ~/.gitconfig.local.
    if grep -qE '^[[:space:]]*(name|email)[[:space:]]*=' git/gitconfig 2>/dev/null; then
        fail "git/gitconfig sets an identity; move it to ~/.gitconfig.local"
    else
        pass "git/gitconfig sets no identity"
    fi

    # Obvious key material in anything tracked.
    local hits
    hits=$(git grep -lE '(BEGIN [A-Z ]*PRIVATE KEY|ghp_[A-Za-z0-9]{36}|sk-[A-Za-z0-9]{32})' \
        -- . ':(exclude)scripts/check.sh' 2>/dev/null)

    if [ -n "$hits" ]; then
        fail "possible credentials in tracked files:"
        echo "$hits" | sed 's/^/       /'
    else
        pass "no key material found"
    fi

    # A file the global gitignore hides is a file that silently will not ship.
    local hidden
    hidden=$(git ls-files --others --ignored --exclude-standard \
        -- bootstrap scripts shell git editors mise '*.md' 2>/dev/null)

    if [ -n "$hidden" ]; then
        fail "repo source files are ignored by git:"
        echo "$hidden" | sed 's/^/       /'
    else
        pass "no repo source hidden by a gitignore"
    fi
}

# ============================================================================
# 6. The scripts run
# ============================================================================

check_dry_runs() {
    step "Installer dry runs"

    if [ "$FAST" = true ]; then
        skip "skipped (--fast)"
        return
    fi

    if ! command -v brew >/dev/null 2>&1; then
        skip "Homebrew not available, dry runs skipped"
        return
    fi

    local before after
    before=$(git status --porcelain)

    if ./bootstrap/install.sh --dry-run >/dev/null 2>&1; then
        pass "install.sh --dry-run succeeded"
    else
        fail "install.sh --dry-run failed"
    fi

    if ./scripts/update-tools.sh --dry-run >/dev/null 2>&1; then
        pass "update-tools.sh --dry-run succeeded"
    else
        fail "update-tools.sh --dry-run failed"
    fi

    # A dry run that edits the checkout is the bug this catches: install.sh
    # used to sed a tracked file and append to ~/.zshrc through its symlink.
    after=$(git status --porcelain)
    if [ "$before" = "$after" ]; then
        pass "dry runs left the checkout untouched"
    else
        fail "a dry run modified the checkout:"
        diff <(echo "$before") <(echo "$after") | sed 's/^/       /'
    fi
}

# ============================================================================
# Main
# ============================================================================

main() {
    echo ""
    echo "================================================================"
    echo "  Dev Environment Checks"
    echo "================================================================"

    check_inventory
    check_syntax
    check_shellcheck
    check_manifests
    check_data_files
    check_no_secrets
    check_dry_runs

    echo ""
    echo "================================================================"

    if [ "$FAILED" -eq 0 ]; then
        echo -e "${GREEN}All checks passed${NC}"
        echo ""
        exit 0
    fi

    echo -e "${RED}$FAILED check(s) failed${NC}"
    echo ""
    exit 1
}

main
