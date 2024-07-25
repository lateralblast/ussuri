![alt tag](ussuri.gif)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 0.2.7

Introduction
------------

This script is designed to set up a zsh environment from scratch.
It is coppied to .zshrc and runs inline, i.e. when you login or
execute a new shell it will check the current environment and
install components/configurations if they are not present.

Usage
-----

```
  Usage: ./ussuri.zsh [OPTIONS...]

  When run manually with switches:

    -c|--confirm      Confirm commands (default: false)
    -C|--check.       Check for updates (default: false)
    -d|--debug        Print debug information while executing (default )
    -D|--default(s)   Set defaults (default: false)
    -e|--changelog.   Print changelog
    -f|--font(s).     Install font(s) (default: false)
    -h|--help         Print usage information
    -I|--install      Install ussuri as /Users/spindler/.zshrc
    -n|--notheme      No zsh theme (default: robbyrussell)
    -N|--noenv        Do not initiate environment variables (default: true)
    -o|--ohmyposh     Install oh my posh (default: false)
    -p|--pyenv        Do pyenv check (default: false)
    -P|--package(s)   Do packages check (default: false)
    -r|--rbenv        Do rbenv check (default: false)
    -t|--dryrun       Dry run (default: false)
    -T|--p10k         Do Powerlevel10k config (default: false)
    -U|--update       Check git for updates (default: false)
    -v|--verbose      Verbose output (default: false)
    -V|--version      Print version
    -z|--zinit        Do zinit check (default: false)
    -Z|--zshheme      Zsh theme (default: false)

  Defaults when run inline (i.e. as login script):

    Do defaults check:    true
    Do package check:     true
    Do zinit check:       true
    Do pyenv check:       true
    Do rbenv check:       true
    Do fonts check:       true
    Do oh-my-poss check:  true
    Do oh-my-zsh check:   false
```

License
-------

This software is licensed as CC-BA (Creative Commons By Attrbution)

http://creativecommons.org/licenses/by/4.0/legalcode
