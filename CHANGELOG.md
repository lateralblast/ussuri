# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.9.0] - 2026-10-30

### Fixed

- `--timing` printed no `Slowest:` line when every step took under 0.1 ms (a quick machine, or all the work already done), because nothing was bigger than the starting value of zero. Found by the first CI run on Linux

### Changed

- The smoke tests no longer assume a non root user on a host with Debian, Fedora, Alpine or Arch tools. Found by the first CI run, which ran them in containers as root and on Ubuntu: the spies for the startup test were never made on Linux (`command` is not a program there, so the real utilities were not found), the package manager tests expected `sudo` (root does not use it) and `env DEBIAN_FRONTEND` (visible only through sudo), two tests that remove a stub package manager skip themselves where the real one is installed (`apt-get`, `dnf`), the slowest step can have a name with spaces, and a history file named by the system zshrc (Alpine's) is accepted. Run in Debian, Ubuntu, Fedora and Alpine containers as root: 1065 to 1067 passed, none failed. No change to what the script does apart from the fix above

## [1.8.9] - 2026-10-30

### Changed

- `rm`, `cp` and `mv` no longer ask before overwriting. OMZP::common-aliases makes them `rm -i`, `cp -i` and `mv -i`; the new `plain_file_aliases` runs after it in both plugin lists (as part of the snippet's atload in turbo mode) and removes those three aliases when they are exactly that, leaving any alias of your own alone. The rest of common-aliases is unchanged. To have the questions back, add the aliases to `files/zinit/local.zsh`. The plugin lists only change on `--install` or `--update`

## [1.8.8] - 2026-10-30

### Changed

- `--timing` says where the rest of the time goes. "Everything else" was a quarter of the total, so the start of the script is cut into named pieces by marks (an array append each, no function and no fork, so they cost nothing measurable on a normal login): `config files`, `defining functions` (reading the script itself), `arguments`, `set_defaults` and `history, completion dir`. And the zinit step is cut by line of the plugin lists, each line named by the plugin it loads and the slowest eight shown, with what is left over (zinit starting, reading the lists). The per line timing is only done under `--timing`. On the Mac it was measured on, powerlevel10k (28 ms) is most of the zinit step, the other 28 lines about 15 ms between them (turbo only schedules them) and zinit starting 17 ms

## [1.8.7] - 2026-10-30

### Changed

- `--set`, `--unset` and `--edit` say how to get the change in the window you are in (`exec zsh`) as well as that it applies to new shells

## [1.8.6] - 2026-10-30

### Added

- `--rollback update` undoes the last `--update`: the script it replaced (`ussuri.zsh.<date>`) and the supporting files it replaced (`files.bak/<date>`, the same date) are put back, the script being replaced is kept first (so doing it twice goes forward again), and `--backups` mentions the copies. A file the update added is left where it is, as nothing recorded which were new

## [1.8.5] - 2026-10-30

### Added

- Examples for a different top line on one machine or profile (`--set NAME VALUE --host laptop`) with `battery`, `aws` and `kubecontext`, and a test that a host's or profile's `local.config` does change the top line. No segments are added by default: whether a machine has a battery or a cluster is not known without running something at login

## [1.8.4] - 2026-10-30

### Added

- `--doctor` checks the prompt's top line: a segment that does not exist in this powerlevel10k (found by searching its source, so a typo or a p10k without `cpu_arch` shows), a colour that can not be read (with the `POWERLEVEL9K_<NAME>_FOREGROUND` that fixes it) and a word that is not a segment name. The bottom line is your config's and is not warned about

## [1.8.3] - 2026-10-30

### Added

- `--prompt-preview` shows the prompt's top line without opening a shell: each segment with the text it would show (context, os_version, cpu_arch, date and time are known without a prompt), its foreground and background, the contrast between them (the WCAG ratio, worked out from the xterm 256 colour table, with `#rrggbb` and p10k's colour names too) and a verdict (ok, low, same, default, unknown), drawn in its own colours on a terminal, then the bottom line's names. The layout is the one a login makes: your `~/.p10k.zsh` is read and `apply_prompt_top_line` applied, in a subshell. It has no short form of its own, as every letter was taken (inside it is `-4`)

## [1.8.2] - 2026-10-30

### Added

- `DOTFILES_REPO` (and `DOTFILES_REF`): the dotfiles directory kept as a clone of a git repository. `--dotfiles` clones or fast forwards it first and says what happened; an interactive login does it at most once a day in a detached background job (the stamp touched first, nothing printed, nothing prompted for) and records the result in `dotfiles.sync` for `--doctor`. Only https, ssh and file URLs are accepted (`GIT_ALLOW_PROTOCOL` is set to match, which stops git's `ext::` transport), a directory that is not a clone of that URL or has uncommitted changes is left alone, and only a fast forward is taken

### Changed

- The test git no longer blocks `file://` clones, which the DOTFILES_REPO tests use (it still blocks https, ssh and git)

## [1.8.1] - 2026-10-30

### Added

- `--export [FILE]` and `--import FILE`: your setup in one file for a new machine. The bundle (readable by you alone) holds the config and its profile and machine layers, the local plugin and package lists and their layers, the dotfiles directory and `~/.p10k.zsh`, with a MANIFEST, and nothing the release owns or the machine made. `--import` takes only plain files and directories with names from that list (no links, no absolute paths, no `..`, a MANIFEST required) and keeps what it replaces in `import.bak/<date>/`. Both honour `--dryrun`. They have no short form of their own, as every letter was taken (inside they are `-2` and `-3`)

## [1.8.0] - 2026-10-30

### Added

- `SCRIPT_SHA256` pins the script inside an update, checked whichever way it was fetched (the archive or the script alone), before anything is replaced; `--update` now says the SHA-256 of the script it installed. `UPDATE_SHA256` still pins the archive

## [1.7.9] - 2026-10-30

### Fixed

- The date on the top line could not be read: p10k's own date colour is dark and the prompt's background is 238. POWERLEVEL9K_DATE_FOREGROUND is set to 250 (the light grey of os_version) unless the config has set one

## [1.7.8] - 2026-10-30

### Changed

- The day and date (`Fri 30 Oct 2026`) are on the right of the top line by default: PROMPT_TOP_RIGHT_ELEMENTS defaults to `date`, p10k's own date segment, whose format is set to `%D{%a %d %b %Y}` unless your config already sets POWERLEVEL9K_DATE_FORMAT. `none` in either list means nothing there (an empty value falls back to the default, so it could not be said before). PROMPT_TOP_RIGHT_ELEMENTS="none" brings the old top line back

## [1.7.7] - 2026-10-29

### Added

- Plugins in both lists: OMZP::extract (`extract`, alias `x`), OMZP::copypath, OMZP::copyfile, OMZP::copybuffer (Ctrl-O) and OMZP::fancy-ctrl-z. The copy ones need `clipcopy`, which Oh My Zsh keeps in a library file that a snippet does not fetch, so OMZL::clipboard.zsh is loaded first (it is lazy: nothing is detected until a copy is made). Loaded in a real zinit in a throwaway shell: the functions and the `x` alias exist, copypath put the path on the pasteboard, and extract unpacked an archive

## [1.7.6] - 2026-10-29

### Changed

- The default top line of the two line prompt is now `context os_version cpu_arch`: user@hostname, then the OS version (`macOS 15.1`, `Ubuntu 24.04 LTS`) and the architecture (`arm64`, `x86_64`). It was just `context`. PROMPT_TOP_ELEMENTS="context" brings the old line back

## [1.7.5] - 2026-10-29

### Added

- `os_version` for the top line: a generic label that is the macOS version on a Mac (`macOS 15.1`) and the distribution on Linux (`Ubuntu 24.04 LTS`, from os-release's PRETTY_NAME, or NAME and VERSION_ID without it), so one PROMPT_TOP_ELEMENTS works on every machine. `linux_version` is the Linux half on its own, beside `macos_version`. All three are read once with zsh builtins when the prompt is set up and show nothing where they do not apply. Colours: POWERLEVEL9K_OS_VERSION_FOREGROUND, POWERLEVEL9K_LINUX_VERSION_FOREGROUND

## [1.7.4] - 2026-10-29

### Added

- `macos_version` as a segment for the top line (PROMPT_TOP_ELEMENTS / PROMPT_TOP_RIGHT_ELEMENTS), showing for example `macOS 15.1`. It is a segment of our own, defined only when it is asked for, and reads the version from /System/Library/CoreServices/SystemVersion.plist with zsh builtins once when the prompt is set up (no sw_vers, so no fork and nothing per prompt). On a machine without the file it shows nothing. Colour: POWERLEVEL9K_MACOS_VERSION_FOREGROUND

## [1.7.3] - 2026-10-29

### Changed

- --help is laid out as a table: the switches in groups (look without changing anything, install update and undo, settings, set up, how it runs), each row a short switch, a long one with its value, what it does and, where it has one, its current value in a column of its own, with a summary of what a login does at the end. Every row is made by one function (help_row, so the columns cannot drift apart as lines are added) with printf, a builtin. The wording was tidied: the typos are gone, -n and -N no longer show a default that read the wrong way round, the values a switch takes are shown (--prompt NAME, --defaults-undo [N|list], --drift [WHAT]), and the switches added since the old layout (--set, --unset, --get, --edit, --host, --fix, --adopt, --timing) are in their groups. The README's usage block is the script's own output again, and a test now compares the two word for word (home directory as ~, machine as laptop), so a stale or empty block fails

## [1.7.2] - 2026-10-29

### Added

- -j|--timing: runs the login path (as -i does) and prints how long each step took, in milliseconds on the shell's own clock (EPOCHREALTIME, no process is started to measure it), in the order they ran, then what the steps do not cover (reading the config and its layers, the switches, the defaults, the lock), the total from the start of the script, and the slowest step. The steps are the ones the login already ran: defaults, brew, packages, fonts, posh, zinit, pyenv, rbenv, tools, zoxide, p10k, zosh, ldflags, pkgconfig, cppflags, the package list, the update hint, dotfiles, sudoers. Each is now called through phase, which is the call and nothing else (one function call, no process) unless --timing is on. Plugins deferred by zinit's turbo mode load after the prompt and are not counted
- A test that the rule "a login starts no processes" holds: logging wrappers go in front of the ordinary utilities (awk, basename, cat, cp, cut, date, dirname, find, grep, head, ls, mkdir, mv, readlink, rm, sed, sort, stat, tail, tar, touch, tr, uname, wc and others), and a steady state login, the third in a sandbox, must start none of them, on macOS and on Linux. The same wrappers are checked to log a utility that is run, and a login with work to do (nothing stamped) is checked to start some, so the test cannot pass by watching nothing. It does not see a subshell or a builtin, which are not processes of these kinds, nor a command that is not on the list

## [1.7.1] - 2026-10-29

### Added

- --drift --adopt (-a): adds the packages that are installed but in no list to your local list, asking about each one (y, n, a for all that are left, q to stop), or without asking with --yes, or only showing with --dryrun. Taps go in local.tap, formulae in local.brew, casks in local.cask, and on Linux packages in the local.<ext> of the package manager; -M or -H puts them in that profile's or machine's list. A name already in the list is not added again, what was there is kept, a line says where the rest came from, and the list is backed up (packages-<ext>.<date>, newest ten) and replaced in one rename under the lock. Nothing is installed or removed. Without a terminal and without --yes or --dryrun it refuses. It is refused with --drift settings and without --drift
- --doctor --fix (-Y): repairs what is small, local and reversible, checking afterwards that each repair worked and updating the totals and the exit status: a config, profile or machine file that others can write (chmod go-w); one with a syntax error, by putting back the newest backup that is valid zsh and keeping the broken file as <name>.broken (left alone, and still a failure, if there is none); a missing ~/.p10k.zsh, copied from files/p10k; and a temp file a --set, --edit or --adopt left behind once it is 10 minutes old. It installs nothing, fetches nothing and removes none of your files. --doctor without --fix still changes nothing, and says how many problems --fix could repair. --dryrun lists what it would do; it needs the lock. --fix is refused without --doctor

### Fixed

- The backups of the config were found and pruned with the glob config.*, which also matches config.rejected, config.broken and temp files beside it, so a rejected edit could be taken for a backup, or removed when there were more than ten. Only names with the date suffix are backups now

## [1.7.0] - 2026-10-29

### Added

- Settings for one profile or machine: profiles/<PROFILE>/local.config and hosts/<MACHINE>/local.config next to the config, sourced after it (the profile, then the machine, so the machine wins, and the command line wins over all). They use the same layout as the package and plugin layers (local_layer_files gained a third argument, layers, that leaves out the every machine file, and it and check_layer_name now live above the config block because the config is read before the rest of the script). Two file checks and no processes when there are none. PROFILE and MACHINE are those of the environment or the config: -M and -H come after the config is read, so they choose the file to change but do not pull in that profile's settings for the run. A profile or machine name that could leave the directory is refused
- -H|--host NAME: the machine for hosts/NAME, as -M is for the profile. With --set, --unset or --edit, -M or -H picks the file that is changed (profiles/<name>/local.config or hosts/<name>/local.config, started from a short header when it is new); both at once, or a name that is not usable, is refused. Backups of those files are config-profile-<name>.<date> and config-host-<name>.<date>, the newest ten of each, apart from the config's own. --get names the file that a value comes from, the last of the config and its layers to set it, and --get with no name includes names only a layer sets. --doctor checks the layer files (syntax, and writable by others)
- -K|--edit: opens a copy of the config (or a layer, with -M or -H) in $VISUAL, $EDITOR or vi, and replaces the file only if the result is valid zsh. A syntax error leaves it as it was and the edit in <file>.rejected; a name that is not one of ussuri's settings is noted but kept; an edit that changes nothing changes nothing; the old file is backed up; a missing config starts from the template. The editor may have arguments. --dryrun shows what would run. Tested with editor scripts, not an interactive editor
- Tab completion for the script (files/completions/_ussuri, put on the fpath at login by add_completions_dir, which does one directory test and no processes): the switches with their descriptions, the settings after --set, --unset and --get, true and false for a true/false setting, the engines for PROMPT_ENGINE, profile and machine names from the layers there are, and the tools, plugin managers and engines the other switches take. Checked in a real terminal (a pseudo terminal with compinit): --se completes to --set, PROMPT_T to the two PROMPT_T settings, and the values to true and false. The tests fail if its list of settings or switches goes out of step with the script

### Changed

- A bug found on the way: add_completions_dir first used typeset -U fpath, which inside a function makes a local copy, so the fpath was not changed. It is typeset -gU

## [1.6.9] - 2026-10-29

### Added

- OMZP::common-aliases in both plugin lists (l, ll, la, lt, grep, h, p, the global aliases H, T, G, L... and more), with zsh-you-should-use told to leave them alone so it is not noisy. mark_aliases and ignore_new_aliases (new, in the script) note the aliases there are before the snippet loads and add every alias and global alias that appeared since to YSU_IGNORED_ALIASES and YSU_IGNORED_GLOBAL_ALIASES, which the plugin reads each time it checks a command. In turbo mode they run as the snippet's atinit and atload, in the same deferred step as the snippet. The aliases themselves still work; your git, kubectl and other aliases are still reminded. They can wrap any snippet in your own local.zsh. Checked with the real zinit and the real plugin in a throwaway shell, both ways: eager, and turbo in a pseudo terminal. 36 aliases and 10 global aliases were ignored, typing `ll` gave no reminder and `git status` still gave `You should use: "gst"`. Note what the snippet itself does: it makes rm, cp and mv ask before overwriting (`-i`) and adds colour and directory exclusions to grep

## [1.6.8] - 2026-10-29

### Added

- Oh My Zsh alias snippets for what the machine has, in both plugin lists, so zsh-you-should-use has more to remind you of: brew (if `brew` is on the PATH), docker and docker-compose (if the command is), systemd (on Linux, if systemctl is), debian (apt aliases, on Debian, Ubuntu, Mint and anything else like debian) and dnf (on Fedora and its derivatives). Each is checked once, as the list is read. Each snippet was loaded in a throwaway zinit with the real plugin: all six load without errors and define aliases (brew 42, docker 46, docker-compose 31, systemd 129, debian 33, dnf 19). Existing installs get them with --update or --install

### Not added

- OMZP::macos: as a zinit snippet it sources two files that are not downloaded with it (music and spotify) and prints two errors on every shell. The svn ice that fetches the whole plugin needs Subversion, which is not installed here and which GitHub no longer serves. Its functions (ofd, cdf, pfd...) are not loaded

## [1.6.7] - 2026-10-29

### Added

- zsh-you-should-use (MichaelAquilina/zsh-you-should-use) in both plugin lists: when you type a command that has an alias, it reminds you of the alias (typing `git status` with `gst` defined prints `You should use: "gst"`). It reads the aliases at the time you run a command, so the order it loads in does not matter, and it works with the Oh My Zsh git snippet and forgit's renamed aliases. Its own settings (YSU_MESSAGE_POSITION, YSU_HARDCORE, YSU_IGNORED_ALIASES...) are read from your environment. It is not turned off by a ussuri setting: remove its line from `~/.ussuri/files/zinit/*.zsh`, or set `YSU_MODE=ALL`/`BESTMATCH` to change what it reports. Checked in a throwaway shell with the real plugin: with `alias gst="git status"` set, `git status` prints the reminder. Not checked in a full ussuri login with zinit's turbo loading

## [1.6.6] - 2026-10-28

### Added

- --set NAME VALUE, --unset NAME and --get NAME: change a setting for every new shell without editing the script (which --update replaces). They edit ~/.ussuri/config, the file the script already sources at the top of each login, and never the script. --set NAME=VALUE and several --set/--unset in one run also work. Names are the settings the config template lists (--force allows any other upper case name), true/false settings and PROMPT_ENGINE check their value, and a value is written quoted and never evaluated (a value holding $(...) or backticks is saved as text). A new setting goes in under its commented example in the template so the explanation stays; an existing active line is replaced in place; your own lines and comments are kept. The file is written to a temporary copy (keeping its permissions) and renamed, under the lock, so a shell starting at that moment never reads half of it, and the previous file is kept as ~/.ussuri/config.<date> (newest ten). --dryrun shows what would be written. --get says whether the value comes from the config, the environment or the built in default (and shows that default); with no name it lists every setting the template knows, plus any others the config sets, with value and source
- A few notes in the README on the prompt settings and which segments suit the top line

## [1.6.5] - 2026-10-27

### Added

- atuin (opt in): searchable shell history in place of Ctrl-R. Set INSTALL_ATUIN=true or use --tool atuin. It records every command, so it is in none of the package lists. It is installed with brew, pacman or nix (the package managers its documentation lists); on others it says to run cargo install atuin --locked. Its official install script, which signs you up to Atuin Cloud, is never used, and ussuri never registers, logs in or syncs. Its init goes through the init cache. The up arrow stays with history substring search (atuin is started with --disable-up-arrow) unless ATUIN_BIND_UP=true, in which case the substring search bindings for the arrows are skipped. Existing history is imported once when building (ATUIN_IMPORT=false skips it). --doctor reports it when asked for. Checked against a stub only: not yet against the real atuin
- Tests refuse any git clone from the network and log it, so a test can't download a repository

### Changed

- The init cache file name now includes the command, so the same tool run with different options has a cache for each rather than being served stale. Existing cache files are simply rebuilt once

## [1.6.4] - 2026-10-27

### Changed

- README rewritten and reorganised by what you are trying to do (quick start, how it works, usage, configuration with a settings reference, prompt, plugins, packages, languages and tools, system settings, dotfiles, maintenance, security notes, testing and CI, files and directories), with a generated table of contents. It had grown section by section and had two License sections, a 2024 install transcript and an out of date usage block. The usage block and install transcript are now the script's own output from a clean environment, and a check confirms every link resolves, every command line switch's long name appears, and every user facing setting in the script is documented (the rest are listed as internal). Features that were never documented are included: sudoers, --force and the lock, PATH and the build flags, GOPATH, the start directory, oh-my-zsh, fonts, rbenv and pyenv building, the alternative long switch names, and exit statuses
- Examples no longer use real user names, host names or third party names: the prompt example is alice@laptop, paths are ~/..., and the tap in the drift example, and in two tests, is example/tap

## [1.6.3] - 2026-10-27

### Added

- A two line powerlevel10k prompt: a configurable line above the one you have, starting with user@hostname. PROMPT_TOP_ELEMENTS (default: context) are the p10k segments on the left of the top line and PROMPT_TOP_RIGHT_ELEMENTS (default: none) on its right, and your existing line stays below with its right hand segments. PROMPT_TWO_LINE=false keeps a single line. It is applied by apply_prompt_top_line after ~/.p10k.zsh is read (so it works on top of any config, including one from p10k configure, and ~/.p10k.zsh and the shipped files/p10k/p10k.zsh are not edited), puts an explicit newline in both element lists, takes a segment moved to the top off the bottom line so it isn't repeated, makes context visible whatever the user (p10k hides it for a default user), leaves a config that already has more than one line alone, and asks p10k to reload. Segment names are limited to letters, digits and underscores and nothing is eval'd. Run through execute_command, so --dryrun shows it without doing it, with the show option so a warning isn't discarded. Checked in a real terminal with a copy of the real ~/.p10k.zsh: the default, a customised top line, and the switch off. A newline alone puts the right hand segments on the top line (p10k's default for a multi line prompt), which is why both lists get one
- --doctor reports whether the prompt is one or two lines and what is on the top one

## [1.6.2] - 2026-10-27

### Added

- CI: .github/workflows/ci.yml. The smoke tests and the package name check on macOS and Ubuntu runners, and on Debian, Ubuntu, Fedora, Arch and Alpine in containers, where --install, --doctor and --drift packages are also run for real (the paths the smoke tests can only check against stubs). Read only apart from the throwaway container. Not yet run on GitHub: the YAML is valid, and what it runs was checked locally
- tests/package-names.zsh: checks every package named in the shipped list for this system exists in its repositories (apt-cache show, pacman -Si, dnf repoquery, apk search -e, brew info), installing nothing, using the script's own distribution detection. Against the real Homebrew all 92 names in macos.brew and macos.cask were found. Tested offline with stub package managers, including the cask fallback

### Changed

- The smoke tests no longer depend on the host: they pretend to be macOS (TEST_OS, TEST_OS_REL) whatever they run on, and TEST_PATH_PREFIX puts another userland in front of the sandbox's PATH. Before they were only ever run on macOS, and on Linux the kernel version would have changed a setting count (USSURI_OS_REL now overrides the kernel release the script reads for a macOS version check)
- set_osx_file_state hides the error from the BSD-only ls -O on other systems, and where the flags can't be read it skips the check instead of reporting a setting that differs. Found by running the whole suite with GNU coreutils, sed and grep first in PATH (an approximation of a Linux userland): it passed 618 of 623, and the failures were this (four settings drift tests) and a test whose stat fallback was in the wrong order for GNU stat, both fixed

## [1.6.1] - 2026-10-27

### Added

- Package drift: -G|--drift [settings|packages|all] (a bare --drift is all, each part under a heading). Packages compares what is installed with your package lists, all their layers, from live queries and never the cached lists, read only. In a list but not installed is drift (exit status 1, what -P would install); installed because you chose it (brew leaves and casks, apt-mark showmanual, pacman -Qqe, dnf repoquery --userinstalled, the apk world file) but in no list is shown for information and is not drift, as that is what you would add to a local list. macOS covers taps, formulae and casks. Exit status 2 if there is nothing to compare with. Run against the real Homebrew: it found one genuinely missing formula (rust) and your 36 extra formulae, 23 casks and one tap

### Changed

- A bare --drift now includes packages; --drift settings is the previous behaviour. Settings drift is run_settings_drift

### Fixed

- Found by that real run: a name in the formula list that is installed as a cask (blackhole-2ch, multipass, utm, warp, xquartz are in the shipped macos.brew but are casks) was reported as a missing formula, though brew install falls back to the cask and -P already counts it as installed. The report now counts brew list (formulae and casks) as installed, and a name in either list as listed

## [1.6.0] - 2026-10-27

### Added

- Profiles and machines for packages and plugins, the same layering dotfiles already had. For a list in files/packages or files/zinit the layers are local.<ext>, profiles/<PROFILE>/local.<ext> and hosts/<MACHINE>/local.<ext> (casks and taps too), later ones winning, none of them touched by updates or --install. PROFILE (or -M) and MACHINE (default: the short hostname) are the one profile and machine name for dotfiles, packages and plugins; DOTFILES_PROFILE and DOTFILES_HOST still override them for dotfiles alone
- A package line !name takes a package out of what the earlier layers added (matched exactly, never as a pattern), and a later layer can put it back
- The profile is part of the package list checksum (only when there is one, so existing stamps are unchanged), so switching profile is noticed on a login. --doctor shows the profile, the machine and the local lists it found, layer by layer

### Fixed

- A profile or machine name is part of a file path, and wasn't checked: -M ../x or a DOTFILES_HOST of ../x read files outside the layers. Names with a slash or starting with a dot are now refused with a warning
- With an empty host name the dotfiles host layer became the hosts/ directory itself, linking every machine's files. It is now skipped

## [1.5.9] - 2026-10-27

### Added

- Casks and taps on macOS: files/packages/macos.cask and macos.tap (shipped with only comments, so nothing is installed or tapped by default) and your own local.cask, local.tap and local.brew, which updates never overwrite. -P adds taps first (so a formula from one can be found by its short name), then formulae, then casks (brew install --cask). A cask is "installed" if it is in brew list, and a tap if it is in brew tap (compared in lower case, as brew prints them). Each list has its own stamp. Checked against the real brew: brew list includes casks and tap names are lower case. An install from before these existed has its taps list written on its own

### Changed

- The package list code takes the list as an argument (package_layer_files, read_required_list, package_list_changed, all_packages_installed and process_package_list), which is what lets casks and taps be lists of their own

### Fixed

- Casks were never installed as casks, the Nerd Font included. verbose_message set a global called TYPE, and check_osx_package kept its package type in a global with the same name and then called verbose_message, which wiped it, so brew install ran without --cask and fails for a cask. verbose_message's variables are now local, and check_osx_package uses its own. A test checks the font is installed with --cask

## [1.5.8] - 2026-10-27

### Added

- An update hint, off unless UPDATE_HINT=true as it contacts GitHub from your shell. At most once a day a check runs in the background (a disowned job with its output detached, so a login never waits for it, and the stamp is touched first so shells opened together start one check) and writes the latest version to ~/.ussuri/update.latest, only if the answer looks like a version. If that is newer than this script a one line hint is shown at the next prompt, at most once a day, from a one-shot prompt hook (show_update_hint) rather than during startup. Only interactive logins, never a manual run. A normal login with it on costs nothing: the stamps are checked with glob qualifiers and the file read with $(<file), 0 external processes measured. Checked in a real terminal (hint shown once at the first prompt, not on the next session), a real fetch from GitHub parsed correctly, and a test proves the login returns while the fetch is still running. --doctor reports it and warns when an update is available

## [1.5.7] - 2026-10-27

### Added

- Undo for OS X defaults. Each setting the script changes is journalled in ~/.ussuri/defaults.journal (run, domain, key, previous type and value or "not set", value set), quoted with ${(q)} and read back with ${(Q)} so any value is safe and nothing is eval'd. An entry is written only after a read back shows the write took effect, so declined (--confirm), refused or ignored writes (e.g. a domain that doesn't take) are not recorded and --dryrun records nothing
- -J|--defaults-undo [N|list]: list the runs, or put back the newest (or Nth newest) run, each setting with its previous type and value, or deleted if it was not set. A setting changed since by you is left alone and reported, as is one whose previous value was an array or dictionary. The Dock and Finder are restarted as needed (restart_osx_services, now shared with applying), the run is then marked undone so the next undo goes back one run, and --dryrun and --confirm are honoured. --doctor says how many runs can be undone. Checked against the real defaults binary on a scratch plist: types, an awkward string (quote and tab) and a new key all came back exactly. Only changes made from this version on are recorded; Linux GNOME settings are not covered

## [1.5.6] - 2026-10-27

### Added

- --update now fetches the release archive (UPDATE_URL, default GitHub's main tarball) and updates the supporting files as well as the script. New files are added, changed ones replaced after the old copy is saved in ~/.ussuri/files.bak/<date>/, nothing is deleted, and local.* files are never touched. Before, --update replaced only ussuri.zsh, so new plugin and package lists never arrived. The archive is refused if its script doesn't parse or isn't the expected version, if any path in it is absolute or contains .. (nothing is written outside the temporary directory), or if UPDATE_SHA256 is set and doesn't match; if it can't be fetched the script alone is updated, with a warning. Checked against GitHub's real archive layout
- Your own plugins and packages in files that updates and --install never overwrite: ~/.ussuri/files/zinit/local.zsh (run after the shipped list, same format) and ~/.ussuri/files/packages/local.<ext> (local.brew, local.apt, local.pacman, local.dnf, local.apk, local.nix). Both lists are in the package checksum, so a package added to the local list is noticed. --doctor reports them

### Fixed

- A release that fails validation is now always reported (the warning was only shown with --verbose)

## [1.5.5] - 2026-10-27

### Changed

- One prompt engine instead of two. PROMPT_ENGINE is p10k (default), posh or none, and decides which of powerlevel10k and oh-my-posh is installed, set up on login, and loaded by the zinit plugin lists (the powerlevel10k plugin is now `if prompt_engine_is p10k`). Before, both were set up on every login and both hooked every prompt (checked in a real terminal: _omp_precmd and _p9k_precmd side by side), which also cost time: with the real script and oh-my-posh a login went from about 167 to 129 ms. An unknown value warns and falls back to p10k
- -o selects oh-my-posh and -T powerlevel10k for that run, -E|--prompt|--engine NAME selects either, and -A (do all) now follows the engine instead of doing both. The last one given wins
- --doctor reports the engine, only looks for the engine's own tool, and warns if DO_POSH_CHECK or DO_P10K_CHECK is on for the other engine. Existing installs need --install to refresh their copy of the plugin lists, otherwise their lists load powerlevel10k whatever the engine is

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
