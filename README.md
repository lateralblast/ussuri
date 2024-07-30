![alt tag](ussuri.gif)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 0.4.2

Introduction
------------

This script is designed to set up a zsh environment from scratch.
It is coppied to .zshrc and runs inline, i.e. when you login or
execute a new shell it will check the current environment and
install components/configurations if they are not present.

Usage
-----

```
  When run manually with switches:

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -I|--install      Install ussuri as /Users/spindler/.zshrc
    -b|--build        Build sources       (default: false)
    -c|--confirm      Confirm commands    (default: false)
    -C|--check.       Check for updates   (default: false)
    -d|--debug        Enable debug        (default: false)
    -D|--default(s)   Set defaults        (default: false)
    -f|--font(s).     Install font(s)     (default: false)
    -n|--notheme      No zsh theme        (default: true)
    -N|--noenv        Ignore environment  (default: true)
    -o|--ohmyposh     Install oh my posh  (default: false)
    -O|--ohmyzsh      Install oh my zsh   (default: false)
    -p|--pyenv        Do pyenv check      (default: false)
    -P|--package(s)   Do packages check   (default: false)
    -r|--rbenv        Do rbenv check      (default: false)
    -t|--dryrun       Dry run mode        (default: false)
    -T|--p10k         Do p10k config      (default: false)
    -U|--update       Check for updates   (default: false)
    -v|--verbose      Verbose output      (default: false)
    -z|--zinit        Do zinit check      (default: false)
    -Z|--zshheme      Set zsh theme       (default: robbyrussell)

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
    Do p10k  check        true
    Do oh-my-posh check:  true
    Do oh-my-zsh check:   false
    Do verbose mode       false
```

License
-------

This software is licensed as CC-BA (Creative Commons By Attrbution)

http://creativecommons.org/licenses/by/4.0/legalcode
