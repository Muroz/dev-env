# Troubleshooting

Symptoms you might hit, and what fixes them. Run `./scripts/doctor.sh`
first: it names most of these without you having to guess.

---

## Bootstrap script fails with missing dependencies

**Problem**: Script exits with "Missing required dependencies" error

**Solution**:
```bash
# Install Xcode command line tools
xcode-select --install

# Verify installation
command -v git
command -v curl
```

## Bootstrap script reports errors

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

## Test bootstrap without making changes

**Problem**: Want to see what would be installed without modifying system

**Solution**:
```bash
./bootstrap/install.sh --dry-run
```

This shows exactly what would be installed, symlinked, and configured.

## Symlinks not working

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

## VS Code extensions not installing

**Problem**: `code` command not found

**Solution**:
1. Open VS Code
2. Press `Cmd+Shift+P`
3. Run "Shell Command: Install 'code' command in PATH"
4. Restart terminal

## Git user not configured

**Problem**: Git shows wrong username or "PLACEHOLDER_NAME"

**Solution**:
```bash
export GIT_USER_NAME="Your Name"
export GIT_USER_EMAIL="your.email@example.com"
git config --global user.name "$GIT_USER_NAME"
git config --global user.email "$GIT_USER_EMAIL"
```

## Shell aliases not working

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

## Homebrew packages fail to install

**Problem**: Some packages fail during bootstrap

**Solution**:
- Most packages have dependencies that will install automatically
- Check if failed package is actually needed (see `brew-packages.txt` comments)
- Install manually: `brew install package-name`
- Some packages may be macOS version specific

## Script permissions

**Problem**: Cannot execute scripts

**Solution**:
```bash
chmod +x bootstrap/install.sh
chmod +x scripts/update-tools.sh
```

## Mise installation issues

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

## Wrong version manager active

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

## Leftover nvm, pyenv or bun after migrating to mise

**Problem**: `node` or `bun` is not the version `mise current` reports

**Cause**: nvm, pyenv and a standalone bun put shims on `PATH` ahead of mise,
so a leftover install wins silently.

**Solution**:
```bash
./scripts/doctor.sh                                  # names what is left
./bootstrap/uninstall.sh --sections nvm,pyenv,bun    # removes it
```

Add `--remove-data` to delete the downloaded Node and Python versions too.
Check what won afterwards:

```bash
mise current
command -v node bun
```

---
