#!/usr/bin/env bash

# ============================================================================
# Manifest Parsing
# ============================================================================
# Single place that reads the package manifests, so install.sh,
# update-tools.sh, doctor.sh and check.sh can never disagree about what
# belongs on a machine.
#
# Functions:
# - read_manifest()     - Emit the entries of a manifest
# - formula_installed() - Exact-match check for a brew formula
# - cask_installed()    - Exact-match check for a brew cask
#
# Manifest format: one entry per line. Blank lines and comments are ignored.
# ============================================================================

# Emit every entry of a manifest.
#
# Usage: read_manifest <path>
read_manifest() {
    local manifest="$1"

    if [ ! -f "$manifest" ]; then
        return 1
    fi

    local line
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
        echo "$line"
    done < "$manifest"
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
# Cask artifacts
# ============================================================================

# What a cask puts on disk, so an app installed by hand can be told apart from
# a missing one. Prints one line per app bundle, then "PKG" if the cask
# installs a pkg rather than an app: --adopt cannot take over a pkg install.
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

# True when a cask's app is already in /Applications, whoever installed it.
cask_app_present() {
    local app
    while IFS= read -r app; do
        [ -n "$app" ] || continue
        [ "$app" = "PKG" ] && continue
        if [ -d "/Applications/$app" ] || [ -d "$HOME/Applications/$app" ]; then
            return 0
        fi
    done < <(cask_artifacts "$1")
    return 1
}
