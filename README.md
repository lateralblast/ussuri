![alt tag](ussuri.jpg)

# ussuri

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Current Version: 1.6.6

License: CC BY-NC-SA, https://creativecommons.org/licenses/by-nc-sa/4.0/

Fund me here: https://ko-fi.com/richardatlateralblast

## Contents

- [What it does](#what-it-does)
- [Quick start](#quick-start)
- [Installation](#installation)
- [How it works](#how-it-works)
- [Usage](#usage)
- [Configuration](#configuration)
- [Prompt](#prompt)
- [Plugins](#plugins)
- [History](#history)
- [PATH and build flags](#path-and-build-flags)
- [Packages](#packages)
- [Languages and tools](#languages-and-tools)
- [System settings](#system-settings)
- [Dotfiles](#dotfiles)
- [Maintenance](#maintenance)
- [Security notes](#security-notes)
- [Testing and CI](#testing-and-ci)
- [Files and directories](#files-and-directories)
- [License](#license)

## What it does

ussuri is a single zsh script that sets up a shell environment from scratch, on macOS and Linux. It is copied to `~/.zshrc` and runs
inline: every time you log in or start a new shell it checks the environment and installs or configures whatever is missing, so a new
machine is one `--install` away from your usual setup. With no switches it is a login script; with switches it is a command line tool.

![Config example](https://raw.githubusercontent.com/lateralblast/ussuri/master/ussuri.png)

What it manages:

- **Shell**: zinit plugins (loaded in turbo mode), a powerlevel10k prompt with a configurable second line (or oh-my-posh), history
  settings, zoxide, forgit, history search, and an init cache so a login stays fast
- **Packages**: Homebrew formulae, casks and taps on macOS; apt, pacman, dnf, apk and nix on Linux; layered per profile and per machine,
  with a drift report that compares what is installed with your lists
- **Languages and tools**: rbenv and pyenv, and optionally fnm, rustup, uv, mise and atuin
- **System settings**: macOS defaults (with a journal so they can be undone) and a set of GNOME settings on Linux, plus the Transmission
  blocklist and an optional sudoers entry
- **Dotfiles**: symlinked from layers (common, profile, machine), with backups
- **The script itself**: self-update that also refreshes its support files, an optional once-a-day update hint, `.zshrc` backups with
  rollback and uninstall, and a read-only `--doctor`

It is careful about what it does to your machine: everything with a side effect honours `--dryrun` and `--confirm`, nothing is deleted
without a copy being kept, downloaded installers can be checked against a checksum, and the read-only commands (`--doctor`, `--drift`,
`--help`, `--version`) change nothing. See [Security notes](#security-notes).

## Quick start

```
git clone https://github.com/lateralblast/ussuri.git
cd ussuri
./ussuri.zsh --doctor           # what is there and what is missing (read only)
./ussuri.zsh --install          # back up ~/.zshrc and install ussuri as it
exec zsh                        # start a new shell: missing components are installed on this first login
```

To see what a run would do without doing it, add `--dryrun --verbose`. To go back, `./ussuri.zsh --uninstall`.

## Installation

`--install` copies the script to `~/.zshrc` and its supporting files (`files/`: package lists, plugin lists and the powerlevel10k
config) to `~/.ussuri/files`. It first saves your current `~/.zshrc` in `~/.ussuri` (see [Backups, rollback and
uninstall](#backups-rollback-and-uninstall)). A dry run shows exactly what it would do:

```
./ussuri.zsh --install --dryrun --verbose
Information:    Instantiated by ./ussuri.zsh on Tue 27 Oct 2026 16:24:46 AEDT by alice@laptop.example.com
Information:    Setting defaults
Adding:         /usr/local/bin to PATH
Adding:         /usr/local/sbin to PATH
Adding:         /opt/local/bin to PATH
Adding:         /opt/local/sbin to PATH
Adding:         ~/.local/bin to PATH
Adding:         ~/.cargo/bin to PATH
Information:    Running without executing commands
Saving:         ~/.zshrc to ~/.ussuri/.zshrc.27_10_2026_16_24_46
Executing:      cp ~/.zshrc ~/.ussuri/.zshrc.27_10_2026_16_24_46
Replacing:      ~/.zshrc with ./ussuri.zsh
Executing:      cp ./ussuri.zsh ~/.zshrc
Executing:      ( cd ~/code/ussuri/files && tar -cpf - . )|( cd ~/.ussuri/files && tar -xpf - )
Executing:      cp ~/.ussuri/files/p10k/p10k.zsh ~/.p10k.zsh
```

Run from a checkout, ussuri updates that copy when you use `--update`; run it from `~/.zshrc` to update the installed one (or run
`--install` again after updating the checkout).

## How it works

**Login mode.** With no switches ussuri runs as a login script. It sets its defaults, then does the checks that are enabled for logins
(defaults, fonts, zinit, rbenv, pyenv, the prompt engine, zoxide, ...). Each check installs what is missing and sets up the environment, and
stays quiet when there is nothing to do.

**Manual mode.** Any switch makes it a command line tool that does only what you ask. `-A` (do all) and `-i` (inline defaults) make a manual
run behave like a login.

**Staying fast.** The script runs on every new shell, so the normal path starts no other processes. Work that only needs doing now and then
is tracked in `~/.ussuri` and skipped otherwise: the OS X defaults (a stamp, `DEFAULTS_MAX_AGE` days), the output of `rbenv init`, `pyenv init`,
`brew shellenv`, `mise activate` and `zoxide init` (a cache, rebuilt when the tool changes; `DO_CACHE_INIT=false` turns it off), and the package
lists (a checksum, so only a changed list is reprocessed). Anything that touches the network on a login is opt-in and runs in the background.

**Locking.** Steps that install or change things take a lock (`~/.ussuri.lock`, a directory, taken atomically and considered stale after 10
minutes), so several shells opened at once don't race. A shell that doesn't get the lock skips those steps. `--force` clears the lock and
ignores the stamps.

**Switch behaviour.** `--dryrun` shows each command without running it; `--verbose` logs them; `--confirm` asks before each; `--yes` answers
the questions for you; `--debug` turns on `set -x`. Every side effect goes through one function, so these apply to all of them.

**Settings.** Every default can be changed, in this order of precedence: the built in defaults, then the environment, then the
[config file](#configuration), then command line switches.

## Usage

```
  Usage: ./ussuri.zsh [OPTIONS...]

  When run manually with switches:

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -A|--doall        Do all function (where set to true)
    -i|--inline       Set inline defaults when not running inline mode
    -I|--install      Installs ussuri as: ~/.zshrc
    -b|--build        Build sources       (default: false)
    -c|--confirm      Confirm commands    (default: false)
    -C|--check        Check for updates   (default: false)
    -d|--debug        Enable debug        (default: false)
    -D|--default(s)   Set defaults        (default: false)
    -E|--prompt NAME  Prompt engine       (default: p10k: p10k, posh or none)
    -f|--font(s)      Install font(s)     (default: false)
    -F|--force        Force action        (default: false)
    -g|--gopath       Set GOPATH          (default: ~/go)
    -G|--drift [settings|packages|all]  Report what differs from the defaults and the package lists (read only)
    -k|--config       Create config file  (~/.ussuri/config)
    --set NAME VALUE  Save a setting in the config file, for every new shell
    --unset NAME      Remove a setting from the config file
    --get [NAME]      Show a setting (default: all) and where it comes from
    -J|--defaults-undo [N|list]  Undo the Nth newest run of defaults changes (default: newest)
    -l|--location     Set start dir       (default: none)
    -B|--backups      List .zshrc backups
    -R|--rollback [N] Restore a backup    (default: newest)
    -X|--uninstall    Restore the .zshrc from before ussuri
    -L|--dotfiles     Link dotfiles       (default: false)
    -M|--profile NAME Profile for dotfiles, packages and plugins (default: none, machine: laptop)
    -u|--unlink       Unlink dotfiles
    -m|--manager      Plugin manager      (default: zinit)
    -n|--notheme      No zsh theme        (default: true)
    -N|--noenv        Ignore environment  (default: true)
    -o|--ohmyposh     Install oh my posh  (default: false)
    -O|--ohmyzsh      Install oh my zsh   (default: false)
    -p|--pyenv        Do pyenv check      (default: false)
    -P|--package(s)   Do packages check   (default: false)
    -r|--rbenv        Do rbenv check      (default: false)
    -s|--sudoers      Do sudoers check    (default: false)
    -S|--sudoersentry Set sudoers entry   (default: ALL=(ALL) NOPASSWD:ALL)
    -t|--dryrun       Dry run mode        (default: false)
    -T|--p10k         Do p10k config      (default: false)
    -U|--update       Update the script   (default: false)
    -v|--verbose      Verbose output      (default: false)
    -y|--yes          Answer yes, no prompts (default: false)
    -W|--tool NAME    Install a tool      (fnm, rustup, uv, mise or atuin)
    -x|--doctor       Check environment   (read only)
    -z|--zinit        Do zinit check      (default: false)
    -Z|--zshtheme     Set zsh theme       (default: robbyrussell)

  Defaults when run inline (i.e. as login script):

    Do build mode         false
    Do confirm mode       false
    Do update check       false
    Do debug mode         false
    Do defaults check:    true
    Do fonts check:       true
    Do package check:     false
    Do zinit check:       true
    Do pyenv check:       true
    Do rbenv check:       true
    Do p10k check         true
    Do oh-my-posh check:  false
    Do oh-my-zsh check:   false
    Do verbose mode       false
    Do sudoers check:     false
    Do PKGCONFIG check:   true
    Do CPPFLAGS check:    true
    Do LDFLAGS check:     true
    Plugin Manager:       zinit
    Start Directory:      none
```

The switches by what they are for:

| For | Switches |
|---|---|
| Installing and removing | `-I` install, `-X` uninstall, `-B` list backups, `-R [N]` roll back, `-U` update, `-C` check for a newer version |
| Looking without touching (read only) | `-x` doctor, `-G [settings\|packages\|all]` drift, `-J list` defaults journal, `-h` help, `-V` version, `-e` changelog |
| Settings | `-k` create the config, `--set NAME VALUE` save a setting, `--unset NAME` remove it, `--get [NAME]` show one or all |
| What to set up | `-A` everything, `-z` zinit, `-E NAME`/`-T`/`-o` prompt engine, `-p` pyenv, `-r` rbenv, `-W NAME` fnm, rustup, uv, mise or atuin, `-P` packages, `-D` defaults, `-f` fonts, `-L` dotfiles, `-s` sudoers |
| Undoing | `-J [N]` undo a run of defaults changes, `-u` unlink dotfiles, `-R`/`-X` restore a `.zshrc` |
| How it runs | `-t` dry run, `-v` verbose, `-c` confirm, `-y` yes, `-F` force, `-d` debug, `-N` no environment setup, `-b` build language versions |
| Choosing | `-M NAME` profile, `-m` plugin manager, `-Z` zsh theme, `-n` no theme, `-O` oh-my-zsh, `-g` GOPATH, `-l` start directory, `-S` sudoers entry |

Notes on the switches:

- **Other long names:** most switches have more than one. The others are `--assume-yes` and `--assumeyes` (`--yes`), `--changes` (`--changelog`),
  `--compile` (`--build`), `--engine` (`--prompt`), `--fonts` (`--font`), `--gohome` (`--gopath`), `--packages` (`--package`), `--plugin`
  (`--manager`), `--posh` (`--ohmyposh`), `--startdir` (`--location`), `--test` (`--dryrun`), `--usage` (`--help`) and `--zosh` (`--ohmyzsh`).
  `--set`, `--unset` and `--get` have no short form.
- **Bundling and values:** short switches can be bundled (`-vt`). A switch that takes a value ignores a leading `-` in it.
- **Mistakes:** a switch that is missing its value, or an unknown switch, prints the usage and exits with status 1.
- **Exit statuses:** `--doctor` is 0, or 1 if anything failed. `--drift` is 0 for none, 1 for drift, 2 if there was nothing to compare with.
  `--defaults-undo`, `--rollback` and `--uninstall` are 0, or 1 if there was nothing (or no such backup or run) to act on. `--set`, `--unset` and
  `--get` are 0, or 1 if a name or value was refused.

## Configuration

```
./ussuri.zsh --config
```

Creates `~/.ussuri/config` (or the file named by `USSURI_CONFIG`) with every setting commented out, and tells you where it is. It is sourced
as zsh before any defaults are set, so a line such as

```
DO_VERBOSE=true
ZINIT_TURBO=false
START_DIR=~/code
```

changes the default for every shell without editing the script (which would then stop being updatable). It is executed, so keep it writable
only by you; `--doctor` warns if it is not, and if it has a syntax error. `--config` never overwrites an existing file. Some defaults can also be declared at the top
of the script itself. To change a setting without opening the file, see below.

### Changing a setting from the command line

```
./ussuri.zsh --set PROMPT_TOP_ELEMENTS "context os_icon"    # saved for every new shell
./ussuri.zsh --set PROMPT_TWO_LINE=false                    # NAME=VALUE works too
./ussuri.zsh --unset PROMPT_TOP_ELEMENTS                    # back to the default
./ussuri.zsh --get PROMPT_TOP_ELEMENTS                      # the value, and whether it is from the config, the environment or the default
./ussuri.zsh --get                                          # every setting, one per line, with its value and where it comes from
```

These edit `~/.ussuri/config` (or the file named by `USSURI_CONFIG`), so nothing in the script, which is replaced by `--update`, is touched, and
the new value applies from the next shell. The file is created from the template if there is none.

- **Which names:** the settings the template lists (`--config`). Another upper case name needs `--force`. A setting that is true or false, and
  `PROMPT_ENGINE`, refuse any other value.
- **Values are text:** a value is saved quoted and never run, so `$(...)` and backticks in one are kept as they were typed.
- **Your file stays yours:** a new setting is added under its commented example in the template, an existing line is replaced where it is, and
  your own lines and comments are left alone. Several `--set` and `--unset` in one run are written together.
- **Safe to run at any time:** the file is written to a copy and renamed into place, under the lock, so a shell that starts at that moment reads
  the old file or the new one. The previous file is kept as `~/.ussuri/config.<date>` (the newest ten). `--dryrun` shows what would be written.

### Settings

True or false unless a value is given. Defaults are for a login shell. `--get` prints the current value of every setting here, and where
each comes from.

**Behaviour**

| Setting | Default | What it does |
|---|---|---|
| `DO_VERBOSE`, `DO_DRYRUN`, `DO_CONFIRM`, `DO_DEBUG`, `DO_FORCE` | false | the `-v`, `-t`, `-c`, `-d` and `-F` switches |
| `ASSUME_YES` | false | never prompt (`-y`) |
| `DO_BUILD` | false | build the rbenv and pyenv versions (`-b`) |
| `DO_ENV_SETUP` | true | set up each tool's environment in the shell (`-N` turns it off) |
| `START_DIR` | none | directory new shells start in |
| `GO_HOME` | `~/go` | GOPATH, set and added to PATH if the directory exists |
| `DO_CACHE_INIT` | true | cache the output of tool init commands |
| `DEFAULTS_MAX_AGE` | 7 | days before the OS X defaults are applied again on a login |
| `UPDATE_HINT` | false | once a day, check for a newer version in the background |
| `USSURI_CONFIG` | `~/.ussuri/config` | the config file |
| `DOCTOR_MAX_BACKUPS` | 10 | `--doctor` warns when there are more `.zshrc` backups than this |

**Shell**

| Setting | Default | What it does |
|---|---|---|
| `PLUGIN_MANAGER` | zinit | `zinit` or `oh-my-zsh` (`-m`) |
| `ZINIT_TURBO` | true | load plugins after the prompt, from `zinit-turbo.zsh`; false loads `zinit.zsh` before it |
| `ZSH_THEME`, `DO_ZSH_THEME` | robbyrussell, true | the oh-my-zsh theme (`-Z`, `-n`) |
| `SHARE_HISTORY`, `DO_HISTORY`, `HISTORY_SIZE` | true, true, 50000 | [history settings](#history) |
| `PROMPT_ENGINE` | p10k | `p10k`, `posh` or `none` (`-E`) |
| `PROMPT_TWO_LINE`, `PROMPT_TOP_ELEMENTS`, `PROMPT_TOP_RIGHT_ELEMENTS` | true, context, none | the [two line prompt](#two-line-prompt) and its [settings](#prompt-settings) |
| `INSTALL_ZOXIDE` | true | set zoxide up if it is installed |

**Components** (installed and set up on a login when true)

| Setting | Default |
|---|---|
| `INSTALL_ZINIT`, `INSTALL_RBENV`, `INSTALL_PYENV`, `INSTALL_FONTS`, `INSTALL_BREW` (macOS packages) | true |
| `INSTALL_P10K`, `INSTALL_POSH` | follow `PROMPT_ENGINE` |
| `INSTALL_OZSH`, `INSTALL_FNM`, `INSTALL_RUSTUP`, `INSTALL_UV`, `INSTALL_MISE`, `INSTALL_ATUIN` | false |
| `ATUIN_BIND_UP` | false (history substring search keeps the up arrow) |
| `ATUIN_IMPORT` | true (import existing history once, when building) |

**What a login checks** (`DO_..._CHECK`; the switches turn these on for a manual run)

| Setting | Default |
|---|---|
| `DO_DEFAULTS_CHECK`, `DO_FONTS_CHECK`, `DO_ZINIT_CHECK`, `DO_RBENV_CHECK`, `DO_PYENV_CHECK`, `DO_TOOLS_CHECK`, `DO_ZOXIDE_CHECK`, `DO_BREW_CHECK` (macOS: Homebrew's environment) | true |
| `DO_P10K_CHECK`, `DO_POSH_CHECK` | follow `PROMPT_ENGINE` |
| `DO_PACKAGE_CHECK`, `DO_ZOSH_CHECK`, `DO_SUDOERS_CHECK`, `DO_DOTFILES_CHECK`, `DO_GNOME_DEFAULTS` | false |
| `DO_PKGCONFIG_CHECK`, `DO_CPPFLAGS_CHECK`, `DO_LDFLAGS_CHECK` | true (see [PATH and build flags](#path-and-build-flags)) |

**Versions**

| Setting | Default |
|---|---|
| `RUBY_VER`, `PYTHON_VER` | the latest stable, when building |
| `FNM_NODE`, `RUSTUP_TOOLCHAIN_WANTED`, `UV_PYTHON`, `MISE_TOOLS` | none; installed only when building (`--tool` or `--build`) |

**Profiles and packages**

| Setting | Default |
|---|---|
| `PROFILE` | none (`-M`) |
| `MACHINE` | the short hostname |
| `DOTFILES_DIR` | `~/.ussuri/dotfiles` |
| `DOTFILES_PROFILE`, `DOTFILES_HOST` | follow `PROFILE` and `MACHINE`; override them for dotfiles alone |
| `PKG_MANAGER` | from the distribution: `apt`, `pacman`, `dnf`, `apk` or `nix` |
| `OS_RELEASE_FILE`, `APK_WORLD_FILE` | `/etc/os-release`, `/etc/apk/world`: where the distribution and the apk packages you asked for are read from |
| `SUDOERS_ENTRY` | `ALL=(ALL) NOPASSWD:ALL` (`-S`) |

**Locations** (all under your home directory by default)

| Setting | Default |
|---|---|
| `WORK_DIR` | `~/.ussuri` |
| `ZINIT_HOME`, `RBENV_HOME`, `PYENV_HOME`, `POSH_HOME`, `ZOSH_HOME`, `P10K_HOME` | `~/.zinit`, `~/.rbenv`, `~/.pyenv`, `~/.oh-my-posh`, `~/.oh-my-zsh`, `~/.powerlevel10k` |
| `P10K_INIT` | `~/.p10k.zsh` |
| `ZINIT_FILE` | the plugin list that is run: `~/.ussuri/files/zinit/zinit-turbo.zsh`, or `zinit.zsh` if `ZINIT_TURBO=false` |
| `FNM_HOME`, `UV_BIN_DIR`, `MISE_BIN` | `~/.local/share/fnm`, `~/.local/bin`, `~/.local/bin/mise` |
| `TORRENT_DIR`, `SCREENSHOT_LOCATION` | `~/Downloads/transmission`, `~/Pictures/Screenshots` |

The other names `set_env` is called with in the script are internal state, not settings: the switches' own flags (such as `DO_DRIFT` or `DO_DOCTOR`) and working paths (such as
`REQUIRED_FILE`, `INSTALLED_FILE` and `JOURNAL_FILE`). Don't set them.

**Pinning and sources** (see [Installers and pinning](#installers-and-pinning))

| Setting | What it does |
|---|---|
| `BREW_INSTALL_SHA256`, `POSH_INSTALL_SHA256`, `FNM_INSTALL_SHA256`, `RUSTUP_INSTALL_SHA256`, `UV_INSTALL_SHA256`, `MISE_INSTALL_SHA256` | refuse the installer unless it matches |
| `ZINIT_REF`, `RBENV_REF`, `RUBY_BUILD_REF`, `PYENV_REF`, `NERD_FONTS_REF`, `ZOSH_REF`, `P10K_REF` | pin the first clone to a branch, tag or commit |
| `BREW_INSTALL_URL`, `POSH_INSTALL_URL`, `FNM_INSTALL_URL`, `RUSTUP_INSTALL_URL`, `UV_INSTALL_URL`, `MISE_INSTALL_URL` | where the installers come from |
| `SCRIPT_URL`, `UPDATE_URL`, `UPDATE_SHA256` | where `--update` and the update hint look, and an optional checksum for the release |
| `TRANSMISSION_BLOCKLIST_URL` | the [Transmission blocklist](#transmission-blocklist) |

## Prompt

Only one prompt engine is installed and loaded: powerlevel10k (`p10k`, the default), oh-my-posh (`posh`) or neither (`none`). Both at once
hook every prompt and fight over it, and cost time on every login. Set `PROMPT_ENGINE` (for example in the config) to choose, or use `-E posh`
for one run. The setting decides what is installed, what is set up on login and whether the zinit plugin lists load the powerlevel10k plugin.
`-o` and `-T` select oh-my-posh and powerlevel10k for that run, `-A` follows the setting, and if several are given the last wins. `--doctor`
shows the engine and warns if the other one has been switched on.

### Two line prompt

With powerlevel10k the prompt is two lines: a configurable line on top, starting with `user@hostname`, and your existing line below it, as it
was, with its right hand segments:

```
╭─░▒▓ alice@laptop                                                                ─╮
╰─░▒▓    ~/c/project    main !2 ?6                                      ✔  16:15:40  ▓▒░─╯
```

The top line is whatever powerlevel10k segments you name, in the config (the names are the ones in the `LEFT_PROMPT_ELEMENTS` and
`RIGHT_PROMPT_ELEMENTS` lists of `~/.p10k.zsh`, for example `os_icon`, `dir`, `vcs`, `context`, `time`, `status`, `kubecontext`, `aws`):

```
PROMPT_TOP_ELEMENTS="os_icon context"     # the left of the top line (default: context, which is user@hostname)
PROMPT_TOP_RIGHT_ELEMENTS="time"          # the right of the top line (default: nothing)
PROMPT_TWO_LINE=false                     # a single line prompt, as before
```

A segment on the top line is taken off the bottom one, so it is never shown twice, and `context` is shown whatever the user (powerlevel10k hides
it for a default user). It is applied after your `~/.p10k.zsh` is read, so it works on top of whatever that holds, including one made by
`p10k configure`; a config that already has more than one line is yours and is left alone. Names are limited to letters, digits and underscores,
and one that is not is ignored with a warning. If your config has a transient prompt, old prompts still collapse to one line, and the frame
characters are the ones in `~/.p10k.zsh` (`POWERLEVEL9K_MULTILINE_*`). `--doctor` says what the layout is.

#### Prompt settings

Set these in `~/.ussuri/config` (see [Configuration](#configuration)), with `--set` (for example `--set PROMPT_TOP_ELEMENTS "os_icon context"`),
in the environment, or at the top of the script. `--config` writes them commented out.

| Setting | Default | What it does |
|---|---|---|
| `PROMPT_ENGINE` | `p10k` | `p10k`, `posh` or `none`. Only that engine is installed and loaded. The settings below apply to `p10k` only |
| `PROMPT_TWO_LINE` | `true` | `false` keeps a single line prompt: the config's own lines are left exactly as they are |
| `PROMPT_TOP_ELEMENTS` | `context` | Space separated segments on the left of the top line, in the order given |
| `PROMPT_TOP_RIGHT_ELEMENTS` | none | Space separated segments on the right of the top line, in the order given |

The order of a line is the order of the words, first on the left. A segment named in either variable is removed from the bottom line, and a
segment with nothing to show at that moment (no battery, no VPN, not in a project) is skipped rather than leaving a gap.

```
PROMPT_TOP_ELEMENTS="os_icon context"
PROMPT_TOP_RIGHT_ELEMENTS="battery cpu_arch time"
```

#### Segments for the top line

Any powerlevel10k segment name works. Some that suit the top line:

| Segment | Shows | Notes |
|---|---|---|
| `context` | `user@hostname` | always shown on the top line, whatever the user |
| `os_icon` | the operating system's icon | |
| `time` | the current time | format: `POWERLEVEL9K_TIME_FORMAT` |
| `battery` | charge and charging state | low threshold: `POWERLEVEL9K_BATTERY_LOW_THRESHOLD` |
| `wifi` | SSID and link speed | recent macOS versions restrict where the SSID can be read from |
| `ip` | address and bandwidth of one interface | set `POWERLEVEL9K_IP_INTERFACE`: the default pattern (`[ew].*`) matches Linux names, on macOS use `en0` or `en[0-9]+` |
| `public_ip` | external address | makes a network request, so it is slow |
| `vpn_ip` | VPN address, when a VPN interface is up | interfaces: `POWERLEVEL9K_VPN_IP_INTERFACE` |
| `proxy` | system wide http/https/ftp proxy | |
| `load`, `ram`, `swap`, `disk_usage` | system resources | warning levels, for example `POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL` |
| `cpu_arch` | `arm64` or `x86_64` | useful on Apple Silicon with Rosetta |
| `node_version`, `go_version`, `rust_version`, `java_version`, `php_version`, `dotnet_version`, `terraform_version` | tool version | by default only inside a project (`POWERLEVEL9K_*_VERSION_PROJECT_ONLY`) |
| `status`, `command_execution_time`, `kubecontext`, `aws`, `gcloud`, `azure` | as on the bottom line | |

The full list is `LEFT_PROMPT_ELEMENTS` and `RIGHT_PROMPT_ELEMENTS` in `~/.p10k.zsh` (shipped as `files/p10k/p10k.zsh`), including the commented
out ones. A segment's colours and options are in its own `[ segment: ... ]` block further down that file, as `POWERLEVEL9K_<SEGMENT>_*`
variables, and they apply wherever the segment is shown. Because `files/` is replaced by `--update`, put such overrides in your own `~/.p10k.zsh`
rather than in the shipped copy.

## Plugins

The zinit plugin lists are `files/zinit/zinit-turbo.zsh` (the default: the prompt appears first and the other plugins load just after it, about
75 ms sooner) and `files/zinit/zinit.zsh` (`ZINIT_TURBO=false`: everything loads before the prompt). Both load the same plugins in the same order:
powerlevel10k (only when it is the prompt engine), zsh-syntax-highlighting, zsh-completions, zsh-autosuggestions, fzf-tab,
zsh-history-substring-search, forgit and a set of Oh My Zsh snippets (git, sudo, archlinux, aws, kubectl, kubectx, command-not-found).

- **History search.** Type part of a command and press Up or Down to step through the history entries that contain it (the arrow keys are bound for
  both keypad modes).
- **forgit** (https://github.com/wfxr/forgit) gives interactive git commands driven by fzf: add, log, diff, checkout, stash, rebase and more, with
  previews. It defines short aliases, and 16 of them (`ga`, `gd`, `gco`, `gcb`, `gss`, `glo`...) have the same name as aliases in the Oh My Zsh git snippet,
  which would silently change what they do (`gcb` creates a branch, but forgit's `gcb` is an interactive picker). Those 16 are renamed with an `f` in front
  (`fga`, `fgd`, `fgco`, `fgcb`, `fgss`, `fglo`...); your git aliases keep their meaning, and forgit's others (`gi`, `gat`, `gfu`...) keep their names.
  `zsh tests/forgit-aliases.zsh` (needs the network) checks the renames against the current forgit and git snippet, and is worth running when either
  is updated.
- **zoxide** (https://github.com/ajeetdsouza/zoxide) is a smarter `cd`: `z foo` jumps to the directory you use most that matches foo, and `zi` picks
  interactively with fzf. It only adds `z` and `zi`; it does not replace `cd`. It is in the package lists, so `-P` installs it (note that `-P` installs
  every missing package in your lists, not only this one; to install just zoxide use your package manager, for example `brew install zoxide`). A login
  sets it up only if it is installed, so nothing is downloaded on login, and its init output goes through the init cache. `INSTALL_ZOXIDE=false` leaves
  it alone.
- **System specific snippets.** A line that only applies to some systems is written as a one line `if os_is_like arch; then ...; fi`: the Arch aliases
  load only on Arch and its derivatives.
- **Your own plugins** go in `~/.ussuri/files/zinit/local.zsh` (same format, run after the shipped list, never overwritten), with profile and machine
  layers; see [Local files, profiles and machines](#local-files-profiles-and-machines). A plugin added there loads after the shipped list's completions
  step, so one that only ships completion files may need a restart to be picked up.
- **Other managers.** `-m oh-my-zsh` and `-O` use oh-my-zsh instead of zinit; `-Z` sets its theme.

The lists are copied to `~/.ussuri/files` when installed, so a changed shipped list reaches an existing install with `--update` or `--install`.

## History

A login shell keeps 50000 lines of history (macOS defaults to 2000, a bare zsh to 30) in the history file (`~/.zsh_history` unless `HISTFILE` is already
set), shared between shells, and leaves out repeated commands, commands typed with a leading space (a way to keep one out of history) and extra blanks.
Set `HISTORY_SIZE` to change the size, or `DO_HISTORY=false` to leave all of this to the system (`SHARE_HISTORY=false` turns sharing off separately).

### atuin (optional)

[atuin](https://atuin.sh) replaces Ctrl-R with a searchable database of your history (with directory, exit status and duration). It records every command, so it is off
unless you ask: `--tool atuin` once, or `INSTALL_ATUIN=true` in the config. It is installed with Homebrew on macOS and with pacman or nix on Arch and NixOS, the
package managers atuin's documentation lists; elsewhere it tells you to `cargo install atuin --locked`, and sets atuin up once it is there. Its official install script
is never run, as it signs you up to Atuin Cloud. Its init output goes through the init cache (a cache for each set of flags, so changing an option takes effect
at once).

- The up arrow stays with history substring search; atuin gets Ctrl-R. `ATUIN_BIND_UP=true` gives atuin the up arrow as well.
- Existing history is imported once, when building (`--tool atuin` or `--build`; `ATUIN_IMPORT=false` skips it).
- **ussuri never syncs.** It does not register, log in or sync, so your history stays on this machine until you run `atuin register` or `atuin login` yourself.

## PATH and build flags

On a login the script adds `/usr/local/bin`, `/usr/local/sbin`, `/opt/local/bin`, `/opt/local/sbin`, `~/.local/bin` and `~/.cargo/bin` to `PATH` (once, with no
repeats), sets up Homebrew's environment on macOS, and adds `GO_HOME` (and sets `GOPATH`) if that directory exists. It also exports `CPPFLAGS`, `LDFLAGS` and
`PKG_CONFIG_PATH` pointing at the `include`, `lib` and `pkgconfig` directories that exist under `/usr`, `/usr/local`, `/opt/local` and Homebrew's prefix, so builds find
Homebrew's headers and libraries without per-project flags. That makes native builds in your shell depend on what is linked there (a keg-only formula is not,
and a different major version of a library than the system's may be picked up), so they are less hermetic. Turn it off with `DO_CPPFLAGS_CHECK=false`,
`DO_LDFLAGS_CHECK=false` and `DO_PKGCONFIG_CHECK=false` in the config.

## Packages

`-P` (or `DO_PACKAGE_CHECK=true`) installs what is in the package lists for your system that is not installed. The lists are in `files/packages`:
`macos.brew`, `macos.cask`, `macos.tap`, `ubuntu.apt`, `arch.pacman`, `endeavouros.pacman`, `fedora.dnf`, `alpine.apk` and `nix.nix`, one package per
line, with `#` comments. Each package is installed on its own, so one that doesn't exist in your distribution's repositories only fails that package. A
list is only reprocessed when it has changed (it is checksummed), or when you ask with `-P`, and it is only stamped as done once everything in it is installed, so
failures are retried. Note that `-P` installs every missing package in the lists, which on a new machine is a lot.

### macOS: formulae, casks and taps

```
files/packages/macos.tap     taps, added first so a formula from one can be found by its short name
files/packages/macos.brew    formulae
files/packages/macos.cask    casks (applications and fonts), installed with brew install --cask
```

The shipped `macos.tap` and `macos.cask` contain only comments, so nothing is installed or tapped by default. Put your own in
`~/.ussuri/files/packages/local.tap`, `local.brew` and `local.cask` (see below). Each list has its own stamp. A package that is already installed
(casks are in `brew list` too) or a tap that is already there (compared without regard to case) is skipped. brew install falls back to a cask for a name that is not a
formula, so a cask named in the formula list works.

### Linux

The package manager is chosen from the distribution's os-release `ID` and `ID_LIKE`, so derivatives work:

| Manager | Distributions | List |
|---|---|---|
| apt | Ubuntu, Debian, Mint, Pop!_OS... | `ubuntu.apt` |
| pacman | Arch, EndeavourOS, Manjaro... | `arch.pacman` (`endeavouros.pacman`) |
| dnf | Fedora, RHEL, Rocky, Alma... | `fedora.dnf` |
| apk | Alpine | `alpine.apk` |
| nix | NixOS (or any system with `PKG_MANAGER=nix`) | `nix.nix` |

Set `PKG_MANAGER` to override it, such as `nix` on Ubuntu. Root is obtained with `sudo`, or `doas` if there is no sudo, or not at all if you are root, and
nix is never run as root. apt gets its index refreshed once before the first install, and pacman is run with `-S --needed`, never `-Sy`. The dnf, apk and nix
lists are a conservative subset of the apt one, so edit them to taste. The nix installed-package list is read from `nix profile list`, which changed format in
Nix 2.20, so both are handled on a best effort basis.

### Local files, profiles and machines

The shipped lists are replaced by updates and `--install`, so don't edit them. Your own additions go in files that are never touched, and one set of
settings can differ per profile (work, personal) and per machine. A profile (`-M work`, or `PROFILE=work` in the config) and a machine name (`MACHINE`, the
short hostname by default) add layers on top of the common ones, for packages, plugins and dotfiles alike. In `~/.ussuri/files`:

```
packages/local.brew                       every machine (local.cask, local.tap, local.apt, local.pacman, local.dnf, local.apk, local.nix likewise)
packages/profiles/work/local.brew         machines using the work profile
packages/hosts/mybox/local.brew           just the machine called mybox
zinit/local.zsh, zinit/profiles/work/local.zsh, zinit/hosts/mybox/local.zsh      the same, for plugins
```

and `~/.ussuri/dotfiles/{common,profiles/<name>,hosts/<machine>}` for [dotfiles](#dotfiles). Layers are applied in that order and later ones win. For
packages a line `!name` takes a package out of what the earlier layers added (the shipped list included), matched exactly rather than as a pattern, and a later
layer can put it back:

```
# packages/profiles/work/local.brew
!docker
!lftp
```

Adding a package, or switching profile, is noticed on the next login, as every layer and the profile are part of the list's checksum. A profile or machine name is part of
a file path, so one containing a slash or starting with a dot is refused with a warning. `--doctor` shows the profile, the machine and the local lists found.
`DOTFILES_PROFILE` and `DOTFILES_HOST` (the older names) still override them for dotfiles alone.

### Unattended installs

```
./ussuri.zsh -P --yes
```

Package installs are already unattended where the package manager allows it (apt, dnf and pacman are always run with `-y` or `--noconfirm`, and apk, nix and brew
don't ask). `--yes` (or `ASSUME_YES=true`) also turns off what those flags don't cover: apt's debconf dialogs (`DEBIAN_FRONTEND=noninteractive`), the "Press RETURN" wait
in the Homebrew installer (`NONINTERACTIVE=1`), and the script's own `--confirm` prompts, which are answered yes. It can't remove a password prompt: sudo, and Homebrew
casks that run an installer, still ask for your password unless sudo is passwordless for you (`--sudoers` sets that up, see [System settings](#system-settings)).

### Installers and pinning

Installers (Homebrew, oh-my-posh, fnm, rustup, uv, mise) are downloaded to a file and then run, rather than piped into a shell. To verify them, set the expected
SHA-256 before the script runs, for example `BREW_INSTALL_SHA256` (a mismatch is refused); without one they still run, with a notice. Git installs follow the
latest by default; to pin the first clone to a branch, tag or commit set `ZINIT_REF`, `RBENV_REF`, `RUBY_BUILD_REF`, `PYENV_REF`, `NERD_FONTS_REF`, `ZOSH_REF` or
`P10K_REF`. An existing install is never changed. The settings are listed in [Settings](#settings).

### Package drift

```
./ussuri.zsh --drift packages
```

(`--drift` alone is settings and packages, each under a heading.) It compares what is installed with your package lists, every layer of them (local, profile,
machine, with `!name` exclusions applied). It reads only, from live queries to the package manager and never the cached lists:

```
Packages (brew)
  taps added but not in your lists (1):
    example/tap
  formulae not installed (1):
    rust
  casks installed but not in your lists (23):
    firefox iterm2 slack ...

1 packages from your lists are not installed (-P installs them); 59 installed ones are not in your lists (shown for information)
```

What is in a list but not installed is drift (exit status 1), which `-P` would install. What is installed because you chose it (brew leaves and casks,
`apt-mark showmanual`, `pacman -Qe`, dnf userinstalled, the apk world file) but is in no list is only shown, as that is what you would add to a local list to keep it, so a
machine that only has extras is not drift (exit status 0). On macOS a name in the formula list that is installed as a cask counts as installed, as it does for `-P`.
Exit status 2 means there was nothing to compare (no supported package manager, or its tool is not installed).

## Languages and tools

- **rbenv and pyenv** (`-r`, `-p`, on by default for a login): installed from git, their environment set up (with the init output cached). `-b` (or `-r`/`-p`, which imply it)
  builds a version: `RUBY_VER` and `PYTHON_VER`, by default the latest stable (found with `sort -V`, and only looked up when building). Only an installed version is made the
  global one, and `local` is never used, as it writes a version file into whatever directory the shell started in.
- **fnm, rustup, uv and mise** (and [atuin](#atuin-optional)) can be installed and set up too. They are off unless you ask, either once with `--tool NAME` or permanently with `INSTALL_<NAME>=true` in the
  config (on a login they are then installed if missing and set up, and no versions are installed):

  ```
  fnm     Node          FNM_NODE=lts-latest                installed to ~/.local/share/fnm
  rustup  Rust          RUSTUP_TOOLCHAIN_WANTED=stable     installed to ~/.cargo
  uv      Python        UV_PYTHON=3.13                     installed to ~/.local/bin
  mise    many, and a   MISE_TOOLS="node@lts python@3.13"  installed to ~/.local/bin
          replacement for the others (it also reads asdf's .tool-versions)
  ```

  The version settings are only acted on when building (`--tool` or `--build`). The installers are told not to edit your shell files. mise's activation is cached like
  rbenv's; fnm's can't be, as it points at a directory made for each shell. fnm is offered rather than nvm because nvm's init costs hundreds of milliseconds per shell.
- **Fonts** (`-f`): the Fira Code Nerd Font, as a Homebrew cask on macOS and from the nerd-fonts repository on Linux, as the prompt needs it for its icons.
- **zoxide** and **forgit**: see [Plugins](#plugins).

## System settings

### macOS defaults

A login (or `-D`, or `-A`) applies a set of OS X defaults, read first so that only what differs is written: Finder, Dock (including hot corners), screen capture, key repeat and other global
settings, Safari, the App Store and software update, and a few apps' debug menus, with the Library folder unhidden. `TORRENT_DIR` and `SCREENSHOT_LOCATION` set two of the paths. The Dock,
Finder and SystemUIServer are restarted if a change needs it. Reading about a hundred settings takes over a second, so on a login they are only applied when the script has changed since
the last time, after `DEFAULTS_MAX_AGE` days, or when asked for (`-D`, `--force`), tracked by `~/.ussuri/defaults.stamp`. The list is in the script (`set_osx_*_defaults`).

**Undoing.** Every setting the script changes is recorded in `~/.ussuri/defaults.journal` (what it was before, with its type, or that it was not set, and what it was set to), once a read back
shows the write took effect (a write that was declined, refused or ignored isn't recorded). A run is one apply.

```
./ussuri.zsh --defaults-undo list
./ussuri.zsh --defaults-undo [N]
```

`list` shows the runs, and `--defaults-undo` puts back the newest (or the Nth newest, 1 being the newest), each setting exactly as it was, with the same type, or deleted if it was not set. A
setting you changed yourself since is left alone and reported, as is one whose previous value was an array or dictionary (those can't be put back from the journal). The Dock and Finder are
restarted if needed. A run that has been undone is marked, so the next undo goes back one run. `--dryrun` shows what would be put back, and `--confirm` is honoured (and, as some may be declined,
leaves the run to be undone again). Only changes made from version 1.5.7 on are recorded, and it covers OS X defaults, not the Linux GNOME settings or the Library folder's hidden flag.

**Drift.** `--drift settings` reads every setting the script would apply and prints the ones that differ, as actual -> expected and grouped by domain, then a summary. It writes nothing and exits 1 if
there is drift:

```
com.apple.dock
  tilesize                                 48 -> 32
  autohide-delay                           (not set) -> 0.2

2 of 105 settings differ from what ussuri would apply. Run --defaults to apply them.
```

### Transmission blocklist

On macOS the script sets Transmission's blocklist to Bluetack's Level 1 list as served by iblocklist.com over HTTPS (the list Transmission itself used to ship, refreshed daily), with
auto-update on. Set `TRANSMISSION_BLOCKLIST_URL` to use another one. The URL is checked before it is written, and an unreachable one is reported and not written, so it never replaces a working setting.
Neither the list nor the service is endorsed by the Transmission developers, and Level 1 blocks the address ranges of organisations known for anti-filesharing activity, so decide for yourself whether you want it.

### Linux (GNOME)

On Linux, `--defaults` applies a short list of GNOME settings through `gsettings` (keyboard repeat, show hidden files and directories first in file choosers, list view in Files, button layout, privacy
clean-up and so on), and `--drift` reports where they differ. A setting that doesn't exist on your desktop is skipped, and nothing is done without `gsettings` and a desktop session (without a session
bus `gsettings` only writes to a throwaway store). Unlike on macOS these are not applied on every login unless you set `DO_GNOME_DEFAULTS=true`. The list is `apply_linux_defaults` in the script.

### sudoers

`-s` (`DO_SUDOERS_CHECK`) installs a sudoers entry for your user, by default `ALL=(ALL) NOPASSWD:ALL` (`-S` or `SUDOERS_ENTRY` changes it), in `/etc/sudoers.d/<you>`. It is off by default. The entry is
checked with `visudo -cf` before it is installed (so a bad one can't break sudo), installed mode 0440, and only if sudo doesn't already allow it (the check is made without a password prompt).
That default gives your user passwordless root, so think before using it.

## Dotfiles

```
./ussuri.zsh --dotfiles [--profile work]
```

Links dotfiles from `~/.ussuri/dotfiles` into your home directory, in layers so one set can differ per machine. Later layers win for the same path:

```
~/.ussuri/dotfiles/common/.gitconfig               every machine
~/.ussuri/dotfiles/profiles/work/.gitconfig        machines using the "work" profile
~/.ussuri/dotfiles/hosts/mybox/.gitconfig          only the machine whose short hostname is mybox
```

A file at `<layer>/.config/app/conf` is linked as `~/.config/app/conf`. The profile comes from `--profile` or `PROFILE` (or `DOTFILES_PROFILE`), the host from `MACHINE` (or `DOTFILES_HOST`;
default is the short hostname), and the directory from `DOTFILES_DIR`. Nothing is ever deleted: a real file (or a link pointing somewhere else) that is in the way is moved to
`~/.ussuri/dotfile-backups/<date>/` first. Running it again changes nothing, `--dryrun --verbose` shows what it would do, and `--unlink` removes only the links that point into the dotfiles directory (backups are
left for you to restore by hand). It runs only when asked, unless you set `DO_DOTFILES_CHECK=true` to keep the links in place on every login. File names are treated as plain text, whatever is in them.

## Maintenance

### Updating

```
./ussuri.zsh --update
```

Downloads the release archive from GitHub (one request, the script and its `files/`), checks the script parses and is the version expected, saves the current script in `~/.ussuri`, replaces it, and then
brings `~/.ussuri/files` up to date: new files are added and changed ones replaced, with the copy that is replaced first saved in `~/.ussuri/files.bak/<date>/`, so an edit of yours is never lost.
Nothing is deleted, and your `local.*` files are never touched. It refuses an archive that fails the checks (a script that doesn't parse, paths that would escape the target, or a checksum that doesn't match
`UPDATE_SHA256` if you set one), and if the archive can't be fetched it updates the script alone and says the supporting files were not updated. `UPDATE_URL` points it somewhere else. It updates the script you
ran: run it from `~/.zshrc`, or run `--install` after updating a checkout. `--check` only compares versions.

**Update hint.** `UPDATE_HINT=true` (off by default, because it contacts GitHub from your shell) checks at most once a day, in the background (a disowned job with its output detached, so a login never waits for it), and records
the latest version in `~/.ussuri/update.latest`. When that is newer than your script, one line is shown at the next prompt, at most once a day:

```
ussuri 1.7.0 is available (this is 1.6.4): run ussuri.zsh --update  (UPDATE_HINT=false turns this off)
```

It is shown from a prompt hook after startup finishes, not during it, as output during startup upsets powerlevel10k's instant prompt. A normal login does no extra work for it: two checks of stamp files and one small file
read. Only interactive logins check (never a manual run), a damaged or unexpected answer is ignored, and several shells opened together start one check.

### Backups, rollback and uninstall

```
./ussuri.zsh --backups
./ussuri.zsh --rollback [N]
./ussuri.zsh --uninstall
```

`--install` saves your current `~/.zshrc` in `~/.ussuri` before replacing it (two installs in the same second keep both). `--backups` lists them, newest first, with the version of each and whether it is ussuri or a
`.zshrc` of your own. `--rollback` puts one back (N is the number from `--backups`, a file name, or nothing for the newest). `--uninstall` goes back to the `.zshrc` you had before ussuri: the newest backup that isn't ussuri
itself, or, if you had none, it moves ussuri's aside. Either way the `.zshrc` being replaced is saved first, so a rollback can itself be undone. Installed components and the backups in `~/.ussuri` are left alone, and
`--unlink` removes dotfile links. All of them honour `--dryrun`.

### Doctor

```
./ussuri.zsh --doctor
```

Checks the shell, tools, install (the `.zshrc` version, support files, the lists and the local ones), config, profile and machine, lock, components, fonts, backups and state (defaults stamp, journal, init cache, PATH, the update
hint), and prints `ok`, `warn` or `FAIL` for each. A warning is something that will probably fix itself on the next login or is worth a look, a failure is something that will not. It exits non-zero if there are
any failures, and it never changes anything (a missing directory is reported, not recreated).

## Security notes

- Installers are downloaded to a file, optionally checked against a SHA-256, and only then run; nothing is piped into a shell. Git installs can be pinned.
- Every path, name and version that goes into a command is quoted, and values read back from the defaults journal and the dotfile names are never evaluated. Profile and machine names and prompt segment names are validated.
- `--update` refuses an archive with an unsafe path or a wrong checksum, never deletes anything, and keeps a copy of every file it replaces.
- Anything that contacts the network on a login (the update hint) is off by default, runs in the background and never blocks. `--drift`, `--doctor`, `--help` and `--version` change nothing.
- `~/.ussuri/config` is executed on every shell, so it should be writable only by you. `--set` saves a value quoted and never runs it, and replaces the file with one rename. A sudoers entry with `NOPASSWD:ALL` gives your user passwordless root.
- What the script writes outside `~/.ussuri` and your dotfiles is what you enable: the OS X defaults and Transmission blocklist, GNOME settings, packages, language managers, a sudoers file, and `~/.zshrc` itself. Each has an undo
  or a backup, except installed packages.

## Testing and CI

```
zsh tests/smoke.zsh [name-filter]
zsh tests/package-names.zsh [-v]
zsh tests/forgit-aliases.zsh        # needs the network, see Plugins
```

The smoke tests run against a copy of the script in a throwaway home directory with the system commands (`defaults`, `brew`, `sudo`, `rbenv`, `pyenv`, the package managers...) stubbed, so they do not touch the real system.
They pretend to be macOS whatever the host is (`TEST_OS=linux` and `TEST_OS_REL` change that), and `TEST_PATH_PREFIX` goes in front of the sandbox's `PATH`, to try another userland, for example GNU tools on a Mac:
`TEST_PATH_PREFIX=/opt/homebrew/opt/coreutils/libexec/gnubin: zsh tests/smoke.zsh`. Where a stub can't show it, a few things were also checked by hand against the real thing (the real Homebrew, the real `defaults` on a
scratch file, a real terminal for the prompt, plugins and hint).

`tests/package-names.zsh` checks that every package named in the shipped list for this system exists in its repositories (`apt-cache`, `pacman -Si`, `dnf repoquery`, `apk search` or `brew info`), installing nothing. It needs a fresh
package index, and it is how a wrong name in a list is found before `-P` fails on it.

`.github/workflows/ci.yml` runs the smoke tests and the name check on macOS and Ubuntu runners, and on Debian, Ubuntu, Fedora, Arch and Alpine in containers, where it also runs `--install`, `--doctor` and `--drift packages` for real, as those are the
paths the smoke tests can only check against stubs. Nothing in it installs packages from your lists or changes the runner. The actions are pinned to a major version (`actions/checkout@v4`), not to a commit.

What is checked only against stubs so far is the Linux package managers and their drift queries, the package names for everything but Homebrew, the GNOME settings and the fnm, rustup, uv and mise installers; the workflow is how those get checked on
real systems.

## Files and directories

```
~/.zshrc                      the installed script (ussuri.zsh)
~/.p10k.zsh                   your powerlevel10k config (copied from files/p10k on install if it is missing)
~/.ussuri.lock                the lock (a directory, present only while a run holds it)
~/.ussuri/
  config                      your settings (--config creates it, --set and --unset edit it)
  config.<date>               the newest ten copies of it from before a --set or --unset
  files/                      the shipped lists, copied from the repository (replaced by --update and --install)
    packages/  zinit/  p10k/  local.* files in here are yours and are never touched
  files.bak/<date>/           files --update replaced
  .zshrc.<date>               backups of ~/.zshrc (--backups lists them)
  dotfiles/  dotfile-backups/ your dotfile layers, and what linking moved aside
  cache/                      cached tool init output
  defaults.stamp  defaults.journal    when the defaults were applied, and what they were before
  brew.list  brew.taps  apt.list ...  what is installed, as of the last package check
  <list>.sum                  checksums of the package lists, so only a changed one is reprocessed
  update.check  update.latest  update.hinted    the update hint's state
~/.zinit  ~/.rbenv  ~/.pyenv  ~/.oh-my-posh  ~/.powerlevel10k       components, when installed
```

## License

This software is licensed as CC BY-NC-SA (Creative Commons Attribution-NonCommercial-ShareAlike)

https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode

See CHANGELOG.md for what changed in each version.
