![alt tag](ussuri.jpg)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 1.6.2

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

By default this script uses zinit as the zsh plugin manager
and powerlevel10k as the prompt (oh-my-posh is available instead, see Prompt), e.g.

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

    -G|--drift [settings|packages|all]  Report what differs from the defaults and package lists (read only)
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
    -E|--prompt NAME  Prompt engine       (default: p10k: p10k, posh or none)
    -f|--font(s)      Install font(s)     (default: false)
    -k|--config       Create config file  (~/.ussuri/config)
    -L|--dotfiles     Link dotfiles       (default: false)
    -M|--profile NAME Profile for dotfiles, packages and plugins (default: none)
    -J|--defaults-undo [N|list]  Undo the Nth newest run of defaults changes (default: newest)
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
    -y|--yes          Answer yes, no prompts (default: false)
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

Update hint
-----------

UPDATE_HINT=true

Off by default, because it contacts GitHub from your shell. Turn it on (for example in the config) and, at most
once a day, a check runs in the background (a disowned job with its output detached, so a login never waits for
it) and records the latest version in ~/.ussuri/update.latest. When that is newer than your script, one line is
shown at the next prompt, at most once a day:

    ussuri 1.6.0 is available (this is 1.5.8): run ussuri.zsh --update  (UPDATE_HINT=false turns this off)

It is shown from a prompt hook after startup finishes, not during startup, as output during startup upsets
powerlevel10k's instant prompt. A normal login does no extra work: two checks of stamp files and one small file
read, with no new processes. Only interactive logins check (never a manual run), a damaged or unexpected answer is
ignored, and several shells opened together start one check. `--doctor` reports the state and warns when an update
is available.

Updating, and your own plugins and packages
-------------------------------------------

./ussuri.zsh --update

Downloads the release archive from GitHub (one request, the script and its files/), checks the script parses and
is the version expected, saves the current script in ~/.ussuri, replaces it, and then brings ~/.ussuri/files up to
date: new files are added and changed ones replaced, with the copy that is replaced first saved in
~/.ussuri/files.bak/<date>/, so an edit of yours is never lost. Nothing is deleted. It refuses an archive that
fails the checks (a script that doesn't parse, paths that would escape the target, or a checksum that doesn't match
UPDATE_SHA256 if you set one), and if the archive can't be fetched it updates the script alone and says the supporting
files were not updated. UPDATE_URL points it somewhere else. It updates the script you ran: run it from
~/.zshrc, or run --install after updating a checkout.

The shipped lists are replaced by updates and --install, so don't edit them. Your own additions go in files
that are never touched:

    ~/.ussuri/files/zinit/local.zsh        zinit lines, same format as zinit.zsh, run after it
    ~/.ussuri/files/packages/local.brew    one package per line (local.apt, local.pacman, local.dnf, local.apk, local.nix)

A plugin added to local.zsh loads after the shipped list's completions step, so one that only ships completion files
may need a restart to be picked up. Packages in the local list are installed with the shipped ones, and adding one is
noticed on the next login. `--doctor` shows how many lines each has.

Prompt
------

Only one prompt engine is installed and loaded: powerlevel10k (`p10k`, the default), oh-my-posh (`posh`) or
neither (`none`). Earlier versions set both up on every login, and the two hook every prompt and fight over it.
Set PROMPT_ENGINE (for example in the config) to choose, or use `-E posh` for one run. The setting decides what
is installed, what is set up on login and whether the zinit plugin lists load the powerlevel10k plugin. `-o` and
`-T` select oh-my-posh and powerlevel10k for that run, `-A` follows the setting (it used to do both), and if
several are given the last wins. `--doctor` shows the engine and warns if the other one has been switched on.
Measured with the real script and oh-my-posh, dropping the second engine took a login from about 167 to 129 ms.

Plugins
-------

The zinit plugin lists are files/zinit/zinit-turbo.zsh (the default) and zinit.zsh. Besides the prompt,
syntax highlighting, completions, autosuggestions and fzf-tab, they load zsh-history-substring-search:
type part of a command and press Up or Down to step through the history entries that contain it (the
arrow keys are bound for both keypad modes).

It also loads forgit (https://github.com/wfxr/forgit), interactive git commands driven by fzf (git add,
log, diff, checkout, stash, rebase and more with previews). forgit defines short aliases, and 16 of them (ga,
gd, gco, gcb, gss, glo...) have the same name as aliases in the Oh My Zsh git snippet, which would silently
change what they do (gcb creates a branch, but forgit's gcb is an interactive picker). So those 16 are renamed
with an f in front (fga, fgd, fgco, fgcb, fgss, fglo...), your git aliases keep their meaning, and forgit's other
aliases (gi, gat, gfu...) keep their names. `zsh tests/forgit-aliases.zsh` (needs the network) checks the
renames against the current forgit and git snippet, and is worth running when either is updated.

zoxide (https://github.com/ajeetdsouza/zoxide) is a smarter cd: `z foo` jumps to the directory you use most
that matches foo, and `zi` picks interactively with fzf. It is in the package lists, so `-P` installs it,
but note that `-P` installs every package in your list that is missing, not just this one; to install only
zoxide use your package manager (for example `brew install zoxide`). On Ubuntu releases before 22.10 the
package doesn't exist and apt will skip it. A login sets it up only if it is installed, so nothing is ever
downloaded on login, and its init output goes through the init cache. Set INSTALL_ZOXIDE=false (for example in
the config) to leave it alone. It only adds z and zi, it does not replace cd.

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

Undoing defaults changes
------------------------

./ussuri.zsh --defaults-undo list
./ussuri.zsh --defaults-undo [N]

Every OS X setting the script changes is recorded in ~/.ussuri/defaults.journal, with what it was before (its
value and type, or that it was not set) and what it was set to. A run is one apply. `--defaults-undo list` shows
the runs, and `--defaults-undo` puts back the newest (or the Nth newest, 1 being the newest), each setting exactly
as it was, with the same type, or deleted if it was not set. A setting you changed yourself since is left alone
and reported, as is one whose previous value was an array or dictionary (those can't be put back from the
journal). The Dock and Finder are restarted if they need it. A run that has been undone is marked, so the next
undo goes back one run. `--dryrun` shows what would be put back, and `--confirm` is honoured (and, as some may be
declined, leaves the run to be undone again).

Only changes made from 1.5.7 on are recorded, so it can't undo what earlier versions applied. A write that didn't
take effect (declined with --confirm, refused or ignored by the system) isn't recorded, as it changed nothing.
It covers OS X defaults, not the Linux GNOME settings or the Library folder's hidden flag.

Drift report
------------

./ussuri.zsh --drift [settings|packages|all]

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

Unattended installs
-------------------

./ussuri.zsh -P --yes

Package installs are already unattended where the package manager allows it (apt, dnf and pacman are always run
with -y or --noconfirm, and apk, nix and brew don't ask). --yes (or ASSUME_YES=true, for example in the config)
also turns off what those flags don't cover: apt's debconf dialogs (DEBIAN_FRONTEND=noninteractive), the
"Press RETURN" wait in the Homebrew installer (NONINTERACTIVE=1), and the script's own --confirm prompts, which
are answered yes. It can't remove a password prompt: sudo, and Homebrew casks that run an installer, still ask
for your password unless sudo is passwordless for you (--sudoers sets that up, see its warning).

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

Profiles and machines
---------------------

One set of settings can differ per profile (work, personal) and per machine. A profile (`-M work`, or PROFILE=work in the
config) and a machine name (MACHINE, the short hostname by default) add layers on top of the common ones, for dotfiles,
packages and plugins alike. For a list `files/packages/macos.brew` and the plugin lists in `files/zinit`, your own files are
(in `~/.ussuri/files`, where updates and --install never touch them):

    packages/local.brew                       every machine (local.cask, local.tap, local.apt, local.pacman... likewise)
    packages/profiles/work/local.brew         machines using the work profile
    packages/hosts/mybox/local.brew           just the machine called mybox
    zinit/local.zsh, zinit/profiles/work/local.zsh, zinit/hosts/mybox/local.zsh      the same, for plugins

and ~/.ussuri/dotfiles/{common,profiles/<name>,hosts/<machine>} for dotfiles. Layers are applied in that order and later ones
win. For packages a line `!name` takes a package out of what the earlier layers added (the shipped list included), matched exactly
rather than as a pattern, and a later layer can put it back:

    # packages/profiles/work/local.brew
    !docker
    !lftp

Switching profile is noticed on the next login, as the profile is part of the package list's checksum. A profile or machine name is
part of a file path, so one containing a slash or starting with a dot is refused with a warning. `--doctor` shows the profile, the
machine and the local lists found. DOTFILES_PROFILE and DOTFILES_HOST (the older names) still override them for dotfiles alone.

Casks and taps (macOS)
----------------------

Besides the formulae in files/packages/macos.brew, `-P` handles Homebrew casks (applications and fonts) and taps:

    files/packages/macos.tap     taps, added first so a formula from one can be found by its short name
    files/packages/macos.brew    formulae
    files/packages/macos.cask    casks, installed with brew install --cask

The shipped macos.tap and macos.cask contain only comments, so nothing is installed or tapped by default. The shipped
lists are replaced by updates, so put your own in ~/.ussuri/files/packages/local.tap, local.brew and local.cask, one
per line, which never are:

    # ~/.ussuri/files/packages/local.cask
    firefox
    iterm2

Each list has its own stamp, so a change to one only reprocesses that one, and a package that is already installed (casks
are in `brew list` too) or a tap that is already there (compared without regard to case) is skipped.

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

### Package drift

`--drift packages` (and a bare `--drift`, which is both, each under a heading) compares what is installed with your package lists,
every layer of them (local, profile, machine, and `!name` exclusions applied). It reads only, from live queries to the package
manager and never the cached lists:

    Packages (brew)
      taps added but not in your lists (1):
        dkorunic/tap
      formulae not installed (1):
        rust
      casks installed but not in your lists (23):
        firefox iterm2 slack ...

    1 packages from your lists are not installed (-P installs them); 59 installed ones are not in your lists (shown for information)

What is in a list but not installed is drift (exit status 1), which `-P` would install. What is installed because you chose it (brew leaves
and casks, apt-mark showmanual, pacman -Qe, dnf userinstalled, the apk world file) but is in no list is only shown, as that is what you would
add to a local list to keep it, so a machine that only has extras is not drift (exit status 0). On macOS a name in the formula list that is
installed as a cask counts as installed (brew install falls back to a cask, as -P does). Exit status 2 means there was nothing to compare
(no supported package manager, or its tool is not installed).

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

Testing and CI
--------------

zsh tests/smoke.zsh [name-filter]
zsh tests/package-names.zsh [-v]
zsh tests/forgit-aliases.zsh        (needs the network, see Plugins)

The smoke tests run against a copy of the script in a throwaway home directory with the system commands (defaults, brew, sudo,
rbenv, pyenv...) stubbed, so they do not touch the real system. They pretend to be macOS whatever the host is
(TEST_OS=linux and TEST_OS_REL change that), and TEST_PATH_PREFIX goes in front of the sandbox's PATH, to try another userland,
for example GNU tools on a Mac: `TEST_PATH_PREFIX=/opt/homebrew/opt/coreutils/libexec/gnubin: zsh tests/smoke.zsh`.

tests/package-names.zsh checks that every package named in the shipped list for this system exists in its repositories (apt-cache,
pacman -Si, dnf repoquery, apk search or brew info), installing nothing. It needs a fresh package index. It is how a wrong name in a list is
found before -P fails on it.

.github/workflows/ci.yml runs both on macOS and Ubuntu runners, and on Debian, Ubuntu, Fedora, Arch and Alpine in containers, where it also
runs `--doctor` and `--drift packages` for real, as those are the paths the smoke tests can only check against stubs. Nothing in it installs
packages from your lists or changes the runner. The actions are pinned to a major version (actions/checkout@v4), not to a commit.

License
-------

This software is licensed as CC BY-NC-SA (Creative Commons Attribution-NonCommercial-ShareAlike)

https://creativecommons.org/licenses/by-nc-sa/4.0/legalcode
