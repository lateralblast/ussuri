![alt tag](ussuri.gif)

ussuri
======

Unix Shell Setup Utility Run Inline

Also a breed of cat...

https://www.catster.com/cat-breeds/ussuri-cat/

Version
-------

Current Version: 0.1.7

Introduction
------------

This script is designed to set up a zsh environment from scratch.
It is coppied to .zshrc and runs inline, i.e. when you login or
execute a new shell it will check the current environment and
install components/configurations if they are not present.

Usage
-----

```
./ussuri.sh --help

  Usage: ussuri.sh [OPTIONS...]

    -c|--confirm      Confirm commands
    -C|--check.       Check for updates
    -d|--debug        Print debug information while executing
    -D|--default(s)   Set defaults
    -e|--changelog.   Print changelog
    -h|--help         Print usage information
    -N|--noenv        Do not initiate environment variables
    -p|--pyenv        Do pyenv check
    -P|--package(s)   Do packages check
    -r|--rbenv        Do rbenv check
    -t|--dryrun       Dry run
    -U|--update       Check git for updates
    -v|--verbose      Verbose output
    -V|--version      Print version
    -z|--zinit        Do zinit check
```

License
-------

This software is licensed as CC-BA (Creative Commons By Attrbution)

http://creativecommons.org/licenses/by/4.0/legalcode
