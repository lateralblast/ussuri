#!/usr/bin/env zsh
#
# Version: 0.4.3
#

SCRIPT_FILE="$0"

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
    set|setting)
      echo "Setting:        $OUTPUT"
      ;;
    *)
      echo "$OUTPUT"
      ;;
  esac
}

# Verbose message

verbose_message () {
  MESSAGE="$1"
  TYPE="$2"
  if [ "$DO_VERBOSE" = "true" ]; then
    if [ "$TYPE" = "" ]; then
      handle_output "$MESSAGE" "info"
    else
      handle_output "$MESSAGE" "$TYPE"
    fi
  fi
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
        if [ "$DO_VERBOSE" = "true" ]; then
          eval "$COMMAND"
        else
          eval "$COMMAND > /dev/null 2>&1"
        fi
      fi
    else
      if [ "$DO_VERBOSE" = "true" ]; then
        eval "$COMMAND"
      else
        eval "$COMMAND > /dev/null 2>&1"
      fi
    fi
  fi
}

# Read file into array and process

execute_from_file () {
  FILE="$1"
  for LINE in "${(@f)"$(<FILE)"}"; do
    if [[ ! "$LINE" =~ "^#" ]]; then
      execute_command "$LINE"
    fi
  done
}

# Priny help information

print_help () {
  cat <<-HELP

  Usage: $SCRIPT_FILE [OPTIONS...]

  When run manually with switches:

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -I|--install      Install $SCRIPT_NAME as $HOME/.zshrc
    -b|--build        Build sources       (default: $DO_BUILD)
    -c|--confirm      Confirm commands    (default: $DO_CONFIRM)
    -C|--check.       Check for updates   (default: $DO_UPDATE_CHECK)
    -d|--debug        Enable debug        (default: $DO_DEBUG)
    -D|--default(s)   Set defaults        (default: $DO_DEFAULTS_CHECK)
    -f|--font(s)      Install font(s)     (default: $DO_FONTS_CHECK)
    -m|--manager      Plugin manager      (default: $PLUGIN_MANAGER)
    -n|--notheme      No zsh theme        (default: $DO_ZSH_THEME)
    -N|--noenv        Ignore environment  (default: $DO_ENV_SETUP)
    -o|--ohmyposh     Install oh my posh  (default: $DO_POSH_CHECK)
    -O|--ohmyzsh      Install oh my zsh   (default: $DO_ZOSH_CHECK)
    -p|--pyenv        Do pyenv check      (default: $DO_PYENV_CHECK)
    -P|--package(s)   Do packages check   (default: $DO_PACKAGE_CHECK)
    -r|--rbenv        Do rbenv check      (default: $DO_RBENV_CHECK)
    -t|--dryrun       Dry run mode        (default: $DO_DRYRUN)
    -T|--p10k         Do p10k config      (default: $DO_P10K_CHECK)
    -U|--update       Check for updates   (default: $DO_UPDATE_CHECK)
    -v|--verbose      Verbose output      (default: $DO_VERBOSE)
    -z|--zinit        Do zinit check      (default: $DO_ZINIT_CHECK)
    -Z|--zshtheme     Set zsh theme       (default: $ZSH_THEME)
HELP
set_inline_defaults
cat <<-INLINE

  Defaults when run inline (i.e. as login script):

    Do build mode         $DO_BUILD
    Do confirm mode       $DO_CONFIRM
    Do update check       $DO_UPDATE_CHECK
    Do debug mode         $DO_DEBUG
    Do defaults check:    $DO_DEFAULTS_CHECK
    Do fonts check:       $DO_FONTS_CHECK
    Do package check:     $DO_PACKAGE_CHECK
    Do zinit check:       $DO_ZINIT_CHECK
    Do pyenv check:       $DO_PYENV_CHECK
    Do rbenv check:       $DO_RBENV_CHECK
    Do p10k  check        $DO_P10K_CHECK
    Do oh-my-posh check:  $DO_POSH_CHECK
    Do oh-my-zsh check:   $DO_ZOSH_CHECK
    Do verbose mode       $DO_VERBOSE
    Plugin Manager:       $PLUGIN_MANAGER

INLINE
}

# Install script as .zshrc

do_install () {
  verbose_message "Backing up $HOME/.zshrc to $WORK_DIR/.zshrc.$DATE_SUFFIX"
  execute_command "cp $HOME/.zshrc $WORK_DIR/.zshrc.$DATE_SUFFIX"
  verbose_message "Replacing $HOME/.zshrc"
  execute_command "cp $SCRIPT_FILE $HOME/.zshrc"
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

# Set environment

set_env () {
  PARAM="$1"
  VALUE="$2"
  verbose_message "Environment parameter \"$PARAM\" to \"$VALUE\"" "set"
  eval "export $PARAM=\"$VALUE\""
}

# Set All Defaults

set_all_defaults () {
  SCRIPT_VERSION=$( grep '^# Version' < "$SCRIPT_FILE" |  awk '{print $3}' )
  OS_NAME=$(uname -o)
  DATE_SUFFIX=$( date +%d_%m_%Y_%H_%M_%S )
  verbose_message "Setting defaults"
  execute_command "PATH=\"/usr/local/bin:/usr/local/sbin:$PATH\""
  execute_command "LD_LIBRARY_PATH=\"/usr/local/lib:$LD_LIBRARY_PATH\""
  set_env "DO_HELP"           "false"
  set_env "DO_DRYRUN"         "false"
  set_env "DO_CONFIRM"        "false"
  set_env "DO_DEBUG"          "false"
  set_env "DO_BUILD"          "false"
  set_env "DO_PLUGINS"        "true"
  set_env "SCRIPT_NAME"       "ussuri"
  set_env "WORK_DIR"          "$HOME/.$SCRIPT_NAME"
  set_env "ZINIT_FILE"        "$WORK_DIR/files/zinit"
  set_env "INSTALL_ZINIT"     "true"
  set_env "INSTALL_RBENV"     "true"
  set_env "INSTALL_PYENV"     "true"
  set_env "INSTALL_POSH"      "true"
  set_env "INSTALL_OZSH"      "false"
  set_env "INSTALL_FONTS"     "true"
  set_env "INSTALL_P10K"      "true"
  set_env "ZINIT_HOME"        "$HOME/.zinit"
  set_env "RBENV_HOME"        "$HOME/.rbenv"
  set_env "PYENV_HOME"        "$HOME/.pyenv"
  set_env "POSH_HOME"         "$HOME/.oh-my-posh"
  set_env "ZOSH_HOME"         "$HOME/.oh-my-zsh"
  set_env "P10K_INIT"         "$HOME/.p10k.zsh"
  set_env "P10K_HOME"         "$HOME/.powerlevel10k"
  set_env "P10K_THEME"        "$P10K_HOME/powerlevel10k.zsh-theme"
  set_env "RUBY_VER"          "3.3.4"
  set_env "PYTHON_VER"        "3.12.4"
  set_env "DO_INSTALL"        "false"
  set_env "DO_VERSION_CHECK"  "false"
  set_env "DO_DEFAULTS_CHECK" "false"
  set_env "DO_PACKAGE_CHECK"  "false"
  set_env "DO_UPDATE_CHECK"   "false"
  set_env "DO_UPDATE_FUNCT"   "false"
  set_env "DO_PYENV_CHECK"    "false"
  set_env "DO_RBENV_CHECK"    "false"
  set_env "DO_ZINIT_CHECK"    "false"
  set_env "DO_FONTS_CHECK"    "false"
  set_env "DO_POSH_CHECK"     "false"
  set_env "DO_P10K_CHECK"     "false"
  set_env "DO_ZOSH_CHECK"     "false"
  set_env "DO_ENV_SETUP"      "true"
  set_env "DO_ZSH_THEME"      "true"
  set_env "ZSH_THEME"         "robbyrussell"
  set_env "PLUGIN_MANAGER"    "zinit"
  if [ ! -d "$WORK_DIR" ]; then
    execute_command "mkdir -p $WORK_DIR"
    execute_command "mkdir -p $WORK_DIR/files"
  fi
}

# Reset all defaults (when script is run inline i.e. as a login script with no options)

set_inline_defaults () {
  set_env "DO_DEFAULTS_CHECK" "true"
  set_env "DO_PACKAGE_CHECK"  "true"
  set_env "DO_ZINIT_CHECK"    "true"
  set_env "DO_PYENV_CHECK"    "true"
  set_env "DO_RBENV_CHECK"    "true"
  set_env "DO_FONTS_CHECK"    "true"
  set_env "DO_POSH_CHECK"     "true"
  set_env "DO_ZOSH_CHECK"     "false"
  set_env "DO_P10K_CHECK"     "true"
  set_env "DO_ZSH_THEME"      "true"
  set_env "DO_VERBOSE"        "false"
  set_env "DO_DRYRUN"         'false'
  set_env "DO_CONFIRM"        "false"
  set_env "DO_DEBUG"          "false"
  set_env "DO_BUILD"          "false"
  set_env "DO_PLUGINS"        "true"
}

# Check zinit config

check_zinit_config () {
  if [ "$INSTALL_ZINIT" = "true" ]; then
    verbose_message "Configuring zinit"
    if [ ! -d "$ZINIT_HOME" ]; then
      execute_command "git clone https://github.com/zdharma-continuum/zinit.git $ZINIT_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      execute_command ". $ZINIT_HOME/zinit.zsh"
    fi
    if [ "$PLUGIN_MANAGER" = "zinit" ]; then
      if [ -f "$ZINIT_FILE" ]; then
        execute_from_file "$ZINIT_FILE"
      fi
    fi
  fi
}

# Check rbenv

check_rbenv_config () {
  if [ "$INSTALL_RBENV" = "true" ]; then
    verbose_message "Configuring rbenv"
    if [ ! -d "$RBENV_HOME" ]; then
      verbose_message "Installing rbenv"
      execute_command "git clone https://github.com/rbenv/rbenv.git $RBENV_HOME"
      verbose_message "Installing rbenv ruby-build plugin"
      execute_command "git clone https://github.com/rbenv/ruby-build.git $RBENV_HOME/plugins/ruby-build"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      verbose_message "Configuring rbenv environment"
      execute_command "export RBENV_ROOT=\"$RBENV_HOME\""
      execute_command "export PATH=\"$RBENV_ROOT/bin:$PATH\""
      execute_command "rbenv init - zsh"
      if [ "DO_BUILD" = "true" ]; then
        RBENV_CHECK=$( rbenv versions --bare | grep -v "$RUBY_VER" )
        if [ -z "$RBENV_CHECK" ]; then
          verbose_message "Installing ruby version $RUBY_VER"
          execute_command "rbenv install $RUBY_VER"
          verbose_message "Setting ruby global version to $RUBY_VER"
          execute_command "rbenv global $RUBY_VER"
        fi
      fi
      RBENV_GLOBAL=$( rbenv global )
      if [ ! "$RBENV_GLOBAL" = "$RUBY_VER" ]; then
        verbose_message "Setting ruby global version to $RUBY_VER"
        execute_command "rbenv global $RUBY_VER"
      fi
    fi
  fi
}

# Check pyenv

check_pyenv_config () {
  if [ "$INSTALL_PYENV" = "true" ]; then
    verbose_message "Configuring pyenv"
    if [ ! -d "$PYENV_HOME" ]; then
      verbose_message "Installing pyenv"
      execute_command "git clone https://github.com/rbenv/rbenv.git $PYENV_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      verbose_message "Configuring pyenv environment"
      execute_command "export PYENV_ROOT=\"$PYENV_HOME\""
      execute_command "export PATH=\"$PYENV_ROOT/bin:$PATH\""
      execute_command "pyenv init -"
      if [ "DO_BUILD" = "true" ]; then
        PYENV_CHECK=$( pyenv versions --bare | grep "$PYTHON_VER" )
        if [ -z "$PYENV_CHECK" ]; then
          verbose_message "Installing python version $PYTHON_VER"
          execute_command "pyenv install $PYTHON_VER"
          verbose_message "Setting python global version to $RUBY_VER"
          execute_command "pyenv global $PYTHON_VER"
        fi
      fi
      PYENV_GLOBAL=$( pyenv global )
      if [ ! "$PYENV_GLOBAL" = "$PYTHON_VER" ]; then
        verbose_message "Setting python global version to $RUBY_VER"
        execute_command "rbenv global $PYTHON_VER"
      fi
    fi
  fi
}

# Check fonts config

check_fonts_config () {
  if [ "$INSTALL_FONTS" = "true" ]; then
    verbose_message "Configuring fonts"
    if [ "$OS_NAME" = "Darwin" ]; then
      check_osx_package "font-fira-code-nerd-font" "cask"
    fi
  fi
}

# Check oh-my-posh config

check_posh_config () {
  if [ "$INSTALL_POSH" = "true" ]; then
    verbose_message "Configuring oh-my-posh"
    if [ ! -d "$POSH_HOME" ]; then
      verbose_message "Installing oh-my-posh"
      execute_command "mkdir -p $POSH_HOME"
      execute_command "curl -s https://ohmyposh.dev/install.sh | bash -s -- -d $POSH_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      verbose_message "Configuring oh-my-posh environment"
      execute_command "export PATH=\"$POSH_HOME:$PATH\""
      execute_command "oh-my-posh init zsh"
    fi
  fi
}

# Check oh-my-zsh config

check_zosh_config () {
  if [ "$INSTALL_ZOSH" = "true" ]; then
    verbose_message "Configuring oh-my-posh"
    if [ ! -d "$ZOSH_HOME" ]; then
      verbose_message "Installing oh-my-zsh"
      execute_command "git clone https://github.com/ohmyzsh/ohmyzsh.git $ZOSH_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      verbose_message "Configuring oh-my-zsh environment"
      execute_command "source $ZOSH_HOME/oh-my-zsh.sh"
    fi
    if [ "$PLUGIN_MANAGER" = "oh-my-zsh" ]; then
      plugins=( git ansible aliases brew common-aliases copyfile copypath \
                debian docker docker-compose docker-machine ubuntu ufw \
                systemd sudo ssh-agent screen ruby rsync python pip perl \
                macos history )
    fi
  fi
}

# Check Powerlevel10k config

check_p10k_config () {
  if [ "$INSTALL_P10K" = "true" ]; then
    verbose_message "Configuring p10k"
    if [ "$INSTALL_ZINIT" = "false" ]; then
      if [ ! -d "$P10K_HOME" ]; then
        verbose_message "Installing p10k"
        execute_command "git clone --depth=1 https://github.com/romkatv/powerlevel10k.git $P10K_HOME"
      fi
      if [ "$DO_ENV_SETUP" = "true" ]; then
        verbose_message "Configuring p10k environment"
        execute_command "typeset -g POWERLEVEL9K_INSTANT_PROMPT=off"
        if [ "$INSTALL_ZINIT" = "false" ]; then
          if [ -f "$P10K_INIT" ]; then
            execute_command "p10k configure"
          fi
          execute_command "source $P10K_INIT"
          if [ -f "$P10K_THEME" ]; then
            execute_command "source $P10K_THEME"
          fi
        fi
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
    verbose_message "Setting parameter \"$PARAM\" to \"$VALUE\""
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
                 xorriso x264 x265 xquartz xz yamllint zsh )
}

# Update package list

update_package_list () {
  if [ "$OS_NAME" = "Darwin" ]; then
    if [ ! -f "$BREW_LIST" ]; then
      execute_command "brew list | sort > $BREW_LIST"
    else
      BREW_TEST=$( find "$BREW_LIST" -mtime -2 2> /dev/null )
      SCRIPT_TEST=$( find "$SCRIPT_FILE" -mtime -2 2> /dev/null )
      if [ -z "$BREW_TEST" ] || [ "$SCRIPT_TEST" ]; then
        execute_command "brew list | sort > $BREW_LIST"
      fi
    fi
  fi
}

# Check OS defaults

check_osx_defaults () {
  verbose_message "Configuring OS X defaults"
  if [ ! -d "$SCREENSHOT_LOCATION" ]; then
    execute_command "mkdir -p $SCREENSHOT_LOCATION"
  fi
  osx_defaults_check "com.apple.screencapture" "location" "string" "$SCREENSHOT_LOCATION"
  if [ "$SHOW_HIDDEN_FILES" = "true" ]; then
    osx_defaults_check "com.apple.Finder" "AppleShowAllFiles" "" "$SHOW_HIDDEN_FILES"
    execute_command    "chflags nohidden $HOME/Library"
  fi
  if [ "$RESTART_FINDER" = "true" ]; then
    verbose_message "Restarting Finder"
    execute_command "killall Finder"
  fi
  if [ "$RESTART_UISERVER" = "true" ]; then
    verbose_message "Restarting SystemUIServer"
    execute_command "killall SystemUIServer"
  fi
}

# Check OSX Package

check_osx_package () {
  PACKAGE="$1"
  TYPE="$2"
  verbose_message "Configuring OS X package \"$PACKAGE\""
  if [ "$INSTALL_BREW" = "true" ]; then
    PACKAGE_TEST=$( grep "^$PACKAGE$" "$BREW_LIST" )
    if [ -z "$PACKAGE_TEST" ]; then
      verbose_message "Installing package \"$PACKAGE\""
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
    verbose_message "Configuring brew"
    BREW_TEST=$(command -v brew)
    if [ -z "$BREW_TEST" ]; then
      for BREW_FILE in /opt/homebrew/bin/brew /usr/local/homebrew/bin/brew; do
        if [ -f "$BREW_FILE" ]; then
          BREW_BIN="$BREW_FILE"
          BREW_DIR=$( dirname $BREW_BIN )
          BREW_BASE=$( dirname $BREW_DIR )
        fi
      done
      if [ -z "$BREW_BIN" ]; then
        execute_command "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        for BREW_FILE in /opt/homebrew/bin/brew /usr/local/homebrew/bin/brew; do
          if [ -f "$BREW_FILE" ]; then
            BREW_BIN="$BREW_FILE"
            BREW_DIR=$( dirname $BREW_BIN )
            BREW_BASE=$( dirname $BREW_DIR )
          fi
        done
        execute_command "export PATH=\"$BREW_BASE/bin:$BREW_BASE/sbin:$PATH\""
      else
        execute_command "export PATH=\"$BREW_BASE/bin:$BREW_BASE/sbin:$PATH\""
        execute_command "export LD_LIBRARY_PATH=/usr/lib:/usr/local/lib:/"
        if [ "$DO_ENV_SETUP" = "true" ]; then
          verbose_message "Configuring brew environment"
          execute_command "$BREW_BIN shellenv"
        fi
      fi
    else
      if [ "$DO_ENV_SETUP" = "true" ]; then
        verbose_message "Configuring brew environment"
        execute_command "$BREW_TEST shellenv"
      fi
    fi
    BREW_TEST=$( find "$BREW_LIST" -mtime -2 2> /dev/null )
    SCRIPT_TEST=$( find "$SCRIPT_FILE" -mtime -2 2> /dev/null )
    if [ "$BREW_TEST" ] || [ "$SCRIPT_TEST" ]; then
      update_package_list
      for PACKAGE in $PACKAGE_LIST; do
        check_osx_package "$PACKAGE" ""
      done
    fi
  fi
}

# Check for update

check_for_update () {
  verbose_message "Checking for updates"
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
  if [ "$OS_NAME" = "Darwin" ]; then
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

if [[ "$*" =~ "verbose" ]]; then
  DO_VERBOSE="true"
else
  DO_VERBOSE="false"
fi

set_defaults

# If given no command arguments run as a normal login script
# Otherwise handle commandline argument

if [ ! "$*" = "" ]; then
  while test $# -gt 0; do
    case $1 in
      -b|--build|--compile)
        DO_BUILD="true"
        shift
        ;;
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
        DO_HELP="true"
        shift
        ;;
      -I|--install)
        DO_INSTALL="true"
        shift
        ;;
      -n|--nothene)
        DO_ZSH_THEME="false"
        shift
        ;;
      -m|--manager|--plugin)
        PLUGIN_MANAGER="$2"
        shift 2
        ;;
      -N|--noenv)
        DO_ENV_SETUP="false"
        shift
        ;;
      -o|--ohmyposh|--posh)
        DO_FONTS_CHECK="true"
        DO_POSH_CHECK="true"
        shift
        ;;
      -o|--ohmyzsh|--zosh)
        DO_FONTS_CHECK="true"
        DO_ZOSH_CHECK="true"
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
        DO_VERSION="true"
        shift
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

if [ "$DO_HELP" = "true" ]; then
  print_help
  exit
fi

if [ "$DO_VERSION" = "true" ]; then
  echo "$SCRIPT_VERSION"
  exit
fi

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

# Do package check

if [ "$DO_PACKAGE_CHECK" ]; then
  check_package_config
fi

# Do font(s) check

if [ "$DO_FONTS_CHECK" = "true" ]; then
  check_fonts_config
fi

if [ "$DO_POSH_CHECK" = "true" ]; then
  check_posh_config
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
