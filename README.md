![alt tag](ussuri.jpg)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 0.8.5

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

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -A|--doall        Do all fuction (where set to true)
    -i|--inline       Set inline defaults when not runing inline mode
    -I|--install      Installs ussuri as: /Users/spindler/.zshrc
    -b|--build        Build sources       (default: false)
    -c|--confirm      Confirm commands    (default: false)
    -C|--check.       Check for updates   (default: false)
    -d|--debug        Enable debug        (default: false)
    -D|--default(s)   Set defaults        (default: false)
    -f|--font(s)      Install font(s)     (default: false)
    -m|--manager      Plugin manager      (default: zinit)
    -n|--notheme      No zsh theme        (default: true)
    -N|--noenv        Ignore environment  (default: true)
    -o|--ohmyposh     Install oh my posh  (default: false)
    -O|--ohmyzsh      Install oh my zsh   (default: false)
    -p|--pyenv        Do pyenv check      (default: false)
    -P|--package(s)   Do packages check   (default: false)
    -r|--rbenv        Do rbenv check      (default: false)
    -s|--startdir     Set start dir       (default: none)
    -t|--dryrun       Dry run mode        (default: false)
    -T|--p10k         Do p10k config      (default: false)
    -U|--update       Check for updates   (default: false)
    -v|--verbose      Verbose output      (default: false)
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

Some defaults can be overridden by declaring them at the top of the script, e.g. DO_VERBOSE.

License
-------

This software is licensed as CC-BA (Creative Commons By Attrbution)

http://creativecommons.org/licenses/by/4.0/legalcode
