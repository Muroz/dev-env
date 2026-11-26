# Development Environment Configuration

A centralized configuration repository for consistent development environments across multiple macOS machines. This repository contains shell configurations, git settings, editor preferences, and automation scripts to quickly bootstrap and maintain development setups.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Checking for drift](#checking-for-drift)
- [Quality gates](#quality-gates)
- [Detailed Configuration](#detailed-configuration)
  - [Bootstrap](#bootstrap)
  - [Shell Configuration](#shell-configuration)
  - [Git Configuration](#git-configuration)
  - [VS Code Settings](#vs-code-settings)
  - [Version Management](#version-management)
  - [Cask applications](#cask-applications)
  - [Update Scripts](#update-scripts)
- [Usage Patterns](#usage-patterns)
- [Security](#security)
- [Troubleshooting](#troubleshooting)

---

## Overview

This repository provides:

- **Automated bootstrap**: One script to set up a fresh Mac with all tools and configurations
- **Modular shell config**: Organized zsh configuration with custom aliases and functions
- **Consistent git workflow**: Shared git configuration with modern best practices
- **Synchronized editor**: VS Code settings and extensions across all machines
- **Version management**: Pinned tool versions, with nvm/pyenv or mise
- **Update automation**: Scripts to keep all machines in sync
- **Drift detection**: `scripts/doctor.sh` reports every way a machine differs
  from this repo, and changes nothing itself

**Important**: This repository contains configuration only, no secrets. SSH keys, API tokens, and credentials are managed separately.

---

## Repository Structure

```
dev-env/
├── bootstrap/
│   ├── install.sh           # Main bootstrap script for fresh Mac setup
│   ├── uninstall.sh         # Selective or full removal
│   ├── brew-packages.txt    # Homebrew formulas to install
│   ├── cask-apps.txt        # Homebrew cask applications to install
│   ├── hooks/
│   │   └── pre-commit       # Runs check.sh before a commit
│   └── lib/
│       ├── utils.sh         # Output, prompts, JSON helpers
│       ├── state.sh         # Records what was installed
│       ├── sections.sh      # Section and group definitions
│       ├── packages.sh      # Manifest parsing, shared by install and update
│       └── uninstall-handlers.sh
├── shell/
│   ├── zshrc                # Main zsh configuration
│   ├── zshrc.local.example  # Template for per-machine settings
│   ├── zsh_aliases.sh       # Custom shell aliases
│   └── zsh_functions.sh     # Custom shell functions
├── git/
│   ├── gitconfig            # Global git configuration
│   └── gitignore_global     # Global gitignore patterns
├── editors/
│   └── vscode/
│       ├── settings.json    # VS Code user settings
│       ├── keybindings.json # VS Code keybindings
│       └── extensions.txt   # VS Code extensions list
├── mise/
│   └── config.toml          # Pinned tool versions for mise mode
├── scripts/
│   ├── update-tools.sh      # Sync this machine with the repo
│   ├── doctor.sh            # Report drift between machine and repo
│   └── check.sh             # Quality gate for the repo itself
├── .github/
│   └── workflows/
│       └── checks.yml       # Runs check.sh on push and pull request
├── .gitignore               # Prevent committing sensitive data
├── .env.example             # Environment variables template
└── README.md                # This file
```

---

## Quick Start

### First Time Setup (New Mac)

1. **Clone this repository**:
   ```bash
   git clone <repository-url> ~/dev-env
   cd ~/dev-env
   ```

2. **Choose your version management approach**:

   **Option A: Standard Mode (Traditional)**
   - Uses individual version managers: nvm, pyenv, bun
   - Best for users comfortable with existing workflows

   **Option B: Mise Mode (Unified)**
   - Uses mise for all language version management
   - Simpler, faster, single tool for Node.js, Python, and Bun
   - Recommended for new setups

3. **Preview what will be installed** (recommended):
   ```bash
   chmod +x bootstrap/install.sh

   # Preview standard installation
   ./bootstrap/install.sh --dry-run

   # Preview with mise
   ./bootstrap/install.sh --dry-run --use-mise
   ```

4. **Set environment variables** (for git configuration):
   ```bash
   export GIT_USER_NAME="Your Name"
   export GIT_USER_EMAIL="your.email@example.com"
   ```

5. **Run bootstrap script**:

   **Standard Mode:**
   ```bash
   ./bootstrap/install.sh
   ```

   **Mise Mode:**
   ```bash
   ./bootstrap/install.sh --use-mise
   ```

   The script will:
   - Check system dependencies
   - Install all required tools (conditional based on mode)
   - Create automatic backups of existing configs
   - Report progress and any errors
   - Display a detailed summary at completion showing:
     - ✓ Successfully installed sections
     - ○ Skipped sections (when using --use-mise or --dry-run)
     - ✗ Failed sections (if any errors occurred)
   - Provide next steps at completion

6. **Review local customizations** (optional):
   ```bash
   code ~/.zshrc.local
   ```

7. **Restart your terminal** or source the new configuration:
   ```bash
   source ~/.zshrc
   ```

**Note**: The script is idempotent - you can re-run it safely and it will skip already installed components.

### Updating Existing Setup

On machines that already have the configuration:

```bash
./scripts/update-tools.sh
```

This will:
- Pull the latest commits, then re-run itself so the new version is the one
  that does the work
- Update Homebrew formulas
- Install anything added to the manifests since last time
- Install new VS Code extensions and copy the settings over
- Update the version managers for the mode this machine was installed in
- Refresh the symlinks

Preview it first with `./scripts/update-tools.sh --dry-run`, which prints every
command it would run and changes nothing.

It never upgrades casks. See [Cask applications](#cask-applications).

---

## Checking for drift

Two laptops only stay interchangeable if you can see when they stop being so.

```bash
./scripts/doctor.sh
```

It compares this machine against the repo and reports every difference:
symlinks that are not in place, formulas and apps installed on one machine but
not tracked, extensions missing or extra, VS Code settings that differ, tool
versions, git identity and whether the checkout is behind the remote.

It reads only. Nothing is installed, changed or removed, and each finding comes
with the command that would fix it. Exit status is 0 when the machine matches
the repo and 1 when it does not, so it also works in a shell prompt or a
pre-flight check.

Run it on both laptops. Matching output is the whole point of this repo.

```bash
./scripts/doctor.sh --quiet
```

`--quiet` reports only the problems.

### Adopting apps installed by hand

An app downloaded from the vendor is present but not managed by Homebrew.
Doctor reports that as a note, not a problem, because the app is there and
that is what makes two machines equivalent. Who installed it does not matter.

If you want brew to manage it anyway, `--adopt` is the gentle option, and it
usually will not work:

```bash
brew install --cask --adopt ghostty obsidian
```

Three things get in the way:

- **It only adopts an identical app.** The flag's own wording is "artifacts in
  the destination that are identical to those being installed". Every app
  worth tracking updates itself, so it drifts from the cask version within
  days. Tried here on six apps, five had already moved on, Ghostty 1.3.1
  against the cask's 1.4.0 among them.
- **It needs your password.** Adoption runs `sudo chgrp -hR admin` on the
  bundle, so it never works unattended.
- **SIP blocks it on a root-owned bundle.** An app left by a pkg installer is
  owned by `root:wheel`, and that `chgrp` then fails with `Operation not
  permitted` even under sudo. Slack here is one.

The option that does work is letting brew reinstall the app:

```bash
brew install --cask slack
```

That replaces the bundle with the cask's version and registers it. Settings in
`~/Library` are untouched, and because the cask is `auto_updates true` brew
leaves it alone afterwards while the app updates itself. One deliberate
reinstall per app, and only if you want the bookkeeping.

---

## Uninstalling

The uninstall system allows you to remove all or specific components installed by the bootstrap script.

### Full Uninstall

Remove everything installed by the bootstrap script:

```bash
cd ~/dev-env
./bootstrap/uninstall.sh --all
```

The script will:
- Show what will be removed
- Request confirmation
- Uninstall selected components
- Preserve user data by default (Node versions, Python virtualenvs, etc.)
- Display a detailed summary showing:
  - ✓ Successfully uninstalled sections
  - ✗ Failed sections (if any errors occurred)
  - ○ Sections that would be affected (in dry-run mode)
- Provide option to restore backups

### Selective Uninstall

Remove specific components only:

```bash
# Remove version managers
./bootstrap/uninstall.sh --sections "nvm,pyenv,bun"

# Switch from nvm/pyenv to mise
./bootstrap/uninstall.sh --sections "nvm,pyenv,bun"
./bootstrap/install.sh --use-mise

# Remove VS Code extensions
./bootstrap/uninstall.sh --sections "vscode_extensions"
```

### Preview Changes (Dry-Run)

See what would be removed without making changes:

```bash
./bootstrap/uninstall.sh --all --dry-run
```

### Remove User Data

By default, user data is preserved (Node.js versions, Python virtualenvs, globally installed packages). To remove everything including data:

```bash
./bootstrap/uninstall.sh --all --remove-data
```

**Warning**: This will delete:
- All Node.js versions and npm packages (if using nvm)
- All Python versions and virtualenvs (if using pyenv)
- All mise-managed tools (if using mise)

### Check Installation Status

See what's currently installed:

```bash
./bootstrap/uninstall.sh --status

# Detailed view with package lists
./bootstrap/uninstall.sh --status --verbose
```

### Restore Backups

Original config files are backed up before being replaced. To restore them:

```bash
./bootstrap/uninstall.sh --restore-backups
```

### Available Sections

You can uninstall any of these sections individually:

**Individual Sections:**
- **homebrew** - Homebrew package manager (only removed if safe)
- **brew_packages** - Homebrew formula packages
- **brew_casks** - GUI applications (claude-code)
- **oh_my_zsh** - Oh-My-Zsh framework
- **nvm** - Node Version Manager (standard mode only)
- **pyenv** - Python version manager (standard mode only)
- **bun** - Bun JavaScript runtime (standard mode only)
- **mise** - Mise unified version manager (mise mode only)
- **rust** - Rust toolchain
- **symlinks** - Configuration symlinks (.zshrc, .gitconfig, .gitignore_global)
- **vscode_extensions** - VS Code extensions
- **git_config** - Git user configuration
- **shell_config** - Local shell configuration (~/.zshrc.local)

**Section Groups:**

You can also uninstall groups of related sections:

```bash
# Remove all version managers
./bootstrap/uninstall.sh --sections "version_managers"
# Includes: nvm, pyenv, bun, mise, rust

# Remove all configuration files
./bootstrap/uninstall.sh --sections "configs"
# Includes: symlinks, git_config, shell_config

# Remove VS Code setup
./bootstrap/uninstall.sh --sections "vscode"
# Includes: vscode_extensions

# Remove all Homebrew components
./bootstrap/uninstall.sh --sections "homebrew_all"
# Includes: homebrew, brew_packages, brew_casks

# Minimal setup (just configs)
./bootstrap/uninstall.sh --sections "minimal"
# Includes: symlinks, git_config, shell_config

# Everything
./bootstrap/uninstall.sh --sections "all"
# Same as --all flag
```

### Safety Features

The uninstall system includes multiple safety mechanisms:

1. **Data Preservation**: User data kept by default (use `--remove-data` to remove)
2. **Homebrew Protection**: Only removed if no other packages depend on it
3. **Confirmation Prompts**: Interactive confirmation before removing sections
4. **Dry-Run Mode**: Preview changes before applying them
5. **Backup Restoration**: Restore original config files from backups
6. **State Tracking**: Knows what was installed and in which mode

### Command-Line Options

**Uninstall Flags:**

- `--all` - Uninstall all installed sections
- `--sections "id1,id2,..."` - Uninstall specific sections (comma-separated list or group name)
- `--dry-run` - Preview changes without making modifications
- `--remove-data` - Remove user data (Node.js versions, Python virtualenvs, etc.)
- `--force` - Skip confirmation prompts (use with caution)
- `--restore-backups` - Restore original config files from backup directory
- `--status` - Show current installation status
- `--list-sections` - Display all available sections and groups
- `--verbose` - Show detailed output during uninstallation
- `--help` - Display help message with examples

**Examples:**

```bash
# Show all options
./bootstrap/uninstall.sh --help

# List available sections and groups
./bootstrap/uninstall.sh --list-sections

# Check what's installed
./bootstrap/uninstall.sh --status

# Preview full uninstall
./bootstrap/uninstall.sh --all --dry-run

# Uninstall specific sections
./bootstrap/uninstall.sh --sections "nvm,pyenv,bun"

# Uninstall using group
./bootstrap/uninstall.sh --sections "version_managers"

# Force uninstall without prompts (dangerous!)
./bootstrap/uninstall.sh --all --force

# Remove everything including user data
./bootstrap/uninstall.sh --all --remove-data

# Verbose output for debugging
./bootstrap/uninstall.sh --all --verbose
```

---

## Quality gates

`doctor.sh` checks the machine. `check.sh` checks the repo.

```bash
./scripts/check.sh
```

It runs in three or four seconds and verifies:

- **Script inventory** — every shell script in the repo is covered by the
  checks below. A new script that nobody wired up fails here rather than going
  unchecked.
- **Syntax** — `bash -n` on the scripts, `zsh -n` on the shell config.
- **shellcheck** — `-x` so sourced files are followed, held at
  `--severity=warning`. Info-level notes are left alone: they are style
  preferences, and gating on them would mean churn without a bug fixed.
- **Manifests** — each one parses to a non-empty list, no entry contains
  whitespace or a stray comment, and the `[CONDITIONAL]` markers actually
  change the package set between modes.
- **Tracked files** — no identity in `git/gitconfig`, no key material
  anywhere, and nothing the global gitignore is silently hiding.
- **Installer dry runs** — both modes of `install.sh` and `update-tools.sh`
  exit 0 and leave the checkout byte-identical. This is the check that catches
  an installer editing a tracked file.

`--fast` skips the dry runs, which are the slow part.

### Where it runs

**Before each commit.** `install.sh` links `bootstrap/hooks/pre-commit` into
this checkout, which runs `check.sh --fast`. To commit regardless:

```bash
git commit --no-verify
```

**On push and pull request.** `.github/workflows/checks.yml` runs on
`macos-latest`, because these scripts assume Homebrew and `/Applications`. CI
runs the full set including the dry runs.

Install the hook by hand if you did not run the bootstrap script:

```bash
ln -sfn ../../bootstrap/hooks/pre-commit .git/hooks/pre-commit
```

`shellcheck` is tracked in `bootstrap/brew-packages.txt`, so a machine set up
from this repo can run the gate.

---

## Detailed Configuration

### Bootstrap

**File**: `bootstrap/install.sh`

The bootstrap script automates the entire setup process with robust error handling and idempotent design.

**What it does**:
1. Validates macOS system and required dependencies (curl, git)
2. Installs Homebrew (if not present) for both Intel and Apple Silicon Macs
3. Installs all packages from `brew-packages.txt` and `cask-apps.txt`
4. Installs oh-my-zsh (robbyrussell theme)
5. Sets up version managers:
   - Standard mode: nvm, pyenv, bun, rust, conda
   - Mise mode (`--use-mise`): mise (unified), rust, conda
6. Creates symlinks for shell and git configurations with automatic backups
7. Installs VS Code extensions and copies settings
8. Configures git with environment variables
9. Creates `~/.zshrc.local` for machine-specific customizations

**Features**:
- **Idempotent**: Safe to run multiple times, skips already installed components
- **Graceful error handling**: Continues on individual failures, reports issues at end
- **Automatic backups**: Backs up existing config files before creating symlinks
- **Progress reporting**: Shows installation counts (X/Y installed) and failed items
- **Dry-run mode**: Preview changes without making modifications
- **Download verification**: Validates all downloaded installers before execution

**Usage**:

```bash
# Standard installation
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your.email@example.com"
./bootstrap/install.sh

# Preview what would be installed (dry-run)
./bootstrap/install.sh --dry-run

# Skip backup creation (faster re-runs)
./bootstrap/install.sh --skip-backups

# Use mise for version management
./bootstrap/install.sh --use-mise

# View available options
./bootstrap/install.sh --help
```

**Command-line Options**:
- `--dry-run` - Preview changes without making modifications
- `--skip-backups` - Skip creating backups of existing configuration files
- `--use-mise` - Use mise for unified version management instead of nvm/pyenv/bun
- `--help` - Display usage information and available options

**Version Management Options**:

The bootstrap script supports two approaches for managing programming language versions:

1. **Standard Mode (default)**:
   - Installs individual version managers: nvm (Node.js), pyenv (Python), bun
   - Each tool is managed separately with its own commands
   - Best for users comfortable with traditional version managers
   - Maintains compatibility with existing workflows
   - **Packages installed**: nvm, pyenv, poetry, tippecanoe, pmtiles
   - **Packages skipped**: mise

2. **Mise Mode (`--use-mise` flag)**:
   - Installs mise as a unified version manager for Node.js, Python, and Bun
   - Single tool to manage all language versions
   - Configuration in `mise/config.toml` (versions automatically activated)
   - Uses mise commands for all version management
   - Best for users wanting simplified, unified tooling
   - **Packages installed**: mise, poetry, tippecanoe, pmtiles
   - **Packages skipped**: nvm, pyenv
   - When enabled, the script automatically:
     - Installs mise via Homebrew
     - Skips individual nvm, pyenv, bun installations
     - Uncomments tool versions in `mise/config.toml`
     - Creates symlink to global mise config (`~/.config/mise/config.toml`)
     - Activates mise in your shell configuration
     - Installs all configured tools (Node.js, Python, Bun)
     - Shows installed tool versions

**How the conditional installation works**:
- The script reads `brew-packages.txt` which contains conditional markers
- Packages marked `[CONDITIONAL: USE_MISE]` are only installed with `--use-mise`
- Packages marked `[CONDITIONAL: !USE_MISE]` are skipped when using `--use-mise`
- During installation, you'll see clear messages about which packages are skipped and why
- This ensures clean, non-conflicting installations in both modes

**Note**: Rust (via rustup) and Conda are installed separately in both modes as they have their own specialized installers and ecosystems.

**Machine-specific Settings**:

The script copies `shell/zshrc.local.example` to `~/.zshrc.local`, which is not
tracked in git, and `shell/zshrc` sources it last:
- PATH additions for one machine only
- Machine-specific aliases or functions
- Sourcing local credentials
- Anything that differs between machines

This is what lets `shell/zshrc` stay byte-identical on every laptop. If you
find yourself editing the tracked `zshrc` for something true of one machine,
it belongs in `~/.zshrc.local` instead.

**Brew Packages** (`brew-packages.txt`):
- `mise` - Unified version manager (only with `--use-mise`)
- `nvm` - Node.js version manager (skipped with `--use-mise`)
- `pyenv` - Python version manager (skipped with `--use-mise`)
- `poetry` - Python dependency management (always installed)
- `tippecanoe` - Vector tileset creation for mapping (always installed)
- `pmtiles` - Cloud-optimized map tiles (always installed)

**Note**: Only explicitly installed packages are listed. Dependencies are installed automatically by Homebrew. Packages with conditional markers are installed based on the `--use-mise` flag.

**Error Handling**:

The script tracks errors but continues execution:
- Failed package installations are logged and reported
- Missing dependencies cause immediate exit with helpful message
- Returns exit code 1 if any errors occurred
- Provides summary of warnings/errors at completion

---

### Shell Configuration

**Files**:
- `shell/zshrc` - Main configuration
- `shell/zsh_aliases.sh` - Aliases
- `shell/zsh_functions.sh` - Functions

**Modular Structure**:
The shell configuration is split into multiple files for better maintainability and machine-specific customization:

```
~/.zshrc (symlink) → ~/dev-env/shell/zshrc
                      ├─ sources ~/dev-env/shell/zsh_aliases.sh
                      ├─ sources ~/dev-env/shell/zsh_functions.sh
                      └─ sources ~/.zshrc.local (machine-specific)
```

#### Main Configuration (`zshrc`)

Sets up:
- oh-my-zsh with robbyrussell theme and git plugin
- Node.js via nvm
- Python via pyenv
- Anaconda/Conda environment
- Bun JavaScript runtime
- Rust/Cargo toolchain
- NPM global packages
- Google Cloud SDK (if installed)
- Optional mise integration (commented out)

#### Local Configuration (`~/.zshrc.local`)

**Not tracked in git** - created by the bootstrap script from
`shell/zshrc.local.example`, and never overwritten if it already exists.

This file is for machine-specific settings:
- Custom PATH additions for this machine only
- Machine-specific aliases or functions
- Local environment variables
- Any settings that differ between machines

**Example customizations**:
```bash
# Custom PATH for this machine
export PATH="$HOME/custom/bin:$PATH"

# Machine-specific alias
alias vpn-connect="sudo openconnect vpn.company.com"

# Project shortcuts
alias myproject="cd ~/projects/myproject && code ."
```

**Benefits**:
- Repository stays clean and portable
- No accidental commits of machine-specific settings
- Easy to identify what's local vs shared across machines

#### Aliases (`zsh_aliases.sh`)

**Navigation**:
- `..`, `...`, `....` - Navigate up directories
- `~` - Go to home directory

**Git Shortcuts**:
- `gs` - git status
- `ga` - git add
- `gc` - git commit
- `gp` - git push
- `gl` - git pull
- `gd` - git diff
- `gco` - git checkout
- `gb` - git branch
- `glog` - Pretty git log with graph

**Development**:
- `nr` - npm run
- `nrd` - npm run dev
- `nrb` - npm run build
- `nrt` - npm run test
- `ni` - npm install
- `py` - python3
- `pip` - pip3

**System**:
- `ll` - Detailed list with hidden files
- `la` - List all files
- `showfiles` / `hidefiles` - Toggle hidden files in Finder
- `ip` - Show public IP address
- `localip` - Show local IP address

**Docker**:
- `d` - docker
- `dc` - docker-compose
- `dps` - docker ps
- `dimg` - docker images

**Environment**:
- `reload` - Reload shell configuration
- `edit-zsh` - Open zshrc in VS Code
- `update-dotfiles` - Pull latest configs and reload

#### Functions (`zsh_functions.sh`)

**Directory Management**:
- `mkcd <dir>` - Create directory and cd into it
- `groot` - Go to git repository root

**Development Helpers**:
- `serve [port]` - Quick HTTP server (default port 8000)
- `killport <port>` - Kill process running on specific port

**Git Helpers**:
- `gcm <type> <message>` - Conventional commit (feat, fix, docs, etc.)
- `gacp <message>` - Quick add, commit, and push

**Node/NPM**:
- `clean-install` - Remove node_modules and reinstall
- `npm-update-global` - Update all global npm packages

**Python**:
- `venv-create` - Create and activate virtual environment
- `venv` - Activate existing virtual environment (.venv or venv)

**System**:
- `sysinfo` - Display system and development tool versions

---

### Git Configuration

**Files**:
- `git/gitconfig` - Global git settings
- `git/gitignore_global` - Global ignore patterns

**Symlinks**:
```
~/.gitconfig → ~/dev-env/git/gitconfig
~/.gitignore_global → ~/dev-env/git/gitignore_global
```

#### Git Config Features

**Modern Settings**:
- `pull.ff = only` - Prevent accidental merge commits
- `push.autoSetupRemote = true` - Auto-setup remote tracking
- `push.followTags = true` - Push relevant tags automatically
- `fetch.prune = true` - Auto-remove deleted remote branches
- `merge.conflictStyle = zdiff3` - Better conflict resolution
- `rebase.autoStash = true` - Auto-stash before rebasing
- `diff.algorithm = histogram` - Better diff output

**Extensive Aliases** (30+ commands):
- `git s` - Short status
- `git lg` - Beautiful colored log
- `git pf` - Safe force push (--force-with-lease)
- `git cleanup` - Remove merged branches
- `git wip` - Quick work-in-progress commit
- `git recent` - Show recently used branches
- `git contributors` - Show commit statistics

See `git/gitconfig` for complete list.

**User Configuration**:

User identity is set via environment variables (not committed):
```bash
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your.email@example.com"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
```

The bootstrap script handles this automatically.

#### Global Gitignore

Ignores common files across all repositories:
- macOS system files (.DS_Store, etc.)
- Editor files (.vscode/, .idea/, *.swp)
- Node.js (node_modules/, npm-debug.log)
- Python (__pycache__/, .env, venv/)
- Build outputs (dist/, build/)
- Temporary files and logs

---

### VS Code Settings

**Files**:
- `editors/vscode/settings.json` - User settings
- `editors/vscode/keybindings.json` - Custom keybindings
- `editors/vscode/extensions.txt` - Extensions list

#### Settings Highlights

**Editor**:
- Auto-save after 1 second delay
- Trim trailing whitespace on save
- Format on save enabled
- Bracket pair colorization
- Column rulers at 80 and 120 characters

**Git Integration**:
- Auto-fetch enabled
- Smart commit (auto-stage all if nothing staged)
- GitLens with customized views

**Formatters**:
- TypeScript/JavaScript: Prettier + ESLint auto-fix
- Python: Built-in formatter with import organization
- JSON/JSONC: Built-in / Prettier
- CSS/HTML/Markdown: Prettier

**TypeScript**:
- Inlay hints for parameters and return types
- Never auto-update imports on file move

**Python**:
- Basic type checking with Pylance
- Auto-import completions

**Tailwind CSS**:
- IntelliSense for `cva()` and `cx()` utilities

#### Extensions (31 total)

**AI & Productivity**:
- Claude Code

**Linting & Formatting**:
- ESLint, Prettier, EditorConfig

**Version Control**:
- GitLens

**Docker & Remote**:
- Docker, Remote Containers, Remote SSH, Remote Explorer

**GitHub**:
- Codespaces, GitHub Actions

**Python**:
- Python, Pylance, Debugpy, Python Environments

**Jupyter**:
- Jupyter, Jupyter Keymap, Jupyter Renderers, Cell Tags, Slideshow

**Testing**:
- Jest, Vitest Runner, Vitest Explorer

**Languages**:
- HTML/CSS IntelliSense, Auto Rename Tag, Tailwind Headwind

**Styling**:
- Styled Components, SVG Preview

**TypeScript**:
- Pretty TypeScript Errors

**Installing Extensions**:
```bash
cat editors/vscode/extensions.txt | grep -v '^#' | xargs -L 1 code --install-extension
```

---

### Version Management

**File**: `mise/config.toml`

The repository supports two version management approaches. Choose the one that fits your workflow:

---

#### Comparison Table

| Feature | Standard Mode | Mise Mode |
|---------|--------------|-----------|
| **Installation** | `./bootstrap/install.sh` | `./bootstrap/install.sh --use-mise` |
| **Node.js** | nvm | mise |
| **Python** | pyenv | mise |
| **Bun** | Standalone | mise |
| **Rust** | rustup (both modes) | rustup (both modes) |
| **Conda** | Conda (both modes) | Conda (both modes) |
| **Commands** | `nvm use`, `pyenv shell`, etc. | `mise use`, `mise install` |
| **Config File** | Multiple (.nvmrc, .python-version) | Single (.mise.toml) |
| **Auto-switching** | Limited | Yes, per directory |
| **Speed** | Slower (shell wrappers) | Faster (native binary) |

---

#### Standard Mode (Default)

Uses **individual version managers**:
- **nvm** for Node.js
- **pyenv** for Python
- **bun** standalone
- **cargo/rustup** for Rust
- **conda** for data science environments

Versions are whatever each manager has installed. Run `./scripts/doctor.sh` to
print what this machine is on; `mise/config.toml` records the versions the two
laptops are meant to share.

**Installation**:
```bash
./bootstrap/install.sh
```

**Usage Examples**:
```bash
# Node.js
nvm install 20.11.0
nvm use 20.11.0

# Python
pyenv install 3.11.0
pyenv global 3.11.0

# Bun
bun upgrade
```

**Best for**:
- Users familiar with traditional version managers
- Projects with existing `.nvmrc` or `.python-version` files
- Teams using standard tooling

---

#### Mise Mode (Unified Alternative)

Uses **mise** as a unified version manager that replaces nvm, pyenv, and bun with a single tool.

**Automatic Setup (Recommended)**:
```bash
./bootstrap/install.sh --use-mise
```

This automatically:
1. Installs mise via Homebrew
2. Skips individual nvm/pyenv/bun installations
3. Symlinks `~/.config/mise/config.toml` to this repo's `mise/config.toml`
4. Installs the tools that config pins
5. Shows installed tool versions

The installer does not edit `mise/config.toml`. Its versions are used exactly
as committed, which keeps the checkout clean — a dirty checkout would stop the
`git pull` in `update-tools.sh`. `shell/zshrc` activates mise by itself
whenever `~/.config/mise/config.toml` exists, so nothing patches your shell
config either.

**Usage Examples**:
```bash
# View installed tools
mise list

# Install a different version
mise install node@20.11.0
mise use node@20.11.0

# Update all tools
mise upgrade

# See which version is active
mise current
```

**Configuration**:
Global config at `~/.config/mise/config.toml`, symlinked to this repo's
`mise/config.toml`:
```toml
[tools]
node = "22"
python = "3.12"
bun = "1.4"
```

Changing a version here and running `mise install` on each laptop is how both
machines move together. `mise/config.toml` also lists the current upstream
versions as upgrade targets, so moving to Node 26 or Python 3.14 stays a
deliberate edit rather than something an install does behind your back.

**Per-Project Versions**:
Create `.mise.toml` in any project to override global versions:
```toml
[tools]
node = "20.11.0"
python = "3.11"
bun = "1.1.0"
```

mise will automatically switch to these versions when you `cd` into the project directory.

**Benefits of Mise**:
- Single tool for all language versions
- Significantly faster than nvm/pyenv (native binary vs shell wrappers)
- Project-specific `.mise.toml` overrides with auto-switching
- Automatic version switching per directory
- Consistent interface across all tools
- Better integration with modern development workflows
- Can still read `.nvmrc` and `.python-version` files

**Best for**:
- New setups or fresh installations
- Users wanting simplified, unified tooling
- Projects using multiple language runtimes
- Teams adopting modern development practices

---

#### Manual Migration (Standard → Mise)

If you're already using standard mode and want to migrate:

1. **Install mise**:
   ```bash
   brew install mise
   ```

2. **Edit shell configuration**:
   ```bash
   code ~/dev-env/shell/zshrc
   # Uncomment the mise activation section
   # Optionally comment out nvm/pyenv sections
   ```

3. **Activate tool versions**:
   ```bash
   code ~/dev-env/mise/config.toml
   # Uncomment tool version lines (node, python, bun)
   ```

4. **Create symlink and install tools**:
   ```bash
   mkdir -p ~/.config/mise
   ln -sf ~/dev-env/mise/config.toml ~/.config/mise/config.toml
   mise install
   ```

5. **Reload shell**:
   ```bash
   source ~/.zshrc
   ```

6. **Verify installation**:
   ```bash
   mise list
   node --version
   python --version
   bun --version
   ```

**Note**: You can keep both systems installed, but make sure only one is active in your shell at a time.

---

### Cask applications

**File**: `bootstrap/cask-apps.txt`

Casks are used to bootstrap a machine and to inventory what belongs on it. They
are not an update channel. Every tracked app ships its own updater, and the
repo leaves them to it.

#### Why an app seems to need reinstalling

Homebrew records the version a cask installed. A self-updating app then moves
past that version on its own, so brew considers it outdated. Two things follow
from that:

- `brew upgrade --cask` skips casks marked `auto_updates true`, which is almost
  all of them, so by default nothing happens. Add `--greedy` (or set
  `HOMEBREW_UPGRADE_GREEDY`) and brew reinstalls its older pinned version over
  the app that had updated itself. **Never pass `--greedy` here.**
  `update-tools.sh` runs `brew upgrade --formula`, never `--cask`.
- `brew install --cask` on an app already in `/Applications` from a manual
  download either refuses or overwrites it. Passing `--adopt` tries to take
  the existing app over in place instead, and `install.sh` and
  `update-tools.sh` both do. It often cannot; see below.

#### What cannot be tracked

A cask whose artifact is a `pkg` rather than an `app` cannot be adopted:
`--adopt` only works on app bundles, so brew has no way to take over an
existing install and runs the vendor's installer instead. For an app with a
system extension or a login item, such as Tailscale, that is a disruptive
reinstall rather than a no-op. Check before adding one:

```bash
brew info --cask --json=v2 <name> | grep -o '"pkg"'
```

A self-updating CLI is the other case to avoid: its cask pins a version while
the tool updates itself, so brew keeps reinstalling the older one. The Claude
Code binary is the example here, and it is installed natively instead.

#### Tracked apps

Ghostty, VS Code, Obsidian, Docker Desktop, DBeaver Community, NordPass and
Slack.

Anything not listed is simply not managed by this repo. Nothing removes it,
and doctor does not report it, so an app you want on one laptop only needs no
bookkeeping.

Add one by appending it to `bootstrap/cask-apps.txt`, then run
`./scripts/doctor.sh` on the other laptop to see it reported as missing.

---

### Update Scripts

**File**: `scripts/update-tools.sh`

Synchronizes configuration changes across all machines.

**What it does**:
1. Pulls the repo, then re-executes itself if the pull brought in changes, so
   a half-old and half-new script never runs
2. Updates Homebrew formulas (`brew upgrade --formula`, never casks)
3. Installs anything added to `brew-packages.txt` and `cask-apps.txt`
4. Updates VS Code extensions and copies the settings over, backing up the
   existing ones first
5. Updates the version managers for the mode this machine was installed in,
   read from `~/.dev-env/state.json`, so a mise machine is never handed nvm
   and pyenv as well
6. Refreshes the configuration symlinks, leaving any regular file in place

**Usage**:
```bash
./scripts/update-tools.sh
```

Preview without changing anything:
```bash
./scripts/update-tools.sh --dry-run
```

Skip the pull and use the checkout as it stands:
```bash
./scripts/update-tools.sh --no-pull
```

It stops short of pulling when the checkout has uncommitted changes, rather
than failing partway through.

After running, restart your terminal or:
```bash
source ~/.zshrc
```

**Options**:

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every command it would run, change nothing. Implies `--no-pull`. |
| `--no-pull` | Use the working tree as it stands. |
| `--help` | Usage. |

---

## Usage Patterns

### Making Changes

**On your main machine**:

1. Edit configuration files in `~/dev-env/`
2. Test changes locally
3. Commit and push:
   ```bash
   cd ~/dev-env
   git add .
   git commit -m "Update: description of changes"
   git push
   ```

**On other machines**:

```bash
cd ~/dev-env
./scripts/update-tools.sh
```

### Common Workflows

**Add new Homebrew package**:
1. Install locally: `brew install package-name`
2. Add to `bootstrap/brew-packages.txt`
3. Commit and push
4. On other machines: run `update-tools.sh`

**Add new VS Code extension**:
1. Install in VS Code
2. Run: `code --list-extensions > editors/vscode/extensions.txt`
3. Commit and push
4. On other machines: run `update-tools.sh`

**Add new shell alias/function**:
1. Edit `shell/zsh_aliases.sh` or `shell/zsh_functions.sh`
2. Test: `source ~/.zshrc`
3. Commit and push
4. On other machines: run `update-tools.sh`

**Update tool version**:
1. Update version locally (e.g., `nvm install 20.11.0`)
2. Document in `mise/config.toml` comments
3. Commit and push
4. On other machines: manually update or use mise

---

## Security

### What NOT to Commit

This repository explicitly excludes:
- SSH keys (`.ssh/`)
- API tokens and credentials
- Environment files with secrets (`.env`, `.env.local`)
- Private certificates (`.pem`, `.key`, `.crt`)
- Credential files (`credentials.json`)

See `.gitignore` for complete list.

### Environment Variables

Use the `.env.example` template:

1. Copy template:
   ```bash
   cp .env.example ~/.env.local
   ```

2. Fill in actual values:
   ```bash
   # ~/.env.local
   export GIT_USER_NAME="Your Name"
   export GIT_USER_EMAIL="your.email@example.com"
   export OPENAI_API_KEY="sk-..."
   ```

3. Source in shell (optional):
   ```bash
   # Add to ~/.zshrc
   [ -f ~/.env.local ] && source ~/.env.local
   ```

### Git User Identity

User name and email are set via environment variables:

**During bootstrap**:
```bash
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your.email@example.com"
./bootstrap/install.sh
```

**Manual configuration**:
```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
```

---

## Troubleshooting

### Bootstrap script fails with missing dependencies

**Problem**: Script exits with "Missing required dependencies" error

**Solution**:
```bash
# Install Xcode command line tools
xcode-select --install

# Verify installation
command -v git
command -v curl
```

### Bootstrap script reports errors

**Problem**: Script completes but shows warnings or errors

**Solution**:
The script is designed to continue on errors. Review the output for:
1. **Failed packages**: Individual packages that failed to install
2. **Error count**: Shown at the end with summary

To address specific failures:
```bash
# Re-run bootstrap (it will skip already installed items)
./bootstrap/install.sh

# Or install failed packages manually
brew install <package-name>
code --install-extension <extension-id>
```

### Test bootstrap without making changes

**Problem**: Want to see what would be installed without modifying system

**Solution**:
```bash
./bootstrap/install.sh --dry-run
```

This shows exactly what would be installed, symlinked, and configured.

### Symlinks not working

**Problem**: Configuration not loading after bootstrap

**Solution**:
```bash
# Check if backups were created
ls -la ~/.dotfiles-backup-*

# Re-run bootstrap (it will recreate symlinks)
./bootstrap/install.sh --skip-backups

# Or create symlinks manually
ln -sf ~/dev-env/shell/zshrc ~/.zshrc
ln -sf ~/dev-env/git/gitconfig ~/.gitconfig
ln -sf ~/dev-env/git/gitignore_global ~/.gitignore_global
source ~/.zshrc
```

### VS Code extensions not installing

**Problem**: `code` command not found

**Solution**:
1. Open VS Code
2. Press `Cmd+Shift+P`
3. Run "Shell Command: Install 'code' command in PATH"
4. Restart terminal

### Git user not configured

**Problem**: Git shows wrong username or "PLACEHOLDER_NAME"

**Solution**:
```bash
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your.email@example.com"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
```

### Shell aliases not working

**Problem**: Aliases from `zsh_aliases.sh` not available

**Solution**:
`shell/zshrc` works out the repo location from the `~/.zshrc` symlink, so this
normally resolves itself. Check what it found:

```bash
echo $DOTFILES_DIR
```

If `~/.zshrc` is a regular file rather than a symlink, the lookup falls back to
`~/dev-env`. Re-run the bootstrap script to back up the file and link it:

```bash
./bootstrap/install.sh
```

`~/.zshrc.local` is sourced after the aliases, so setting `DOTFILES_DIR` there
is too late to help. To override it without the symlink, export it from
`~/.zprofile`, which zsh reads first:

```bash
export DOTFILES_DIR="$HOME/Coding/dev-env"
```

### Homebrew packages fail to install

**Problem**: Some packages fail during bootstrap

**Solution**:
- Most packages have dependencies that will install automatically
- Check if failed package is actually needed (see `brew-packages.txt` comments)
- Install manually: `brew install package-name`
- Some packages may be macOS version specific

### Script permissions

**Problem**: Cannot execute scripts

**Solution**:
```bash
chmod +x bootstrap/install.sh
chmod +x scripts/update-tools.sh
```

### Mise installation issues

**Problem**: `mise install` fails or mise tools not activating

**Solution**:
```bash
# Verify mise is installed
mise --version

# Check if config is properly symlinked
ls -la ~/.config/mise/config.toml

# If not, create symlink manually
mkdir -p ~/.config/mise
ln -sf ~/dev-env/mise/config.toml ~/.config/mise/config.toml

# Verify tool versions are uncommented in config
cat ~/dev-env/mise/config.toml | grep -v '^#' | grep -E '(node|python|bun)'

# Try installing again
mise install

# Check shell activation
grep -E 'mise activate' ~/.zshrc
```

### Wrong version manager active

**Problem**: Using mise mode but nvm/pyenv commands still work (or vice versa)

**Solution**:
```bash
# Check what's active in your shell
which nvm node python

# If using mise mode, ensure mise is activated
grep 'mise activate' ~/.zshrc

# Ensure old version managers are commented out
grep 'NVM_DIR\|pyenv init' ~/.zshrc

# Reload shell
source ~/.zshrc

# Verify mise is working
mise current
```

### Conflicting package installations

**Problem**: Both mise and nvm/pyenv are installed after running bootstrap

**Solution**:
This can happen if you ran the script without `--use-mise` first, then with `--use-mise`.

```bash
# To clean up and use mise:
brew uninstall nvm pyenv
rm -rf ~/.nvm ~/.pyenv

# Re-run bootstrap with mise
./bootstrap/install.sh --use-mise --skip-backups

# Or to clean up and use standard mode:
brew uninstall mise
rm -rf ~/.config/mise

# Re-run bootstrap without mise flag
./bootstrap/install.sh --skip-backups
```

### Dry-run shows incorrect packages

**Problem**: Dry-run output doesn't match expected packages for chosen mode

**Solution**:
Make sure you're using the correct flags:
```bash
# For standard mode preview
./bootstrap/install.sh --dry-run

# For mise mode preview
./bootstrap/install.sh --dry-run --use-mise
```

The output should clearly show which packages are skipped and why.

---

## Additional Resources

**Git Configuration**:
- [Git Config Documentation](https://git-scm.com/docs/git-config)
- See `git/gitconfig` for all available aliases

**Shell Functions**:
- See `shell/zsh_functions.sh` for implementation details
- Run `type <function-name>` to see function definition

**Homebrew**:
- [Homebrew Documentation](https://docs.brew.sh/)
- Use `brew leaves` to see top-level packages
- Use `brew deps <package>` to see dependencies

**Mise Version Manager**:
- [Mise Documentation](https://mise.jdx.dev/)
- See `mise/config.toml` for migration instructions

---

## License

This is a personal configuration repository. Use as inspiration for your own setup.
