#!/usr/bin/env zsh
emulate -LR bash
#
# Version: 0.1.1
#


# Get the path the script starts from

START_PATH=$( pwd )

# Get the version of the script from the script itself

SCRIPT_VERSION=$( cd "$START_PATH" || exit ; grep '^# Version' < "$0"| awk '{print $3}' )

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
  if [ "$VERBOSE" = "true" ] || [ "$DRYRUN" = "true" ]; then
    handle_output "$COMMAND" "execute"
  fi
  if [ "$DRYRUN" = "false" ]; then
    if [ "$CONFIRM" = "true" ]; then
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

  Usage: ${0##*/} [OPTIONS...]

    -c|--confirm      Confirm commands
    -C|--check.       Check for updates
    -d|--debug        Print debug information while executing
    -D|--default(s)   Set defaults
    -h|--help         Print usage information
    -p|--pyenv        Do pyenv check
    -P|--package(s)   Do packages check
    -r|--rbenv        Do rbenv check
    -t|--dryrun       Dry run
    -U|--update       Check git for updates
    -v|--verbose      Verbose output 
    -V|--version      Print version
    -z|--zinit        Do zinit check

HELP
}

# Check All Defaults

check_all_defaults () {
  OS_NAME=$(uname -o)
  VERBOSE="false"
  DRYRUN='false'
  DEBUG="false"
  CONFIRM="false"
  SCRIPT_NAME="ussuri"
  WORK_DIR="$HOME/$SCRIPT_NAME"
  INSTALL_ZINIT="true"
  INSTALL_RBENV="true"
  INSTALL_PYENV="true"
  ZINIT_HOME="$HOME/.zinit"
  RBENV_HOME="$HOME/.rbenv"
  PYENV_HOME="$HOME/.pyenv"
  RUBY_VER="3.3.4"
  PYTHON_VER="3.12.4"
  DO_VERSION_CHECK="false"
  DO_DEFAULTS_CHECK="false"
  DO_PACKAGE_CHECK="false"
  DO_UPDATE_CHECK="false"
  DO_PYENV_CHECK="false"
  DO_RBENV_CHECK="false"
  DO_ZINIT_CHECK="false"
}

# Check Base Config

check_base_config () {
  if [ ! -d "$WORK_DIR" ]; then
    mkdir -p "$WORK_DIR"
  fi
}

# Check zinit config

check_zinit_config () {
  if [ "$INSTALL_ZINIT" = "true" ]; then
    if [ ! -d "$ZINIT_HOME" ]; then
      execute_command "mkdir -p $ZINIT_HOME"
      execute_command "git clone https://github.com/zdharma-continuum/zinit.git $ZINIT_HOME"
    fi
    execute_command "source $ZINIT_HOME/zinit.zsh"
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
      execute_command "mkdir -p $RBENV_HOME"
      execute_command "git clone https://github.com/rbenv/rbenv.git $RBENV_HOME"
    fi
    execute_command "export RBENV_HOME=\"$RBENV_HOME\""
    execute_command "export PATH=\"$PYENV_ROOT/bin:$PATH\""
    execute_command "eval  rbenv init - zsh )"
    RBENV_CHECK=$( rbenv versions --bare )
    if [ -z "$RBENV_CHECK" ]; then
      execute_command "rbenv install $RUBY_VER"
      execute_command "rbenv global $RUBY_VER"
    fi
  fi
}

# Check pyenv

check_pyenv_config () {
  if [ "$INSTALL_PYENV" = "true" ]; then
    if [ ! -d "$PYENV_HOME" ]; then
      execute_command "mkdir -p $PYENV_HOME"
      execute_command "git clone https://github.com/rbenv/rbenv.git $PYENV_HOME"
    fi
    execute_command  "export PYENV_HOME=\"$PYENV_HOME\""
    execute_command  "export PATH=\"$PYENV_ROOT/bin:$PATH\""
    execute_command  "pyenv init - "
    PYENV_CHECK=$( pyenv versions --bare )
    if [ -z "$PYENV_CHECK" ]; then
      execute_command "rbenv install $PYTHON_VER"
      execute_command "rbenv global $PYTHON_VER"
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

# Set OSX X Environment

check_osx_config () {
  INSTALL_BREW="true"
  SHOW_HIDDEN_FILES="true"
  RESTART_FINDER="false"
  RESTART_UISERVER="false"
  SCREENSHOT_LOCATION="$HOME/Pictures/Screenshots"
  PACKAGE_LIST="ansible ansible-list autoconf automake bat bash blackhole-2ch \
                bpytop btop bzip2 ca-certificates cmake cpio cpufetch curl \
                docker dos2unix exiftool ffmpeg flac fortune fzf gcc gettext \
                ghostscript giflib git git-lfs gmp gnu-getop gnu-sed gnutle go \
                grep htop jpeg-turbo jpeg-xl jq imagemagick lame lego lftp \
                libarchive libheif libogg libpng libvirt libvirt-glib \
                libvirt-pyton libvorbis libxml libyaml lsd lua lx4 lzo mpg123 \
                multipass netpbm openssh openssl opentofu osinfo-db osx-cpu-temp \
                p7zip pwgen pyton qemu rpm2cpio ruby ruby-build rust shellcheck \
                socat sqlite tcl-tk tesseract tmux tree utm virt-manager warp wget \
                xorriso x264 x265 xquartz xz zsh"
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
  if [ "$INSTALL_BREW" = "true" ]; then
    BREW_LIST="$WORK_DIR/brew_list"
    BREW_TEST=$( find "$BREW_LIST" -mtime -5 )  
    if [ -z "$BREW_LIST" ]; then
      execute_command "brew list > $BREW_LIST"
    fi 
    INSTALL_LIST=$( cat "$BREW_LIST" )
    PACKAGE_TEST=$( grep "$PACKAGE" "$INSTALL_LIST" )
    if [ -z "$PACKAGE_TEST" ]; then
      execute_command "brew install $PACKAGE"
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
        execute_command "$BREW_BIN shellenv"
      fi
    else
       execute_command "$BREW_TEST shellenv"
    fi
    for PACKAGE in $PACKAGE_LIST; do
      check_osx_package "$PACKAGE"
    done
  fi
}

# Compare version

compare_version () {
    if [[ $1 == $2 ]]; then
      return 0
    fi
    local IFS=.
    local i VER1=($1) VER2=($2)
    for ((i=${#VER1[@]}; i<${#VER2[@]}; i++))
    do
        VER1[i]=0
    done
    for ((i=0; i<${#VER1[@]}; i++))
    do
        if [[ -z ${VER2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            VER2[i]=0
        fi
        if ((10#${vVER[i]} > 10#${VER2[i]}))
        then
            return 1
        fi
        if ((10#${VER1[i]} < 10#${VER2[i]}))
        then
            return 2
        fi
    done
    return 0
}

# Check for update

check_for_update () {
  README_URL="https://raw.githubusercontent.com/lateralblast/ussuri/main/README.md" 
  REMOTE_VERSION=$( curl -vs "$README_URL" 2>&1 | grep "Current Version" | awk '{ print $3 }' )
  echo "Local version:  $SCRIPT_VERSION"
  echo "Remote version: $REMOTE_VERSION"
  compare_version "$SCRIPT_VERSION" "$REMOTE_VERSION"
  case $? in
    0)
      handle_output "Local version is the same as remote version" "info"
      ;;
    1)
      handle_output "Local version is newer than remote version" "info"
      ;;
    2)
      handle_output "Local version is older than remote version" "info"
      ;;
  esac
}

# Check defaults

check_defaults () {
  check_all_defaults
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

check_all_defaults

# If given no command arguments run as a normal login script
# Otherwise handle commandline argument

if [ ! "$*" = "" ]; then
  while test $# -gt 0; do
    case $1 in
      -c|--confirm)
        CONFIRM="true"
        shift
        ;;
      -C|--check)
        DO_VERSION_CHECK="true"
        shift
        ;;
      -d|--debug)
        DEBUG="true"
        shift
        set -x
        ;;
      -D|--default|--defaults)
        DO_DEFAULTS_CHECK="true"
        shift
        exit
        ;;
      -h|--help|--usage)
        print_help
        shift
        exit
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
        DRYRUN="true"
        shift
        handle_output "Running without executing commands"
        ;;
      -U|--update)
        DO_UPDATE_CHECK="true"
        shift
        ;;
      -v|--verbose)
        VERBOSE="true"
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
    esac
  done
else
  DO_DEFAULTS_CHECK="true"
  DO_PACKAGE_CHECK="true"
  DO_ZINIT_CHECK="true"
  DO_PYENV_CHECK="true"
  DO_RBENV_CHECK="true"
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

# Do checks

check_base_config

# Do OSX specific checks

if [ "$OS_NAME" = "Darwin" ]; then
  check_osx_config
  check_osx_packages
fi

# Do package check

if [ "$DO_PACKAGE_CHECK" ]; then
  check_package_config
fi

# Do zinit checks

if [ "$DO_ZINIT_CHECK" = "true" ]; then
  check_zinit_config
  exit
fi

# Do pyenv checks

if [ "$DO_PYENV_CHECK" = "true" ]; then
  check_pyenv_config
fi

# Do rbenv checks

if [ "$DO_RBENV_CHECK" = "true" ]; then
  check_rbenv_config
fi
