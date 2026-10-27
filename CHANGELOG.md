# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.5.4] - 2026-10-27

### Added

- -y|--yes|--assume-yes (ASSUME_YES=true, e.g. in the config): never prompt. Package installs were already unattended where possible (apt -y, dnf -y, pacman --noconfirm; apk, nix and brew don't ask), so this covers what those don't: apt's debconf dialogs (DEBIAN_FRONTEND=noninteractive, passed through sudo with env), the Homebrew installer's wait for RETURN (NONINTERACTIVE=1, which doesn't leak into your shell), and the script's own --confirm prompts, which are answered yes (even with no terminal). Without it nothing changes. It can't remove a password prompt: sudo, and Homebrew casks that run an installer

## [1.5.3] - 2026-10-27

### Added

- zoxide (a smarter cd: z and zi) in every package list (macos.brew, ubuntu.apt, arch.pacman, endeavouros.pacman, fedora.dnf, alpine.apk, nix.nix), and check_zoxide_config, which sets it up on login only if it is installed (a login never downloads anything), through the init cache since its init output is the same every time. INSTALL_ZOXIDE=false turns it off. --doctor says if it isn't installed
- register_zoxide_completion: zoxide registers its completion only if compdef exists when it is set up, and in turbo mode that is before compinit has run, so z would have had no completion. The turbo plugin list now registers it right after compinit. Checked in a real terminal (pty) using zoxide's documented guard: registered in turbo mode, and nothing breaks without zoxide. The eager list is unaffected, as compinit has run by then

## [1.5.2] - 2026-10-27

### Added

- forgit (wfxr/forgit) in both plugin lists: interactive git commands driven by fzf, which is in every package list. 16 of its default aliases (ga, gbd, gbl, gcb, gcf, gclean, gco, gcp, gd, glo, grb, grh, grs, gss, gsw, gwt) have the same name as aliases in the Oh My Zsh git snippet, so they are renamed with an f in front (fga, fgd, fgcb...) before it loads, to leave the git aliases' meanings alone. Checked in a real terminal session (pty): gcb is still git checkout -b, fgcb is forgit's, gi and gat (no clash) keep their names
- tests/forgit-aliases.zsh (needs the network): checks the renames against the current forgit and git snippet and fails if one clashes without being renamed, is renamed without clashing, or the new name clashes itself. Tried against a deliberately broken copy to confirm it fails

## [1.5.1] - 2026-10-27

### Added

- zsh-history-substring-search in both plugin lists, after zsh-syntax-highlighting as its README requires: type part of a command and press Up or Down to step through the history entries containing it. Checked in a real terminal session (pty) with both arrow key sequences. bind_history_search binds Up/Down for the usual escape sequences and terminfo's, and skips duplicates (to match hist_find_no_dups). In turbo mode the keys are bound once the plugin has loaded, as its widgets don't exist before. (The plugin README's suggested _history_substring_search_config function no longer exists, so it isn't used.) Existing installs need --install to refresh their copy of the lists

## [1.5.0] - 2026-10-27

### Added

- History settings: HISTSIZE and SAVEHIST are raised to HISTORY_SIZE (default 50000, from the system's 2000 on macOS or zsh's 30), HISTFILE is set to ~/.zsh_history if nothing has set it (without one nothing is saved), and repeated commands, commands with a leading space and extra blanks are left out (hist_ignore_dups, hist_ignore_space, hist_find_no_dups, hist_reduce_blanks). DO_HISTORY=false leaves it all to the system. Sharing between shells is unchanged and still controlled by SHARE_HISTORY

## [1.4.9] - 2026-10-27

### Changed

- The Oh My Zsh archlinux snippet (Arch and pacman aliases) is loaded only on Arch and its derivatives (Manjaro, EndeavourOS...), not on every system. It is a one line `if os_is_like arch; then ...; fi` in both plugin lists. The copies in ~/.ussuri/files are not updated automatically: run --install again to refresh them (this replaces them)

### Added

- os_is_like: whether this Linux distribution is, or is derived from, the given one (os-release ID or a word in ID_LIKE)

### Fixed

- Found while writing os_is_like: subscripting a nested `${${=VAR}[(Ie)word]}` in zsh searches inside one string, so "arch" would have matched a word that merely contains it. It goes through an array instead

## [1.4.8] - 2026-10-27

### Changed

- The Transmission blocklist is now Bluetack's Level 1 list from iblocklist.com over HTTPS. The previous default, http://john.bitsurge.net/public/biglist.p2p.gz, no longer answers (and was plain HTTP), so Transmission had never been able to load a blocklist
- It is a setting, TRANSMISSION_BLOCKLIST_URL (for example in the config)

### Added

- url_reachable: the blocklist URL is checked before it is written. An unreachable one is reported (without needing --verbose) and not written, so it can't replace a working setting. A setting that already matches isn't checked, so there is no network access once it is set
- --drift shows the old URL as moving to the new one

## [1.4.7] - 2026-10-27

### Added

- Language managers fnm (Node), rustup (Rust), uv (Python) and mise (many languages, a replacement for the others). Off unless INSTALL_<NAME>=true (e.g. in the config) or -W|--tool NAME. Each is installed if missing (from FNM_INSTALL_URL etc, verifiable with FNM_INSTALL_SHA256 etc, told not to edit your shell files) and set up; versions (FNM_NODE, RUSTUP_TOOLCHAIN_WANTED, UV_PYTHON, MISE_TOOLS) are only installed when building, never on a login
- mise's activation goes through the init cache. fnm's env points at a per-shell directory so it can't be cached
- --doctor reports tools that are wanted but not installed, and says nothing about the ones that aren't

## [1.4.6] - 2026-10-27

### Added

- Package managers: dnf (Fedora, RHEL, Rocky, Alma...), apk (Alpine) and nix (NixOS, or anywhere with PKG_MANAGER=nix), with package lists files/packages/fedora.dnf, alpine.apk and nix.nix. Debian and Arch derivatives (Mint, Pop!_OS, Manjaro...) are now supported too
- The distro is mapped from os-release ID and ID_LIKE to PKG_MANAGER, which can be set beforehand to override it
- doas is used if there is no sudo, and neither if you are root. nix is never run through sudo

### Changed

- Everything that differs between package managers is in one place (set_pkg_manager: tool, list, installed-list command, index refresh, install command) instead of LSB_ID checks spread over seven functions. LSB_ID is now just a name for messages
- --doctor checks the distro's own package manager and says how to choose one on an unsupported distro

## [1.4.5] - 2026-10-27

### Added

- Linux defaults: check_linux_defaults is no longer a stub. apply_linux_defaults sets a short list of GNOME settings through gsettings (set_linux_default), skipping any schema or key that doesn't exist on the desktop, and doing nothing without gsettings and a desktop session (without a session bus gsettings writes to a throwaway store). Applied by --defaults, or on login if DO_GNOME_DEFAULTS=true (off by default, unlike OS X), with the same stamp as OS X so it is not repeated
- --drift works on Linux for the same settings
- --doctor checks for gsettings and a desktop session on Linux
- USSURI_OS (darwin or linux) overrides the detected OS, so the Linux code can be exercised anywhere

### Changed

- The "is it time to apply the defaults" test is shared between OS X and Linux (defaults_due)

## [1.4.4] - 2026-10-27

### Added

- -G|--drift reports every OS X setting that differs from what ussuri would apply, as "actual -> expected" grouped by domain (booleans as true/false, missing ones as "(not set)"), with a summary and exit status 1 if there is any drift. It reads only. It reuses the settings lists, so there is no second copy to keep in step
- is_read_only, used by --doctor and --drift, so a read only mode never creates directories or copies files

## [1.4.3] - 2026-10-27

### Added

- -B|--backups lists the .zshrc backups made by --install, newest first, with the version of each and whether it is ussuri or another .zshrc
- -R|--rollback [N] restores a backup (a number from --backups, a file name, or the newest if none is given)
- -X|--uninstall goes back to the .zshrc from before ussuri (the newest backup that isn't ussuri), or moves ussuri's aside if there is none. Installed components and backups are left alone
- The .zshrc being replaced is saved first, so a rollback can be undone. All three honour --dryrun and --confirm

### Fixed

- Two installs in the same second no longer overwrite each other's backup (backup_zshrc picks a unique name)

## [1.4.2] - 2026-10-26

### Added

- Dotfile linking with machine profiles. -L|--dotfiles symlinks files from ~/.ussuri/dotfiles into the home directory in layers (common, then profiles/<name> from -M|--profile or DOTFILES_PROFILE, then hosts/<short hostname> from DOTFILES_HOST), later layers winning for the same path. A real file or a link to somewhere else that is in the way is moved to ~/.ussuri/dotfile-backups/<date>/ first, never deleted. It is idempotent, honours --dryrun and --confirm, treats odd file names as plain text, ignores .DS_Store and .gitkeep, and only runs when asked unless DO_DOTFILES_CHECK=true is set (for example in the config)
- -u|--unlink removes only the links that point into the dotfiles directory
- --doctor reports dotfiles that are not linked yet and real files standing in their way
- The config template lists the dotfile settings

## [1.4.1] - 2026-10-26

### Added

- ~/.ussuri/config (or the file named by USSURI_CONFIG): an optional zsh file sourced before any defaults are set, so settings can be changed for every shell without editing the script. Precedence is the built in defaults, then the environment, then the config, then command line switches
- -k|--config creates the config with every setting commented out (never overwrites an existing one, honours --dryrun) and says where it is
- --doctor checks the config for a syntax error and for being writable by others (it is executed)

### Changed

- GO_HOME and START_DIR can now be set before the script assigns them, so they work in the config too

## [1.4.0] - 2026-10-26

### Added

- -x|--doctor: read only checks of the shell, tools, install (~/.zshrc version, support files), lock, components, fonts, backups and state, printing ok/warn/FAIL for each with a summary and a non-zero exit status if anything failed. It never changes anything: check_dir_exists and the support file copies skip themselves in doctor mode
- read_file_version reads the version header from any file

## [1.3.9] - 2026-10-26

### Added

- Turbo mode zinit plugin list (files/zinit/zinit-turbo.zsh), now the default: powerlevel10k loads straight away and the other plugins and snippets load just after the first prompt, with compinit once at the end so every completion is still registered. Same plugins in the same order as zinit.zsh. Measured about 140ms to 65ms to first prompt. ZINIT_TURBO=false uses zinit.zsh

### Changed

- An install from before turbo mode has no turbo plugin list: it is copied from next to the script if possible (just that file, nothing is overwritten), otherwise the original list is used instead of loading no plugins. Run --install again to add it
- The cached pyenv init leaves out the line that forks bash to remove duplicates from PATH (typeset -U path already does that)
- Lazy-loading wrappers for rbenv and pyenv were not added: with the init output cached, rbenv init costs about 0.1ms and pyenv's remaining cost was that bash fork

## [1.3.8] - 2026-10-26

### Added

- tests/smoke.zsh, a sandboxed smoke test suite (throwaway home directory, stubbed system commands, a copy of the script pointed at a stub brew)
- have_lock, is_osx and is_linux guards, and copy_support_files

### Changed

- The HOLD_LOCK and OS_NAME checks use the guards, and the deepest nests (package checks, check_osx_defaults, do_install) are flattened with early returns
- The support file copy, which was pasted in three places, is one function that also checks the work directory exists before copying

## [1.3.7] - 2026-10-26

### Added

- Installers (Homebrew, oh-my-posh) are downloaded to a file, checked against BREW_INSTALL_SHA256 / POSH_INSTALL_SHA256 when set (a mismatch is refused), and only then run, instead of being piped into a shell. The URLs can be overridden with BREW_INSTALL_URL / POSH_INSTALL_URL. Without a checksum they still run, with a notice
- Git installs (zinit, rbenv, ruby-build, pyenv, nerd-fonts, oh-my-zsh, powerlevel10k) can be pinned to a branch, tag or commit with ZINIT_REF, RBENV_REF, RUBY_BUILD_REF, PYENV_REF, NERD_FONTS_REF, ZOSH_REF and P10K_REF. Unset keeps the current behaviour (latest), and a pin only applies to the first clone

## [1.3.6] - 2026-10-26

### Changed

- Short switches can now be bundled (for example -vt)
- Command line switches are parsed with zparseopts (long switches are translated to short ones first), so unknown switches and switches missing their value are rejected up front with the usage text and a non-zero exit status, and a value that looks like a switch is treated as a value

### Fixed

- A switch that takes a value (-g, -l, -m, -S, -Z) given without one no longer loops forever

## [1.3.5] - 2026-10-26

### Fixed

- Paths, names and versions interpolated into commands run through execute_command are now quoted (${(q)var}), so spaces, quotes or a command substitution in a path (for example a home directory name) are treated as plain text instead of being re-evaluated or breaking the command

## [1.3.4] - 2026-10-26

### Changed

- PATH is kept free of duplicates with typeset -U path, and exp_env adds to the path array instead of splitting strings
- Command lookups use $commands (no subshell) instead of command -v

## [1.3.3] - 2026-10-26

### Fixed

- --confirm now shows the command in the prompt (it was only shown with --verbose, so you were asked to confirm something you couldn't see)
- --confirm uses read instead of vared, and says so (instead of silently skipping) when there is no terminal to confirm on

## [1.3.2] - 2026-10-26

### Changed

- The per-shell bootstrap no longer forks: id, whoami, hostname, date, pwd, uname, dirname, cut, grep and awk are replaced by zsh builtins and parameter expansion (OS_NAME comes from OSTYPE; uname -r is only run when applying OS X defaults)
- The Linux distribution is read from /etc/os-release instead of running lsb_release (which is slow and often not installed); lsb_release is still used as a fallback. OS_RELEASE_FILE can override the path
- The script version is read in the shell instead of with grep and awk
- The lock uses zsh/files mkdir and rm builtins and a glob qualifier for the stale check instead of find, mkdir and rm (falls back to the commands if the module isn't available)
- Installed package lookups use an array loaded once instead of forking grep per package, and the package list is only read when it is processed rather than on every shell
- find_brew uses :h instead of dirname

## [1.3.1] - 2026-10-26

### Added

- cached_eval caches the output of rbenv init, pyenv init and brew shellenv (about 250ms each) in ~/.ussuri/cache, and rebuilds it when the tool's binary is newer than the cache. The rehash line is left out of the cache as it forks the tool on every shell. DO_CACHE_INIT=false turns this off

## [1.3.0] - 2026-10-26

### Changed

- OS X defaults are only applied when asked (-D, -A or --force), when the script is newer than the last run, or after DEFAULTS_MAX_AGE days (default 7), tracked by ~/.ussuri/defaults.stamp. Previously every new shell ran defaults read about a hundred times (around 1.3 seconds)

## [1.2.9] - 2026-10-26

### Fixed

- The files/ copy no longer unpacks into the current directory when the work directory does not exist yet (cd ... ; tar became cd ... && tar)

## [1.2.8] - 2026-10-26

### Added

- --update now actually updates the script: it downloads the new version, checks it parses and is the expected version, backs up the current script and replaces it (honours --dryrun and --confirm)

### Changed

- exp_env matches whole entries instead of substrings and no longer uses eval
- LD_LIBRARY_PATH is no longer set on macOS
- The version check uses curl -fsSL, validates the remote version and shares code with the updater
- The "Instantiated by" banner is only shown with --verbose
- Switch pre-scans (-F, -I, -v) match whole arguments instead of substrings

### Fixed

- A failed remote version lookup no longer causes an integer comparison error
- Removed duplicate Finder defaults

## [1.2.7] - 2026-10-26

### Added

- notice_message prints a message even when not verbose, used before slow or interactive installs so the shell doesn't look hung
- "show" option for execute_command to keep command output visible when not verbose (installers, sudo, builds)

## [1.2.6] - 2026-10-26

### Changed

- The sudoers check is off by default for manual runs (it was on, so any manual run could modify sudoers)
- Sudoers entries are validated with visudo and installed with mode 0440 instead of appended with tee, and the check no longer prompts for a password unless a change is needed

## [1.2.5] - 2026-10-26

### Added

- Package list changes are detected with a checksum stamp; -P and -A always process the list

### Fixed

- Package matching uses fixed strings (no regex surprises with g++), ignores tap prefixes, and no longer errors when the installed list is missing
- pacman now uses -S --needed instead of -Sy, and apt-get update runs once before installs
- Failed package installs are retried rather than marked done
- The installed package list code is no longer duplicated

## [1.2.4] - 2026-10-26

### Fixed

- The Homebrew installer is no longer downloaded during --dryrun
- Homebrew discovery is shared in find_brew (and also checks /usr/local/bin/brew); PATH is no longer set from an empty prefix

## [1.2.3] - 2026-10-26

### Changed

- rbenv/pyenv only look up the latest version when building, pick it with sort -V (stable releases only), and only set an installed version as global

### Fixed

- pyenv ran "global" for local version messages and printed the ruby version
- rbenv local wrote .ruby-version into the current directory (neither tool now uses local)

## [1.2.2] - 2026-10-26

### Fixed

- Removed the nonexistent files/defaults/macos.defaults check that copied files/ on every shell start
- A missing package list no longer causes an error when it is read (blank lines and comments are also ignored)

## [1.2.1] - 2026-10-26

### Changed

- The lock is now an atomic directory (mkdir) and is released on every exit path

### Fixed

- --force now removes the lock file (it never did, as dryrun state was unset at that point)
- The lock is no longer left behind by --help, --version, --install, --update, --changelog, --dryrun or X11 shells

## [1.2.0] - 2026-10-26

### Fixed

- oh-my-posh init and brew shellenv output is now evaluated instead of discarded

## [1.1.9] - 2026-10-26

### Fixed

- set_env only exports GOPATH, so a login shell no longer leaks its DO_* flags into manual runs and nested shells

## [1.1.8] - 2026-10-26

### Changed

- set_env no longer overrides a variable that is already set (pass "force" as a third argument, or set SET_ENV_FORCE=true, to override), so switches and top-of-script overrides take precedence over defaults
- set_env uses typeset instead of eval

## [1.1.7] - 2026-10-26

### Changed

- Command line arguments are now parsed before set_defaults runs
- OS X defaults are now applied by check_osx_defaults (under the lock, when defaults check is enabled) rather than during set_defaults

### Fixed

- --dryrun and --confirm are now honoured for OS X defaults, directory creation and chflags
- --help and --version no longer write OS X defaults

## [1.1.6] - 2026-09-30

### Changed

- Set the user's cargo path in the environment

### Fixed

- set_env now actually sets an environment variable

## [1.1.5] - 2026-09-29

### Fixed

- Final `cd` to the start directory no longer errors when the directory doesn't exist; falls back to the initial directory like the earlier check does

## [1.1.4] - 2026-09-29

### Fixed

- `-F/--force` now actually clears a stale lock file: the check is pre-scanned before the lock file is evaluated instead of running (with `DO_FORCE` unset) before argument parsing

## [1.1.3] - 2026-09-29

### Fixed

- Main dispatch guard now matches the same X11/XQuartz detection used for OS detection, instead of an inconsistent exact-string comparison

## [1.1.2] - 2026-09-29

### Fixed

- `-O/--ohmyzsh` now installs and configures oh-my-zsh: fixed `check_zosh_config`'s variable name (`INSTALL_OZSH`) and wired the function into the main dispatch

## [1.1.1] - 2026-09-29

### Fixed

- Missing brace in the package-installed check for Linux and macOS packages so `-P/--packages` actually installs missing packages

## [1.1.0] - 2026-09-29

### Fixed

- `set_env` no longer clobbers pre-set environment variables on every run; overrides declared before the script runs are now respected for all variables, not just `DO_VERBOSE`/`WORK_DIR`

## [1.0.12] - 2026-09-21

### Added

- Missing help entries for -g/--gopath, -s/--sudoers and -S/--sudoersentry

## [1.0.11] - 2026-09-21

### Fixed

- -F/--force help text and made stale lock file removal actually execute

## [1.0.10] - 2026-09-21

### Added

- Wired up -C/--check and -U/--update flags to trigger check_for_update and update_script

## [1.0.9] - 2026-09-21

### Added

- update_script function to fetch and compare remote version via curl or wget

## [1.0.8] - 2026-09-21

### Fixed

- Malformed test expression for brew check

## [1.0.7] - 2026-09-21

### Fixed

- -s/--startdir help text mismatch by documenting -l/--location instead

## [1.0.6] - 2026-09-21

### Fixed

- --notheme option typo preventing it from being recognized

## [1.0.5] - 2026-09-21

### Fixed

- Package check flag always running regardless of setting

## [1.0.4] - 2026-09-01

### Added

- Instantiation information

## [1.0.3] - 2026-07-24

### Changed

- Improved determination of what is calling shell

## [1.0.2] - 2026-05-14

### Changed

- Improved environment updates

## [1.0.1] - 2026-05-14

### Added

- LDFLAGS check

## [1.0.0] - 2026-05-14

### Added

- CPPFLAGS check

## [0.9.9] - 2026-05-14

### Added

- pkgconfig check

## [0.9.8] - 2026-05-15

### Fixed

- Additional fixes for XQuartz check

## [0.9.7] - 2026-05-14

### Added

- Check to see if being called from XQuartz

## [0.9.6] - 2025-12-18

### Added

- /opt/local to PATH and LD_LIBRARY_PATH

## [0.9.5] - 2025-07-10

### Added

- Option to incrementally update history and share across sessions

## [0.9.4] - 2025-07-09

### Fixed

- Fixes for MacOS 25 Tahoe

## [0.9.3] - 2025-07-04

### Changed

- Improvements

## [0.9.2] - 2025-06-18

### Fixed

- Bug fixes

## [0.9.1] - 2025-06-18

### Changed

- Code cleanup and improvements

## [0.9.0] - 2025-04-08

### Added

- Check to see files directory exists

## [0.8.9] - 2025-03-29

### Fixed

- Issue with running inline and script dir being set to /usr/bin

## [0.8.8] - 2025-03-25

### Fixed

- Bug fixes

## [0.8.7] - 2025-03-25

### Added

- Support for Arch/Endeavour Linux

## [0.8.6] - 2025-01-03

### Fixed

- Determining calling script when running inline

## [0.8.5] - 2024-12-08

### Changed

- Disabled package install for inline mode

## [0.8.4] - 2024-11-25

### Changed

- More improvements for pyenv/rbenv

## [0.8.3] - 2024-11-21

### Changed

- Improvements for pyenv/rbenv

## [0.8.2] - 2024-11-09

### Fixed

- Find command

## [0.8.1] - 2024-11-07

### Fixed

- Issue with brew environment not being set

## [0.8.0] - 2024-11-07

### Changed

- Improved lock file check

## [0.7.9] - 2024-11-03

### Added

- Code to create lock and only run one session of updates/installs

## [0.7.8] - 2024-10-26

### Changed

- Updated OSX defaults method

## [0.7.7] - 2024-10-25

### Changed

- Improved package list update code

## [0.7.6] - 2024-10-25

### Added

- Code to expand variable

## [0.7.5] - 2024-10-25

### Changed

- Cleaned up environment variable handling

## [0.7.4] - 2024-10-25

### Added

- Check for ruby/python version using rbenv/pyenv and ability to override

## [0.7.3] - 2024-10-24

### Changed

- Expanded environment override capability

## [0.7.2] - 2024-10-24

### Fixed

- Package check on Ubuntu Linux

## [0.7.1] - 2024-10-24

### Added

- Ability to override some defaults and set inline defaults in non inline mode with --inline

## [0.7.0] - 2024-10-24

### Added

- libyaml-dev package for building ruby and improved package list creation on Ubuntu

## [0.6.9] - 2024-09-20

### Added

- Sudoers option

## [0.6.8] - 2024-09-20

### Changed

- Improved startdir option

## [0.6.7] - 2024-09-06

### Fixed

- rbenv/pyenv init

## [0.6.6] - 2024-08-09

### Changed

- Updated defaults processing

## [0.6.5] - 2024-08-08

### Fixed

- pyenv and rbenv install

## [0.6.4] - 2024-08-08

### Added

- -A/--doall switch and fixed p10k init

## [0.6.3] - 2024-08-08

### Fixed

- Packaged install check

## [0.6.2] - 2024-08-08

### Changed

- Set INSTALL_BREW to true for inline execution

## [0.6.1] - 2024-08-08

### Added

- Check for required packages file existing

## [0.6.0] - 2024-08-03

### Changed

- Updated p10k config

## [0.5.9] - 2024-08-03

### Changed

- Updated powerlevel10k setup

## [0.5.8] - 2024-08-03

### Fixed

- Inline script file determination

## [0.5.7] - 2024-08-03

### Fixed

- More fixes for install function

## [0.5.6] - 2024-08-02

### Fixed

- Install function

## [0.5.5] - 2024-07-31

### Fixed

- Running inline

## [0.5.4] - 2024-07-31

### Fixed

- Bug fixes

## [0.5.3] - 2024-07-31

### Added

- Set start directory

## [0.5.2] - 2024-07-31

### Fixed

- More fixes for initial environment setup

## [0.5.1] - 2024-07-31

### Fixed

- Bug with package list creation

## [0.5.0] - 2024-07-31

### Fixed

- Environment setup

## [0.4.9] - 2024-07-30

### Added

- Code to install fonts on Linux

## [0.4.8] - 2024-07-30

### Fixed

- Read from file

## [0.4.7] - 2024-07-30

### Fixed

- Package list processing

## [0.4.6] - 2024-07-30

### Fixed

- Environment setup

## [0.4.5] - 2024-07-30

### Changed

- Updated install code

## [0.4.4] - 2024-07-30

### Changed

- Updated package code to support Ubuntu Linux

## [0.4.3] - 2024-07-30

### Fixed

- Exit condition

## [0.4.2] - 2024-07-30

### Changed

- Improved help and version switches

## [0.4.1] - 2024-07-30

### Added

- set_env function and improved verbose option

## [0.4.0] - 2024-07-29

### Fixed

- Package check so it doesn't run twice

## [0.3.9] - 2024-07-27

### Added

- Plugin manager switch

## [0.3.8] - 2024-07-27

### Changed

- Improved package check

## [0.3.7] - 2024-07-27

### Changed

- Improved verbose output

## [0.3.6] - 2024-07-26

### Changed

- Updated documentation and verbose messages

## [0.3.5] - 2024-07-26

### Added

- Verbose message function and messages

## [0.3.4] - 2024-07-26

### Changed

- Improved rbenv and pyenv version detection

## [0.3.3] - 2024-07-26

### Fixed

- Brew config

## [0.3.2] - 2024-07-26

### Added

- Build switch

## [0.3.1] - 2024-07-26

### Fixed

- pyenv

## [0.3.0] - 2024-07-26

### Fixed

- rbenv

## [0.2.9] - 2024-07-26

### Fixed

- Documentation updates and bug fixes

## [0.2.8] - 2024-07-26

### Fixed

- oh-my-posh/zsh

## [0.2.7] - 2024-07-25

### Changed

- Updated help

## [0.2.6] - 2024-07-25

### Changed

- Updated zinit support

## [0.2.5] - 2024-07-25

### Added

- Initial oh-my-posh/zsh support

## [0.2.4] - 2024-07-25

### Added

- zsh theme

## [0.2.3] - 2024-07-24

### Changed

- Improved package check code

## [0.2.2] - 2024-07-23

### Added

- Fonts function

## [0.2.1] - 2024-07-23

### Added

- Install function

## [0.2.0] - 2024-07-23

### Fixed

- Package check

## [0.1.9] - 2024-07-23

### Removed

- Bash emulation statement

## [0.1.8] - 2024-07-23

### Fixed

- Bug fixes

## [0.1.7] - 2024-07-23

### Removed

- mkdirs before git clones

## [0.1.6] - 2024-07-23

### Fixed

- Package check

## [0.1.5] - 2024-07-23

### Added

- Code to ignore environment variable setup (useful for testing)

## [0.1.4] - 2024-07-23

### Fixed

- Version check

## [0.1.3] - 2024-07-23

### Added

- Code to print changelog

## [0.1.2] - 2024-07-23

### Changed

- Improved version check

## [0.1.1] - 2024-07-23

### Added

- Code to check for updates

## [0.1.0] - 2024-07-22

### Added

- Check for updates switch

## [0.0.9] - 2024-07-22

### Fixed

- Read function for zsh

## [0.0.8] - 2024-07-22

### Changed

- Updated help and documentation

## [0.0.7] - 2024-07-22

### Changed

- Initial commit

## [0.0.6] - 2024-07-22

### Added

- execute_command routine

## [0.0.5] - 2024-07-20

### Changed

- Broke out zinit, rbenv and pyenv

## [0.0.4] - 2024-07-20

### Added

- Defaults check

## [0.0.3] - 2024-07-20

### Added

- Help

## [0.0.2] - 2024-07-20

### Added

- Verbose switch

## [0.0.1] - 2024-07-19

### Added

- Initial version
