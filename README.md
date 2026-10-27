![alt tag](ussuri.jpg)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 1.5.0

License
-------

CC BY-NC-SA: https://creativecommons.org/licenses/by-nc-sa/4.0/

Fund me here: https://ko-fi.com/richardatlateralblast

Introduction
------------

This script is designed to set up a zsh environment from scratch.
It is coppied to .zshrc and runs inline, i.e. when you login or
execute a new shell it will check the current environment and
install components/configurations if they are not present.

By default this script uses zinit as the zsh plugin manager,
oh-my-posh, and powerlevel10k as the theme, e.g.

![Config example](https://raw.githubusercontent.com/lateralblast/ussuri/master/ussuri.png)

The defaults can be changed by editing the script.

Installation
------------

The script will install as .zshrc using the --install switch.
This will also make a backup of the existing .zshrc file.

```
./ussuri.zsh --install --verbose
Setting:        Environment parameter "WORK_DIR" to "/Users/testuser/.ussuri"
Executing:      mkdir -p /Users/testuser/.ussuri/files
Information:    Setting defaults
Executing:      PATH="/usr/local/bin:/usr/local/sbin:/Users/testuser/.rbenv/bin:/Users/testuser/.pyenv/bin:/Users/testuser/.zinit/polaris/bin:/Users/testuser/.oh-my-posh:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin:/System/Cryptexes/App/usr/bin:/usr/bin:/bin:/usr/sbin:/sbin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/local/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/bin:/var/run/com.apple.security.cryptexd/codex.system/bootstrap/usr/appleinternal/bin:/opt/X11/bin:/Library/Apple/usr/bin:/Applications/VMware Fusion.app/Contents/Public"
Executing:      LD_LIBRARY_PATH="/usr/local/lib:/usr/lib:/usr/local/lib:/"
Setting:        Environment parameter "DO_HELP" to "false"
Setting:        Environment parameter "DO_DRYRUN" to "false"
Setting:        Environment parameter "DO_CONFIRM" to "false"
Setting:        Environment parameter "DO_DEBUG" to "false"
Setting:        Environment parameter "DO_BUILD" to "false"
Setting:        Environment parameter "DO_PLUGINS" to "true"
Setting:        Environment parameter "ZINIT_FILE" to "/Users/testuser/.ussuri/files/zinit/zinit.zsh"
Setting:        Environment parameter "INSTALL_ZINIT" to "true"
Setting:        Environment parameter "INSTALL_RBENV" to "true"
Setting:        Environment parameter "INSTALL_PYENV" to "true"
Setting:        Environment parameter "INSTALL_POSH" to "true"
Setting:        Environment parameter "INSTALL_OZSH" to "false"
Setting:        Environment parameter "INSTALL_FONTS" to "true"
Setting:        Environment parameter "INSTALL_P10K" to "true"
Setting:        Environment parameter "ZINIT_HOME" to "/Users/testuser/.zinit"
Setting:        Environment parameter "RBENV_HOME" to "/Users/testuser/.rbenv"
Setting:        Environment parameter "PYENV_HOME" to "/Users/testuser/.pyenv"
Setting:        Environment parameter "POSH_HOME" to "/Users/testuser/.oh-my-posh"
Setting:        Environment parameter "ZOSH_HOME" to "/Users/testuser/.oh-my-zsh"
Setting:        Environment parameter "P10K_INIT" to "/Users/testuser/.p10k.zsh"
Setting:        Environment parameter "SOURCE_P10K_INIT" to "/Users/testuser/.ussuri/files/p10k/p10k.zsh"
Setting:        Environment parameter "P10K_HOME" to "/Users/testuser/.powerlevel10k"
Setting:        Environment parameter "P10K_THEME" to "/Users/testuser/.powerlevel10k/powerlevel10k.zsh-theme"
Setting:        Environment parameter "RUBY_VER" to "3.3.4"
Setting:        Environment parameter "PYTHON_VER" to "3.12.4"
Setting:        Environment parameter "DO_VERSION_CHECK" to "false"
Setting:        Environment parameter "DO_DEFAULTS_CHECK" to "false"
Setting:        Environment parameter "DO_PACKAGE_CHECK" to "false"
Setting:        Environment parameter "DO_UPDATE_CHECK" to "false"
Setting:        Environment parameter "DO_UPDATE_FUNCT" to "false"
Setting:        Environment parameter "DO_PYENV_CHECK" to "false"
Setting:        Environment parameter "DO_RBENV_CHECK" to "false"
Setting:        Environment parameter "DO_ZINIT_CHECK" to "false"
Setting:        Environment parameter "DO_FONTS_CHECK" to "false"
Setting:        Environment parameter "DO_POSH_CHECK" to "false"
Setting:        Environment parameter "DO_P10K_CHECK" to "false"
Setting:        Environment parameter "DO_ZOSH_CHECK" to "false"
Setting:        Environment parameter "DO_ENV_SETUP" to "true"
Setting:        Environment parameter "DO_ZSH_THEME" to "true"
Setting:        Environment parameter "ZSH_THEME" to "robbyrussell"
Setting:        Environment parameter "PLUGIN_MANAGER" to "zinit"
Information:    Backing up /Users/testuser/.zshrc to /Users/testuser/.ussuri/.zshrc.03_08_2024_21_09_20
Executing:      cp /Users/testuser/.zshrc /Users/testuser/.ussuri/.zshrc.03_08_2024_21_09_20
Information:    Replacing /Users/testuser/.zshrc
Executing:      cp ./ussuri.zsh /Users/testuser/.zshrc
Setting:        Environment parameter "WORK_DIR" to "/Users/testuser/.ussuri"
Executing:      mkdir -p /Users/testuser/.ussuri/files
Executing:      ( cd /Users/testuser/ussuri/files ; tar -cpf - . )|( cd /Users/testuser/.ussuri/files ; tar -xpf - )
Executing:      cp /Users/testuser/.ussuri/files/p10k/p10k.zsh /Users/testuser/.p10k.zsh
```

Usage
-----

```
  Usage: ./ussuri.zsh [OPTIONS...]

  When run manually with switches:

    -G|--drift        Report settings that differ from the defaults (read only)
    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -A|--doall        Do all fuction (where set to true)
    -i|--inline       Set inline defaults when not runing inline mode
    -I|--install      Installs ussuri as: /Users/spindler/.zshrc
    -b|--build        Build sources       (default: false)
    -B|--backups      List .zshrc backups
    -c|--confirm      Confirm commands    (default: false)
    -C|--check.       Check for updates   (default: false)
    -d|--debug        Enable debug        (default: false)
    -D|--default(s)   Set defaults        (default: false)
    -f|--font(s)      Install font(s)     (default: false)
    -k|--config       Create config file  (~/.ussuri/config)
    -L|--dotfiles     Link dotfiles       (default: false)
    -M|--profile      Dotfiles profile    (default: none)
    -m|--manager      Plugin manager      (default: zinit)
    -n|--notheme      No zsh theme        (default: true)
    -N|--noenv        Ignore environment  (default: true)
    -o|--ohmyposh     Install oh my posh  (default: false)
    -O|--ohmyzsh      Install oh my zsh   (default: false)
    -p|--pyenv        Do pyenv check      (default: false)
    -P|--package(s)   Do packages check   (default: false)
    -r|--rbenv        Do rbenv check      (default: false)
    -R|--rollback [N] Restore a backup    (default: newest)
    -s|--startdir     Set start dir       (default: none)
    -t|--dryrun       Dry run mode        (default: false)
    -T|--p10k         Do p10k config      (default: false)
    -u|--unlink       Unlink dotfiles
    -U|--update       Update the script   (default: false)
    -v|--verbose      Verbose output      (default: false)
    -W|--tool NAME    Install a tool      (fnm, rustup, uv or mise)
    -X|--uninstall    Restore the .zshrc from before ussuri
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
    Do package check:     true
    Do zinit check:       true
    Do pyenv check:       true
    Do rbenv check:       true
    Do p10k check         true
    Do oh-my-posh check:  true
    Do oh-my-zsh check:   false
    Do verbose mode       false
    Do sudoers check:     false
    Plugin Manager:       zinit
    Start Directory:      none
```

Defaults
--------

Some defaults can be overridden by declaring them at the top of the script, e.g. DO_VERBOSE,
but it is better to use a config file so the script itself stays untouched and updatable.

Config file
-----------

./ussuri.zsh --config

Creates ~/.ussuri/config (or the file named by USSURI_CONFIG) with every setting commented out,
and tells you where it is. It is sourced as zsh before any defaults are set, so a line such as

    DO_VERBOSE=true
    ZINIT_TURBO=false
    START_DIR=~/code

changes the default for every shell. The order of precedence is: built in defaults, then the
environment, then the config file, then command line switches. It is executed, so keep it writable
only by you (--doctor warns if it is not, and if it has a syntax error). It is never overwritten.

History
-------

A login shell keeps 50000 lines of history (macOS defaults to 2000, a bare zsh to 30) in the history file
(~/.zsh_history unless HISTFILE is already set), shared between shells, and leaves out repeated commands,
commands typed with a leading space (a way to keep one out of history) and extra blanks. Set HISTORY_SIZE to
change the size, or DO_HISTORY=false to leave all of this to the system (SHARE_HISTORY=false turns sharing
off separately), for example in the config.

Startup
-------

The script runs on every new shell, so the normal path avoids starting other processes.
Work that only needs doing occasionally is tracked in ~/.ussuri:

- OS X defaults are applied when asked for (-D), when the script has changed, or every
  DEFAULTS_MAX_AGE days (default 7), tracked by defaults.stamp
- Output of rbenv init, pyenv init and brew shellenv is cached in ~/.ussuri/cache and rebuilt
  when the tool changes (set DO_CACHE_INIT=false to turn this off)
- The package list is only processed when it has changed, or when asked for (-P)
- zinit plugins load in turbo mode (files/zinit/zinit-turbo.zsh): the prompt appears first and the
  other plugins load just after it, about 75ms sooner. Set ZINIT_TURBO=false for the original list
  (files/zinit/zinit.zsh) that loads everything before the prompt
- Plugin lists are run one line at a time, so a snippet that only applies to some systems is written as
  a one line `if os_is_like arch; then ...; fi` (the Arch aliases load only on Arch and its derivatives).
  The lists are copied to ~/.ussuri/files when installed, so a changed list reaches an existing install
  when you run --install again (which replaces the copies there)

Drift report
------------

./ussuri.zsh --drift

Reads every OS X (or, on Linux, GNOME) setting ussuri would apply and prints the ones that differ, as actual -> expected and
grouped by domain, then a summary. It never writes anything, and exits 1 if there is drift (0 if there
is none), so it can be used in a check:

    com.apple.dock
      tilesize                                 48 -> 32
      autohide-delay                           (not set) -> 0.2

    2 of 105 settings differ from what ussuri would apply. Run --defaults to apply them.

Transmission blocklist
----------------------

On OS X the script sets Transmission's blocklist to Bluetack's Level 1 list as served by iblocklist.com
over HTTPS (the list Transmission itself used to ship, refreshed daily), with auto-update on. Set
TRANSMISSION_BLOCKLIST_URL (for example in the config) to use another one. The URL is checked before it
is written, and an unreachable one is reported and not written, so it never replaces a working setting.
Neither list nor service is endorsed by the Transmission developers, and Level 1 blocks the address
ranges of organisations known for anti-filesharing activity, so decide for yourself that you want it.

Language managers
-----------------

Besides rbenv (--rbenv) and pyenv (--pyenv), four more can be installed and set up. They are off unless
you ask for them, either once with --tool NAME or permanently with INSTALL_<NAME>=true in the config
(on login they are then installed if missing and set up, and no versions are installed):

    fnm     Node          FNM_NODE=lts-latest                installed to ~/.local/share/fnm
    rustup  Rust          RUSTUP_TOOLCHAIN_WANTED=stable     installed to ~/.cargo
    uv      Python        UV_PYTHON=3.13                     installed to ~/.local/bin
    mise    many, and a   MISE_TOOLS="node@lts python@3.13"  installed to ~/.local/bin
            replacement for the others (it also reads asdf's .tool-versions)

The version settings are only acted on when building (--tool or --build), never on an ordinary login.
Installers are downloaded then run like the others, and can be verified with FNM_INSTALL_SHA256,
RUSTUP_INSTALL_SHA256, UV_INSTALL_SHA256 or MISE_INSTALL_SHA256. They are told not to edit your shell
files. mise's activation is cached like rbenv's; fnm's can't be, as it points at a directory made for
each shell. fnm is offered rather than nvm because nvm's init costs hundreds of milliseconds per shell.

Linux package managers
----------------------

The package manager is chosen from the distribution's os-release ID and ID_LIKE, so derivatives work:

    apt     Ubuntu, Debian, Mint, Pop!_OS...     files/packages/ubuntu.apt
    pacman  Arch, EndeavourOS, Manjaro...        files/packages/arch.pacman (endeavouros.pacman)
    dnf     Fedora, RHEL, Rocky, Alma...         files/packages/fedora.dnf
    apk     Alpine                               files/packages/alpine.apk
    nix     NixOS                                files/packages/nix.nix

Set PKG_MANAGER (for example in the config) to override it, such as nix on Ubuntu. Root is obtained with
sudo, or doas if there is no sudo, or not at all if you are root, and nix is never run as root. Each
package is installed on its own, so one that doesn't exist in your distribution's repositories only fails
that package. The dnf, apk and nix lists are a conservative subset of the apt one, edit them to taste.
The nix installed-package list is read from nix profile list, which changed format in Nix 2.20, so
both are handled on a best effort basis.

Linux defaults (GNOME)
----------------------

On Linux, --defaults applies a short list of GNOME settings through gsettings (keyboard repeat, show
hidden files and directories first in file choosers, list view in Files, button layout, privacy
clean-up and so on), and --drift reports where they differ. A setting that doesn't exist on your
desktop is skipped, and nothing is done without gsettings and a desktop session (without a session bus
gsettings only writes to a throwaway store). Unlike on OS X these are not applied on every login unless
you set DO_GNOME_DEFAULTS=true (for example in the config). The list is apply_linux_defaults in the script.

Backups, rollback and uninstall
-------------------------------

./ussuri.zsh --backups
./ussuri.zsh --rollback [N]
./ussuri.zsh --uninstall

--install saves your current ~/.zshrc in ~/.ussuri before replacing it. --backups lists them, newest
first, with the version of each and whether it is ussuri or a .zshrc of your own. --rollback puts one
back (N is the number from --backups, a file name, or nothing for the newest). --uninstall goes back
to the .zshrc you had before ussuri: the newest backup that isn't ussuri itself, or, if you had
none, it moves ussuri's aside. Either way the .zshrc being replaced is saved first, so a rollback
can itself be undone. Installed components and the backups in ~/.ussuri are left alone, and
--unlink removes dotfile links. All of them honour --dryrun.

Dotfiles
--------

./ussuri.zsh --dotfiles [--profile work]

Links dotfiles from ~/.ussuri/dotfiles into your home directory, in layers so one set can differ
per machine. Later layers win for the same path:

    ~/.ussuri/dotfiles/common/.gitconfig               every machine
    ~/.ussuri/dotfiles/profiles/work/.gitconfig        machines using the "work" profile
    ~/.ussuri/dotfiles/hosts/mybox/.gitconfig          only the machine whose short hostname is mybox

A file at <layer>/.config/app/conf is linked as ~/.config/app/conf. The profile comes from
--profile or DOTFILES_PROFILE, the host from DOTFILES_HOST (default is the short hostname), and the
directory from DOTFILES_DIR.

Nothing is ever deleted: a real file (or a link pointing somewhere else) that is in the way is moved
to ~/.ussuri/dotfile-backups/<date>/ first. Running it again changes nothing, --dryrun --verbose
shows what it would do, and --unlink removes only the links that point into the dotfiles directory
(backups are left for you to restore by hand). It runs only when asked, unless you set
DO_DOTFILES_CHECK=true in the config to keep the links in place on every login. --doctor reports
dotfiles that are not linked yet and real files standing in the way.

Doctor
------

./ussuri.zsh --doctor

Checks the shell, tools, install, lock, components, fonts, backups and state, and prints ok, warn
or FAIL for each. A warning is something that will probably fix itself on the next login or is
worth a look, a failure is something that will not. It exits non-zero if there are any failures,
and it never changes anything (a missing directory is reported, not recreated).

Pinning installs
----------------

Installers are downloaded to a file and then run, rather than piped into a shell. To verify them,
set the expected SHA-256 before the script runs, e.g. BREW_INSTALL_SHA256 or POSH_INSTALL_SHA256
(a mismatch is refused). Without one they still run, with a notice.

Git installs follow the latest by default. To pin the first clone to a branch, tag or commit set
ZINIT_REF, RBENV_REF, RUBY_BUILD_REF, PYENV_REF, NERD_FONTS_REF, ZOSH_REF or P10K_REF.
An existing install is never changed.

Testing
-------

zsh tests/smoke.zsh [name-filter]

The tests run against a copy of the script in a throwaway home directory with the system commands
(defaults, brew, sudo, rbenv, pyenv...) stubbed, so they do not touch the real system.

License
-------

This software is licensed as CC BY-NC-SA (Creative Commons Attribution-NonCommercial-ShareAlike)

https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
