# Development Environment Configuration

A centralized configuration repository for consistent development environments across multiple macOS machines. This repository contains shell configurations, git settings, editor preferences, and automation scripts to quickly bootstrap and maintain development setups.

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Quick Start](#quick-start)
- [Detailed Configuration](#detailed-configuration)
  - [Bootstrap](#bootstrap)
  - [Shell Configuration](#shell-configuration)
  - [Git Configuration](#git-configuration)
  - [VS Code Settings](#vs-code-settings)
  - [Version Management](#version-management)
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
- **Version management**: Document current tool versions with optional mise migration path
- **Update automation**: Scripts to keep all machines in sync

**Important**: This repository contains configuration only, no secrets. SSH keys, API tokens, and credentials are managed separately.

---

## Repository Structure

```
dev-env/
├── bootstrap/
│   ├── install.sh           # Main bootstrap script for fresh Mac setup
│   ├── brew-packages.txt    # Homebrew formula packages to install
│   └── cask-apps.txt        # Homebrew cask applications to install
├── shell/
│   ├── zshrc                # Main zsh configuration
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
│   └── config.toml          # Version management configuration (optional)
├── scripts/
│   └── update-tools.sh      # Script to sync changes across machines
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
cd ~/dev-env
./scripts/update-tools.sh
```

This will:
- Pull latest changes from git
- Update Homebrew and packages
- Install new VS Code extensions
- Refresh symlinks
- Update version managers

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

The script creates `~/.zshrc.local` for machine-specific customizations that aren't tracked in git:
- `DOTFILES_DIR` environment variable
- Custom PATH additions
- Machine-specific aliases or functions
- Local environment variables

This keeps the repository clean while allowing per-machine customization.

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

**Not tracked in git** - created automatically by bootstrap script.

This file is for machine-specific settings:
- `DOTFILES_DIR` environment variable (set to `~/dev-env`)
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
- **nvm** for Node.js (v22.13.1)
- **pyenv** for Python (system)
- **bun** standalone (1.0.0)
- **cargo/rustup** for Rust (1.91.1)
- **conda** for data science environments

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
3. Uncomments tool versions in `mise/config.toml`
4. Creates symlink: `~/.config/mise/config.toml` → `~/dev-env/mise/config.toml`
5. Activates mise in shell configuration
6. Installs all configured tools (Node.js 22.13.1, Python 3.13, Bun 1.0.0)
7. Shows installed tool versions

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
Global config at `~/.config/mise/config.toml` (symlinked to `~/dev-env/mise/config.toml`):
```toml
[tools]
node = "22.13.1"
python = "3.13"
bun = "1.0.0"
```

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

### Update Scripts

**File**: `scripts/update-tools.sh`

Synchronizes configuration changes across all machines.

**What it does**:
1. Pulls latest changes from git repository
2. Updates Homebrew and all packages
3. Installs new packages from brew-packages.txt
4. Updates VS Code extensions
5. Copies latest VS Code settings
6. Updates version managers (nvm, pyenv, bun, rust, conda)
7. Runs `mise install` if mise is installed
8. Refreshes configuration symlinks

**Usage**:
```bash
cd ~/dev-env
./scripts/update-tools.sh
```

After running, restart your terminal or:
```bash
source ~/.zshrc
```

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
```bash
# Check if DOTFILES_DIR is set
echo $DOTFILES_DIR

# If not set, add to ~/.zshrc:
export DOTFILES_DIR="$HOME/dev-env"

# Reload
source ~/.zshrc
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
