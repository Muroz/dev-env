# dev-env

Keeps two macOS laptops on the same development toolchain, so that working on
one is the same as working on the other.

The repo holds the definition: which Homebrew packages, which applications,
which VS Code extensions and which tool versions belong on a machine, plus the
shell and git configuration to go with them. Three scripts act on that
definition: one sets a machine up, one brings it back in line and one reports
every way a machine has drifted from it.

The last of those is the point. Two machines only stay interchangeable if you
can see when they stop being so.

## Requirements

- macOS on Apple silicon or Intel
- Git and `curl`, both of which ship with the Xcode Command Line Tools
- An account with administrator rights, for Homebrew

## Set up a machine

1. Clone the repo. Any location works, because the shell config finds it from
   its own symlink:

   ```bash
   git clone https://github.com/Muroz/dev-env.git ~/dev-env
   cd ~/dev-env
   ```

2. Preview what the installer would do. Nothing changes:

   ```bash
   ./bootstrap/install.sh --dry-run
   ```

3. Set your git identity in `~/.gitconfig.local`, which stays out of git. On a
   machine that has none yet, start from the template:

   ```bash
   cp -n git/gitconfig.local.example ~/.gitconfig.local
   ```

   If `~/.gitconfig` already holds an identity, skip this step. The installer
   moves it to `~/.gitconfig.local` before it replaces the file.

4. Run the installer:

   ```bash
   ./bootstrap/install.sh
   ```

5. Open a new terminal, then confirm the result:

   ```bash
   ./scripts/doctor.sh
   ```

The installer backs up any file it replaces into
`~/.dotfiles-backup-<timestamp>`, and records what it installed in
`~/.dev-env/state.json`.

## Check a machine

`doctor.sh` compares this machine against the repo:

```bash
./scripts/doctor.sh
```

It reports symlinks that are not in place, Homebrew packages and applications
installed but not tracked, missing or extra VS Code extensions, settings that
differ, tool versions, your git identity and whether the checkout is behind its
remote. Each finding comes with the command that fixes it.

It reads only. Nothing is installed, changed or removed. The exit status is 0
when the machine matches the repo and 1 when it does not, so you can use it in
a script. Pass `--quiet` to see only the problems.

Run it on both laptops. Identical output is the goal.

## Bring a machine back in line

```bash
./scripts/update-tools.sh
```

This pulls the latest commits and re-runs itself, upgrades Homebrew formulas,
installs anything added to the manifests, syncs VS Code, updates the tools mise
manages, then refreshes the symlinks. Add `--dry-run` to print every command it
would run without running any of them.

It never upgrades applications. Each one updates itself, and forcing Homebrew
to upgrade a self-updating app reinstalls an older version over the top. See
[Cask applications](docs/configuration.md#cask-applications).

## What the repo defines

| File | Contents |
|------|----------|
| `bootstrap/brew-packages.txt` | Homebrew formulas |
| `bootstrap/cask-apps.txt` | Applications, with the rules for managing them |
| `editors/vscode/extensions.txt` | VS Code extensions |
| `editors/vscode/settings.json` | VS Code settings and keybindings |
| `mise/config.toml` | Node and Bun versions |
| `shell/zshrc` | Shell configuration, identical on every machine |
| `git/gitconfig` | Git configuration, without any identity |

Each manifest is a list of names, one per line, with blank lines and comments
ignored.

Two files stay out of git, because they differ per machine. `~/.zshrc.local`
holds shell settings true of one laptop, and `~/.gitconfig.local` holds your
git identity. The templates are `shell/zshrc.local.example` and
`git/gitconfig.local.example`.

### Tool versions

mise manages Node and Bun from `mise/config.toml`. Rust stays with rustup, and
Python stays with conda, which already provides it. For why, see
[Version management](docs/configuration.md#version-management).

```bash
mise current     # what is active here
mise install     # install what the config pins
mise outdated    # what is behind the pins
```

Changing a version in `mise/config.toml` and running `mise install` on each
laptop is how both machines move together.

## Stay current

The repo watches two different kinds of staleness.

**On a machine.** A launchd agent runs `scripts/notify-drift.sh` every Monday
at 10:00. It reports drift against the repo, Homebrew formulas with a newer
version available and mise tools behind the pins, then raises a macOS
notification if anything turns up. The detail goes to `~/.dev-env/drift.log`.
Nothing runs by hand, though you can see the report now:

```bash
./scripts/notify-drift.sh --stdout
```

**In the repo.** Renovate opens a pull request when a pinned version falls
behind upstream, covering both `mise/config.toml` and the GitHub Actions
workflow. `renovate.json` configures it.

## Quality gates

`check.sh` checks the repo, where `doctor.sh` checks the machine:

```bash
./scripts/check.sh
```

It verifies that every script is covered by the checks, that the shell scripts
and shell config parse, that ShellCheck is clean at warning level, that the
manifests parse to well-formed lists, that both installers leave the checkout
byte-identical and that no identity or key material sits in a tracked file.
The byte-identical check is the one that catches an installer editing its own
repo.

Two places run it. A pre-commit hook runs `check.sh --fast` before each commit,
which you can skip with `git commit --no-verify`. The
[checks workflow](.github/workflows/checks.yml) runs the full set on
`macos-latest` for every push and pull request.

## Remove it

```bash
./bootstrap/uninstall.sh --list-sections      # what can be removed
./bootstrap/uninstall.sh --dry-run --all      # preview
./bootstrap/uninstall.sh --sections nvm,pyenv # remove two sections
```

Installed tool versions are kept unless you pass `--remove-data`. See
[Uninstalling](docs/uninstalling.md) for the sections, the groups and the
safety rules.

## Further reading

- [Configuration reference](docs/configuration.md) covers every managed file in
  detail.
- [Uninstalling](docs/uninstalling.md) covers selective removal and backups.
- [Troubleshooting](docs/troubleshooting.md) covers the symptoms you are most
  likely to hit.

## Security

This repo holds configuration, never secrets. SSH keys, API tokens and
credentials stay outside it: `.gitignore` blocks the usual filenames, and
`check.sh` fails the build if key material or a git identity reaches a tracked
file.

Keep secrets in `~/.env.local`, which `.env.example` documents, and source it
from `~/.zshrc.local`.
