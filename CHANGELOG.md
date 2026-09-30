# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

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
