# Troubleshooting

Run the doctor first. It names most of what follows without you having to
guess:

```bash
./scripts/doctor.sh
```

- [Node or Bun is the wrong version](#node-or-bun-is-the-wrong-version)
- [mise will not install from Homebrew](#mise-will-not-install-from-homebrew)
- [Homebrew builds everything from source](#homebrew-builds-everything-from-source)
- [Aliases and functions are missing](#aliases-and-functions-are-missing)
- [Git is using the wrong name or email](#git-is-using-the-wrong-name-or-email)
- [The doctor says it cannot reach the remote](#the-doctor-says-it-cannot-reach-the-remote)
- [An application will not come under Homebrew](#an-application-will-not-come-under-homebrew)
- [The weekly check never notifies](#the-weekly-check-never-notifies)
- [The installer reports warnings](#the-installer-reports-warnings)
- [The `code` command is not found](#the-code-command-is-not-found)
- [A script will not execute](#a-script-will-not-execute)

---

## Node or Bun is the wrong version

`node --version` disagrees with `mise current`.

nvm, pyenv and a standalone bun put shims on `PATH` ahead of mise, so a
leftover install wins silently. Find out what is answering:

```bash
command -v node bun
mise current
```

A path under `~/.nvm` or `~/.bun` means a superseded manager is still in play.
The doctor names it, and the uninstaller removes it:

```bash
./bootstrap/uninstall.sh --sections nvm,pyenv,bun
```

Your downloaded versions are kept. See
[Uninstalling](uninstalling.md#what-is-kept-and-what---remove-data-deletes).

## mise will not install from Homebrew

`brew install mise` starts building z3, ninja, LLVM, libgit2 and Rust from
source, or fails against your Command Line Tools.

Homebrew publishes no bottle for mise on macOS 14 arm64. Confirm it for
yourself:

```bash
brew info --json=v2 mise | grep -c arm64_sonoma
```

A zero means no bottle for this platform, so brew has to compile. Do not wait
for that build. The installer uses mise's own installer, which fetches a
prebuilt binary into `~/.local/bin`:

```bash
./bootstrap/install.sh
```

`shell/zshrc` already has `~/.local/bin` on `PATH`, and mise keeps itself
current with `mise self-update`.

## Homebrew builds everything from source

Every `brew install` compiles, and the output mentions a Tier 3 configuration.

Homebrew supports the latest macOS release and the two before it. Older than
that is Tier 3: no CI, no bottles, so every formula is built locally. Check
where you stand:

```bash
sw_vers
softwareupdate --list
```

Upgrading macOS is the only fix. A point release within the same major version
does not restore bottles.

## Aliases and functions are missing

`gs`, `mkcd` or `gcm` are not found in a new shell.

First, check that the shell config found this repo:

```bash
echo $DOTFILES_DIR
```

`shell/zshrc` works this out from the `~/.zshrc` symlink. An empty or wrong
value means `~/.zshrc` is a regular file rather than a symlink, and the lookup
has fallen back to `~/dev-env`. Re-run the installer, which backs up the file
before linking it:

```bash
./bootstrap/install.sh
```

Setting `DOTFILES_DIR` in `~/.zshrc.local` will not help, because that file is
sourced after the aliases. Export it from `~/.zprofile`, which zsh reads
first:

```bash
export DOTFILES_DIR="$HOME/Coding/dev-env"
```

If only some functions are missing, an alias is shadowing one. zsh expands an
alias when it reads `name()`, and that parse error stops the rest of the file
loading. `shell/zsh_functions.sh` clears the names it defines before defining
them; a function added without that treatment can still collide.

## Git is using the wrong name or email

Read the value back without `--global`:

```bash
git config --get user.name
git config --get user.email
```

The `--global` form prints nothing here, which is expected. Identity lives in
`~/.gitconfig.local`, and `git config --global --get` does not follow the
`[include]` that pulls it in.

Edit that file, or start it from the template:

```bash
cp -n git/gitconfig.local.example ~/.gitconfig.local
```

**Caution:** do not fix this with `git config --global user.email`.
`~/.gitconfig` is a symlink into this repo and git writes through a symlink, so
that command writes your address into a tracked file. `check.sh` fails the
build if it finds one, but the simplest course is not to put it there.

## The doctor says it cannot reach the remote

`git fetch` is failing, which used to pass unnoticed and let a machine fall
months behind. Read the error:

```bash
git fetch
```

An SSH remote with no key loaded in the agent is the usual cause:

```bash
ssh-add -l
```

Either load the key, or move the remote to HTTPS and let the credential helper
answer:

```bash
ssh-add ~/.ssh/id_ed25519
git remote set-url origin https://github.com/Muroz/dev-env.git
```

## An application will not come under Homebrew

`brew install --cask --adopt <name>` fails, often asking for a password it
cannot read.

This is expected more often than not, and it does not matter: the application
is installed, which is what makes two machines equivalent. The doctor reports
an unmanaged app as a note, not a problem. See
[Cask applications](configuration.md#why---adopt-usually-fails) for the three
reasons adoption fails.

To hand one to brew anyway, let it reinstall rather than adopt:

```bash
brew install --cask <name>
```

Your settings in `~/Library` are untouched.

## The weekly check never notifies

Confirm launchd has the job, and that it points at this checkout:

```bash
launchctl print "gui/$(id -u)/com.dev-env.drift" | grep -E "state|path"
```

`state = not running` is correct between runs. Run it now rather than waiting
for Monday:

```bash
./scripts/notify-drift.sh --stdout
launchctl kickstart -p "gui/$(id -u)/com.dev-env.drift"
```

If the report is right but no notification appears, macOS is withholding
permission for the process that posts it. Allow notifications for your
terminal in **System Settings > Notifications**. The report is appended to
`~/.dev-env/drift.log` either way, and launchd's own errors land in
`~/.dev-env/launchd.err.log`.

A moved checkout breaks the job, because the plist holds an absolute path.
Re-run `./bootstrap/install.sh` to rewrite and reload it.

## The installer reports warnings

A warning means an optional tool is absent. It does not affect the exit status,
and the summary counts warnings separately from errors. Only an error or a
failed section makes the script exit 1.

To retry a failed package on its own:

```bash
brew install <formula>
code --install-extension <extension-id>
```

Re-running the installer is safe, and skips what is already in place.

## The `code` command is not found

VS Code has not put its CLI on `PATH`. In VS Code, open the command palette
with **Cmd+Shift+P**, then run **Shell Command: Install 'code' command in
PATH** and open a new terminal.

## A script will not execute

```bash
chmod +x bootstrap/*.sh scripts/*.sh bootstrap/hooks/pre-commit
```

Or run one through its interpreter, which needs no execute bit:

```bash
bash ./scripts/doctor.sh
```
