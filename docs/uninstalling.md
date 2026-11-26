# Uninstalling

`bootstrap/uninstall.sh` removes all or part of what `bootstrap/install.sh`
put in place. It reads `~/.dev-env/state.json` to know what the installer
recorded, so it removes what this repo added and leaves the rest alone.

Tool versions you downloaded are kept unless you ask for them to go.

- [Remove everything](#remove-everything)
- [Remove part of it](#remove-part-of-it)
- [Sections](#sections)
- [Groups](#groups)
- [Restore the original files](#restore-the-original-files)
- [Options](#options)

---

## Remove everything

Preview first. Nothing changes:

```bash
./bootstrap/uninstall.sh --all --dry-run
```

Then remove:

```bash
./bootstrap/uninstall.sh --all
```

The script lists what it is about to remove, asks you to confirm, works
through the sections in reverse dependency order and prints a summary of what
succeeded and what failed.

## Remove part of it

Name the sections you want gone:

```bash
./bootstrap/uninstall.sh --sections nvm,pyenv,bun
```

Or name a group:

```bash
./bootstrap/uninstall.sh --sections version_managers
```

To see what is on the machine before deciding:

```bash
./bootstrap/uninstall.sh --status
./bootstrap/uninstall.sh --status --verbose   # with package lists
```

## Sections

```bash
./bootstrap/uninstall.sh --list-sections
```

| Section | Removes |
|---------|---------|
| `homebrew` | Homebrew itself, and only when nothing else depends on it. |
| `brew_packages` | The formulas in `bootstrap/brew-packages.txt`. |
| `brew_casks` | The applications in `bootstrap/cask-apps.txt` that brew manages. |
| `oh_my_zsh` | The oh-my-zsh framework. |
| `nvm` | nvm, both the Homebrew formula and `~/.nvm`. |
| `pyenv` | pyenv, both the formula and `~/.pyenv`. |
| `bun` | A standalone bun install at `~/.bun`. |
| `mise` | mise and its configuration symlink. |
| `rust` | The rustup toolchain. |
| `symlinks` | `~/.zshrc`, `~/.gitconfig` and `~/.gitignore_global`. |
| `vscode_extensions` | The extensions in `editors/vscode/extensions.txt`. |
| `git_config` | Git settings this repo applied. |
| `shell_config` | `~/.zshrc.local`. |
| `drift_agent` | The weekly drift check, unloaded from launchd and deleted. |

nvm, pyenv and bun remain as sections although nothing installs them any more.
mise replaced all three, and these are how a machine still carrying them gets
cleaned up.

A cask section only removes an application Homebrew actually manages. One you
installed by hand is left alone, whether or not it appears in the manifest.

## Groups

A group is shorthand for several sections:

| Group | Expands to |
|-------|-----------|
| `version_managers` | `nvm`, `pyenv`, `bun`, `mise`, `rust` |
| `configs` | `symlinks`, `git_config`, `shell_config` |
| `minimal` | The same three as `configs` |
| `vscode` | `vscode_extensions` |
| `homebrew_all` | `homebrew`, `brew_packages`, `brew_casks` |
| `all` | Every section, the same as `--all` |

## Restore the original files

Before replacing a configuration file with a symlink, the installer copies the
original into `~/.dotfiles-backup-<timestamp>`. To put those files back:

```bash
./bootstrap/uninstall.sh --restore-backups
```

## Options

| Flag | Effect |
|------|--------|
| `--all` | Remove every installed section. |
| `--sections "a,b"` | Remove the named sections or group. |
| `--dry-run` | Print what would happen. Nothing changes. |
| `--remove-data` | Also delete downloaded tool versions. |
| `--force` | Skip the confirmation prompts. |
| `--restore-backups` | Put the original configuration files back. |
| `--status` | Print what is currently installed. |
| `--list-sections` | Print the sections and groups. |
| `--verbose` | Print more detail while working. |
| `--help` | Print usage and examples. |

## What is kept, and what `--remove-data` deletes

By default the uninstaller removes a version manager but keeps what it
downloaded. Removing `nvm` empties `~/.nvm` except for `versions/`, and
removing `pyenv` does the same to `~/.pyenv`, so your interpreters survive and
you can reach them by full path.

**Warning:** `--remove-data` deletes those version directories, every global
npm package installed under them and every mise-managed tool. There is no
backup of a downloaded interpreter, so a `--remove-data` run means
reinstalling anything you still want.

```bash
./bootstrap/uninstall.sh --all --remove-data
```

## Safety

Six things make the uninstaller harder to regret:

- Downloaded tool versions survive unless you pass `--remove-data`.
- Homebrew comes off only when nothing else depends on it.
- Each section asks for confirmation, unless you pass `--force`.
- `--dry-run` prints the same work without doing any of it.
- `--restore-backups` puts the original configuration files back.
- The shell configuration is left untouched when `~/.zshrc` is a symlink into
  this repo, because editing it would write through the symlink into a tracked
  file.
