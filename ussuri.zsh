#!/usr/bin/env zsh
#
# Version: 0.7.5
#

SCRIPT_FILE="$0"
if [ "$SCRIPT_FILE" = "-zsh" ]; then
  SCRIPT_FILE="$HOME/.zshrc"
else
  SCRIPT_DIR=$( dirname "$SCRIPT_FILE" )
  if [ "$SCRIPT_DIR" = "." ]; then
    SCRIPT_DIR=$( pwd )
  fi
fi
SCRIPT_NAME="ussuri"
START_DIR="none"

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
  OPTION="$2"
  if [ "$DO_VERBOSE" = "true" ] || [ "$DO_DRYRUN" = "true" ]; then
    handle_output "$COMMAND" "execute"
  fi
  if [ "$DO_DRYRUN" = "false" ] || [ "$OPTION" = "run" ]; then
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
  for LINE in "${(@f)"$(<$FILE)"}"; do
    if [[ ! "$LINE" =~ "^#" ]]; then
      if [[ "$LINE" =~ "Finder" ]]; then
        set_env "RESTART_FINDER" "true"
      fi
      if [[ "$LINE" =~ "SystemUIServer" ]]; then
        set_env "RESTART_UISERVER" "true"
      fi
      execute_command "$LINE"
    fi
  done
}

# Priny help information

print_help () {
  set_defaults
  cat <<-HELP

  Usage: $SCRIPT_FILE [OPTIONS...]

  When run manually with switches:

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -A|--doall        Do all fuction (where set to true)
    -i|--inline       Set inline defaults when not runing inline mode
    -I|--install      Installs $SCRIPT_NAME as: $HOME/.zshrc
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
    -s|--startdir     Set start dir       (default: $START_DIR)
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
    Do p10k check         $DO_P10K_CHECK
    Do oh-my-posh check:  $DO_POSH_CHECK
    Do oh-my-zsh check:   $DO_ZOSH_CHECK
    Do verbose mode       $DO_VERBOSE
    Do sudoers check:     $DO_SUDOERS_CHECK
    Plugin Manager:       $PLUGIN_MANAGER
    Start Directory:      $START_DIR

INLINE
}

# Install script as .zshrc

do_install () {
  verbose_message "Backing up $HOME/.zshrc to $WORK_DIR/.zshrc.$DATE_SUFFIX"
  execute_command "cp $HOME/.zshrc $WORK_DIR/.zshrc.$DATE_SUFFIX"
  verbose_message "Replacing $HOME/.zshrc"
  execute_command "cp $SCRIPT_FILE $HOME/.zshrc"
  set_env "WORK_DIR"    "$HOME/.$SCRIPT_NAME"
  execute_command "mkdir -p $WORK_DIR/files" "run"
  if [ "$DO_INSTALL" = "true" ]; then
    if [ ! "$SCRIPT_FILE" = "$HOME/.zshrc" ]  && [ ! "$SCRIPT_FILE" = "$HOME/.zprofile" ]; then
      if [ -d "$WORK_DIR/files" ]; then
        if [ ! "$SCRIPT_DIR" = "" ] && [ ! "$WORK_DIR" = "" ]; then
          execute_command "( cd $SCRIPT_DIR/files ; tar -cpf - . )|( cd $WORK_DIR/files ; tar -xpf - )" "run"
        fi
        if [ ! -f "$P10K_INIT" ]; then
          if [ -f "$SOURCE_P10K_INIT" ]; then
            execute_command "cp $SOURCE_P10K_INIT $P10K_INIT"
          fi
        fi
      fi
    fi
  fi
}

# Print changelog

print_changelog () {
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

# Set environment variable if hasn't been set
# Doing it this was allows a manul override at the top of the script for some variables

set_env () {
  PARAM="$1"
  VALUE="$2"
  if [[ "$PARAM" =~ "VERBOSE|WORK_DIR" ]]; then
    if [ "${(P)PARAM}" = "" ]; then
      verbose_message "Environment parameter \"$PARAM\" to \"$VALUE\"" "set"
      eval "export $PARAM=\"$VALUE\""
    fi
  else
    verbose_message "Environment parameter \"$PARAM\" to \"$VALUE\"" "set"
    eval "export $PARAM=\"$VALUE\""
  fi
}

# Set All Defaults

set_all_defaults () {
  SCRIPT_VERSION=$( grep '^# Version' < "$SCRIPT_FILE" |  awk '{print $3}' )
  OS_NAME=$(uname -o)
  if [[ "$OS_NAME" =~ "Linux" ]]; then
    OS_NAME="Linux"
    LSB_ID=$( lsb_release -i -s 2> /dev/null )
  fi
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
  set_env "ZINIT_FILE"        "$WORK_DIR/files/zinit/zinit.zsh"
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
  set_env "SOURCE_P10K_INIT"  "$WORK_DIR/files/p10k/p10k.zsh"
  set_env "P10K_HOME"         "$HOME/.powerlevel10k"
  set_env "P10K_THEME"        "$P10K_HOME/powerlevel10k.zsh-theme"
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
  set_env "DO_SUDOERS_CHECK"  "true"
  set_env "ZSH_THEME"         "robbyrussell"
  set_env "PLUGIN_MANAGER"    "zinit"
  set_env "SUDOERS_ENTRY"     "ALL=(ALL) NOPASSWD:ALL"
  if [ ! -d "$WORK_DIR" ]; then
    execute_command "mkdir -p $WORK_DIR"
    execute_command "mkdir -p $WORK_DIR/files"
  fi
}

# Reset all defaults (when script is run inline i.e. as a login script with no options)

set_inline_defaults () {
  verbose_message "Setting defaults"
  execute_command "PATH=\"/usr/local/bin:/usr/local/sbin:$PATH\""
  execute_command "LD_LIBRARY_PATH=\"/usr/local/lib:$LD_LIBRARY_PATH\""
  set_env "WORK_DIR"          "$HOME/.$SCRIPT_NAME"
  set_env "DO_HELP"           "false"
  set_env "DO_DRYRUN"         "false"
  set_env "DO_CONFIRM"        "false"
  set_env "DO_DEBUG"          "false"
  set_env "DO_BUILD"          "false"
  set_env "DO_PLUGINS"        "true"
  set_env "ZINIT_FILE"        "$WORK_DIR/files/zinit/zinit.zsh"
  set_env "INSTALL_BREW"      "true"
  set_env "INSTALL_ZINIT"     "true"
  set_env "INSTALL_RBENV"     "true"
  set_env "INSTALL_PYENV"     "true"
  set_env "INSTALL_POSH"      "true"
  set_env "INSTALL_OZSH"      "false"
  set_env "INSTALL_FONTS"     "true"
  set_env "INSTALL_P10K"      "true"
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
  set_env "DO_DRYRUN"         "false"
  set_env "DO_CONFIRM"        "false"
  set_env "DO_DEBUG"          "false"
  set_env "DO_BUILD"          "false"
  set_env "DO_PLUGINS"        "true"
  set_env "DO_SUDOERS_CHECK"  "false"
  set_env "SUDOERS_ENTRY"     "ALL=(ALL) NOPASSWD:ALL"
}

# Check sudoers config

check_sudoers_config () {
  verbose_message "Checking sudoers"
  SUDO_VALUE=$( echo "$SUDOERS_ENTRY" |cut -f2 -d= |cut -f1 -d: )
  SUDO_CHECK=$( sudo -l |grep "$SUDO_VALUE" |wc -c |sed "s/ //g" )
  if [ "$SUDO_CHECK" = "0" ] || [ "$DO_DRYRUN" = "true" ]; then
    execute_command "echo \"$USER $SUDOERS_ENTRY\" |sudo tee -a /etc/sudoers.d/$USER"
  fi
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
      execute_command "eval \"\$(rbenv init - zsh)\""
      if [ "$RUBY_VER" = "" ]; then
        RUBY_VER=$( rbenv install --list-all | awk '{ print $1 }' |grep "^[0-9]" | grep -Ev 'd|b|p' | tail -1 )
      fi
      if [ "$DO_BUILD" = "true" ]; then
        if [ ! -d "$RBENV_HOME/versions/$RUBY_VER" ]; then
          verbose_message "Installing ruby version $RUBY_VER"
          execute_command "rbenv install $RUBY_VER"
          verbose_message "Setting ruby local version to $RUBY_VER"
          execute_command "rbenv local $RUBY_VER"
          verbose_message "Setting ruby global version to $RUBY_VER"
          execute_command "rbenv global $RUBY_VER"
        fi
      fi
      RBENV_LOCAL=$( rbenv local )
      if [ ! "$RBENV_LOCAL" = "$RUBY_VER" ]; then
        verbose_message "Setting ruby local version to $RUBY_VER"
        execute_command "rbenv local $RUBY_VER"
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
      execute_command "git clone https://github.com/pyenv/pyenv.git $PYENV_HOME"
    fi
    if [ "$DO_ENV_SETUP" = "true" ]; then
      verbose_message "Configuring pyenv environment"
      execute_command "export PYENV_ROOT=\"$PYENV_HOME\""
      execute_command "export PATH=\"$PYENV_ROOT/bin:$PATH\""
      execute_command "eval \"\$(pyenv init -)\""
      if [ "$PYTHON_VER" = "" ]; then
        PYTHON_VER=$( pyenv install --list | awk '{ print $1 }' |grep "^[0-9]" | grep -Ev 'd|b|p' | tail -1 )
      fi
      if [ "$DO_BUILD" = "true" ]; then
        if [ ! -d "$PYENV_HOME/versions/$PYTHON_VER" ]; then
          verbose_message "Installing python version $PYTHON_VER"
          execute_command "pyenv install $PYTHON_VER"
          verbose_message "Setting python local version to $PYTHON_VER"
          execute_command "pyenv global $PYTHON_VER"
          verbose_message "Setting python global version to $RUBY_VER"
          execute_command "pyenv global $PYTHON_VER"
        fi
      fi
      PYENV_LOCAL=$( pyenv local )
      if [ ! "$PYENV_LOCAL" = "$PYTHON_VER" ]; then
        verbose_message "Setting python local version to $PYTHON_VER"
        execute_command "pyenv global $PYTHON_VER"
      fi
      PYENV_GLOBAL=$( pyenv global )
      if [ ! "$PYENV_GLOBAL" = "$PYTHON_VER" ]; then
        verbose_message "Setting python global version to $PYTHON_VER"
        execute_command "pyenv global $PYTHON_VER"
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
    else
      if [ "$OS_NAME" = "Linux" ]; then
        execute_command "git clone --depth 1 https://github.com/ryanoasis/nerd-fonts.git $WORK_DIR/nerd-fonts"
        execute_command "cd $WORK_DIR/nerd-fonts ; ./install.sh"
      fi
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
          if [ ! -f "$P10K_INIT" ]; then
            if [ -f "$SOURCE_P10K_INIT" ]; then
              execute_command "cp $SOURCE_P10K_INIT $P10K_INIT"
            else
              execute_command "p10k configure"
            fi
          fi
          execute_command "source $P10K_INIT"
          if [ -f "$P10K_THEME" ]; then
            execute_command "source $P10K_THEME"
          fi
        fi
      fi
    else
      if [ ! -f "$P10K_INIT" ]; then
        if [ -f "$SOURCE_P10K_INIT" ]; then
          execute_command "cp $SOURCE_P10K_INIT $P10K_INIT"
        else
          execute_command "p10k configure"
        fi
      fi
      execute_command "source $P10K_INIT"
      if [ -f "$P10K_THEME" ]; then
        execute_command "source $P10K_THEME"
      fi
    fi
  fi
}

# Set Linux defaults

set_linux_defaults () {
  set_env "DEFAULTS_FILE" "$WORK_DIR/files/defaults/linux.defaults"
  if [ "$LSB_ID" = "Ubuntu" ]; then
    set_env "REQUIRED_FILE"  "$WORK_DIR/files/packages/ubuntu.apt"
    set_env "INSTALL_APT"    "true"
    set_env "INSTALLED_FILE" "$WORK_DIR/apt.list"
  fi
  if [ "$DO_INSTALL" = "false" ]; then
    if [ ! -f "$REQUIRED_FILE" ] || [ ! -f "$DEFAULTS_FILE" ]; then
      execute_command "( cd $SCRIPT_DIR/files ; tar -cpf - . )|( cd $WORK_DIR/files ; tar -xpf - )" "run"
    fi
    REQUIRED_LIST=$( tr "\n" " " < "$REQUIRED_FILE" )
    REQUIRED_LIST=(${(@s: :)REQUIRED_LIST})
  fi
}

# Set OSX defaults

set_osx_defaults () {
  set_env "INSTALL_BREW"        "true"
  set_env "RESTART_FINDER"      "false"
  set_env "RESTART_UISERVER"    "false"
  set_env "SCREENSHOT_LOCATION" "$HOME/Pictures/Screenshots"
  set_env "INSTALLED_FILE"      "$WORK_DIR/brew.list"
  set_env "REQUIRED_FILE"       "$WORK_DIR/files/packages/macos.brew"
  set_env "DEFAULTS_FILE"       "$WORK_DIR/files/defaults/macos.defaults"
  if [ "$DO_INSTALL" = "false" ]; then
    if [ ! -f "$REQUIRED_FILE" ] || [ ! -f "$DEFAULTS_FILE" ]; then
      execute_command "( cd $SCRIPT_DIR/files ; tar -cpf - . )|( cd $WORK_DIR/files ; tar -xpf - )" "run"
    fi
    REQUIRED_LIST=$( tr "\n" " " < "$REQUIRED_FILE" )
    REQUIRED_LIST=(${(@s: :)REQUIRED_LIST})
  fi
}

# Update package list

update_package_list () {
  if [ ! -f "$INSTALLED_FILE" ]; then
    if [ "$OS_NAME" = "Darwin" ]; then
      execute_command "brew list 2> /dev/null | sort > $INSTALLED_FILE"
    else
      if [ "$OS_NAME" = "Linux" ]; then
        if [ "$LSB_ID" = "Ubuntu" ]; then
          execute_command "dpkg -l | grep ^ii | awk '{ print \$2 }' | sed 's/:amd64//g'> $INSTALLED_FILE"
        fi
      fi
    fi
  else
    INSTALLED_TEST=$( find "$INSTALLED_FILE" -mtime -2 2> /dev/null )
    SCRIPT_TEST=$( find "$SCRIPT_FILE" -mtime -2 2> /dev/null )
    if [ -z "$INSTALLED_TEST" ] || [ "$SCRIPT_TEST" ]; then
      if [ "$OS_NAME" = "Darwin" ]; then
        execute_command "brew list 2> /dev/null | sort > $INSTALLED_FILE"
      else
        if [ "$OS_NAME" = "Linux" ]; then
          if [ "$LSB_ID" = "Ubuntu" ]; then
            execute_command "dpkg -l | grep ^ii | awk '{ print \$2 }' | sed 's/:amd64//g' > $INSTALLED_FILE"
          fi
        fi
      fi
    fi
  fi
}

# Check Linux Defaults

check_linux_defaults () {
  # Insert code here, e.g. gsettings
  true;
}

# Check OS Defaults

check_osx_defaults () {
  verbose_message "Configuring OS X defaults"
  if [ ! -d "$SCREENSHOT_LOCATION" ]; then
    execute_command "mkdir -p $SCREENSHOT_LOCATION"
  fi
  execute_from_file "$DEFAULTS_FILE"
  if [ "$RESTART_FINDER" = "true" ]; then
    verbose_message "Restarting Finder"
    execute_command "killall Finder"
  fi
  if [ "$RESTART_UISERVER" = "true" ]; then
    verbose_message "Restarting SystemUIServer"
    execute_command "killall SystemUIServer"
  fi
}

# Check Linux Package

check_linux_package () {
  PACKAGE="$1"
  verbose_message "Configuring Linux package \"$PACKAGE\""
  if [ "$LSB_ID" = "Ubuntu" ]; then
    if [ "$INSTALL_APT" = "true" ]; then
      PACKAGE_TEST=$( grep "^$PACKAGE$" "$INSTALLED_FILE" )
      if [ -z "$PACKAGE_TEST" ]; then
        execute_command "sudo apt install -y $PACKAGE"
      fi
    fi
  fi
}

# Check OSX Package

check_osx_package () {
  PACKAGE="$1"
  TYPE="$2"
  verbose_message "Configuring OS X package \"$PACKAGE\""
  if [ "$INSTALL_BREW" = "true" ]; then
    PACKAGE_TEST=$( grep "^$PACKAGE$" "$INSTALLED_FILE" )
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

# Check Linux Applications

check_linux_packages () {
  if [ "$LSB_ID" = "Ubuntu" ]; then
    if [ "$INSTALL_APT" = "true" ]; then
      REQUIRED_TEST=$( find "$REQUIRED_FILE" -mtime -2 2> /dev/null )
      SCRIPT_TEST=$( find "$SCRIPT_FILE" -mtime -2 2> /dev/null )
      if [ "$REQUIRED_TEST" ] || [ "$SCRIPT_TEST" ]; then
        update_package_list
        for PACKAGE in "${REQUIRED_LIST[@]}"; do
          check_linux_package "$PACKAGE" ""
        done
      fi
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
          BREW_DIR=$( dirname "$BREW_BIN" )
          BREW_BASE=$( dirname "$BREW_DIR" )
        fi
      done
      if [ -z "$BREW_BIN" ]; then
        execute_command "/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        for BREW_FILE in /opt/homebrew/bin/brew /usr/local/homebrew/bin/brew; do
          if [ -f "$BREW_FILE" ]; then
            BREW_BIN="$BREW_FILE"
            BREW_DIR=$( dirname "$BREW_BIN" )
            BREW_BASE=$( dirname "$BREW_DIR" )
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
    REQUIRED_TEST=$( find "$REQUIRED_FILE" -mtime -2 2> /dev/null )
    SCRIPT_TEST=$( find "$SCRIPT_FILE" -mtime -2 2> /dev/null )
    if [ "$REQUIRED_TEST" ] || [ "$SCRIPT_TEST" ]; then
      update_package_list
      for PACKAGE in "${REQUIRED_LIST[@]}"; do
        check_osx_package "$PACKAGE" ""
      done
    fi
  fi
}

# Check for update

check_for_update () {
  verbose_message "Checking for updates"
  set_env "README_URL" "https://raw.githubusercontent.com/lateralblast/ussuri/main/README.md"
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
  set_env "WORK_DIR"    "$HOME/.$SCRIPT_NAME"
  execute_command "mkdir -p $WORK_DIR/files" "run"
  set_all_defaults
  if [ "$DO_INSTALL" = "false" ]; then
    if [ "$OS_NAME" = "Darwin" ]; then
      set_osx_defaults
    fi
    if [ "$OS_NAME" = "Linux" ]; then
      set_linux_defaults
    fi
  fi
}

# Check defaults

check_defaults () {
  if [ "$OS_NAME" = "Darwin" ]; then
    check_osx_defaults
  fi
  if [ "$OS_NAME" = "Linux" ]; then
    check_linux_defaults
  fi
}

# Check packages

check_package_config () {
  if [ "$OS_NAME" = "Darwin" ]; then
    check_osx_packages
  fi
  if [ "$OS_NAME" = "Linux" ]; then
    check_linux_packages
  fi
}

# Handle install mode

if [[ "$*" =~ "install" ]]; then
  DO_INSTALL="true"
else
  set_env "DO_INSTALL" "false"
fi

# Set defauts

if [[ "$*" =~ "verbose" ]]; then
  DO_VERBOSE="true"
else
  set_env "DO_VERBOSE" "false"
fi

set_defaults

# If given no command arguments run as a normal login script
# Otherwise handle commandline argument

if [ ! "$*" = "" ]; then
  while test $# -gt 0; do
    case $1 in
      -A|--doall)
        DO_BUILD="true"
        DO_DEFAULTS_CHECK="true"
        DO_FONTS_CHECK="true"
        DO_ZSH_THEME="true"
        DO_ZINIT_CHECK="true"
        DO_P10K_CHECK="true"
        DO_RBENV_CHECK="true"
        DO_PYENV_CHECK="true"
        DO_PACKAGE_CHECK="true"
        DO_FONTS_CHECK="true"
        DO_POSH_CHECK="true"
        DO_ENV_SETUP="true"
        shift
        ;;
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
      -i|--inline)
        set_inline_defaults
        shift
        ;;
      -I|--install)
        DO_INSTALL="true"
        shift
        ;;
      -l|--location|--startdir)
        START_DIR="$2"
        shift 2
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
      -O|--ohmyzsh|--zosh)
        DO_FONTS_CHECK="true"
        DO_ZOSH_CHECK="true"
        shift
        ;;
      -P|--package|--packages)
        DO_PACKAGE_CHECK="true"
        shift
        ;;
      -p|--pyenv)
        DO_BUILD="true"
        DO_PYENV_CHECK="true"
        INSTALL_PYENV="true"
        DO_ENV_SETUP="true"
        shift
        ;;
      -r|--rbenv)
        DO_BUILD="true"
        DO_RBENV_CHECK="true"
        INSTALL_RBENV="true"
        DO_ENV_SETUP="true"
        shift
        ;;
      -s|--sudoers)
        DO_SUDOERS_CHECK="true"
        shift
        ;;
      -S|--sudoersentry)
        SUDOERS_ENTRY="$2"
        shift 2
        ;;
      -t|--test|--dryrun)
        DO_DRYRUN="true"
        shift
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

# Handle dryrun

if [ "$DO_DRYRUN" = "true" ]; then
  handle_output "Running without executing commands" "info"
fi

# Set debug

if [ "$DO_DEBUG" = "true" ]; then
  set -x
fi

# Print help

if [ "$DO_HELP" = "true" ]; then
  print_help
  exit
fi

# Print version

if [ "$DO_VERSION" = "true" ]; then
  echo "$SCRIPT_VERSION"
  exit
fi

# Do sudoers

if [ "$DO_SUDOERS_CHECK" = "true" ]; then
  check_sudoers_config
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

if [ ! "$START_DIR" = "none" ] && [ ! "$START_DIR" = "" ]; then
  if [ -d "$START_DIR" ]; then
    cd "$START_DIR" || return
  fi
fi
