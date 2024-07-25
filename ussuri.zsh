#!/usr/bin/env zsh
#
# Version: 0.2.7
#

SCRIPT_FILE="$0"

# Get the version of the script from the script itself

SCRIPT_VERSION=$( grep '^# Version' < "$0"| awk '{print $3}' )

# Handle output

handle_output () {
  OUTPUT="$1"
  STYLE="$2"
  case "$STYLE" in
    warn|warning)
      echo "Warning:        $OUTPUT"
      ;;
    execute|executing)
      echo "Executing:      $OUTPUT"
      ;;
    command)
      echo "Command:        $OUTPUT"
      ;;
    info|information)
      echo "Information:    $OUTPUT"
      ;;
    *)
      echo "$OUTPUT"
      ;;
  esac
}

# Execute command

execute_command () {
  COMMAND="$1"
  if [ "$DO_VERBOSE" = "true" ] || [ "$DO_DRYRUN" = "true" ]; then
    handle_output "$COMMAND" "execute"
  fi
  if [ "$DO_DRYRUN" = "false" ]; then
    if [ "$DO_CONFIRM" = "true" ]; then
      RESPONSE=""
      handle_output "$COMMAND" "command" 
      vared -p "Execute [y/n]:  " RESPONSE
      if [ "$RESPONSE" = "y" ]; then
        eval "$COMMAND"
      fi
    else
      eval "$COMMAND"
    fi
  fi
}

# Priny help information

print_help () {
  cat <<-HELP

  Usage: $SCRIPT_FILE [OPTIONS...]

  When run manually with switches:

    -c|--confirm      Confirm commands (default: $DO_CONFIRM)
    -C|--check.       Check for updates (default: $DO_UPDATE_CHECK)
    -d|--debug        Print debug information while executing (default $DO_DEBUG)
    -D|--default(s)   Set defaults (default: $DO_DEFAULTS_CHECK)
    -e|--changelog.   Print changelog
    -f|--font(s).     Install font(s) (default: $DO_FONTS_CHECK)
    -h|--help         Print usage information
    -I|--install      Install $SCRIPT_NAME as $HOME/.zshrc
    -n|--notheme      No zsh theme (default: $ZSH_THEME)
    -N|--noenv        Do not initiate environment variables (default: $DO_ENV_SETUP)
    -o|--ohmyposh     Install oh my posh (default: $DO_POSH_CHECK)
    -p|--pyenv        Do pyenv check (default: $DO_PYENV_CHECK)
    -P|--package(s)   Do packages check (default: $DO_PACKAGE_CHECK)
    -r|--rbenv        Do rbenv check (default: $DO_RBENV_CHECK)
    -t|--dryrun       Dry run (default: $DO_DRYRUN)
    -T|--p10k         Do Powerlevel10k config (default: $DO_P10K_CHECK)
    -U|--update       Check git for updates (default: $DO_UPDATE_CHECK)
    -v|--verbose      Verbose output (default: $DO_VERBOSE)
    -V|--version      Print version
    -z|--zinit        Do zinit check (default: $DO_ZINIT_CHECK)
    -Z|--zshheme      Zsh theme (default: $DO_ZSH_THEME)
HELP
set_inline_defaults
cat <<-INLINE

  Defaults when run inline (i.e. as login script):

    Do defaults check:    $DO_DEFAULTS_CHECK
    Do package check:     $DO_PACKAGE_CHECK
    Do zinit check:       $DO_ZINIT_CHECK
    Do pyenv check:       $DO_PYENV_CHECK
    Do rbenv check:       $DO_RBENV_CHECK
    Do fonts check:       $DO_FONTS_CHECK
    Do oh-my-poss check:  $DO_POSH_CHECK
    Do oh-my-zsh check:   $DO_ZOSH_CHECK

INLINE
}

# Install script as .zshrc

do_install () {
  execute_command "cp $HOME/.zshrc $WORK_DIR/.zshrc.$DATE_SUFFIX"
  execute_command "cp $SCRIPT_FILE ~/.zshrc"
}

# Print changelog

print_changelog () {
  SCRIPT_DIR=$( dirname "$SCRIPT_FILE" )
  CHANGE_FILE="$SCRIPT_DIR/changelog"
  echo ""
  echo "Changelog:"
  echo ""
  if [ -f "$CHANGE_FILE" ]; then
    grep "^#" "$CHANGE_FILE" | sed "s/^# //g"
  else
    CHANGE_URL="https://raw.githubusercontent.com/lateralblast/ussuri/main/changelog" 
    curl -vs "$CHANGE_URL" 2>&1 | grep "^#" |sed "s/^# //g" 
  fi
  echo ""
}

# Set All Defaults

set_all_defaults () {
  OS_NAME=$(uname -o)
  DO_VERBOSE="false"
  DO_DRYRUN='false'
  DO_CONFIRM="false"
  SCRIPT_NAME="ussuri"
  WORK_DIR="$HOME/.$SCRIPT_NAME"
  INSTALL_ZINIT="true"
  INSTALL_RBENV="true"
  INSTALL_PYENV="true"
  INSTALL_POSH="true"
  INSTALL_OZSH="false"
  ZINIT_HOME="$HOME/.zinit"
  RBENV_HOME="$HOME/.rbenv"
  PYENV_HOME="$HOME/.pyenv"
  POSH_HOME="$HOME/.oh-my-posh"
  ZOSH_HOME="$HOME/.oh-my-zsh"
  P10K_INIT="$HOME/.p10k.zsh"
  P10k_HOME="$HOME/.powerlevel10k" 
  P10K_THEME="$P10k_HOME/powerlevel10k.zsh-theme"
  RUBY_VER="3.3.4"
  PYTHON_VER="3.12.4"
  DO_INSTALL="false"
  DO_VERSION_CHECK="false"
  DO_DEFAULTS_CHECK="false"
  DO_PACKAGE_CHECK="false"
  DO_UPDATE_CHECK="false"
  DO_UPDATE_FUNCT="false"
  DO_PYENV_CHECK="false"
  DO_RBENV_CHECK="false"
  DO_ZINIT_CHECK="false"
  DO_FONTS_CHECK="false"
  DO_POSH_CHECK="false"
  DO_P10K_CHECK="false"
  DO_ZOSH_CHECK="false"
  DO_ENV_SETUP="true"
  DO_ZSH_THEME="false"
  ZSH_THEME="robbyrussell"
  DATE_SUFFIX=$( date +%d_%m_%Y_%H_%M_%S )
  if [ ! -d "$WORK_DIR" ]; then
    execute_command "mkdir -p $WORK_DIR"
  fi
}

# Reset all defaults (when script is run inline i.e. as a login script with no options)

set_inline_defaults () {
  DO_DEFAULTS_CHECK="true"
  DO_PACKAGE_CHECK="true"
  DO_ZINIT_CHECK="true"
  DO_PYENV_CHECK="true"
  DO_RBENV_CHECK="true"
  DO_FONTS_CHECK="true"
  DO_POSH_CHECK="true"
  DO_ZOSH_CHECK="false"
  DO_P10K_CHECK="true"
  DO_ZSH_THEME="true"
}

# Check zinit config

check_zinit_config () {
  if [ "$INSTALL_ZINIT" = "true" ]; then
    if [ ! -d "$ZINIT_HOME" ]; then
      execute_command "git clone https://github.com/zdharma-continuum/zinit.git $ZINIT_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      execute_command ". $ZINIT_HOME/zinit.zsh"
    fi
    # Add in zsh plugins
    execute_command "zinit light zsh-users/zsh-syntax-highlighting"
    execute_command "zinit light zsh-users/zsh-completions"
    execute_command "zinit light zsh-users/zsh-autosuggestions"
    execute_command "zinit light Aloxaf/fzf-tab"
    # Add in snippets
    execute_command "zinit snippet OMZP::git"
    execute_command "zinit snippet OMZP::sudo"
    execute_command "zinit snippet OMZP::archlinux"
    execute_command "zinit snippet OMZP::aws"
    execute_command "zinit snippet OMZP::kubectl"
    execute_command "zinit snippet OMZP::kubectx"
    execute_command "zinit snippet OMZP::command-not-found"
    # Load completions
    execute_command "autoload -Uz compinit && compinit"
    execute_command "zinit cdreplay -q"
  fi
}

# Check rbenv

check_rbenv_config () {
  if [ "$INSTALL_RBENV" = "true" ]; then
    if [ ! -d "$RBENV_HOME" ]; then
      execute_command "git clone https://github.com/rbenv/rbenv.git $RBENV_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      execute_command "export RBENV_ROOT=\"$RBENV_HOME\""
      execute_command "export PATH=\"$PYENV_HOME/bin:$PATH\""
      execute_command "rbenv init - zsh )"
      RBENV_CHECK=$( rbenv versions --bare )
      if [ -z "$RBENV_CHECK" ]; then
        execute_command "rbenv install $RUBY_VER"
        execute_command "rbenv global $RUBY_VER"
      fi
    fi
  fi
}

# Check pyenv

check_pyenv_config () {
  if [ "$INSTALL_PYENV" = "true" ]; then
    if [ ! -d "$PYENV_HOME" ]; then
      execute_command "git clone https://github.com/rbenv/rbenv.git $PYENV_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      execute_command  "export PYENV_ROOT=\"$PYENV_HOME\""
      execute_command  "export PATH=\"$PYENV_HOME/bin:$PATH\""
      execute_command  "pyenv init - "
      PYENV_CHECK=$( pyenv versions --bare )
      if [ -z "$PYENV_CHECK" ]; then
        execute_command "rbenv install $PYTHON_VER"
        execute_command "rbenv global $PYTHON_VER"
      fi
    fi
  fi
}

# Check fonts config

check_fonts_config () {
  if [ "$OS_NAME" = "Darwin" ]; then
    check_osx_package "font-fira-code-nerd-font" "cask"
  fi
}

# Check oh-my-posh config

check_posh_config () {
  if [ "$INSTALL_POSH" = "true" ]; then
    if [ ! -d "$POSH_HOME" ]; then
      execute_command "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d $POSH_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      execute_command "export POSH_ROOT=\"$POSH_HOME\""
      execute_command "export PATH=\"$POSH_HOME/bin:$PATH\""
      execute_command "oh-my-posh init zsh )"
    fi
  fi
}

# Check oh-my-zsh config

check_zosh_config () {
  if [ "$INSTALL_ZOSH" = "true" ]; then
    if [ ! -d "$ZOSH_HOME" ]; then
      execute_command "git clone https://github.com/ohmyzsh/ohmyzsh.git $ZOSH_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
#      execute_command "export ZOSH_ROOT=\"$ZOSH_HOME\""
#      execute_command "export PATH=\"$ZOSH_HOME/bin:$PATH\""
#      execute_command "oh-my-posh init zsh )"
      execute_command "source $ZOSH_HOME/oh-my-zsh.sh"
    fi
  fi
}

# Check Powerlevel10k config

check_p10k_config () {
  if [ "$INSTALL_P10K" = "true" ]; then
    if [ "$INSTALL_ZINIT" = "false" ]; then
      if [ ! -d "$P10k_HOME" ]; then
        execute_command "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $P10k_HOME"
      fi
      if [ "$DO_ENV_SETUP" = "true" ]; then
        execute_command "typeset -g POWERLEVEL9K_INSTANT_PROMPT=off"
        if [ -f "$P10K_INIT" ]; then
          execute_command "p10k configure"
        fi
        execute_command "source $P10K_INIT"
        if [ -f "$P10K_THEME" ]; then
          execute_command "source $P10K_THEME"
        fi
      else
        execute_command "zinit ice depth=1; zinit light romkatv/powerlevel10k"
      fi
    fi
  fi
}

# Check OSX Defaults

osx_defaults_check () {
  APP="$1"
  PARAM="$2"
  TYPE="$3"
  VALUE="$4"
  ACTUAL=$( defaults read "$APP" "$PARAM" )
  if [ "$ACTUAL" != "$VALUE" ]; then
    if [ ! "$TYPE" = "" ]; then
      execute_command "defaults write $APP $PARAM -$TYPE $VALUE"
    else
      execute_command "defaults write $APP $PARAM $VALUE"
    fi
    if [[ "$APP" =~ "Finder" ]]; then
      RESTART_FINDER="true"
    fi
    if [[ "$APP" =~ "SystemUIServer" ]]; then
      RESTART_UISERVER="true"
    fi
  fi
}

# Set OSX defaults

set_osx_defaults () {
  INSTALL_BREW="true"
  SHOW_HIDDEN_FILES="true"
  RESTART_FINDER="false"
  RESTART_UISERVER="false"
  SCREENSHOT_LOCATION="$HOME/Pictures/Screenshots"
  BREW_LIST="$WORK_DIR/brew.list"
  PACKAGE_LIST=( ansible ansible-lint autoconf automake bat bash \
                 blackhole-2ch bpytop btop bzip2 ca-certificates cmake cpio \
                 cpufetch curl docker dos2unix exiftool ffmpeg flac fortune \
                 fzf gcc gettext ghostscript giflib git git-lfs gmp gnu-getopt \
                 gnu-sed gnutls go grep htop jpeg-turbo jpeg-xl jq imagemagick \
                 lame lego lftp libarchive libheif libogg libpng libvirt libvirt-glib \
                 libvirt-python libvorbis libxml2 libyaml lsd lua lz4 lzo mpg123 \
                 multipass netpbm openssh openssl@3 opentofu osinfo-db osx-cpu-temp \
                 p7zip pwgen python@3.12 qemu rpm2cpio ruby ruby-build rust shellcheck \
                 socat sqlite tcl-tk tesseract tmux tree utm virt-manager warp wget \
                 xorriso x264 x265 xquartz xz zsh )
}

# Update package list

update_package_list () {
  if [ "$OS_NAME" = "Darwin" ]; then
    if [ ! -f "$BREW_LIST" ]; then
      execute_command "brew list | sort > $BREW_LIST"
    fi
    REQ_LIST="$WORK_DIR/$SCRIPT_NAME.list" 
    REQ_TEST=$( find "$REQ_LIST" -mtime -5 2> /dev/null )
    if [ -z "$REQ_TEST" ]; then
      if [ -f "$REQ_TEST" ]; then
        rm "$REQ_LIST"
      fi
      touch "$REQ_LIST"
      for PACKAGE in $PACKAGE_LIST; do
        echo "$PACKAGE" >> "$REQ_LIST"
      done
    fi
  fi
}

# Check OS defaults

check_osx_defaults () {
  if [ ! -d "$SCREENSHOT_LOCATION" ]; then
    execute_command "mkdir -p $SCREENSHOT_LOCATION"
  fi
  osx_defaults_check "com.apple.screencapture" "location" "string" "$SCREENSHOT_LOCATION" 
  if [ "$SHOW_HIDDEN_FILES" = "true" ]; then
    osx_defaults_check "com.apple.Finder" "AppleShowAllFiles" "" "$SHOW_HIDDEN_FILES" 
    execute_command "chflags nohidden $HOME/Library"
  fi
  if [ "$RESTART_FINDER" = "true" ]; then
   execute_command "killall Finder"
  fi
  if [ "$RESTART_UISERVER" = "true" ]; then
    execute_command "killall SystemUIServer"
  fi
}

# Check OSX Package

check_osx_package () {
  PACKAGE="$1"
  TYPE="$2"
  if [ "$INSTALL_BREW" = "true" ]; then
    PACKAGE_TEST=$( grep "^$PACKAGE$" "$BREW_LIST" )
    if [ -z "$PACKAGE_TEST" ]; then
      if [ "$TYPE" = "cask" ]; then
        execute_command "brew install --cask $PACKAGE"
      else
        execute_command "brew install $PACKAGE"
      fi
      update_package_list
    fi
  fi  
}

# Check OSX Applications

check_osx_packages () {
  if [ "$INSTALL_BREW" = "true" ]; then
    BREW_TEST=$(command -v brew)
    if [ -z "$BREW_TEST" ]; then
      for BREW_FILE in /opt/homebrew/bin/brew /usr/local/homebrew/bin/brew; do
        if [ -f "$BREW_FILE" ]; then
          BREW_BIN="$BREW_FILE"
        fi
      done
      if [ -z "$BREW_BIN" ]; then
        execute_command "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
      else
        if [ "$DO_ENV_SETUP" = "true" ]; then
          execute_command "$BREW_BIN shellenv"
        fi
      fi
    else
        if [ "$DO_ENV_SETUP" = "true" ]; then
         execute_command "$BREW_TEST shellenv"
       fi
    fi
    for PACKAGE in $PACKAGE_LIST; do
      check_osx_package "$PACKAGE" ""
    done
  fi
}

# Check for update

check_for_update () {
  README_URL="https://raw.githubusercontent.com/lateralblast/ussuri/main/README.md" 
  REMOTE_VERSION=$( curl -vs "$README_URL" 2>&1 | grep "Current Version" | awk '{ print $3 }' )
  LOCAL_VERSION="${SCRIPT_VERSION/\./}"
  LOCAL_VERSION="${LOCAL_VERSION/\./}"
  echo "Local version:  $SCRIPT_VERSION"
  echo "Remote version: $REMOTE_VERSION"
  REMOTE_VERSION="${REMOTE_VERSION/\./}"
  REMOTE_VERSION="${REMOTE_VERSION/\./}"
  if [ "$LOCAL_VERSION" -lt "$REMOTE_VERSION" ]; then
    handle_output "Local version is older than remote version" "info"
  else
    if [ "$LOCAL_VERSION" -gt "$REMOTE_VERSION" ]; then
      handle_output "Local version is newer than remote version" "info"
    else
      handle_output "Local version is the same as remote version" "info"
    fi
  fi
}

# Set defaults

set_defaults () {
  set_all_defaults
  if [ "$OS_NAME" ]; then
    set_osx_defaults
  fi
}

# Check defaults

check_defaults () {
  if [ "$OS_NAME" = "Darwin" ]; then
    check_osx_defaults
  fi
}

# Check packages

check_package_config () {
  if [ "$OS_NAME" = "Darwin" ]; then
    check_osx_packages
  fi
}

# Set defauts

set_defaults

# If given no command arguments run as a normal login script
# Otherwise handle commandline argument

if [ ! "$*" = "" ]; then
  while test $# -gt 0; do
    case $1 in
      -c|--confirm)
        DO_CONFIRM="true"
        shift
        ;;
      -C|--check)
        DO_VERSION_CHECK="true"
        shift
        ;;
      -d|--debug)
        DO_DEBUG="true"
        shift
        ;;
      -D|--default|--defaults)
        DO_DEFAULTS_CHECK="true"
        shift
        exit
        ;;
      -e|--changes|--changelog)
        print_changelog
        shift
        exit
        ;;
      -f|--font|--fonts)
        DO_FONTS_CHECK="true"
        shift
        ;;
      -h|--help|--usage)
        print_help
        shift
        exit
        ;;
      -I|--install)
        DO_INSTALL="true"
        shift
        ;;
      -n|--nothene)
        DO_ZSH_THEME="false"
        shift
        ;;
      -N|--noenv)
        DO_ENV_SETUP="false"
        shift
        ;;
      -o|--ohmyposh)
        DO_FONTS_CHECK="true"
        DO_POSH_CHECK="true"
        shift
        ;;
      -P|--package|--packages)
        DO_PACKAGE_CHECK="true"
        shift
        ;;
      -p|--pyenv)
        DO_PYENV_CHECK="true"
        shift
        ;;
      -r|--rbenv)
        DO_RBENV_CHECK="true"
        shift
        ;;
      -t|--test|--dryrun)
        DO_DRYRUN="true"
        shift
        handle_output "Running without executing commands"
        ;;
      -T|--p10k)
        DO_P10K_CHECK="true"
        shift
        ;;
      -U|--update)
        DO_UPDATE_FUNCT="true"
        shift
        ;;
      -v|--verbose)
        DO_VERBOSE="true"
        shift
        ;;
      -V|--version)
        echo "$SCRIPT_VERSION"
        shift
        exit
        ;;
      -z|--zinit)
        DO_ZINIT_CHECK="true"
        shift
        ;;
      -Z|--zshtheme)
        ZSH_THEME="$2"
        shift 2
        ;;
      *)
        print_help
        exit
        ;;
    esac
  done
else
  set_inline_defaults
fi

# Set debug

if [ "$DO_DEBUG" = "true" ]; then
  set -x
fi

# Do install

if [ "$DO_INSTALL" = "true" ]; then
  DO_ENV_SETUP="false"
  do_install
  exit
fi

# Do check defaults

if [ "$DO_DEFAULTS_CHECK" = "true" ]; then
  check_defaults
fi

# Do check for updates

if [ "$DO_UPDATE_CHECK" = "true" ] || [ "$DO_VERSION_CHECK" = "true" ]; then
  check_for_update
  if [ "$DO_UPDATE_CHECK" = "true" ]; then
    update_script
  fi
  exit
fi

# Do OSX specific checks

if [ "$OS_NAME" = "Darwin" ]; then
  update_package_list
  check_osx_packages
fi

# Do font(s) check

if [ "$DO_FONTS_CHECK" = "true" ]; then
  check_fonts_config
fi

if [ "$DO_POSH_CHECK" = "true" ]; then
  check_posh_config
fi

# Do package check

if [ "$DO_PACKAGE_CHECK" ]; then
  check_package_config
fi

# Do zinit checks

if [ "$DO_ZINIT_CHECK" = "true" ]; then
  check_zinit_config
fi

# Do pyenv checks

if [ "$DO_PYENV_CHECK" = "true" ]; then
  check_pyenv_config
fi

# Do rbenv checks

if [ "$DO_RBENV_CHECK" = "true" ]; then
  check_rbenv_config
fi

# Do Powerlevel10k config

if [ "$DO_P10K_CHECK" = "true" ]; then
  check_p10k_config
fi

# Handle zsh theme

if [ "$DO_ZSH_THEME" = "false" ]; then
  ZSH_THEME=""
fi
