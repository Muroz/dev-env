# Uninstalling

The uninstaller removes all or part of what `bootstrap/install.sh`
installed. Every section can be removed on its own, and user data is
kept unless you ask for it to go.

---

## Full uninstall

Remove everything installed by the bootstrap script:

```bash
cd ~/dev-env
./bootstrap/uninstall.sh --all
```

The script will:
- Show what will be removed
- Request confirmation
- Uninstall selected components
- Preserve user data by default (Node versions, Python virtualenvs)
- Display a detailed summary showing:
  - ✓ Successfully uninstalled sections
  - ✗ Failed sections (if any errors occurred)
  - ○ Sections that would be affected (in dry-run mode)
- Provide option to restore backups

## Selective uninstall

Remove specific components only:

```bash
# Remove version managers
./bootstrap/uninstall.sh --sections "nvm,pyenv,bun"

# Switch from nvm/pyenv to mise
./bootstrap/uninstall.sh --sections "nvm,pyenv,bun"

# Remove VS Code extensions
./bootstrap/uninstall.sh --sections "vscode_extensions"
```

## Preview changes (dry-run)

See what would be removed without making changes:

```bash
./bootstrap/uninstall.sh --all --dry-run
```

## Remove user data

By default, user data is preserved (Node.js versions, Python virtualenvs, globally installed packages). To remove everything including data:

```bash
./bootstrap/uninstall.sh --all --remove-data
```

**Warning**: This will delete:
- All Node.js versions and npm packages (if using nvm)
- All Python versions and virtualenvs (if using pyenv)
- All mise-managed tools (if using mise)

## Check installation status

See what's currently installed:

```bash
./bootstrap/uninstall.sh --status

# Detailed view with package lists
./bootstrap/uninstall.sh --status --verbose
```

## Restore backups

Original config files are backed up before being replaced. To restore them:

```bash
./bootstrap/uninstall.sh --restore-backups
```

## Available sections

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

## Safety features

The uninstall system includes multiple safety mechanisms:

1. **Data Preservation**: User data kept by default (use `--remove-data` to remove)
2. **Homebrew Protection**: Only removed if no other packages depend on it
3. **Confirmation Prompts**: Interactive confirmation before removing sections
4. **Dry-Run Mode**: Preview changes before applying them
5. **Backup Restoration**: Restore original config files from backups
6. **State Tracking**: Knows what was installed and in which mode

## Command-Line options

**Uninstall Flags:**

- `--all` - Uninstall all installed sections
- `--sections "id1,id2,..."` - Uninstall specific sections (comma-separated list or group name)
- `--dry-run` - Preview changes without making modifications
- `--remove-data` - Remove user data (Node.js versions, Python virtualenvs)
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
