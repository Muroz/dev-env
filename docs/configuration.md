# Configuration reference

Every file this repo manages, what it sets and why. To install or check a
machine, see the [README](../README.md).

- [Bootstrap](#bootstrap)
- [Shell configuration](#shell-configuration)
- [Git configuration](#git-configuration)
- [VS Code](#vs-code)
- [Version management](#version-management)
- [Cask applications](#cask-applications)
- [Update script](#update-script)

---

## Bootstrap

`bootstrap/install.sh` takes a machine from nothing to a working setup. You can
run it as often as you like: it skips what is already in place, so a second run
reports and changes nothing.

It works through eleven steps:

1. Checks that this is macOS and that `git` and `curl` are present.
2. Installs Homebrew if it is missing, on Apple silicon or Intel.
3. Installs the formulas in `bootstrap/brew-packages.txt`.
4. Installs the applications in `bootstrap/cask-apps.txt`, skipping any whose
   app is already in `/Applications`.
5. Installs oh-my-zsh if it is missing.
6. Installs mise, symlinks `mise/config.toml` and installs the tools it pins.
7. Installs rustup if `cargo` is missing. It reports conda but never installs
   it, since conda ships its own installer.
8. Symlinks the shell and git configuration, backing up whatever it replaces.
9. Installs the VS Code extensions and copies the settings over.
10. Writes your git identity to `~/.gitconfig.local` if it is not there yet.
11. Creates `~/.zshrc.local` from the template, leaves an existing one alone,
    installs the pre-commit hook and schedules the weekly drift check.

### Options

| Flag | Effect |
|------|--------|
| `--dry-run` | Print what would happen. Nothing changes. |
| `--skip-backups` | Replace configuration without backing it up first. |
| `--help` | Print usage. |

```bash
./bootstrap/install.sh --dry-run
```

### How it handles failure

A missing system dependency stops the script at once, because nothing else can
succeed without it. Anything else is reported and the run continues, so one
unavailable package does not abandon the rest of the setup.

The summary separates the two. Warnings count an optional tool that is absent,
which is normal and does not affect the exit status. Errors and failed sections
do: the script exits 1 when either occurs.

### What it backs up

Before replacing a configuration file with a symlink, the script copies the
original to `~/.dotfiles-backup-<timestamp>`. It records what it installed in
`~/.dev-env/state.json`, which the uninstaller later reads to know what it may
remove. A dry run writes neither.

**Caution:** the Homebrew and oh-my-zsh installers run as their vendors publish
them, without checksum verification. The mise installer verifies its own
download against a checksum it carries. If running vendor installers is not
acceptable to you, install those three by hand and run this script afterwards;
it skips what is already present.

### Formulas

`bootstrap/brew-packages.txt` tracks the formulas you asked for, not their
dependencies, which Homebrew resolves itself.

| Formula | Purpose |
|---------|---------|
| `jq` | Required. `bootstrap/lib/state.sh` writes its state as JSON. |
| `shellcheck` | Required by `scripts/check.sh`. |
| `poetry` | Python dependency management. |
| `gh`, `git-filter-repo` | GitHub from the terminal, and history rewriting. |
| `helm`, `kind` | Kubernetes. |
| `openjdk@17` | Java. |
| `tippecanoe`, `pmtiles` | Vector tilesets and cloud-optimized map tiles. |
| `cmake`, `autoconf`, `pkgconf`, `python@3.15` | Homebrew's build toolchain. |

mise is **not** in that file. Homebrew publishes no bottle for it on macOS 14
arm64, so brew would build it from source along with LLVM and Rust. The
installer uses mise's own installer instead, which fetches a prebuilt binary
into `~/.local/bin`.

The build toolchain is tracked for a related reason. Because this platform has
no bottles, Homebrew builds `poetry`, `lz4`, `webp` and others locally, and it
needs those four to do so. `brew uninstall` refuses to remove them.

The file also carries a commented list of candidates, `uv` and `ruff` among
them, each noting what it would replace.

---

## Shell configuration

Three tracked files and one that is not:

```
~/.zshrc (symlink) → shell/zshrc
                     ├─ sources shell/zsh_aliases.sh
                     ├─ sources shell/zsh_functions.sh
                     └─ sources ~/.zshrc.local   (per machine, untracked)
```

### Main configuration

`shell/zshrc` is identical on every machine. In order, it:

1. Resolves the Homebrew prefix rather than hardcoding it, so the file works on
   Apple silicon and Intel.
2. Puts `~/bin` and `~/.local/bin` on `PATH`. The second matters, because
   self-updating tools install there.
3. Loads oh-my-zsh with the `robbyrussell` theme and the `git` plugin.
4. Activates mise, which provides Node and Bun.
5. Adds `~/.cargo/bin` for rustup's toolchains.
6. Activates conda from whichever of four locations holds it.
7. Sources the Google Cloud SDK if it finds one.
8. Works out this repo's location from the `~/.zshrc` symlink, then sources the
   aliases and functions.
9. Sources `~/.zshrc.local` last, so anything there wins.

If mise is absent, step 4 falls back to nvm and a standalone bun and says so on
stderr. Without that fallback a machine part-way through the migration has no
`node` at all.

### Machine-local configuration

`~/.zshrc.local` is not tracked. The installer creates it from
`shell/zshrc.local.example` and never overwrites an existing one. Put anything
true of a single machine there:

```bash
export PATH="$HOME/custom/bin:$PATH"
alias work="cd ~/clients/acme"
[ -f "$HOME/.env.local" ] && source "$HOME/.env.local"
```

Keeping those out of `shell/zshrc` is what lets the tracked file stay
byte-identical everywhere. If you are editing the tracked file for something
true of one laptop, it belongs here instead.

`DOTFILES_DIR` is one exception. `shell/zshrc` resolves it before sourcing the
aliases, so setting it in `~/.zshrc.local` is too late to take effect. Export
it from `~/.zprofile` if you ever need to override it.

### Aliases

`shell/zsh_aliases.sh` defines 34 aliases.

Navigation:

- `..`, `...`, `....` move up one, two or three directories
- `~` goes home
- `ll`, `la`, `l` list in long form, including hidden files, and in columns

Git:

- `gs`, `ga`, `gc`, `gp`, `gl`, `gd`, `gco`, `gb` for status, add, commit,
  push, pull, diff, checkout and branch
- `glog` prints a graph log

npm and Python:

- `nr`, `nrd`, `nrb`, `nrt`, `ni` for run, run dev, run build, run test and
  install
- `py` and `pip` for `python3` and `pip3`

Docker:

- `d`, `dc`, `dps`, `dimg` for docker, docker-compose, `ps` and `images`

macOS and this repo:

- `showfiles` and `hidefiles` toggle hidden files in Finder
- `ip` and `localip` print your public and local addresses
- `reload` re-sources the shell, `edit-zsh` opens the config in VS Code
- `update-dotfiles` pulls this repo and reloads

### Functions

`shell/zsh_functions.sh` defines 11 functions.

| Function | What it does |
|----------|--------------|
| `mkcd <dir>` | Creates a directory and changes into it. |
| `groot` | Changes to the git repository root. |
| `serve [port]` | Serves the current directory over HTTP, port 8000 by default. |
| `killport <port>` | Kills whatever is listening on a port. |
| `gcm <type> <message>` | Commits in conventional-commit form. |
| `gacp <message>` | Adds, commits and pushes in one step. |
| `clean-install` | Removes `node_modules` and reinstalls. |
| `npm-update-global` | Updates every global npm package. |
| `venv-create` | Creates a virtual environment and activates it. |
| `venv` | Activates an existing `.venv` or `venv`. |
| `sysinfo` | Prints the system and tool versions. |

The file clears any alias that shares a name with one of these before defining
it. zsh expands an alias when it reads `name()`, and the resulting parse error
would stop the rest of the file loading. Oh My Zsh's git plugin defines `gcm`,
so without that step `gcm` and everything after it would be missing.

---

## Git configuration

```
~/.gitconfig        → git/gitconfig
~/.gitignore_global → git/gitignore_global
```

### Settings

`git/gitconfig` sets, among others:

| Setting | Effect |
|---------|--------|
| `pull.ff = only` | A pull that cannot fast-forward fails rather than merging. |
| `push.autoSetupRemote = true` | A new branch gets its upstream on first push. |
| `push.followTags = true` | Pushes annotated tags along with commits. |
| `fetch.prune = true` | Drops remote branches that no longer exist. |
| `merge.conflictStyle = zdiff3` | Shows the common ancestor in a conflict. |
| `rebase.autoStash = true` | Stashes and restores around a rebase. |
| `diff.algorithm = histogram` | Produces more readable diffs. |

It also defines 39 aliases, including `git s` for a short status, `git lg` for a
graph log, `git pf` for a force-push with `--force-with-lease`, `git cleanup` to
drop merged branches and `git wip` for a quick work-in-progress commit. Read
`git/gitconfig` for the rest.

### Your identity

Identity lives in `~/.gitconfig.local`, which is not tracked, and
`git/gitconfig` pulls it in with an `[include]` at the end.

It must not go in the tracked file. `~/.gitconfig` is a symlink into this repo,
and git writes through a symlink, so `git config --global user.email` would
write your address into a file you then commit.

Set it from the template, or let the installer move an existing identity across:

```bash
cp -n git/gitconfig.local.example ~/.gitconfig.local
```

One consequence is worth remembering: `git config --global --get user.name`
does not follow includes and prints nothing. Read it back without `--global`:

```bash
git config --get user.name
```

### Global gitignore

`git/gitignore_global` applies to every repository on the machine, so it lists
only patterns that are unambiguous: macOS and editor files, credentials and key
material, Python bytecode, `node_modules`, logs and backups.

Bare directory names such as `build`, `dist`, `out`, `target` and `lib` are
deliberately absent, although the upstream Node and Python templates include
them. Globally they hide real source: `lib/` once made
`bootstrap/lib/packages.sh` in this repo invisible, with no error and nothing in
`git status`. Put those in a project's own `.gitignore`, where they are scoped
to that project.

To find out what is hiding a file:

```bash
git check-ignore -v <path>
```

---

## VS Code

Three files, two copied and one read as a list:

- `editors/vscode/settings.json` becomes `~/Library/Application Support/Code/User/settings.json`
- `editors/vscode/keybindings.json` becomes the matching `keybindings.json`
- `editors/vscode/extensions.txt` lists 44 extensions to install

The installer backs up an existing settings file before replacing it, and skips
the copy when the two already match.

### Settings

The tracked settings are deliberately small. They set per-language formatters
for TypeScript, JavaScript, Vue, Markdown, JSON, JSONC, CSS and HTML, turn on
`git.autofetch`, group the GitLens source-control views, keep TypeScript from
rewriting imports when a file moves, wrap editor tabs, label `index.ts` files by
their parent directory and put Claude Code in the panel.

They do not set a theme, a font, rulers, auto-save or format-on-save. An earlier
version of this repo carried a much larger settings file that had never been
applied to either machine; it was replaced with what the machines actually run.

### Keybindings

One binding: `shift+enter` sends a line continuation to the integrated terminal,
so you can write a multi-line command without running it.

### Extensions

`extensions.txt` is a plain list, so you can install it without this repo's
scripts:

```bash
grep -v '^#' editors/vscode/extensions.txt | grep -v '^$' | xargs -L 1 code --install-extension
```

`doctor.sh` compares the list against what is installed and reports both
directions, so an extension you add on one laptop shows up as untracked until
you add it to the file.

---

## Version management

mise manages Node and Bun from `mise/config.toml`, which the installer symlinks
to `~/.config/mise/config.toml`. `shell/zshrc` activates it, and it switches
versions per directory for any project carrying its own `.mise.toml`, `.nvmrc`
or `.python-version`.

```bash
mise current     # what is active here
mise install     # install what the config pins
mise outdated    # what is behind the pins
```

Changing a version in `mise/config.toml` and running `mise install` on each
laptop is how both machines move together. Renovate watches the file and opens
a pull request when a tool has a newer release.

The installer never rewrites `mise/config.toml`. Its versions are used as
committed, which keeps the checkout clean, and a dirty checkout would stop the
`git pull` in `update-tools.sh`.

### What mise does not manage

| Tool | Managed by | Why |
|------|-----------|-----|
| Rust | rustup | It manages its own toolchains and updates them in place. |
| Python | conda | conda already provides it at `/opt/anaconda3`. Both tools rewrite `PATH` on activation, so giving Python to mise would put a second interpreter ahead of conda's for no gain. |

### Superseded managers

nvm, pyenv and a standalone bun put shims on `PATH` ahead of mise, so a stale
one wins silently. `doctor.sh` reports any that can still load, and the
uninstaller removes them:

```bash
./bootstrap/uninstall.sh --sections nvm,pyenv,bun
```

Installed Node and Python versions are preserved unless you pass
`--remove-data`. Those sections remain in the uninstaller although nothing
installs them, because they are how a machine still carrying them gets cleaned
up.

---

## Cask applications

`bootstrap/cask-apps.txt` bootstraps the applications a machine should have. It
is not an update channel: every tracked app ships its own updater, and the repo
leaves them to it.

### Why an app seems to need reinstalling

Homebrew records the version a cask installed. A self-updating app then moves
past that version on its own, so brew considers it outdated. Two things follow:

- `brew upgrade --cask` skips casks marked `auto_updates true`, which is nearly
  all of them, so by default nothing happens. Add `--greedy`, or set
  `HOMEBREW_UPGRADE_GREEDY`, and brew reinstalls its older pinned version over
  the app that had moved on. `update-tools.sh` runs `brew upgrade --formula` and
  never touches casks.
- `brew install --cask` on an app already in `/Applications` either refuses or
  overwrites it. `--adopt` tries to take the existing app over in place instead.

**Warning:** never run `brew upgrade --cask --greedy` on a machine set up from
this repo. It is the one command that turns a working app into an older one.

### Why `--adopt` usually fails

Three things get in the way, so expect adoption not to work:

- It adopts only an app **identical** to the cask's version. Every app worth
  tracking updates itself, so it drifts within days. Tried across six apps here,
  five had already moved past the cask.
- It runs `sudo chgrp -hR admin` on the bundle, so it needs a terminal that can
  ask for a password and never works unattended.
- With SIP enabled, that `chgrp` fails outright on a bundle owned by
  `root:wheel`, which is how a pkg installer leaves one.

None of that matters much, because the file's job is a fresh machine. On a
machine where the apps already exist, `doctor.sh` reports an unmanaged app as a
note rather than a problem: the app is there, which is what makes two machines
equivalent.

To hand one to brew anyway, let it reinstall:

```bash
brew install --cask <name>
```

That replaces the bundle and registers it. Settings in `~/Library` are
untouched.

### What cannot be tracked

A cask whose artifact is a `pkg` rather than an `app` cannot be adopted at all,
so brew runs the vendor's installer instead. For an app with a system extension
or a login item, such as Tailscale, that is a disruptive reinstall. Check before
adding one:

```bash
brew info --cask --json=v2 <name> | grep -o '"pkg"'
```

A self-updating CLI is the other case to avoid, for the same reason an app is:
its cask pins a version while the tool updates itself. The Claude Code binary is
the example here, and it is installed natively.

### Tracked apps

Ghostty, VS Code, Obsidian, Docker Desktop, DBeaver Community, NordPass and
Slack.

Anything else is not managed by this repo. Nothing removes it and `doctor.sh`
does not report it, so an app you want on one laptop only needs no bookkeeping.
To track one, append it to the file, then run `./scripts/doctor.sh` on the other
laptop to see it reported as missing.

---

## Update script

`scripts/update-tools.sh` brings a machine back in line with the repo. It:

1. Pulls the repo, then re-executes itself if the pull changed anything, so a
   half-old script never runs on.
2. Upgrades Homebrew formulas with `brew upgrade --formula`, never casks.
3. Installs anything added to the formula and cask manifests.
4. Updates the VS Code extensions and copies the settings over, backing up the
   existing ones first.
5. Updates mise itself with `mise self-update`, installs what
   `mise/config.toml` pins, then updates rustup and conda.
6. Refreshes the configuration symlinks, leaving any regular file in place.

| Flag | Effect |
|------|--------|
| `--dry-run` | Print every command it would run. Implies `--no-pull`. |
| `--no-pull` | Use the working tree as it stands. |
| `--help` | Print usage. |

```bash
./scripts/update-tools.sh --dry-run
```

It declines to pull when the checkout has uncommitted changes, rather than
failing partway through. When it finishes, open a new terminal or run
`source ~/.zshrc`.
