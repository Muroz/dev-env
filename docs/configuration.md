# Configuration reference

Each file this repo manages, what it sets and why. For how to install
and check a machine, see the [README](../README.md).

---

## Bootstrap

**File**: `bootstrap/install.sh`

The bootstrap script automates the entire setup process with robust error handling and idempotent design.

**What it does**:
1. Validates macOS system and required dependencies (curl, git)
2. Installs Homebrew (if not present) for both Intel and Apple Silicon Macs
3. Installs all packages from `brew-packages.txt` and `cask-apps.txt`
4. Installs oh-my-zsh (robbyrussell theme)
5. Sets up version managers:
   - Standard mode: nvm, pyenv, bun, rust, conda
   - mise for Node and Bun, rustup for Rust, conda for Python
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


# View available options
./bootstrap/install.sh --help
```

**Command-line Options**:
- `--dry-run` - Preview changes without making modifications
- `--skip-backups` - Skip creating backups of existing configuration files
- `--help` - Display usage information and available options

**Version Management Options**:

The bootstrap script supports two approaches for managing programming language versions:

mise manages Node and Bun from `mise/config.toml`. Rust stays with rustup and
Python stays with conda, both of which have their own installers and
ecosystems. See [Version Management](#version-management) for why Python is
left alone.

The manifests are read verbatim: one entry per line, blank lines and comments
ignored. There are no conditional markers any more — there is one mode, so
there is nothing to branch on.

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
- `mise` - manages the Node and Bun versions in `mise/config.toml`
- `jq` - required: `bootstrap/lib/state.sh` records what it installed as JSON
- `shellcheck` - required by `scripts/check.sh`
- `poetry` - Python dependency management
- `gh`, `git-filter-repo` - GitHub CLI and history rewriting
- `helm`, `kind` - Kubernetes
- `openjdk@17` - Java
- `tippecanoe`, `pmtiles` - vector tilesets and cloud-optimized map tiles

**Note**: Only explicitly installed packages are listed; Homebrew pulls in
dependencies itself. The file also carries a commented list of candidates,
`uv` and `ruff` among them, each saying what it would replace.

**Error Handling**:

The script tracks errors but continues execution:
- Failed package installations are logged and reported
- Missing dependencies cause immediate exit with helpful message
- Returns exit code 1 if any errors occurred
- Provides summary of warnings/errors at completion

---

## Shell configuration

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

### Main configuration (`zshrc`)

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

### Local configuration (`~/.zshrc.local`)

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

### Aliases (`zsh_aliases.sh`)

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

### Functions (`zsh_functions.sh`)

**Directory Management**:
- `mkcd <dir>` - Create directory and cd into it
- `groot` - Go to git repository root

**Development Helpers**:
- `serve [port]` - Quick HTTP server (default port 8000)
- `killport <port>` - Kill process running on specific port

**Git Helpers**:
- `gcm <type> <message>` - Conventional commit (feat, fix, docs)
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

## Git configuration

**Files**:
- `git/gitconfig` - Global git settings
- `git/gitignore_global` - Global ignore patterns

**Symlinks**:
```
~/.gitconfig → ~/dev-env/git/gitconfig
~/.gitignore_global → ~/dev-env/git/gitignore_global
```

### Git config features

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

### Global gitignore

Ignores common files across all repositories:
- macOS system files (.DS_Store)
- Editor files (.vscode/, .idea/, *.swp)
- Node.js (node_modules/, npm-debug.log)
- Python (__pycache__/, .env, venv/)
- Build outputs (dist/, build/)
- Temporary files and logs

---

## VS Code settings

**Files**:
- `editors/vscode/settings.json` - User settings
- `editors/vscode/keybindings.json` - Custom keybindings
- `editors/vscode/extensions.txt` - Extensions list

### Settings highlights

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

### Extensions (31 total)

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

## Version management

**File**: `mise/config.toml`

mise manages Node and Bun, from the versions pinned in that file. It is
symlinked to `~/.config/mise/config.toml`, activated by `shell/zshrc`, and
switches versions per directory when a project has its own `.mise.toml`,
`.nvmrc` or `.python-version`.

There used to be a `--use-mise` flag choosing between mise and nvm/pyenv. That
second path is gone. One way of setting up a machine is the entire point of
this repo, and the dual mode was where the bug lived that reinstalled nvm and
pyenv onto a mise machine.

```bash
mise current          # what is active here
mise install          # install what config.toml pins
mise outdated         # what is behind the pins
```

The installer does not rewrite `mise/config.toml`. Its versions are used as
committed, which keeps the checkout clean — a dirty checkout would stop the
`git pull` in `update-tools.sh`.

### What mise does not manage

| Tool | Managed by | Why |
|------|-----------|-----|
| Rust | rustup | It manages its own toolchains and updates in place. |
| Python | conda | conda already provides it at `/opt/anaconda3`. Both tools rewrite `PATH` on activation, so handing Python to mise would put a second interpreter ahead of conda's for no gain. |

pyenv was removed rather than migrated. It was set to `system` and managing
nothing: Python came from conda the whole time.

### Leftovers

nvm, pyenv and a standalone bun put shims on `PATH` ahead of mise, so a stale
one wins silently. `doctor.sh` reports any that are still present, and they
come off with:

```bash
./bootstrap/uninstall.sh --sections nvm,pyenv,bun
```

Those sections remain in the uninstaller for exactly this reason, although
nothing installs them any more.

---

## Cask applications

**File**: `bootstrap/cask-apps.txt`

Casks are used to bootstrap a machine and to inventory what belongs on it. They
are not an update channel. Every tracked app ships its own updater, and the
repo leaves them to it.

### Why an app seems to need reinstalling

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

### What cannot be tracked

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

### Tracked apps

Ghostty, VS Code, Obsidian, Docker Desktop, DBeaver Community, NordPass and
Slack.

Anything not listed is not managed by this repo. Nothing removes it,
and doctor does not report it, so an app you want on one laptop only needs no
bookkeeping.

Add one by appending it to `bootstrap/cask-apps.txt`, then run
`./scripts/doctor.sh` on the other laptop to see it reported as missing.

---

## Update scripts

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
