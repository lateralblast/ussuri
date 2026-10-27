#!/usr/bin/env zsh
#
# Version: 1.5.3
#
# License: CC BY-NC-SA 4.0
# https://creativecommons.org/licenses/by-nc-sa/4.0/
#

# Set some initial variables

SCRIPT_FILE="$0"
DO_UPDATE_LIST="false"
HOME_DIR="${HOME}"
INIT_DIR="${PWD}"
CALLER="${0}"
ARGS=( "$@" )

# This runs on every new shell, so avoid forking where zsh can do the job itself
# (id, whoami, hostname, date, pwd, uname, dirname, cut, grep and awk are all builtin equivalents below)

MY_USERID="${UID}"
MY_USERNAME="${USERNAME}"
HOSTNAME="${HOST}"
# Keep PATH free of duplicates (and let exp_env treat it as an array)

typeset -U path

zmodload zsh/datetime 2> /dev/null
if (( $+builtins[strftime] )); then
  strftime -s DATE '%a %d %b %Y %T %Z' "${EPOCHSECONDS}"
else
  DATE=$( date )
fi

if [[ ! "${CALLER}" =~ "X11|Antigravity" ]]; then

  # Optional user settings (see --config), e.g. DO_VERBOSE=true. Sourced before anything reads
  # these variables, so it wins over the environment, and command line switches win over it

  CONFIG_FILE="${USSURI_CONFIG:-${HOME_DIR}/.ussuri/config}"
  if [ -r "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
  fi

  # USSURI_OS (darwin or linux) overrides the detected OS, which the tests use to exercise
  # the Linux code on any machine
  case "${USSURI_OS:-${OSTYPE}}" in
    darwin*)
      OS_NAME="Darwin"
      ;;
    linux*)
      OS_NAME="GNU/Linux"
      ;;
    *)
      OS_NAME=$( uname -o )
      ;;
  esac

  GO_HOME="${GO_HOME:-${HOME}/go}"

  if [ "$INIT_DIR" = "" ]; then
    INIT_DIR="${HOME_DIR}"
  fi

  if [ "${SCRIPT_FILE}" = "-zsh" ] || [ "${SCRIPT_FILE}" = "-/bin/zsh" ] || [ "${SCRIPT_FILE}" = "zsh" ]; then
    SCRIPT_FILE="${HOME_DIR}/.zshrc"
  else
    SCRIPT_DIR="${SCRIPT_FILE:h}"
    if [ "${SCRIPT_DIR}" = "." ]; then
      SCRIPT_DIR="${PWD}"
    fi
  fi
fi

SCRIPT_NAME="ussuri"
START_DIR="${START_DIR:-none}"

# Create a lock file
# The lock is a directory so taking it is atomic (mkdir either creates it or fails)
# A lock older than 10 minutes is considered stale

HOLD_LOCK="false"
LOCK_FILE="${HOME_DIR}/.${SCRIPT_NAME}.lock"

# zsh/files provides mkdir and rm as builtins (loaded with a zf_ prefix so the real
# commands aren't replaced), which saves three forks per shell. Falls back to the commands.

zmodload -F zsh/files b:zf_mkdir b:zf_rm 2> /dev/null

release_lock () {
  if [ "${HOLD_LOCK}" = "true" ]; then
    if (( $+builtins[zf_rm] )); then
      zf_rm -rf "${LOCK_FILE}"
    else
      rm -rf "${LOCK_FILE}"
    fi
    HOLD_LOCK="false"
  fi
}

acquire_lock () {
  # (Nmm+10) matches a lock last modified more than 10 minutes ago
  LOCK_STALE=( ${LOCK_FILE}(Nmm+10) )
  if (( ${#LOCK_STALE} )); then
    rm -rf "${LOCK_FILE}"
  fi
  if (( $+builtins[zf_mkdir] )); then
    zf_mkdir "${LOCK_FILE}" 2> /dev/null && HOLD_LOCK="true"
  else
    mkdir "${LOCK_FILE}" 2> /dev/null && HOLD_LOCK="true"
  fi
}

# Read only modes (--doctor, --drift) must not create or copy anything

is_read_only () {
  [ "${DO_DOCTOR}" = "true" ] || [ "${DO_DRIFT}" = "true" ]
}

# Guards used throughout: is the lock held, and which OS is this
# (OS_NAME is GNU/Linux until set_all_defaults tidies it up, so match on the Linux part)

have_lock () {
  [ "${HOLD_LOCK}" = "true" ]
}

is_osx () {
  [ "${OS_NAME}" = "Darwin" ]
}

is_linux () {
  [[ "${OS_NAME}" == *Linux* ]]
}

# Key bindings for zsh-history-substring-search (called from the plugin lists in files/zinit):
# Up and Down search history for what has been typed so far. Terminals send different codes for
# the arrow keys depending on keypad mode (zsh switches to "application mode" while editing),
# so the usual ones are bound as well as the one terminfo names. A key whose widget isn't there
# (the plugin didn't load) is left alone

bind_history_search () {
  zmodload zsh/terminfo 2> /dev/null
  typeset -g HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
  local key
  for key in '^[[A' '^[OA' "${terminfo[kcuu1]}"; do
    [[ -n "${key}" ]] && bindkey "${key}" history-substring-search-up 2> /dev/null
  done
  for key in '^[[B' '^[OB' "${terminfo[kcud1]}"; do
    [[ -n "${key}" ]] && bindkey "${key}" history-substring-search-down 2> /dev/null
  done
  return 0
}

# Is this Linux distribution the given one, or derived from it? (os-release ID, or one of the
# words in ID_LIKE: Manjaro and EndeavourOS are "arch", Mint and Pop!_OS are "debian"/"ubuntu".)
# Used by the plugin lists in files/zinit to load a snippet only where it applies

os_is_like () {
  [[ "${OS_ID}" == "$1" ]] && return 0
  # Via an array: subscripting ${${=OS_LIKE}[...]} directly searches inside one string, so "arch"
  # would match a word that merely contains it
  local like_words=( ${=OS_LIKE} )
  (( ${like_words[(Ie)$1]} ))
}

# Handle output

handle_output () {
  OUTPUT="$1"
  STYLE="$2"
  if [ "${DO_VERBOSE}" = "true" ]; then
    case "${STYLE}" in
      add|adding)
        echo "Adding:         ${OUTPUT}"
        ;;
      warn|warning)
        echo "Warning:        ${OUTPUT}"
        ;;
      execute|executing)
        echo "Executing:      ${OUTPUT}"
        ;;
      command)
        echo "Command:        ${OUTPUT}"
        ;;
      info|information)
        echo "Information:    ${OUTPUT}"
        ;;
      set|setting)
        echo "Setting:        ${OUTPUT}"
        ;;
      check|checking)
        echo "Checking:       ${OUTPUT}"
        ;;
      save|saving)
        echo "Saving:         ${OUTPUT}"
        ;;
      replace|replacing)
        echo "Replacing:      ${OUTPUT}"
        ;;
      restart|restarting)
        echo "Restarting:     ${OUTPUT}"
        ;;
      *)
        echo "${OUTPUT}"
        ;;
    esac
  fi
}

# Drift reporting (--drift): the same checks as applying the defaults, but reporting what
# differs ("actual -> expected", grouped under a domain) instead of writing anything

report_drift () {
  DRIFT_COUNT=$(( DRIFT_COUNT + 1 ))
  if [ ! "$1" = "${DRIFT_LAST_GROUP}" ]; then
    print -r -- "$1"
    DRIFT_LAST_GROUP="$1"
  fi
  printf '  %-40s %s -> %s\n' "$2" "$3" "$4"
}

run_drift () {
  DRIFT_COUNT=0
  DRIFT_TOTAL=0
  DRIFT_LAST_GROUP=""
  if is_osx; then
    apply_osx_defaults
  elif is_linux; then
    if ! linux_defaults_available; then
      print -r -- "No desktop session (gsettings and a session bus are needed), so there is nothing to compare"
      return 2
    fi
    apply_linux_defaults
  else
    print -r -- "Drift reporting isn't available on ${OS_NAME}"
    return 2
  fi
  print
  if (( DRIFT_COUNT )); then
    print -r -- "${DRIFT_COUNT} of ${DRIFT_TOTAL} settings differ from what ussuri would apply. Run --defaults to apply them."
    return 1
  fi
  print -r -- "All ${DRIFT_TOTAL} settings match."
}

# GNOME settings (Linux), through gsettings
#
# set_linux_default SCHEMA KEY VALUE, with VALUE written the way gsettings prints it: true, 'text'
# or uint32 250. A schema or key that doesn't exist on this desktop is skipped, so the list can
# name settings that only some versions have. Applied by --defaults (and on login if
# DO_GNOME_DEFAULTS=true), and covered by --drift.

linux_defaults_available () {
  (( $+commands[gsettings] )) && [ -n "${DBUS_SESSION_BUS_ADDRESS}" ]
}

set_linux_default () {
  L_SCHEMA="$1"
  L_KEY="$2"
  L_VALUE="$3"
  verbose_message "GNOME setting ${L_SCHEMA} ${L_KEY} is ${L_VALUE}" "check"
  L_CURRENT=$( gsettings get "${L_SCHEMA}" "${L_KEY}" 2> /dev/null )
  if (( $? )); then
    verbose_message "${L_SCHEMA} ${L_KEY} doesn't exist on this desktop, skipping"
    return
  fi
  if [ "${DO_DRIFT}" = "true" ]; then
    DRIFT_TOTAL=$(( DRIFT_TOTAL + 1 ))
    if [ ! "${L_CURRENT}" = "${L_VALUE}" ]; then
      report_drift "${L_SCHEMA}" "${L_KEY}" "${L_CURRENT}" "${L_VALUE}"
    fi
    return
  fi
  if [ ! "${L_CURRENT}" = "${L_VALUE}" ]; then
    verbose_message "GNOME setting ${L_SCHEMA} ${L_KEY} to ${L_VALUE}" "set"
    execute_command "gsettings set ${(q)L_SCHEMA} ${(q)L_KEY} ${(q)${L_VALUE#uint32 }}"
  fi
}

apply_linux_defaults () {
  set_linux_default "org.gnome.desktop.peripherals.keyboard" "repeat"                    "true"
  set_linux_default "org.gnome.desktop.peripherals.keyboard" "delay"                     "uint32 250"
  set_linux_default "org.gnome.desktop.peripherals.keyboard" "repeat-interval"           "uint32 30"
  set_linux_default "org.gnome.desktop.interface"            "show-battery-percentage"   "true"
  set_linux_default "org.gnome.desktop.interface"            "clock-show-date"           "true"
  set_linux_default "org.gnome.desktop.wm.preferences"       "button-layout"             "'appmenu:minimize,maximize,close'"
  set_linux_default "org.gnome.desktop.privacy"              "report-technical-problems" "false"
  set_linux_default "org.gnome.desktop.privacy"              "remove-old-trash-files"    "true"
  set_linux_default "org.gnome.desktop.privacy"              "remove-old-temp-files"     "true"
  set_linux_default "org.gnome.nautilus.preferences"         "default-folder-viewer"     "'list-view'"
  set_linux_default "org.gtk.Settings.FileChooser"           "show-hidden"               "true"
  set_linux_default "org.gtk.Settings.FileChooser"           "sort-directories-first"    "true"
  set_linux_default "org.gtk.gtk4.Settings.FileChooser"      "show-hidden"               "true"
  set_linux_default "org.gtk.gtk4.Settings.FileChooser"      "sort-directories-first"    "true"
}

# Notice message (always printed, for slow or interactive actions so the shell doesn't look hung)

notice_message () {
  echo "Notice:         $1"
}

# Execute command
# OPTION "run":  execute even in dryrun mode (read only helpers like directory listing tar pipes)
# OPTION "show": don't hide the command output when not verbose (installers, sudo, long builds)

execute_command () {
  COMMAND="$1"
  OPTION="$2"
  if [ "${DO_VERBOSE}" = "true" ] || [ "${DO_DRYRUN}" = "true" ]; then
    handle_output "${COMMAND}" "execute"
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] || [ "${OPTION}" = "run" ]; then
    DO_EXECUTE="true"
    if [ "${DO_CONFIRM}" = "true" ]; then
      DO_EXECUTE="false"
      RESPONSE=""
      if [[ -t 0 ]]; then
        # The command is part of the prompt so it is shown even without --verbose
        read -r "RESPONSE?Execute: ${COMMAND} [y/n]:  "
        if [ "${RESPONSE}" = "y" ]; then
          DO_EXECUTE="true"
        fi
      else
        echo "Warning:        No terminal to confirm on, skipping: ${COMMAND}"
      fi
    fi
    if [ "${DO_EXECUTE}" = "true" ]; then
      if [ "${DO_VERBOSE}" = "true" ] || [ "${OPTION}" = "show" ]; then
        eval "${COMMAND}"
      else
        eval "${COMMAND} > /dev/null 2>&1"
      fi
    fi
  fi
}

# Evaluate the output of a tool's init command (rbenv init, brew shellenv, etc) via a cache
# Each of these takes a few hundred milliseconds, which is added to every new shell, but
# their output only changes when the tool does. The cache is rebuilt when the tool's binary
# is newer than the cache. Optional third argument is a pattern for output lines to leave
# out of the cache (the "rehash" line of rbenv/pyenv, which forks the tool on every shell).
# CACHE_BLOCK_START and CACHE_BLOCK_END, if set by the caller, are the literal start of the first
# line and end of the last line of a block to leave out (pyenv init forks bash to remove
# duplicates from PATH, which typeset -U path already takes care of).
# Set DO_CACHE_INIT=false to always run the init command.

cached_eval () {
  CACHE_BIN="$1"
  CACHE_CMD="$2"
  CACHE_SKIP="$3"
  if [ ! "${DO_CACHE_INIT}" = "true" ]; then
    eval "$( eval "${CACHE_CMD}" )"
    return
  fi
  CACHE_DIR="${WORK_DIR}/cache"
  CACHE_FILE="${CACHE_DIR}/${CACHE_BIN//\//_}.zsh"
  if [[ -s "${CACHE_FILE}" && ! "${CACHE_BIN}" -nt "${CACHE_FILE}" ]]; then
    source "${CACHE_FILE}"
  else
    CACHE_OUT=$( eval "${CACHE_CMD}" )
    if [ -n "${CACHE_OUT}" ]; then
      if [ ! -d "${CACHE_DIR}" ]; then
        mkdir -p "${CACHE_DIR}"
      fi
      eval "${CACHE_OUT}"
      CACHE_LINES=( "${(@f)CACHE_OUT}" )
      if [ -n "${CACHE_SKIP}" ]; then
        CACHE_LINES=( ${CACHE_LINES:#${~CACHE_SKIP}} )
      fi
      if [ -n "${CACHE_BLOCK_START}" ]; then
        CACHE_KEPT=()
        CACHE_IN_BLOCK="false"
        for CACHE_LINE in "${CACHE_LINES[@]}"; do
          if [ "${CACHE_IN_BLOCK}" = "false" ] && [ "${CACHE_LINE[1,${#CACHE_BLOCK_START}]}" = "${CACHE_BLOCK_START}" ]; then
            CACHE_IN_BLOCK="true"
          fi
          if [ "${CACHE_IN_BLOCK}" = "true" ]; then
            if [ "${CACHE_LINE[-${#CACHE_BLOCK_END},-1]}" = "${CACHE_BLOCK_END}" ]; then
              CACHE_IN_BLOCK="false"
            fi
            continue
          fi
          CACHE_KEPT+=( "${CACHE_LINE}" )
        done
        CACHE_LINES=( "${CACHE_KEPT[@]}" )
      fi
      print -r -- "${(F)CACHE_LINES}" > "${CACHE_FILE}"
    fi
  fi
}

# Download an installer to a file, check its checksum when one is pinned, and only then run it
# (rather than piping curl into a shell, which runs a truncated download and can't be verified).
# Usage: fetch_and_run URL SHA256 [arguments for the installer...]
# The installer is run with bash. An empty SHA256 runs it unverified, with a notice.

sha256_of () {
  if (( $+commands[shasum] )); then
    SHA_OUT=$( shasum -a 256 "$1" 2> /dev/null )
  else
    SHA_OUT=$( sha256sum "$1" 2> /dev/null )
  fi
  print -r -- "${(L)${SHA_OUT%% *}}"
}

fetch_and_run () {
  INSTALL_URL="$1"
  INSTALL_SHA="${(L)2}"
  shift 2
  INSTALL_TMP=$( mktemp )
  if ! fetch_url "${INSTALL_URL}" > "${INSTALL_TMP}" || [ ! -s "${INSTALL_TMP}" ]; then
    echo "Warning:        Could not download ${INSTALL_URL}"
    rm -f "${INSTALL_TMP}"
    return 1
  fi
  if [ -n "${INSTALL_SHA}" ]; then
    INSTALL_SUM=$( sha256_of "${INSTALL_TMP}" )
    if [ ! "${INSTALL_SUM}" = "${INSTALL_SHA}" ]; then
      echo "Warning:        Checksum mismatch for ${INSTALL_URL} (expected ${INSTALL_SHA}, got ${INSTALL_SUM}), not running it"
      rm -f "${INSTALL_TMP}"
      return 1
    fi
  else
    notice_message "${INSTALL_URL} is not pinned to a checksum, running it unverified"
  fi
  bash "${INSTALL_TMP}" "$@"
  INSTALL_RC=$?
  rm -f "${INSTALL_TMP}"
  return ${INSTALL_RC}
}

# Clone a git repository, optionally pinned to a branch, tag or commit (GIT_REF) and/or
# shallow (GIT_DEPTH, ignored when pinned as a pinned commit needs the history).
# Usage: git_clone URL DIR [REF] [DEPTH]
# Pins only apply to the first clone, an existing install is never touched.

git_clone () {
  GIT_URL="$1"
  GIT_DIR="$2"
  GIT_REF="$3"
  GIT_DEPTH="$4"
  GIT_OPTS=()
  if [ -n "${GIT_DEPTH}" ] && [ -z "${GIT_REF}" ]; then
    GIT_OPTS=( --depth "${GIT_DEPTH}" )
  fi
  git clone "${GIT_OPTS[@]}" "${GIT_URL}" "${GIT_DIR}" || return 1
  if [ -n "${GIT_REF}" ]; then
    git -C "${GIT_DIR}" checkout --quiet "${GIT_REF}"
  fi
}

# Handle force mode (must be checked before the lock file is taken below)
# Match whole arguments so values like -S "install" don't trigger a switch

if (( ${ARGS[(Ie)-F]} || ${ARGS[(Ie)--force]} )); then
  DO_FORCE="true"
  rm -rf "${LOCK_FILE}"
else
  DO_FORCE="false"
fi

acquire_lock

# Set OSX Finder defaults

set_osx_finder_defaults () {
  set_osx_default     "com.apple.finder"                  "AppleShowAllFiles"                           "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowPathbar"                                 "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowStatusBar"                               "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowHardDrivesOnDesktop"                     "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowExternalHardDrivesOnDesktop"             "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowMountedServersOnDesktop"                 "bool"    "true"
  set_osx_default     "com.apple.finder"                  "ShowRemovableMediaOnDesktop"                 "bool"    "true"
  set_osx_default     "com.apple.finder"                  "FXEnableExtensionChangeWarning"              "bool"    "false"
  set_osx_default     "com.apple.finder"                  "FXPreferredViewStyle"                        "string"  "Nlsv"
  set_osx_default     "com.apple.finder"                  "DisableAllAnimations"                        "bool"    "true"
  set_osx_default     "com.apple.finder"                  "OpenWindowForNewRemovableDisk"               "bool"    "true"
  set_osx_default     "com.apple.finder"                  "com.apple.springing.delay"                   "float"   "0"
  set_osx_default     "com.apple.TimeMachine"             "DoNotOfferNewDisksForBackup"                 "bool"    "true"
  set_osx_default     "com.apple.desktopservices"         "DSDontWriteNetworkStores"                    "bool"    "true"
  set_osx_default     "com.apple.desktopservices"         "DSDontWriteUSBStores"                        "bool"    "true"
  set_osx_default     "com.apple.frameworks.diskimages"   "auto-open-ro-root"                           "bool"    "true"
  set_osx_default     "com.apple.frameworks.diskimages"   "auto-open-rw-root"                           "bool"    "true"
}

# Set OSX Dock defaults

# Hot corners
# Possible values:
#  0: no-op
#  2: Mission Control
#  3: Show application windows
#  4: Desktop
#  5: Start screen saver
#  6: Disable screen saver
#  7: Dashboard
# 10: Put display to sleep
# 11: Launchpad
# 12: Notification Center
# 13: Lock Screen

set_osx_dock_defaults () {
  set_osx_default     "com.apple.dock"                    "orientation"                                 "string"  "bottom"
  set_osx_default     "com.apple.dock"                    "tilesize"                                    "int"     "32"
  set_osx_default     "com.apple.dock"                    "autohide"                                    "bool"    "false"
  set_osx_default     "com.apple.dock"                    "autohide-time-modifier"                      "float"   "0.5"
  set_osx_default     "com.apple.dock"                    "autohide-delay"                              "float"   "0.2"
  set_osx_default     "com.apple.dock"                    "show-recents"                                "bool"    "false"
  set_osx_default     "com.apple.dock"                    "mineffect"                                   "string"  "scale"
  set_osx_default     "com.apple.dock"                    "wvous-tl-corner"                             "int"     "5"
  set_osx_default     "com.apple.dock"                    "wvous-tl-modifier"                           "int"     "0"
  set_osx_default     "com.apple.dock"                    "wvous-tr-corner"                             "int"     "2"
  set_osx_default     "com.apple.dock"                    "wvous-tr-modifier"                           "int"     "0"
  set_osx_default     "com.apple.dock"                    "wvous-bl-corner"                             "int"     "4"
  set_osx_default     "com.apple.dock"                    "wvous-bl-modifier"                           "int"     "0"
  set_osx_default     "com.apple.dock"                    "wvous-br-corner"                             "int"     "3"
  set_osx_default     "com.apple.dock"                    "wvous-br-modifier"                           "int"     "0"
}

# Set OSX Screen Capture defaults

set_osx_screencapture_defaults () {
  set_env "SCREENSHOT_LOCATION" "${HOME_DIR}/Pictures/Screenshots"
  check_dir_exists    "${SCREENSHOT_LOCATION}"
  set_osx_default     "com.apple.screencapture"           "disable-shadow"                              "bool"    "true"
  set_osx_default     "com.apple.screencapture"           "include-date"                                "bool"    "true"
  set_osx_default     "com.apple.screencapture"           "show-thumbnail"                              "bool"    "true"
  set_osx_default     "com.apple.screencapture"           "type"                                        "string"  "png"
  set_osx_default     "com.apple.screencapture"           "location"                                    "string"  "${SCREENSHOT_LOCATION}"
}

# Can a URL be fetched? Used before a blocklist URL is written into Transmission's settings, so a
# dead host can't quietly replace a working one (the previous default, john.bitsurge.net, went away
# and Transmission was left with a blocklist it had never been able to download)

url_reachable () {
  if (( $+commands[curl] )); then
    curl -fsSIL -m 15 -o /dev/null "$1" 2> /dev/null
  elif (( $+commands[wget] )); then
    wget -q --spider -T 15 "$1" 2> /dev/null
  fi
}

# Set OSX transmission defaults

set_osx_transmission_defaults () {
  set_env "TORRENT_DIR" "${HOME_DIR}/Downloads/transmission"
  # Bluetack's Level 1 list as served by iblocklist.com (what Transmission used to ship), over HTTPS.
  # It redirects to a storage host. Not endorsed by the Transmission developers, see the README
  set_env "TRANSMISSION_BLOCKLIST_URL" "https://list.iblocklist.com/?list=bt_level1&fileformat=p2p&archiveformat=gz"
  check_dir_exists    "${TORRENT_DIR}"
  set_osx_default     "org.m0k.transmission"              "DownloadAsk"                                 "bool"    "false"
  set_osx_default     "org.m0k.transmission"              "MagnetOpenAsk"                               "bool"    "false"
  set_osx_default     "org.m0k.transmission"              "UseIncompleteDownloadFolder"                 "bool"    "true"
  set_osx_default     "org.m0k.transmission"              "IncompleteDownloadFolder"                    "string"  "${TORRENT_DIR}"
  set_osx_default     "org.m0k.transmission"              "DownloadLocationConstant"                    "bool"    "true"
  set_osx_default     "org.m0k.transmission"              "CheckRemoveDownloading"                      "bool"    "true"
  set_osx_default     "org.m0k.transmission"              "DeleteOriginalTorrent"                       "bool"    "true"
  set_osx_default     "org.m0k.transmission"              "WarningDonate"                               "bool"    "false"
  set_osx_default     "org.m0k.transmission"              "WarningLegal"                                "bool"    "false"
  set_osx_default     "org.m0k.transmission"              "BlocklistNew"                                "bool"    "true"
  TRANSMISSION_WRITE_URL="true"
  if [ ! "${DO_DRIFT}" = "true" ]; then
    TRANSMISSION_CURRENT=$( defaults read org.m0k.transmission BlocklistURL 2> /dev/null )
    if [ ! "${TRANSMISSION_CURRENT}" = "${TRANSMISSION_BLOCKLIST_URL}" ] && (( $+commands[curl] || $+commands[wget] )) && ! url_reachable "${TRANSMISSION_BLOCKLIST_URL}"; then
      echo "Warning:        ${TRANSMISSION_BLOCKLIST_URL} is not reachable, leaving the Transmission blocklist URL as it is (${TRANSMISSION_CURRENT:-not set})"
      TRANSMISSION_WRITE_URL="false"
    fi
  fi
  if [ "${TRANSMISSION_WRITE_URL}" = "true" ]; then
    set_osx_default     "org.m0k.transmission"              "BlocklistURL"                                "string"  "${TRANSMISSION_BLOCKLIST_URL}"
  fi
  set_osx_default     "org.m0k.transmission"              "BlocklistAutoUpdate"                         "bool"    "true"
  set_osx_default     "org.m0k.transmission"              "RandomPort"                                  "bool"    "true"
}

# Set App Store and update defaults

set_osx_update_defaults () {
  set_osx_default     "com.apple.commerce"                "AutoUpdate"                                  "bool"    "true"
  set_osx_default     "com.apple.SoftwareUpdate"          "ConfigDataInstall"                           "int"     "1"
  set_osx_default     "com.apple.SoftwareUpdate"          "AutomaticDownload"                           "int"     "1"
  set_osx_default     "com.apple.SoftwareUpdate"          "CriticalUpdateInstall"                       "int"     "1"
  set_osx_default     "com.apple.SoftwareUpdate"          "ScheduleFrequency"                           "int"     "1"
  set_osx_default     "com.apple.SoftwareUpdate"          "AutomaticCheckEnabled"                       "bool"    "true"
  set_osx_default     "com.apple.appstore"                "ShowDebugMenu"                               "bool"    "true"
  set_osx_default     "com.apple.appstore"                "WebKitDeveloperExtras"                       "bool"    "true"
}

# Set OSX App / Utility defaults

set_osx_app_defaults () {
  set_osx_default     "com.apple.DiskUtility"             "DUDebugMenuEnabled"                          "bool"    "true"
  set_osx_default     "com.apple.DiskUtility"             "advanced-image-options"                      "bool"    "true"
  set_osx_default     "com.apple.addressbook"             "ABShowDebugMenu"                             "bool"    "true"
  set_osx_default     "com.apple.print.PrintingPrefs"     "Quit When Finished"                          "bool"    "true"
  OS_REL=$( uname -r )
  OS_REL_MAJ="${OS_REL%%.*}"
  if [ "${OS_REL_MAJ}" -lt 25 ]; then
    set_osx_default     "com.apple.systempreferences"       "NSQuitAlwaysKeepsWindows"                    "bool"    "false"
  fi
}

# Set OSX NSGLobal defaults 

set_osx_nsglobal_defaults () {
  set_osx_default     "NSGlobalDomain"                    "NSTableViewDefaultSizeMode"                  "int"     "1"
  set_osx_default     "NSGlobalDomain"                    "KeyRepeat"                                   "int"     "1"
  set_osx_default     "NSGlobalDomain"                    "InitialKeyRepeat"                            "int"     "10"
  set_osx_default     "NSGlobalDomain"                    "NSToolbarTitleViewRolloverDelay"             "float"   "0"
  set_osx_default     "NSGlobalDomain"                    "NSWindowResizeTime"                          "float"   "0.001"
  set_osx_default     "NSGlobalDomain"                    "NSAutomaticCapitalizationEnabled"            "bool"    "false"
  set_osx_default     "NSGlobalDomain"                    "NSAutomaticDashSubstitutionEnabled"          "bool"    "false"
  set_osx_default     "NSGlobalDomain"                    "NSAutomaticPeriodSubstitutionEnabled"        "bool"    "false"
  set_osx_default     "NSGlobalDomain"                    "NSUseAnimatedFocusRing"                      "bool"    "false"
  set_osx_default     "NSGlobalDomain"                    "NSAutomaticQuoteSubstitutionEnabled"         "bool"    "false"
  set_osx_default     "NSGlobalDomain"                    "AppleMetricUnits"                            "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "NSNavPanelExpandedStateForSaveMode"          "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "NSNavPanelExpandedStateForSaveMode2"         "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "PMPrintingExpandedStateForPrint"             "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "PMPrintingExpandedStateForPrint2"            "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "WebKitDeveloperExtras"                       "bool"    "true"
  set_osx_default     "NSGlobalDomain"                    "AppleMeasurementUnits"                       "string"  "Centimeters"
  set_osx_default     "NSGlobalDomain"                    "AppleLocale"                                 "string"  "en_AU@currency=AUD"
}

# Set OSX Safari defaults

set_osx_safari_defaults () {
  set_osx_default     "com.apple.Safari"                  "InstallExtensionUpdatesAutomatically"        "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "InstallExtensionUpdatesAutomatically"        "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "IncludeDevelopMenu"                          "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "IncludeDevelopMenu"                          "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "IncludeInternalDebugMenu"                    "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "IncludeInternalDebugMenu"                    "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "WebKitDeveloperExtrasEnabledPreferenceKey"   "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "WebKitDeveloperExtrasEnabledPreferenceKey"   "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "WarnAboutFraudulentWebsites"                 "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "WarnAboutFraudulentWebsites"                 "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "SendDoNotTrackHTTPHeader"                    "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "SendDoNotTrackHTTPHeader"                    "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "SuppressSearchSuggestions"                   "bool"    "true"
  set_osx_default     "com.apple.SafariTechnologyPreview" "SuppressSearchSuggestions"                   "bool"    "true"
  set_osx_default     "com.apple.Safari"                  "UniversalSearchEnabled"                      "bool"    "false"
  set_osx_default     "com.apple.SafariTechnologyPreview" "UniversalSearchEnabled"                      "bool"    "false"
  set_osx_default     "com.apple.Safari"                  "WebKitMediaPlaybackAllowsInline"             "bool"    "false"
  set_osx_default     "com.apple.SafariTechnologyPreview" "WebKitMediaPlaybackAllowsInline"             "bool"    "false"
  set_osx_default     "com.apple.Safari"                  "WebKitJavaScriptCanOpenWindowsAutomatically" "bool"    "false"
  set_osx_default     "com.apple.SafariTechnologyPreview" "WebKitJavaScriptCanOpenWindowsAutomatically" "bool"    "false"
  set_osx_default     "com.apple.Safari"                  "AutoOpenSafeDownloads"                       "bool"    "false"
  set_osx_default     "com.apple.SafariTechnologyPreview" "AutoOpenSafeDownloads"                       "bool"    "false"
  set_osx_default     "com.apple.Safari"                  "HomePage"                                    "string"  "about:blank"
  set_osx_default     "com.apple.SafariTechnologyPreview" "HomePage"                                    "string"  "about:blank"
}

# Set OSX defaults

set_osx_defaults () {
  set_env "INSTALL_BREW"      "true"
  set_env "DO_BREW_CHECK"     "true"
  set_env "RESTART_DOCK"      "false"
  set_env "RESTART_FINDER"    "false"
  set_env "RESTART_UISERVER"  "false"
  set_env "INSTALLED_FILE"    "${WORK_DIR}/brew.list"
  set_env "REQUIRED_FILE"     "${WORK_DIR}/files/packages/macos.brew"
  if [ "${DO_INSTALL}" = "false" ]; then
    if [ ! -f "${REQUIRED_FILE}" ]; then
      copy_support_files
    fi
  fi
}

# Read the required package list (one package per line, ignoring blank lines and comments)
# Only called when the list is processed, not on every shell

read_required_list () {
  setopt localoptions extendedglob
  REQUIRED_LIST=()
  if [ -f "${REQUIRED_FILE}" ]; then
    REQUIRED_LIST=( ${${(f)"$(<${REQUIRED_FILE})"}:#(\#*|[[:space:]]#)} )
  fi
}

# Apply OSX defaults (writes settings, so only called from check_osx_defaults
# once the command line has been parsed and dryrun/confirm are known)

apply_osx_defaults () {
  set_osx_file_state "${HOME_DIR}/Library" "nohidden"
  set_osx_finder_defaults
  set_osx_dock_defaults
  set_osx_screencapture_defaults
  set_osx_transmission_defaults
  set_osx_update_defaults
  set_osx_app_defaults
  set_osx_safari_defaults
  set_osx_nsglobal_defaults
}

# Set All Defaults

# Read the version from the header comment without forking grep and awk

read_file_version () {
  FILE_VERSION=""
  if [ -r "$1" ]; then
    while IFS= read -r VERSION_LINE; do
      if [[ "${VERSION_LINE}" == "# Version: "* ]]; then
        FILE_VERSION="${VERSION_LINE#\# Version: }"
        break
      fi
    done < "$1"
  fi
}

read_script_version () {
  read_file_version "${SCRIPT_FILE}"
  SCRIPT_VERSION="${FILE_VERSION}"
}

# Work out the Linux distribution from os-release (lsb_release is slow and often not installed)

set_linux_id () {
  LSB_ID=""
  OS_ID=""
  OS_LIKE=""
  set_env "OS_RELEASE_FILE" "/etc/os-release"
  if [ -r "${OS_RELEASE_FILE}" ]; then
    while IFS="=" read -r OS_KEY OS_VALUE; do
      OS_VALUE="${(L)${OS_VALUE//\"/}}"
      if [ "${OS_KEY}" = "ID" ]; then
        OS_ID="${OS_VALUE}"
      fi
      if [ "${OS_KEY}" = "ID_LIKE" ]; then
        OS_LIKE="${OS_VALUE}"
      fi
    done < "${OS_RELEASE_FILE}"
  fi
  case "${OS_ID}" in
    ubuntu)
      LSB_ID="Ubuntu"
      ;;
    arch)
      LSB_ID="Arch"
      ;;
    endeavouros)
      LSB_ID="EndeavourOS"
      ;;
    *)
      LSB_ID="${(C)OS_ID}"
      ;;
  esac
  if [ -z "${LSB_ID}" ] && (( $+commands[lsb_release] )); then
    LSB_ID=$( lsb_release -i -s 2> /dev/null )
    OS_ID="${(L)LSB_ID}"
  fi
  # The package manager is whatever the distro, or what it is derived from, uses. Set
  # PKG_MANAGER yourself (apt, pacman, dnf, apk or nix) to override it, e.g. nix on Ubuntu
  if [ -z "${PKG_MANAGER}" ]; then
    for OS_CANDIDATE in ${OS_ID} ${=OS_LIKE}; do
      case "${OS_CANDIDATE}" in
        ubuntu|debian)
          PKG_MANAGER="apt"
          ;;
        arch)
          PKG_MANAGER="pacman"
          ;;
        fedora|rhel|centos)
          PKG_MANAGER="dnf"
          ;;
        alpine)
          PKG_MANAGER="apk"
          ;;
        nixos)
          PKG_MANAGER="nix"
          ;;
      esac
      if [ -n "${PKG_MANAGER}" ]; then
        break
      fi
    done
  fi
}

# Everything that differs between package managers is in here
#   PKG_TOOL        the command to look for
#   PKG_LIST_NAME   the package list under files/packages
#   PKG_LIST_CMD    prints the installed package names, one per line
#   PKG_PREPARE     run once before the first install (refresh the index)
#   PKG_INSTALL     installs one package
#   PKG_PRIV        whether it needs root (sudo or doas), nix does not
#   PKG_REF_PREFIX  put in front of the package name when installing

set_pkg_manager () {
  PKG_PRIV="true"
  PKG_PREPARE=""
  PKG_REF_PREFIX=""
  case "${PKG_MANAGER}" in
    apt)
      PKG_TOOL="apt-get"
      PKG_LIST_NAME="ubuntu.apt"
      PKG_LIST_CMD="dpkg -l | grep ^ii | awk '{ print \$2 }' | sed 's/:[a-z0-9]*\$//'"
      PKG_PREPARE="apt-get update"
      PKG_INSTALL="apt install -y"
      ;;
    pacman)
      PKG_TOOL="pacman"
      PKG_LIST_NAME="arch.pacman"
      if [ "${OS_ID}" = "endeavouros" ]; then
        PKG_LIST_NAME="endeavouros.pacman"
      fi
      PKG_LIST_CMD="pacman -Q | awk '{ print \$1 }'"
      # Not -Sy: syncing the database without upgrading is an unsupported partial upgrade on Arch
      PKG_INSTALL="pacman --noconfirm --needed -S"
      ;;
    dnf)
      PKG_TOOL="dnf"
      PKG_LIST_NAME="fedora.dnf"
      PKG_LIST_CMD="rpm -qa --qf '%{NAME}\\n'"
      PKG_INSTALL="dnf install -y"
      ;;
    apk)
      PKG_TOOL="apk"
      PKG_LIST_NAME="alpine.apk"
      PKG_LIST_CMD="apk info"
      PKG_PREPARE="apk update"
      PKG_INSTALL="apk add"
      ;;
    nix)
      PKG_TOOL="nix"
      PKG_LIST_NAME="nix.nix"
      # Best effort: nix profile list changed format between versions, so read both
      PKG_LIST_CMD="NIX_CONFIG='experimental-features = nix-command flakes' nix profile list | awk '/^Name:/ { print \$2 } /legacyPackages\\./ && !/^(Name|Flake attribute):/ { n = split(\$2, a, \".\"); print a[n] }'"
      PKG_INSTALL="NIX_CONFIG='experimental-features = nix-command flakes' nix profile install"
      PKG_PRIV="false"
      PKG_REF_PREFIX="nixpkgs#"
      ;;
    *)
      PKG_TOOL=""
      ;;
  esac
  # Root: nothing if we are root, else sudo, else doas (Alpine often has only doas)
  PKG_SUDO=""
  if [ "${PKG_PRIV}" = "true" ] && [ ! "${UID}" = "0" ]; then
    if (( $+commands[sudo] )); then
      PKG_SUDO="sudo "
    elif (( $+commands[doas] )); then
      PKG_SUDO="doas "
    else
      PKG_SUDO="sudo "
    fi
  fi
}

set_all_defaults () {
  read_script_version
  if [[ "${OS_NAME}" =~ "Linux" ]]; then
    OS_NAME="Linux"
    set_linux_id
  fi
  if (( $+builtins[strftime] )); then
    strftime -s DATE_SUFFIX '%d_%m_%Y_%H_%M_%S' "${EPOCHSECONDS}"
  else
    DATE_SUFFIX=$( date +%d_%m_%Y_%H_%M_%S )
  fi
  verbose_message               "Setting defaults"
  exp_env "PATH"                "/usr/local/bin"
  exp_env "PATH"                "/usr/local/sbin"
  exp_env "PATH"                "/opt/local/bin"
  exp_env "PATH"                "/opt/local/sbin"
  exp_env "PATH"                "${HOME}/.local/bin"
  exp_env "PATH"                "${HOME}/.cargo/bin"
  if ! is_osx; then
    exp_env "LD_LIBRARY_PATH"   "/usr/local/lib"
  fi
  set_env "DO_HELP"             "false"
  set_env "DO_DRYRUN"           "false"
  set_env "DO_CONFIRM"          "false"
  set_env "DO_DEBUG"            "false"
  set_env "DO_BUILD"            "false"
  set_env "DO_FORCE"            "false"
  set_env "DO_PLUGINS"          "true"
  set_env "ZINIT_TURBO"         "true"
  ZINIT_SUFFIX=""
  if [ "${ZINIT_TURBO}" = "true" ]; then
    ZINIT_SUFFIX="-turbo"
  fi
  set_env "ZINIT_FILE"          "${WORK_DIR}/files/zinit/zinit${ZINIT_SUFFIX}.zsh"
  set_env "INSTALL_ZINIT"       "true"
  set_env "INSTALL_RBENV"       "true"
  set_env "INSTALL_PYENV"       "true"
  set_env "INSTALL_POSH"        "true"
  set_env "INSTALL_OZSH"        "false"
  set_env "INSTALL_FONTS"       "true"
  set_env "INSTALL_P10K"        "true"
  set_env "ZINIT_HOME"          "${HOME_DIR}/.zinit"
  set_env "RBENV_HOME"          "${HOME_DIR}/.rbenv"
  set_env "PYENV_HOME"          "${HOME_DIR}/.pyenv"
  set_env "POSH_HOME"           "${HOME_DIR}/.oh-my-posh"
  set_env "ZOSH_HOME"           "${HOME_DIR}/.oh-my-zsh"
  set_env "P10K_INIT"           "${HOME_DIR}/.p10k.zsh"
  set_env "SOURCE_P10K_INIT"    "${WORK_DIR}/files/p10k/p10k.zsh"
  set_env "P10K_HOME"           "${HOME_DIR}/.powerlevel10k"
  set_env "P10K_THEME"          "${P10K_HOME}/powerlevel10k.zsh-theme"
  set_env "DO_VERSION_CHECK"    "false"
  set_env "DO_DEFAULTS_CHECK"   "false"
  set_env "DO_PACKAGE_CHECK"    "false"
  set_env "DO_UPDATE_CHECK"     "false"
  set_env "DO_PYENV_CHECK"      "false"
  set_env "DO_RBENV_CHECK"      "false"
  set_env "DO_ZINIT_CHECK"      "false"
  set_env "DO_FONTS_CHECK"      "false"
  set_env "DO_POSH_CHECK"       "false"
  set_env "DO_P10K_CHECK"       "false"
  set_env "DO_ZOSH_CHECK"       "false"
  set_env "DO_ENV_SETUP"        "true"
  set_env "DO_ZSH_THEME"        "true"
  set_env "DO_CACHE_INIT"       "true"
  set_env "DO_DOCTOR"           "false"
  set_env "DO_CONFIG"           "false"
  set_env "DO_DOTFILES_CHECK"   "false"
  set_env "DO_UNLINK"           "false"
  set_env "DO_BACKUPS"          "false"
  set_env "DO_DRIFT"            "false"
  set_env "DO_GNOME_DEFAULTS"   "false"
  set_env "DO_TOOLS_CHECK"      "false"
  set_env "DO_ZOXIDE_CHECK"     "false"
  set_env "INSTALL_ZOXIDE"      "true"
  set_env "INSTALL_FNM"         "false"
  set_env "INSTALL_RUSTUP"      "false"
  set_env "INSTALL_UV"          "false"
  set_env "INSTALL_MISE"        "false"
  set_env "FNM_HOME"            "${HOME_DIR}/.local/share/fnm"
  set_env "UV_BIN_DIR"          "${HOME_DIR}/.local/bin"
  set_env "MISE_BIN"            "${HOME_DIR}/.local/bin/mise"
  set_env "FNM_INSTALL_URL"     "https://fnm.vercel.app/install"
  set_env "RUSTUP_INSTALL_URL"  "https://sh.rustup.rs"
  set_env "UV_INSTALL_URL"      "https://astral.sh/uv/install.sh"
  set_env "MISE_INSTALL_URL"    "https://mise.run"
  set_env "DO_ROLLBACK"         "false"
  set_env "DO_UNINSTALL"        "false"
  set_env "DOTFILES_DIR"        "${WORK_DIR}/dotfiles"
  set_env "DOTFILES_HOST"       "${HOST%%.*}"
  set_env "DOCTOR_MAX_BACKUPS"  "10"
  set_env "BREW_INSTALL_URL"    "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
  set_env "POSH_INSTALL_URL"    "https://ohmyposh.dev/install.sh"
  set_env "DEFAULTS_MAX_AGE"    "7"
  set_env "DO_SUDOERS_CHECK"    "false"
  set_env "DO_PKGCONFIG_CHECK"  "true"
  set_env "DO_CPPFLAGS_CHECK"   "true"
  set_env "DO_LDFLAGS_CHECK"    "true"
  set_env "ZSH_THEME"           "robbyrussell"
  set_env "PLUGIN_MANAGER"      "zinit"
  set_env "SHARE_HISTORY"       "true"
  set_env "DO_HISTORY"          "true"
  set_env "HISTORY_SIZE"        "50000"
  set_env "SUDOERS_ENTRY"       "ALL=(ALL) NOPASSWD:ALL"
  check_dir_exists              "${WORK_DIR}/files"
}

# Reset all defaults (when script is run inline i.e. as a login script with no options)

set_inline_defaults () {
  verbose_message               "Setting defaults"
  exp_env "PATH"                "/usr/local/bin"
  exp_env "PATH"                "/usr/local/sbin"
  if ! is_osx; then
    exp_env "LD_LIBRARY_PATH"   "/usr/local/lib"
  fi
  set_env "WORK_DIR"            "${HOME_DIR}/.${SCRIPT_NAME}"
  set_env "DO_HELP"             "false"
  set_env "DO_DRYRUN"           "false"
  set_env "DO_CONFIRM"          "false"
  set_env "DO_DEBUG"            "false"
  set_env "DO_BUILD"            "false"
  set_env "DO_PLUGINS"          "true"
  set_env "ZINIT_TURBO"         "true"
  ZINIT_SUFFIX=""
  if [ "${ZINIT_TURBO}" = "true" ]; then
    ZINIT_SUFFIX="-turbo"
  fi
  set_env "ZINIT_FILE"          "${WORK_DIR}/files/zinit/zinit${ZINIT_SUFFIX}.zsh"
  set_env "INSTALL_BREW"        "true"
  set_env "INSTALL_ZINIT"       "true"
  set_env "INSTALL_RBENV"       "true"
  set_env "INSTALL_PYENV"       "true"
  set_env "INSTALL_POSH"        "true"
  set_env "INSTALL_OZSH"        "false"
  set_env "INSTALL_FONTS"       "true"
  set_env "INSTALL_P10K"        "true"
  set_env "DO_DEFAULTS_CHECK"   "true"
  set_env "DO_PACKAGE_CHECK"    "false"
  set_env "DO_ZINIT_CHECK"      "true"
  set_env "DO_PYENV_CHECK"      "true"
  set_env "DO_RBENV_CHECK"      "true"
  set_env "DO_TOOLS_CHECK"      "true"
  set_env "DO_ZOXIDE_CHECK"     "true"
  set_env "DO_FONTS_CHECK"      "true"
  set_env "DO_POSH_CHECK"       "true"
  set_env "DO_ZOSH_CHECK"       "false"
  set_env "DO_P10K_CHECK"       "true"
  set_env "DO_ZSH_THEME"        "true"
  set_env "DO_VERBOSE"          "false"
  set_env "DO_DRYRUN"           "false"
  set_env "DO_CONFIRM"          "false"
  set_env "DO_DEBUG"            "false"
  set_env "DO_BUILD"            "false"
  set_env "DO_PLUGINS"          "true"
  set_env "DO_SUDOERS_CHECK"    "false"
  set_env "DO_PKGCONFIG_CHECK"  "true"
  set_env "DO_CPPFLAGS_CHECK"   "true"
  set_env "DO_LDFLAGS_CHECK"    "true"
  set_env "SUDOERS_ENTRY"       "ALL=(ALL) NOPASSWD:ALL"
}

# Copy the supporting files (package lists, zinit and p10k config) from next to the script
# into the work directory. Needs both to exist, otherwise tar would unpack in the wrong place

copy_support_files () {
  if is_read_only; then
    return
  fi
  if [ -n "${SCRIPT_DIR}" ] && [ ! "${SCRIPT_DIR}" = "/usr/bin" ] && [ -n "${WORK_DIR}" ]; then
    if [ -d "${SCRIPT_DIR}/files" ] && [ -d "${WORK_DIR}/files" ]; then
      execute_command "( cd ${(q)SCRIPT_DIR}/files && tar -cpf - . )|( cd ${(q)WORK_DIR}/files && tar -xpf - )" "run"
    fi
  fi
}

# Copy a single supporting file (relative to files/) if it is missing from the work directory
# and available next to the script. Unlike copy_support_files this never overwrites anything,
# so lists you have edited are left alone. Used when a new version adds a file to an install.

copy_support_file () {
  if is_read_only; then
    return
  fi
  if [ -n "${SCRIPT_DIR}" ] && [ ! "${SCRIPT_DIR}" = "/usr/bin" ] && [ -n "${WORK_DIR}" ]; then
    if [ -f "${SCRIPT_DIR}/files/$1" ] && [ ! -f "${WORK_DIR}/files/$1" ] && [ -d "${WORK_DIR}/files/${1:h}" ]; then
      execute_command "cp ${(q)SCRIPT_DIR}/files/${(q)1} ${(q)WORK_DIR}/files/${(q)1}"
    fi
  fi
}

# Check directory exists

check_dir_exists () {
  CHECK_DIR="$1"
  if [ ! -d "${CHECK_DIR}" ] && ! is_read_only; then
    execute_command "mkdir -p ${(q)CHECK_DIR}"
  fi
}

# Verbose message

verbose_message () {
  MESSAGE="$1"
  TYPE="$2"
  if [ "${DO_VERBOSE}" = "true" ]; then
    if [ "${TYPE}" = "" ]; then
      handle_output "${MESSAGE}" "info"
    else
      handle_output "${MESSAGE}" "${TYPE}"
    fi
  fi
}

# Read file into array and process

execute_from_file () {
  FILE="$1"
  for LINE in "${(@f)"$(<${FILE})"}"; do
    if [[ ! "${LINE}" =~ "^#" ]]; then
      if [[ "${LINE}" =~ "Finder" ]]; then
        set_env "RESTART_FINDER" "true" "force"
      fi
      if [[ "${LINE}" =~ "SystemUIServer" ]]; then
        set_env "RESTART_UISERVER" "true" "force"
      fi
      execute_command "${LINE}"
    fi
  done
}

# Priny help information

print_help () {
  set_defaults
  cat <<-HELP

  Usage: ${SCRIPT_FILE} [OPTIONS...]

  When run manually with switches:

    -h|--help         Print usage
    -V|--version      Print version
    -e|--changelog    Print changelog
    -A|--doall        Do all fuction (where set to true)
    -i|--inline       Set inline defaults when not runing inline mode
    -I|--install      Installs ${SCRIPT_NAME} as: ${HOME_DIR}/.zshrc
    -b|--build        Build sources       (default: ${DO_BUILD})
    -c|--confirm      Confirm commands    (default: ${DO_CONFIRM})
    -C|--check        Check for updates   (default: ${DO_VERSION_CHECK})
    -d|--debug        Enable debug        (default: ${DO_DEBUG})
    -D|--default(s)   Set defaults        (default: ${DO_DEFAULTS_CHECK})
    -f|--font(s)      Install font(s)     (default: ${DO_FONTS_CHECK})
    -F|--force        Force action        (default: ${DO_FORCE})
    -g|--gopath       Set GOPATH          (default: ${GO_HOME})
    -G|--drift        Report settings that differ from the defaults (read only)
    -k|--config       Create config file  (${CONFIG_FILE})
    -l|--location     Set start dir       (default: ${START_DIR})
    -B|--backups      List .zshrc backups
    -R|--rollback [N] Restore a backup    (default: newest)
    -X|--uninstall    Restore the .zshrc from before ussuri
    -L|--dotfiles     Link dotfiles       (default: ${DO_DOTFILES_CHECK})
    -M|--profile      Dotfiles profile    (default: ${DOTFILES_PROFILE:-none}, host: ${DOTFILES_HOST})
    -u|--unlink       Unlink dotfiles
    -m|--manager      Plugin manager      (default: ${PLUGIN_MANAGER})
    -n|--notheme      No zsh theme        (default: ${DO_ZSH_THEME})
    -N|--noenv        Ignore environment  (default: ${DO_ENV_SETUP})
    -o|--ohmyposh     Install oh my posh  (default: ${DO_POSH_CHECK})
    -O|--ohmyzsh      Install oh my zsh   (default: ${DO_ZOSH_CHECK})
    -p|--pyenv        Do pyenv check      (default: ${DO_PYENV_CHECK})
    -P|--package(s)   Do packages check   (default: ${DO_PACKAGE_CHECK})
    -r|--rbenv        Do rbenv check      (default: ${DO_RBENV_CHECK})
    -s|--sudoers      Do sudoers check    (default: ${DO_SUDOERS_CHECK})
    -S|--sudoersentry Set sudoers entry   (default: ${SUDOERS_ENTRY})
    -t|--dryrun       Dry run mode        (default: ${DO_DRYRUN})
    -T|--p10k         Do p10k config      (default: ${DO_P10K_CHECK})
    -U|--update       Update the script   (default: ${DO_UPDATE_CHECK})
    -v|--verbose      Verbose output      (default: ${DO_VERBOSE})
    -W|--tool NAME    Install a tool      (fnm, rustup, uv or mise)
    -x|--doctor       Check environment   (read only)
    -z|--zinit        Do zinit check      (default: ${DO_ZINIT_CHECK})
    -Z|--zshtheme     Set zsh theme       (default: ${ZSH_THEME})
HELP
SET_ENV_FORCE="true" set_inline_defaults
cat <<-INLINE

  Defaults when run inline (i.e. as login script):

    Do build mode         ${DO_BUILD}
    Do confirm mode       ${DO_CONFIRM}
    Do update check       ${DO_UPDATE_CHECK}
    Do debug mode         ${DO_DEBUG}
    Do defaults check:    ${DO_DEFAULTS_CHECK}
    Do fonts check:       ${DO_FONTS_CHECK}
    Do package check:     ${DO_PACKAGE_CHECK}
    Do zinit check:       ${DO_ZINIT_CHECK}
    Do pyenv check:       ${DO_PYENV_CHECK}
    Do rbenv check:       ${DO_RBENV_CHECK}
    Do p10k check         ${DO_P10K_CHECK}
    Do oh-my-posh check:  ${DO_POSH_CHECK}
    Do oh-my-zsh check:   ${DO_ZOSH_CHECK}
    Do verbose mode       ${DO_VERBOSE}
    Do sudoers check:     ${DO_SUDOERS_CHECK}
    Do PKGCONFIG check:   ${DO_PKGCONFIG_CHECK}
    Do CPPFLAGS check:    ${DO_CPPFLAGS_CHECK}
    Do LDFLAGS check:     ${DO_LDFLAGS_CHECK}
    Plugin Manager:       ${PLUGIN_MANAGER}
    Start Directory:      ${START_DIR}

INLINE
}

# Install script as .zshrc

do_install () {
  set_env "WORK_DIR"  "${HOME_DIR}/.${SCRIPT_NAME}"
  check_dir_exists    "${WORK_DIR}/files"
  backup_zshrc
  verbose_message     "${HOME_DIR}/.zshrc with ${SCRIPT_FILE}" "replace"
  execute_command     "cp ${(q)SCRIPT_FILE} ${(q)HOME_DIR}/.zshrc"
  if [ ! "${DO_INSTALL}" = "true" ]; then
    return
  fi
  if [ "${SCRIPT_FILE}" = "${HOME_DIR}/.zshrc" ] || [ "${SCRIPT_FILE}" = "${HOME_DIR}/.zprofile" ]; then
    return
  fi
  copy_support_files
  if [ -d "${WORK_DIR}/files" ] && [ ! -f "${P10K_INIT}" ] && [ -f "${SOURCE_P10K_INIT}" ]; then
    execute_command "cp ${(q)SOURCE_P10K_INIT} ${(q)P10K_INIT}"
  fi
}

# Print changelog

print_changelog () {
  CHANGE_FILE="${SCRIPT_DIR}/CHANGELOG.md"
  echo ""
  if [ -f "$CHANGE_FILE" ]; then
    cat "$CHANGE_FILE"
  else
    CHANGE_URL="https://raw.githubusercontent.com/lateralblast/ussuri/main/CHANGELOG.md"
    curl -fsSL "$CHANGE_URL" 2> /dev/null
  fi
  echo ""
}

# Set OS X file state

set_osx_file_state () {
  FILE="$1"
  STATE="$2"
  CHECK="${STATE}"
  verbose_message "File ${FILE} is ${STATE}" "check"
  if [ "${STATE}" = "nohidden" ]; then
    CHECK="-"
  fi
  CURRENT=$( ls -aOl "${FILE}" | sed -n 2p | awk '{print $5}' )
  if [ "${DO_DRIFT}" = "true" ]; then
    DRIFT_TOTAL=$(( DRIFT_TOTAL + 1 ))
    if [ ! "${CURRENT}" = "${CHECK}" ]; then
      report_drift "(file flags)" "${FILE}" "${${CURRENT:#-}:-nohidden}" "${STATE}"
    fi
    return
  fi
  if [ ! "${CURRENT}" = "$CHECK" ]; then
    verbose_message "File ${FILE} to ${STATE}" "set"
    execute_command "chflags ${STATE} ${(q)FILE}"
  fi
}

# Set OS X defaults

set_osx_default () {
  D_DOMAIN="$1"
  D_PARAM="$2"
  D_TYPE="$3"
  D_VALUE="$4"
  D_CHECK="${D_VALUE}"
  if [ "${D_VALUE}" = "true" ]; then
    D_CHECK="1"
  fi
  if [ "${D_VALUE}" = "false" ]; then
    D_CHECK="0"
  fi
  verbose_message "Defaults domain \"${D_DOMAIN}\" has parameter \"${D_PARAM}\" set to \"${D_VALUE}\"" "check"
  D_CURRENT=$( defaults read "${D_DOMAIN}" "${D_PARAM}" 2> /dev/null)
  D_STATUS=$?
  if [ "${DO_DRIFT}" = "true" ]; then
    DRIFT_TOTAL=$(( DRIFT_TOTAL + 1 ))
    if (( D_STATUS )) || [ ! "${D_CURRENT}" = "${D_CHECK}" ]; then
      D_SHOWN="${D_CURRENT}"
      if (( D_STATUS )); then
        D_SHOWN="(not set)"
      elif [ "${D_TYPE}" = "bool" ]; then
        D_SHOWN="${${D_CURRENT/#1/true}/#0/false}"
      fi
      report_drift "${D_DOMAIN}" "${D_PARAM}" "${D_SHOWN}" "${D_VALUE}"
    fi
    return
  fi
  if [ ! "${D_CURRENT}" = "${D_CHECK}" ]; then
    if [[ "${D_DOMAIN}" =~ "finder" ]]; then
      set_env "RESTART_FINDER" "true" "force"
    fi
    if [[ "${D_DOMAIN}" =~ "dock" ]]; then
      set_env "RESTART_DOCK" "true" "force"
    fi 
    verbose_message "Defaults domain \"${D_DOMAIN}\" parameter \"${D_PARAM}\" to \"${D_VALUE}\"" "set"
    execute_command "defaults write ${(q)D_DOMAIN} ${(q)D_PARAM} -${D_TYPE} ${(q)D_VALUE}"
  fi
}

# Set environment variable if hasn't been set
# Doing it this was allows a manul override at the top of the script for some variables
# and lets command line switches take precedence over defaults
# Pass "force" as the third argument (or set SET_ENV_FORCE=true) to override an existing value

set_env () {
  PARAM="$1"
  VALUE="$2"
  OVERRIDE="$3"
  if [ ! "${PARAM}" = "" ]; then
    if [ "${OVERRIDE}" = "force" ] || [ "${SET_ENV_FORCE}" = "true" ] || [ -z "${(P)PARAM}" ]; then
      verbose_message "Environment parameter \"${PARAM}\" to \"${VALUE}\"" "set"
      # Only export what child processes need, otherwise a login shell leaks
      # its DO_* flags into manual runs and nested shells, which then inherit them
      case "${PARAM}" in
        GOPATH)
          typeset -gx "${PARAM}=${VALUE}"
          ;;
        *)
          typeset -g "${PARAM}=${VALUE}"
          ;;
      esac
    fi
  fi
}

# Expand environment variable

exp_env () {
  PARAM="$1"
  VALUE="$2"
  # PATH is tied to the path array, so use it rather than splitting strings
  if [ "${PARAM}" = "PATH" ]; then
    if (( ! ${path[(Ie)${VALUE}]} )); then
      handle_output "${VALUE} to ${PARAM}" "add"
      path+=( "${VALUE}" )
    fi
    return
  fi
  CURRENT="${(P)PARAM}"
  case "${PARAM}" in
    LDFLAGS)
      ITEM="-L ${VALUE}"
      SEP=" "
      ;;
    CPPFLAGS)
      ITEM="-I ${VALUE}"
      SEP=" "
      ;;
    *)
      ITEM="${VALUE}"
      SEP=":"
      ;;
  esac
  # Match whole entries only, so /usr/lib isn't "found" inside /usr/local/lib
  if [[ "${SEP}${CURRENT}${SEP}" != *"${SEP}${ITEM}${SEP}"* ]]; then
    handle_output "${VALUE} to ${PARAM}" "add"
    if [ -z "${CURRENT}" ]; then
      typeset -gx "${PARAM}=${ITEM}"
    else
      typeset -gx "${PARAM}=${CURRENT}${SEP}${ITEM}"
    fi
  fi
}

# Check sudoers config

check_sudoers_config () {
  verbose_message "Checking sudoers"
  SUDO_VALUE=$( echo "${SUDOERS_ENTRY}" |cut -f2 -d= |cut -f1 -d: )
  SUDO_FILE="/etc/sudoers.d/${MY_USERNAME}"
  SUDO_LINE="${MY_USERNAME} ${SUDOERS_ENTRY}"
  # Try without a password first so a check doesn't prompt unless a change is needed
  SUDO_CHECK=$( sudo -n -l 2> /dev/null | grep -Fc "${SUDO_VALUE}" )
  if [ "${SUDO_CHECK}" = "0" ]; then
    notice_message "Updating ${SUDO_FILE} (sudo may ask for your password)"
    # Validate with visudo before installing, and install 0440 as sudo requires,
    # so a bad entry can't break sudo
    execute_command "SUDO_TMP=\$( mktemp ) && print -r -- ${(q)SUDO_LINE} > \"\${SUDO_TMP}\" && sudo visudo -cf \"\${SUDO_TMP}\" && sudo install -m 0440 \"\${SUDO_TMP}\" ${(q)SUDO_FILE} ; rm -f \"\${SUDO_TMP}\"" "show"
  fi
}

# Check zinit config

check_zinit_config () {
  if [ "${INSTALL_ZINIT}" = "true" ]; then
    verbose_message "Configuring zinit"
    if [ ! -d "${ZINIT_HOME}" ]; then
      execute_command "git_clone https://github.com/zdharma-continuum/zinit.git ${(q)ZINIT_HOME} ${(q)ZINIT_REF}"
    fi
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      execute_command ". ${(q)ZINIT_HOME}/zinit.zsh"
    fi
    if [ "${PLUGIN_MANAGER}" = "zinit" ]; then
      # An install from before turbo mode doesn't have the turbo list yet: copy just that file
      # if the repo is next to the script, otherwise use the original list
      if [ ! -f "${ZINIT_FILE}" ] && have_lock; then
        copy_support_file "zinit/${ZINIT_FILE:t}"
      fi
      if [ ! -f "${ZINIT_FILE}" ] && [ "${ZINIT_TURBO}" = "true" ]; then
        verbose_message "${ZINIT_FILE} is missing, using the original plugin list (run --install again to add it)" "warn"
        ZINIT_FILE="${WORK_DIR}/files/zinit/zinit.zsh"
      fi
      if [ -f "${ZINIT_FILE}" ]; then
        execute_from_file "${ZINIT_FILE}"
      fi
    fi
  fi
}

# Check rbenv

check_rbenv_config () {
  if [ "$INSTALL_RBENV" = "true" ]; then
    verbose_message "Configuring rbenv"
    if [ ! -d "${RBENV_HOME}" ]; then
      verbose_message "Installing rbenv"
      execute_command "git_clone https://github.com/rbenv/rbenv.git ${(q)RBENV_HOME} ${(q)RBENV_REF}"
      verbose_message "Installing rbenv ruby-build plugin"
      execute_command "git_clone https://github.com/rbenv/ruby-build.git ${(q)RBENV_HOME}/plugins/ruby-build ${(q)RUBY_BUILD_REF}"
    fi
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      verbose_message "Configuring rbenv environment"
      execute_command "export RBENV_ROOT=${(q)RBENV_HOME}"
      execute_command "export PATH=${(q)RBENV_HOME}/bin:${(q)PATH}"
      execute_command "cached_eval ${(q)RBENV_HOME}/bin/rbenv \"rbenv init - zsh\" \"command rbenv rehash*\""
      # Only look up the latest version when building, listing versions on every login is slow
      if [ "${RUBY_VER}" = "" ] && [ "${DO_BUILD}" = "true" ]; then
        RUBY_VER=$( rbenv install --list 2> /dev/null | awk '{ print $1 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 )
      fi
      if [ -n "${RUBY_VER}" ]; then
        if [ "${DO_BUILD}" = "true" ] && [ ! -d "${RBENV_HOME}/versions/${RUBY_VER}" ]; then
          notice_message "Installing ruby version ${RUBY_VER} (this can take a while)"
          execute_command "rbenv install ${(q)RUBY_VER}" "show"
        fi
        # Only set a version that is installed. Don't use "rbenv local", it writes
        # .ruby-version into whatever directory the shell happens to start in
        if [ -d "${RBENV_HOME}/versions/${RUBY_VER}" ]; then
          RBENV_GLOBAL=$( rbenv global 2> /dev/null )
          if [ ! "${RBENV_GLOBAL}" = "${RUBY_VER}" ]; then
            verbose_message "Setting ruby global version to ${RUBY_VER}"
            execute_command "rbenv global ${(q)RUBY_VER}"
          fi
        fi
      fi
    fi
  fi
}

# Check pyenv

check_pyenv_config () {
  if [ "${INSTALL_PYENV}" = "true" ]; then
    verbose_message "Configuring pyenv"
    if [ ! -d "${PYENV_HOME}" ]; then
      verbose_message "Installing pyenv"
      execute_command "git_clone https://github.com/pyenv/pyenv.git ${(q)PYENV_HOME} ${(q)PYENV_REF}"
    fi
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      verbose_message "Configuring pyenv environment"
      execute_command "export PYENV_ROOT=${(q)PYENV_HOME}"
      execute_command "export PATH=${(q)PYENV_HOME}/bin:${(q)PATH}"
      CACHE_BLOCK_START='PATH="$(bash --norc'
      CACHE_BLOCK_END="')\""
      execute_command "cached_eval ${(q)PYENV_HOME}/bin/pyenv \"pyenv init -\" \"command pyenv rehash*\""
      CACHE_BLOCK_START=""
      CACHE_BLOCK_END=""
      # Only look up the latest version when building, listing versions on every login is slow
      if [ "${PYTHON_VER}" = "" ] && [ "${DO_BUILD}" = "true" ]; then
        PYTHON_VER=$( pyenv install --list 2> /dev/null | awk '{ print $1 }' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1 )
      fi
      if [ -n "${PYTHON_VER}" ]; then
        if [ "${DO_BUILD}" = "true" ] && [ ! -d "${PYENV_HOME}/versions/${PYTHON_VER}" ]; then
          notice_message "Installing python version ${PYTHON_VER} (this can take a while)"
          execute_command "pyenv install ${(q)PYTHON_VER}" "show"
        fi
        # Only set a version that is installed. Don't use "pyenv local", it writes
        # .python-version into whatever directory the shell happens to start in
        if [ -d "${PYENV_HOME}/versions/${PYTHON_VER}" ]; then
          PYENV_GLOBAL=$( pyenv global 2> /dev/null )
          if [ ! "${PYENV_GLOBAL}" = "${PYTHON_VER}" ]; then
            verbose_message "Setting python global version to ${PYTHON_VER}"
            execute_command "pyenv global ${(q)PYTHON_VER}"
          fi
        fi
      fi
    fi
  fi
}

# Language and tool managers other than rbenv and pyenv: fnm (Node), rustup (Rust), uv (Python)
# and mise (many languages, and a replacement for the others). Each is off unless INSTALL_<NAME>=true
# (for example in the config) or it is asked for with --tool NAME. Versions are only installed when
# building (--tool or --build), never on an ordinary login.

check_fnm_config () {
  verbose_message "Configuring fnm"
  if [ ! -x "${FNM_HOME}/fnm" ] && (( ! $+commands[fnm] )) && have_lock; then
    notice_message "Installing fnm"
    execute_command "fetch_and_run ${(q)FNM_INSTALL_URL} ${(q)FNM_INSTALL_SHA256} --install-dir ${(q)FNM_HOME} --skip-shell" "show"
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    if [ -d "${FNM_HOME}" ]; then
      execute_command "export PATH=${(q)FNM_HOME}:${(q)PATH}"
    fi
    # fnm env points at a directory made for each shell, so unlike the others it can't be cached
    execute_command "eval \"\$(fnm env --use-on-cd --shell zsh)\""
    if [ -n "${FNM_NODE}" ] && [ "${DO_BUILD}" = "true" ]; then
      execute_command "fnm install ${(q)FNM_NODE}" "show"
      execute_command "fnm default ${(q)FNM_NODE}"
    fi
  fi
}

check_rustup_config () {
  verbose_message "Configuring rustup"
  RUSTUP_BIN_DIR="${CARGO_HOME:-${HOME_DIR}/.cargo}/bin"
  if [ ! -x "${RUSTUP_BIN_DIR}/rustup" ] && (( ! $+commands[rustup] )) && have_lock; then
    notice_message "Installing rustup"
    execute_command "fetch_and_run ${(q)RUSTUP_INSTALL_URL} ${(q)RUSTUP_INSTALL_SHA256} -y --no-modify-path" "show"
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    if [ -d "${RUSTUP_BIN_DIR}" ]; then
      execute_command "export PATH=${(q)RUSTUP_BIN_DIR}:${(q)PATH}"
    fi
    if [ -n "${RUSTUP_TOOLCHAIN_WANTED}" ] && [ "${DO_BUILD}" = "true" ]; then
      execute_command "rustup toolchain install ${(q)RUSTUP_TOOLCHAIN_WANTED}" "show"
      execute_command "rustup default ${(q)RUSTUP_TOOLCHAIN_WANTED}"
    fi
  fi
}

check_uv_config () {
  verbose_message "Configuring uv"
  if [ ! -x "${UV_BIN_DIR}/uv" ] && (( ! $+commands[uv] )) && have_lock; then
    notice_message "Installing uv"
    execute_command "UV_NO_MODIFY_PATH=1 UV_INSTALL_DIR=${(q)UV_BIN_DIR} fetch_and_run ${(q)UV_INSTALL_URL} ${(q)UV_INSTALL_SHA256}" "show"
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    if [ -d "${UV_BIN_DIR}" ]; then
      execute_command "export PATH=${(q)UV_BIN_DIR}:${(q)PATH}"
    fi
    if [ -n "${UV_PYTHON}" ] && [ "${DO_BUILD}" = "true" ]; then
      execute_command "uv python install ${(q)UV_PYTHON}" "show"
    fi
  fi
}

check_mise_config () {
  verbose_message "Configuring mise"
  if [ ! -x "${MISE_BIN}" ] && (( ! $+commands[mise] )) && have_lock; then
    notice_message "Installing mise"
    execute_command "MISE_INSTALL_PATH=${(q)MISE_BIN} fetch_and_run ${(q)MISE_INSTALL_URL} ${(q)MISE_INSTALL_SHA256}" "show"
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    if [ -x "${MISE_BIN}" ]; then
      execute_command "export PATH=${(q)MISE_BIN:h}:${(q)PATH}"
      execute_command "cached_eval ${(q)MISE_BIN} \"${(q)MISE_BIN} activate zsh\""
    fi
    if [ -n "${MISE_TOOLS}" ] && [ "${DO_BUILD}" = "true" ]; then
      execute_command "mise use --global ${(j: :)${(q)${=MISE_TOOLS}}}" "show"
    fi
  fi
}

# zoxide: a smarter cd (z and zi). It is installed by the package lists (-P), not here, so a login
# never downloads anything: this only sets it up when it is already installed. Its init output is
# the same every time, so it goes through the cache. Its completions are registered only if compdef
# exists when it loads, so this must run after the plugin lists (which is where compdef comes from)

check_zoxide_config () {
  [ "${INSTALL_ZOXIDE}" = "true" ] || return
  verbose_message "Configuring zoxide"
  if (( ! $+commands[zoxide] )); then
    verbose_message "zoxide is not installed (it is in the package lists, -P installs the packages)"
    return
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    execute_command "cached_eval ${(q)commands[zoxide]} \"${(q)commands[zoxide]} init zsh\""
  fi
}

# Register zoxide's completion for z. zoxide registers it itself, but only if compdef exists when
# it is set up, and in turbo mode that is before compinit has run (compdef comes with it). So the
# turbo plugin list calls this right after compinit. Does nothing if zoxide isn't set up or
# compdef still isn't there

register_zoxide_completion () {
  if (( $+functions[__zoxide_z_complete] && $+functions[compdef] )); then
    compdef __zoxide_z_complete z
  fi
  return 0
}

check_tools_config () {
  if [ "${INSTALL_FNM}" = "true" ]; then
    check_fnm_config
  fi
  if [ "${INSTALL_RUSTUP}" = "true" ]; then
    check_rustup_config
  fi
  if [ "${INSTALL_UV}" = "true" ]; then
    check_uv_config
  fi
  if [ "${INSTALL_MISE}" = "true" ]; then
    check_mise_config
  fi
}

# Check fonts config

check_fonts_config () {
  if [ "${INSTALL_FONTS}" = "true" ] && have_lock; then
    verbose_message "Configuring fonts"
    if is_osx; then
      check_osx_package "font-fira-code-nerd-font" "cask"
    else
      if is_linux; then
        if [ ! -d "${WORK_DIR}/nerd-fonts" ]; then
          notice_message "Installing nerd fonts (this can take a while)"
          execute_command "git_clone https://github.com/ryanoasis/nerd-fonts.git ${(q)WORK_DIR}/nerd-fonts ${(q)NERD_FONTS_REF} 1" "show"
          execute_command "( cd ${(q)WORK_DIR}/nerd-fonts && ./install.sh )" "show"
        fi
      fi
    fi
  fi
}

# Check oh-my-posh config

check_posh_config () {
  if [ "${INSTALL_POSH}" = "true" ]; then
    verbose_message "Configuring oh-my-posh"
    if [ ! -d "${POSH_HOME}" ] && have_lock; then
      notice_message    "Installing oh-my-posh"
      check_dir_exists  "${POSH_HOME}"
      execute_command   "fetch_and_run ${(q)POSH_INSTALL_URL} ${(q)POSH_INSTALL_SHA256} -d ${(q)POSH_HOME}" "show"
    fi
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      verbose_message   "Configuring oh-my-posh environment"
      execute_command   "export PATH=${(q)POSH_HOME}:${(q)PATH}"
      execute_command   "eval \"\$(oh-my-posh init zsh)\""
    fi
  fi
}

# Check oh-my-zsh config

check_zosh_config () {
  if [ "${INSTALL_OZSH}" = "true" ]; then
    verbose_message "Configuring oh-my-zsh"
    if [ ! -d "${ZOSH_HOME}" ] && have_lock; then
      verbose_message "Installing oh-my-zsh"
      execute_command "git_clone https://github.com/ohmyzsh/ohmyzsh.git ${(q)ZOSH_HOME} ${(q)ZOSH_REF}"
    fi
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      verbose_message "Configuring oh-my-zsh environment"
      execute_command "source ${(q)ZOSH_HOME}/oh-my-zsh.sh"
    fi
    if [ "${PLUGIN_MANAGER}" = "oh-my-zsh" ]; then
      plugins=( git ansible aliases brew common-aliases copyfile copypath \
                debian docker docker-compose docker-machine ubuntu ufw \
                systemd sudo ssh-agent screen ruby rsync python pip perl \
                macos history )
    fi
  fi
}

# Check Powerlevel10k config

check_p10k_config () {
  if [ "${INSTALL_P10K}" = "true" ]; then
    verbose_message "Configuring p10k"
    if [ "${INSTALL_ZINIT}" = "false" ]; then
      if [ ! -d "${P10K_HOME}" ]; then
        verbose_message "Installing p10k"
        execute_command "git_clone https://github.com/romkatv/powerlevel10k.git ${(q)P10K_HOME} ${(q)P10K_REF} 1"
      fi
      if [ "${DO_ENV_SETUP}" = "true" ]; then
        verbose_message "Configuring p10k environment"
        execute_command "typeset -g POWERLEVEL9K_INSTANT_PROMPT=off"
        if [ "${INSTALL_ZINIT}" = "false" ]; then
          if [ ! -f "${P10K_INIT}" ]; then
            if [ -f "${SOURCE_P10K_INIT}" ]; then
              execute_command "cp ${(q)SOURCE_P10K_INIT} ${(q)P10K_INIT}"
            else
              execute_command "p10k configure"
            fi
          fi
          execute_command "source ${(q)P10K_INIT}"
          if [ -f "${P10K_THEME}" ]; then
            execute_command "source ${(q)P10K_THEME}"
          fi
        fi
      fi
    else
      if [ ! -f "${P10K_INIT}" ] && have_lock; then
        if [ -f "${SOURCE_P10K_INIT}" ]; then
          execute_command "cp ${(q)SOURCE_P10K_INIT} ${(q)P10K_INIT}"
        else
          execute_command "p10k configure"
        fi
      fi
      execute_command "source ${(q)P10K_INIT}"
      if [ -f "${P10K_THEME}" ]; then
        execute_command "source ${(q)P10K_THEME}"
      fi
    fi
  fi
}

# Set Linux defaults

set_linux_defaults () {
  if [ -n "${PKG_MANAGER}" ]; then
    set_pkg_manager
    set_env "REQUIRED_FILE"  "${WORK_DIR}/files/packages/${PKG_LIST_NAME}"
    set_env "INSTALL_PKG"    "true"
    set_env "INSTALLED_FILE" "${WORK_DIR}/${PKG_MANAGER}.list"
  fi
  if [ "${DO_INSTALL}" = "false" ]; then
    if [ -n "${REQUIRED_FILE}" ] && [ ! -f "${REQUIRED_FILE}" ] && have_lock; then
      copy_support_files
    fi
  fi
}

# Update package list

write_installed_list () {
  if is_osx; then
    execute_command "brew list 2> /dev/null | sort > ${(q)INSTALLED_FILE}"
  else
    if is_linux && [ -n "${PKG_LIST_CMD}" ]; then
      execute_command "${PKG_LIST_CMD} > ${(q)INSTALLED_FILE}"
    fi
  fi
}

# Installed package lookups are done in the shell against an array loaded once,
# rather than forking grep for every package

load_installed_list () {
  INSTALLED_LIST=()
  if [ -f "${INSTALLED_FILE}" ]; then
    INSTALLED_LIST=( ${(f)"$(<${INSTALLED_FILE})"} )
  fi
  INSTALLED_LOADED="true"
}

# Compares the short name, as brew list doesn't include the tap prefix

package_installed () {
  if [ ! "${INSTALLED_LOADED}" = "true" ]; then
    load_installed_list
  fi
  (( ${INSTALLED_LIST[(Ie)${1:t}]} ))
}

update_package_list () {
  if have_lock; then
    # (Nm+2) matches a list last modified more than 2 days ago
    INSTALLED_OLD=( ${INSTALLED_FILE}(Nm+2) )
    if [ ! -f "${INSTALLED_FILE}" ] || (( ${#INSTALLED_OLD} )) || [ "${DO_UPDATE_LIST}" = "true" ]; then
      write_installed_list
      DO_UPDATE_LIST="false"
      INSTALLED_LOADED="false"
    fi
  fi
}

# Package list change detection
# Manual runs (-P/-A) always process the list, login runs only when the list has changed
# (a checksum is used rather than file age so a copied file with an old mtime isn't missed)

package_list_changed () {
  PACKAGE_STAMP="${WORK_DIR}/${REQUIRED_FILE:t}.sum"
  PACKAGE_SUM=$( cksum < "${REQUIRED_FILE}" 2> /dev/null )
  PACKAGE_OLD=""
  if [ -f "${PACKAGE_STAMP}" ]; then
    PACKAGE_OLD=$(<"${PACKAGE_STAMP}")
  fi
  if [ "${PACKAGE_EXPLICIT}" = "true" ] || [ "${DO_FORCE}" = "true" ] || [ ! "${PACKAGE_SUM}" = "${PACKAGE_OLD}" ]; then
    return 0
  fi
  return 1
}

all_packages_installed () {
  for PACKAGE in "${REQUIRED_LIST[@]}"; do
    package_installed "${PACKAGE}" || return 1
  done
  return 0
}

# Process the required package list using the given per package check function
# The stamp is only saved once everything is installed so failed installs are retried

process_package_list () {
  CHECK_FUNCTION="$1"
  if [ -f "${REQUIRED_FILE}" ] && package_list_changed; then
    read_required_list
    update_package_list
    for PACKAGE in "${REQUIRED_LIST[@]}"; do
      ${CHECK_FUNCTION} "${PACKAGE}" ""
    done
    update_package_list
    if all_packages_installed; then
      execute_command "echo ${(q)PACKAGE_SUM} > ${(q)PACKAGE_STAMP}"
    fi
  fi
}

# Check Linux Defaults

check_linux_defaults () {
  have_lock || return
  # Unlike on OS X these are not applied on every login unless asked for (--defaults, or DO_GNOME_DEFAULTS=true)
  if [ ! "${DEFAULTS_EXPLICIT}" = "true" ] && [ ! "${DO_GNOME_DEFAULTS}" = "true" ]; then
    return
  fi
  if ! linux_defaults_available; then
    verbose_message "No desktop session (gsettings and a session bus are needed), skipping GNOME settings"
    return
  fi
  verbose_message "Configuring GNOME settings"
  if defaults_due; then
    apply_linux_defaults
    execute_command "touch ${(q)DEFAULTS_STAMP}"
  else
    verbose_message "GNOME settings are up to date (use --defaults to reapply)"
  fi
}

# Check OS Defaults

defaults_due () {
  DEFAULTS_STAMP="${WORK_DIR}/defaults.stamp"
  DEFAULTS_OLD=( ${DEFAULTS_STAMP}(Nm+${DEFAULTS_MAX_AGE}) )
  [ "${DEFAULTS_EXPLICIT}" = "true" ] || [ "${DO_FORCE}" = "true" ] || [ ! -f "${DEFAULTS_STAMP}" ] || [ "${SCRIPT_FILE}" -nt "${DEFAULTS_STAMP}" ] || (( ${#DEFAULTS_OLD} ))
}

check_osx_defaults () {
  have_lock || return
  verbose_message "Configuring OS X defaults"
  # Applying defaults reads every setting with a separate defaults process (about a hundred),
  # so only do it when asked (-D/-A/--force), when this script has changed since the last
  # time, or when the last time was more than DEFAULTS_MAX_AGE days ago
  if defaults_due; then
    apply_osx_defaults
    execute_command "touch ${(q)DEFAULTS_STAMP}"
  else
    verbose_message "OS X defaults are up to date (use --defaults to reapply)"
  fi
  if [ "${RESTART_FINDER}" = "true" ]; then
    verbose_message "Finder" "restart"
    execute_command "killall Finder"
  fi
  if [ "${RESTART_UISERVER}" = "true" ]; then
    verbose_message "SystemUIServer" "restart"
    execute_command "killall SystemUIServer"
  fi
  if [ "${RESTART_DOCK}" = "true" ]; then
    verbose_message "Dock" "restart"
    execute_command "killall Dock"
  fi
}

# Check Linux Package

check_linux_package () {
  PACKAGE="$1"
  have_lock || return
  verbose_message "Configuring Linux package \"${PACKAGE}\""
  is_linux || return
  [ "${INSTALL_PKG}" = "true" ] || return
  [ -n "${PKG_INSTALL}" ] || return
  package_installed "${PACKAGE}" && return
  if [ -n "${PKG_PREPARE}" ] && [ ! "${PKG_PREPARED}" = "true" ]; then
    notice_message "Refreshing the ${PKG_MANAGER} package index"
    execute_command "${PKG_SUDO}${PKG_PREPARE}" "show"
    PKG_PREPARED="true"
  fi
  notice_message "Installing package ${PACKAGE}"
  execute_command "${PKG_SUDO}${PKG_INSTALL} ${(q)PKG_REF_PREFIX}${(q)PACKAGE}" "show"
  DO_UPDATE_LIST="true"
}

# Check OSX Package

check_osx_package () {
  PACKAGE="$1"
  TYPE="$2"
  have_lock || return
  verbose_message "Configuring OS X package \"${PACKAGE}\""
  [ "${INSTALL_BREW}" = "true" ] || return
  if [ ! -f "${INSTALLED_FILE}" ]; then
    update_package_list
  fi
  package_installed "${PACKAGE}" && return
  notice_message "Installing package ${PACKAGE}"
  if [ "${TYPE}" = "cask" ]; then
    execute_command "brew install --cask ${(q)PACKAGE}" "show"
  else
    execute_command "brew install ${(q)PACKAGE}" "show"
  fi
  DO_UPDATE_LIST="true"
}

# Check Linux Applications

check_linux_packages () {
  have_lock || return
  [ "${INSTALL_PKG}" = "true" ] || return
  process_package_list "check_linux_package"
}

# Find the brew binary and its prefix

find_brew () {
  BREW_BIN=""
  BREW_BASE=""
  for BREW_FILE in /opt/homebrew/bin/brew /usr/local/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -x "${BREW_FILE}" ]; then
      BREW_BIN="${BREW_FILE}"
      BREW_BASE="${BREW_BIN:h:h}"
      break
    fi
  done
}

# Setup brew environment

setup_brew_env () {
  find_brew
  if [ -n "${BREW_BIN}" ]; then
    execute_command "export PATH=${(q)BREW_BASE}/bin:${(q)BREW_BASE}/sbin:${(q)PATH}"
    if [ "${DO_ENV_SETUP}" = "true" ]; then
      verbose_message "Configuring brew environment"
      execute_command "cached_eval ${(q)BREW_BIN} \"${(q)BREW_BIN} shellenv\""
    fi
  fi
}

# Check OSX Applications

check_osx_packages () {
  if [ "${INSTALL_BREW}" = "true" ] && have_lock; then
    verbose_message "Configuring brew"
    BREW_TEST="${commands[brew]}"
    if [ -z "${BREW_TEST}" ]; then
      find_brew
      if [ -z "${BREW_BIN}" ]; then
        notice_message "Installing Homebrew"
        execute_command "fetch_and_run ${(q)BREW_INSTALL_URL} ${(q)BREW_INSTALL_SHA256}" "show"
      fi
      setup_brew_env
    else
      if [ "${DO_ENV_SETUP}" = "true" ]; then
        verbose_message "Configuring brew environment"
        execute_command "cached_eval ${(q)BREW_TEST} \"${(q)BREW_TEST} shellenv\""
      fi
    fi
    process_package_list "check_osx_package"
  else
    setup_brew_env
  fi
}

# Fetch a URL to stdout using curl or wget

fetch_url () {
  if (( $+commands[curl] )); then
    curl -fsSL "$1" 2> /dev/null
  else
    if (( $+commands[wget] )); then
      wget -qO- "$1" 2> /dev/null
    else
      handle_output "Neither curl nor wget found, cannot check for updates" "warn"
      return 1
    fi
  fi
}

# Compare local and remote versions
# Sets REMOTE_VERSION and VERSION_STATE (older, newer, same or unknown)
# Compared by stripping the dots, which only works while each component is a single digit

compare_versions () {
  REMOTE_URL="$1"
  REMOTE_PATTERN="$2"
  VERSION_STATE="unknown"
  REMOTE_VERSION=$( fetch_url "${REMOTE_URL}" | grep -m1 "${REMOTE_PATTERN}" | awk '{ print $3 }' )
  echo "Local version:  ${SCRIPT_VERSION}"
  echo "Remote version: ${REMOTE_VERSION}"
  if [[ ! "${REMOTE_VERSION}" =~ ^[0-9]\.[0-9]\.[0-9]$ ]]; then
    handle_output "Could not determine the remote version" "warn"
    return 1
  fi
  LOCAL_VERSION="${SCRIPT_VERSION//./}"
  REMOTE_NUMBER="${REMOTE_VERSION//./}"
  if [ "${LOCAL_VERSION}" -lt "${REMOTE_NUMBER}" ]; then
    VERSION_STATE="older"
    handle_output "Local version is older than remote version" "info"
  else
    if [ "${LOCAL_VERSION}" -gt "${REMOTE_NUMBER}" ]; then
      VERSION_STATE="newer"
      handle_output "Local version is newer than remote version" "info"
    else
      VERSION_STATE="same"
      handle_output "Local version is the same as remote version" "info"
    fi
  fi
}

# Check for update

check_for_update () {
  if have_lock; then
    verbose_message "Checking for updates"
    set_env "README_URL" "https://raw.githubusercontent.com/lateralblast/ussuri/main/README.md"
    compare_versions "${README_URL}" "^Current Version"
  fi
}

# Update script
# Downloads the new version, checks it parses and is the version expected, backs up the
# current script and then replaces it (the replace goes through execute_command so
# --dryrun and --confirm are honoured)

update_script () {
  if have_lock; then
    verbose_message "Checking for updates"
    set_env "SCRIPT_URL" "https://raw.githubusercontent.com/lateralblast/ussuri/refs/heads/main/ussuri.zsh"
    compare_versions "${SCRIPT_URL}" "^# Version"
    if [ "${VERSION_STATE}" = "older" ]; then
      UPDATE_TMP=$( mktemp )
      fetch_url "${SCRIPT_URL}" > "${UPDATE_TMP}"
      if zsh -n "${UPDATE_TMP}" 2> /dev/null && grep -q "^# Version: ${REMOTE_VERSION}$" "${UPDATE_TMP}"; then
        verbose_message "${SCRIPT_FILE} to version ${REMOTE_VERSION}" "replace"
        check_dir_exists "${WORK_DIR}"
        execute_command "cp ${(q)SCRIPT_FILE} ${(q)WORK_DIR}/${SCRIPT_NAME}.zsh.${DATE_SUFFIX} && cp ${(q)UPDATE_TMP} ${(q)SCRIPT_FILE}.new && mv ${(q)SCRIPT_FILE}.new ${(q)SCRIPT_FILE}"
      else
        handle_output "Downloaded script failed validation, not updating" "warn"
      fi
      rm -f "${UPDATE_TMP}"
    fi
  fi
}

# Dotfiles: symlinks from the home directory into ~/.ussuri/dotfiles, in layers so one set of
# dotfiles can differ per machine. Later layers win for the same path:
#
#   dotfiles/common/.gitconfig                 every machine
#   dotfiles/profiles/<name>/.gitconfig        machines using that profile (--profile or DOTFILES_PROFILE)
#   dotfiles/hosts/<hostname>/.gitconfig       just that machine (DOTFILES_HOST, the short hostname)
#
# A file at <layer>/.config/app/conf is linked as ~/.config/app/conf. Anything that would be
# replaced is moved to ~/.ussuri/dotfile-backups/<date>/ first, never deleted.

dotfiles_layers () {
  DOT_LAYERS=( "${DOTFILES_DIR}/common" )
  if [ -n "${DOTFILES_PROFILE}" ]; then
    DOT_LAYERS+=( "${DOTFILES_DIR}/profiles/${DOTFILES_PROFILE}" )
  fi
  DOT_LAYERS+=( "${DOTFILES_DIR}/hosts/${DOTFILES_HOST}" )
}

# Build DOT_MAP: path relative to the home directory -> the file it should link to

dotfiles_map () {
  typeset -gA DOT_MAP
  DOT_MAP=()
  dotfiles_layers
  for DOT_LAYER in "${DOT_LAYERS[@]}"; do
    if [ -d "${DOT_LAYER}" ]; then
      for DOT_FILE in ${DOT_LAYER}/**/*(DN^/); do
        if [[ "${DOT_FILE:t}" != (.DS_Store|.gitkeep) ]]; then
          DOT_MAP[${DOT_FILE#${DOT_LAYER}/}]="${DOT_FILE}"
        fi
      done
    fi
  done
}

# Work out what is at a target: ok (already the right link), missing, wrong (a link to
# somewhere else, or a broken one) or conflict (a real file or directory in the way)

dotfile_state () {
  DOT_STATE="missing"
  if [ -L "$1" ]; then
    zmodload -F zsh/stat b:zstat 2> /dev/null
    zstat -A DOT_LINK +link -- "$1"
    if [ "${DOT_LINK[1]}" = "$2" ]; then
      DOT_STATE="ok"
    else
      DOT_STATE="wrong"
    fi
  elif [ -e "$1" ]; then
    DOT_STATE="conflict"
  fi
}

check_dotfiles_config () {
  dotfiles_map
  if (( ! ${#DOT_MAP} )); then
    verbose_message "No dotfiles to link in ${DOTFILES_DIR}"
    return
  fi
  verbose_message "Configuring dotfiles from ${DOTFILES_DIR} (profile: ${DOTFILES_PROFILE:-none}, host: ${DOTFILES_HOST})"
  DOT_BACKUP="${WORK_DIR}/dotfile-backups/${DATE_SUFFIX}"
  DOT_LINKED=0
  DOT_BACKED_UP=0
  for DOT_REL in ${(ko)DOT_MAP}; do
    DOT_SOURCE="${DOT_MAP[${DOT_REL}]}"
    DOT_TARGET="${HOME_DIR}/${DOT_REL}"
    dotfile_state "${DOT_TARGET}" "${DOT_SOURCE}"
    if [ "${DOT_STATE}" = "ok" ]; then
      continue
    fi
    check_dir_exists "${DOT_TARGET:h}"
    if [ ! "${DOT_STATE}" = "missing" ]; then
      check_dir_exists "${DOT_BACKUP}/${DOT_REL:h}"
      verbose_message "${DOT_TARGET} to ${DOT_BACKUP}/${DOT_REL}" "save"
      execute_command "mv ${(q)DOT_TARGET} ${(q)DOT_BACKUP}/${(q)DOT_REL}"
      DOT_BACKED_UP=$(( DOT_BACKED_UP + 1 ))
    fi
    verbose_message "${DOT_TARGET} to ${DOT_SOURCE}" "set"
    execute_command "ln -s ${(q)DOT_SOURCE} ${(q)DOT_TARGET}"
    DOT_LINKED=$(( DOT_LINKED + 1 ))
  done
  if (( DOT_LINKED )) && [ ! "${DO_DRYRUN}" = "true" ]; then
    notice_message "Linked ${DOT_LINKED} dotfiles${${DOT_BACKED_UP:#0}:+, ${DOT_BACKED_UP} replaced (kept in ${DOT_BACKUP})}"
  fi
}

# Remove the links this made (only links that point into the dotfiles directory). Backups are
# left where they are, so restoring one is a deliberate act

dotfiles_unlink () {
  dotfiles_map
  DOT_REMOVED=0
  for DOT_REL in ${(ko)DOT_MAP}; do
    DOT_TARGET="${HOME_DIR}/${DOT_REL}"
    if [ -L "${DOT_TARGET}" ]; then
      zmodload -F zsh/stat b:zstat 2> /dev/null
      zstat -A DOT_LINK +link -- "${DOT_TARGET}"
      if [[ "${DOT_LINK[1]}" == "${DOTFILES_DIR}/"* ]]; then
        execute_command "rm ${(q)DOT_TARGET}"
        DOT_REMOVED=$(( DOT_REMOVED + 1 ))
      fi
    fi
  done
  if [ ! "${DO_DRYRUN}" = "true" ]; then
    notice_message "Removed ${DOT_REMOVED} dotfile links (backups of anything they replaced are in ${WORK_DIR}/dotfile-backups)"
  fi
}

# Backups of ~/.zshrc, rollback and uninstall
#
# --install saves the current ~/.zshrc as ~/.ussuri/.zshrc.<date> before replacing it.
# The date in the name doesn't sort (it is day first), so backups are ordered by when they were saved.

list_backups () {
  BACKUPS=( ${WORK_DIR}/.zshrc.*(Nom) )
}

# Does a file look like this script? (as opposed to a .zshrc you wrote yourself)

is_ussuri_script () {
  [ -r "$1" ] || return 1
  while IFS= read -r SCRIPT_LINE; do
    if [[ "${SCRIPT_LINE}" == 'SCRIPT_NAME="ussuri"'* ]]; then
      return 0
    fi
  done < "$1"
  return 1
}

# Save the current ~/.zshrc as a backup. The name never clashes with an earlier backup,
# including one made in the same second

backup_zshrc () {
  BACKUP_FILE="${WORK_DIR}/.zshrc.${DATE_SUFFIX}"
  BACKUP_N=0
  while [ -e "${BACKUP_FILE}" ]; do
    BACKUP_N=$(( BACKUP_N + 1 ))
    BACKUP_FILE="${WORK_DIR}/.zshrc.${DATE_SUFFIX}_${BACKUP_N}"
  done
  verbose_message "${HOME_DIR}/.zshrc to ${BACKUP_FILE}" "save"
  execute_command "cp ${(q)HOME_DIR}/.zshrc ${(q)BACKUP_FILE}"
}

print_backups () {
  list_backups
  if (( ! ${#BACKUPS} )); then
    print -r -- "No backups in ${WORK_DIR}"
    return 1
  fi
  zmodload -F zsh/stat b:zstat 2> /dev/null
  print -r -- "  #  Saved             Version  Kind      File"
  for (( BACKUP_INDEX = 1; BACKUP_INDEX <= ${#BACKUPS}; BACKUP_INDEX++ )); do
    zstat -A BACKUP_TIME +mtime -- "${BACKUPS[BACKUP_INDEX]}"
    strftime -s BACKUP_WHEN '%Y-%m-%d %H:%M' "${BACKUP_TIME[1]}"
    read_file_version "${BACKUPS[BACKUP_INDEX]}"
    BACKUP_KIND="other"
    if is_ussuri_script "${BACKUPS[BACKUP_INDEX]}"; then
      BACKUP_KIND="ussuri"
    fi
    printf '%3d  %s  %-7s  %-8s  %s\n' "${BACKUP_INDEX}" "${BACKUP_WHEN}" "${FILE_VERSION:--}" "${BACKUP_KIND}" "${BACKUPS[BACKUP_INDEX]:t}"
  done
  print -r -- "Restore one with --rollback N (1 is the newest), or --uninstall to go back to before ussuri."
}

# Work out which backup was asked for: a number from --backups, a file name in the work
# directory, or a path

resolve_backup () {
  BACKUP_CHOSEN=""
  list_backups
  if [[ "$1" == <-> ]]; then
    BACKUP_CHOSEN="${BACKUPS[$1]}"
  elif [ -f "$1" ]; then
    BACKUP_CHOSEN="$1"
  elif [ -f "${WORK_DIR}/$1" ]; then
    BACKUP_CHOSEN="${WORK_DIR}/$1"
  fi
  [ -n "${BACKUP_CHOSEN}" ]
}

# Put a file back as ~/.zshrc, keeping the current one as a backup first so this can be undone

restore_zshrc () {
  if [ -f "${HOME_DIR}/.zshrc" ]; then
    if [[ "$(<"${HOME_DIR}/.zshrc")" == "$(<"$1")" ]]; then
      print -r -- "${HOME_DIR}/.zshrc is already the same as ${1:t}"
      return 0
    fi
    backup_zshrc
  fi
  execute_command "cp ${(q)1} ${(q)HOME_DIR}/.zshrc"
  if [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would restore ${1:t} as ${HOME_DIR}/.zshrc"
  else
    print -r -- "Restored ${1:t} as ${HOME_DIR}/.zshrc (the one it replaced is in ${WORK_DIR})"
  fi
}

do_rollback () {
  list_backups
  if (( ! ${#BACKUPS} )); then
    print -r -- "No backups in ${WORK_DIR}"
    return 1
  fi
  if ! resolve_backup "$1"; then
    print -r -- "There is no backup '$1' (see --backups)"
    return 1
  fi
  restore_zshrc "${BACKUP_CHOSEN}"
}

# Go back to the .zshrc you had before ussuri: the newest backup that isn't ussuri itself.
# If you had none, ussuri's is moved aside. ~/.ussuri (components, backups) is left alone

do_uninstall () {
  if [ ! -f "${HOME_DIR}/.zshrc" ] || ! is_ussuri_script "${HOME_DIR}/.zshrc"; then
    print -r -- "${HOME_DIR}/.zshrc is not ussuri, nothing to uninstall"
    return 0
  fi
  list_backups
  UNINSTALL_BACKUP=""
  for UNINSTALL_FILE in ${BACKUPS}; do
    if ! is_ussuri_script "${UNINSTALL_FILE}"; then
      UNINSTALL_BACKUP="${UNINSTALL_FILE}"
      break
    fi
  done
  if [ -n "${UNINSTALL_BACKUP}" ]; then
    restore_zshrc "${UNINSTALL_BACKUP}"
  else
    backup_zshrc
    execute_command "rm ${(q)HOME_DIR}/.zshrc"
    if [ "${DO_DRYRUN}" = "true" ]; then
      print -r -- "Would move ${HOME_DIR}/.zshrc aside (there is no .zshrc from before ussuri to restore)"
    else
      print -r -- "Moved ${HOME_DIR}/.zshrc aside (there is no .zshrc from before ussuri to restore)"
    fi
  fi
  print -r -- "${WORK_DIR} (installed components, backups) was left alone. --unlink removes dotfile links."
}

# Print a config file with every setting commented out

print_config_template () {
  cat << 'CONFIG'
# ussuri config
#
# This file is sourced as zsh by ussuri.zsh before any defaults are set, so a line like
#   DO_VERBOSE=true
# changes the default for every shell without editing the script. It overrides the
# environment, and command line switches override it. Uncomment what you want to change.
# It runs as you, so keep it writable only by you.

# Behaviour
#DO_VERBOSE=true            # log what is being done
#DO_CACHE_INIT=false        # run rbenv/pyenv/brew init every time instead of caching it
#ZINIT_TURBO=false          # load every zinit plugin before the prompt
#DEFAULTS_MAX_AGE=7         # days before OS X defaults are applied again
#START_DIR=~/code           # directory new shells start in
#GO_HOME=~/go               # GOPATH
#ZSH_THEME=robbyrussell
#SHARE_HISTORY=true
#DO_HISTORY=false           # leave history settings to the system
#HISTORY_SIZE=50000         # lines kept in memory and in the history file
#TRANSMISSION_BLOCKLIST_URL=https://example.com/list.p2p.gz   # a .p2p (or .gz) blocklist for Transmission (OS X)

# Components (true or false)
#INSTALL_ZINIT=true
#INSTALL_RBENV=true
#INSTALL_PYENV=true
#INSTALL_POSH=true
#INSTALL_P10K=true
#INSTALL_FONTS=true
#INSTALL_OZSH=false

# What a login shell checks (true or false)
#DO_DEFAULTS_CHECK=true
#DO_PACKAGE_CHECK=false
#DO_FONTS_CHECK=true
#DO_SUDOERS_CHECK=false
#DO_GNOME_DEFAULTS=true    # Linux: also apply GNOME settings on login (--defaults always does)

# zoxide, a smarter cd (z, zi): set up on login if it is installed (the package lists install it)
#INSTALL_ZOXIDE=false

# Other language managers (true or false). They are installed and set up on login, and versions are
# only installed when building (--tool NAME or --build)
#INSTALL_FNM=true           # Node
#INSTALL_RUSTUP=true        # Rust
#INSTALL_UV=true            # Python
#INSTALL_MISE=true          # many languages, a replacement for the above and for rbenv/pyenv
#FNM_NODE=lts-latest
#RUSTUP_TOOLCHAIN_WANTED=stable
#UV_PYTHON=3.13
#MISE_TOOLS="node@lts python@3.13"

# Versions built by --rbenv and --pyenv (default is the latest stable)
#RUBY_VER=3.4.2
#PYTHON_VER=3.13.1

# Dotfiles (see --dotfiles): layers in ~/.ussuri/dotfiles/{common,profiles/<name>,hosts/<host>}
#DO_DOTFILES_CHECK=true     # link them on every login, not just with --dotfiles
#DOTFILES_PROFILE=work      # use profiles/work on top of common
#DOTFILES_HOST=mybox        # default is the short hostname

# Pin installs (a branch, tag or commit for the first clone, a SHA-256 for installers)
#ZINIT_REF=
#RBENV_REF=
#PYENV_REF=
#BREW_INSTALL_SHA256=
#POSH_INSTALL_SHA256=
#FNM_INSTALL_SHA256=
#RUSTUP_INSTALL_SHA256=
#UV_INSTALL_SHA256=
#MISE_INSTALL_SHA256=
CONFIG
}

# Create the config file if there isn't one, and say where it is (--config)

init_config () {
  if [ -e "${CONFIG_FILE}" ]; then
    print -r -- "${CONFIG_FILE} exists, edit it to change the defaults"
  elif [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would create ${CONFIG_FILE}"
  else
    check_dir_exists "${CONFIG_FILE:h}"
    execute_command "print_config_template > ${(q)CONFIG_FILE}"
    print -r -- "Created ${CONFIG_FILE}, edit it to change the defaults"
  fi
}

# Doctor: read only checks of the environment, to answer "why isn't this working?"
# Prints ok/warn/FAIL lines and exits non-zero if there are any failures. A warning is something
# that will probably fix itself on the next login or is worth a look, a failure is something
# that won't. Nothing here changes anything: check_dir_exists and the support file copies skip
# themselves in doctor mode, so a missing directory is reported rather than quietly recreated.

doctor_ok () {
  DOCTOR_OK=$(( DOCTOR_OK + 1 ))
  print -r -- "  ok    $1"
}

doctor_warn () {
  DOCTOR_WARN=$(( DOCTOR_WARN + 1 ))
  print -r -- "  warn  $1"
}

doctor_fail () {
  DOCTOR_FAIL=$(( DOCTOR_FAIL + 1 ))
  print -r -- "  FAIL  $1"
}

doctor_shell () {
  print -r -- "Shell"
  autoload -Uz is-at-least
  if is-at-least 5.5 "${ZSH_VERSION}"; then
    doctor_ok "zsh ${ZSH_VERSION}"
  else
    doctor_fail "zsh ${ZSH_VERSION} is too old, 5.5 or later is needed (zparseopts -F)"
  fi
  if (( $+builtins[strftime] )); then
    doctor_ok "zsh/datetime is available"
  else
    doctor_warn "zsh/datetime is not available, dates are done by forking date"
  fi
  if (( $+builtins[zf_mkdir] )); then
    doctor_ok "zsh/files is available"
  else
    doctor_warn "zsh/files is not available, the lock forks mkdir and rm"
  fi
}

doctor_tools () {
  print -r -- "Tools"
  for DOCTOR_TOOL in git tar bash mktemp; do
    if (( $+commands[${DOCTOR_TOOL}] )); then
      doctor_ok "${DOCTOR_TOOL}"
    else
      doctor_fail "${DOCTOR_TOOL} is not installed (needed to install and update components)"
    fi
  done
  if (( $+commands[curl] )); then
    doctor_ok "curl"
  elif (( $+commands[wget] )); then
    doctor_ok "wget (curl is not installed)"
  else
    doctor_fail "neither curl nor wget is installed (needed for installers and updates)"
  fi
  if (( $+commands[shasum] || $+commands[sha256sum] )); then
    doctor_ok "a SHA-256 tool for checking installers"
  else
    doctor_warn "no shasum or sha256sum, pinned installers can't be verified"
  fi
  if is_osx; then
    if (( $+commands[defaults] )); then
      doctor_ok "defaults"
    else
      doctor_fail "defaults is not installed"
    fi
    if (( $+commands[brew] )); then
      doctor_ok "brew"
    else
      doctor_warn "brew is not installed (it will be installed when packages are checked)"
    fi
  fi
  if is_linux; then
    if linux_defaults_available; then
      doctor_ok "gsettings and a desktop session (GNOME settings can be applied)"
    elif (( $+commands[gsettings] )); then
      doctor_warn "gsettings is installed but there is no desktop session, GNOME settings are skipped"
    else
      doctor_warn "gsettings is not installed, GNOME settings are skipped"
    fi
    if [ -z "${PKG_MANAGER}" ]; then
      doctor_warn "Linux distribution '${LSB_ID:-unknown}' isn't supported, packages won't be managed (set PKG_MANAGER to apt, pacman, dnf, apk or nix to choose one)"
    else
      set_pkg_manager
      if (( $+commands[${PKG_TOOL}] )); then
        doctor_ok "${PKG_TOOL} (${PKG_MANAGER}${LSB_ID:+, ${LSB_ID}})"
      else
        doctor_fail "${PKG_TOOL} is not installed (${PKG_MANAGER}${LSB_ID:+, ${LSB_ID}})"
      fi
      if [ "${PKG_PRIV}" = "true" ] && [ ! "${UID}" = "0" ] && (( ! $+commands[sudo] && ! $+commands[doas] )); then
        doctor_warn "neither sudo nor doas is installed and you are not root, packages can't be installed"
      fi
    fi
  fi
}

doctor_install () {
  print -r -- "Install"
  if [ "${SCRIPT_FILE}" = "${HOME_DIR}/.zshrc" ]; then
    doctor_ok "running as ${HOME_DIR}/.zshrc, version ${SCRIPT_VERSION}"
  elif [ -f "${HOME_DIR}/.zshrc" ]; then
    read_file_version "${HOME_DIR}/.zshrc"
    if [ -z "${FILE_VERSION}" ]; then
      doctor_warn "${HOME_DIR}/.zshrc is not this script (run --install to use it)"
    elif [ "${FILE_VERSION}" = "${SCRIPT_VERSION}" ]; then
      doctor_ok "${HOME_DIR}/.zshrc is version ${FILE_VERSION}, the same as this script"
    else
      doctor_warn "${HOME_DIR}/.zshrc is version ${FILE_VERSION} but this script is ${SCRIPT_VERSION} (run --install to update it)"
    fi
  else
    doctor_warn "${HOME_DIR}/.zshrc does not exist (run --install)"
  fi
  if [ -d "${WORK_DIR}/files" ]; then
    doctor_ok "${WORK_DIR}/files exists"
  else
    doctor_fail "${WORK_DIR}/files is missing (run --install from a copy of the repo)"
  fi
  if [ -n "${REQUIRED_FILE}" ]; then
    if [ -f "${REQUIRED_FILE}" ]; then
      doctor_ok "package list ${REQUIRED_FILE:t}"
    else
      doctor_warn "package list ${REQUIRED_FILE} is missing, no packages will be installed"
    fi
  fi
  if [ "${INSTALL_ZINIT}" = "true" ] && [ "${PLUGIN_MANAGER}" = "zinit" ]; then
    if [ -f "${ZINIT_FILE}" ]; then
      doctor_ok "plugin list ${ZINIT_FILE:t}"
    elif [ -f "${WORK_DIR}/files/zinit/zinit.zsh" ]; then
      doctor_warn "plugin list ${ZINIT_FILE:t} is missing, the original list is used (run --install to add it)"
    else
      doctor_fail "plugin list ${ZINIT_FILE} is missing, no plugins will load"
    fi
  fi
}

doctor_config () {
  print -r -- "Config"
  if [ ! -e "${CONFIG_FILE}" ]; then
    doctor_ok "no config file, the defaults are used (--config creates one)"
    return
  fi
  if zsh -n "${CONFIG_FILE}" 2> /dev/null; then
    doctor_ok "${CONFIG_FILE} is valid"
  else
    doctor_fail "${CONFIG_FILE} has a syntax error (it is sourced on every shell)"
  fi
  # It is executed, so anyone who can write to it can run commands as you
  DOCTOR_WRITABLE=( ${CONFIG_FILE}(Nf:go+w:) )
  if (( ${#DOCTOR_WRITABLE} )); then
    doctor_warn "${CONFIG_FILE} is writable by others, and it is executed on every shell (chmod go-w it)"
  fi
}

doctor_dotfiles () {
  if [ ! -d "${DOTFILES_DIR}" ]; then
    return
  fi
  print -r -- "Dotfiles"
  dotfiles_map
  if (( ! ${#DOT_MAP} )); then
    doctor_warn "${DOTFILES_DIR} has no files in common/, profiles/${DOTFILES_PROFILE:-<none>}/ or hosts/${DOTFILES_HOST}/"
    return
  fi
  DOCTOR_LINKED=0
  DOCTOR_TODO=0
  DOCTOR_BLOCKED=()
  for DOT_REL in ${(ko)DOT_MAP}; do
    dotfile_state "${HOME_DIR}/${DOT_REL}" "${DOT_MAP[${DOT_REL}]}"
    case "${DOT_STATE}" in
      ok)
        DOCTOR_LINKED=$(( DOCTOR_LINKED + 1 ))
        ;;
      conflict)
        DOCTOR_BLOCKED+=( "${HOME_DIR}/${DOT_REL}" )
        ;;
      *)
        DOCTOR_TODO=$(( DOCTOR_TODO + 1 ))
        ;;
    esac
  done
  if (( ${#DOCTOR_BLOCKED} )); then
    doctor_warn "${#DOCTOR_BLOCKED} real files are in the way of dotfiles (${(j:, :)DOCTOR_BLOCKED[1,3]}), --dotfiles backs them up and links"
  fi
  if (( DOCTOR_TODO )); then
    doctor_warn "${DOCTOR_TODO} dotfiles are not linked yet (run --dotfiles)"
  fi
  if (( ! ${#DOCTOR_BLOCKED} && ! DOCTOR_TODO )); then
    doctor_ok "all ${DOCTOR_LINKED} dotfiles are linked (profile: ${DOTFILES_PROFILE:-none}, host: ${DOTFILES_HOST})"
  fi
}

doctor_lock () {
  print -r -- "Lock"
  if have_lock; then
    doctor_ok "no other run is holding ${LOCK_FILE}"
  else
    doctor_warn "${LOCK_FILE} is held by another run (it is taken over after 10 minutes)"
  fi
}

doctor_components () {
  print -r -- "Components"
  if [ "${INSTALL_ZINIT}" = "true" ]; then
    if [ -d "${ZINIT_HOME}" ]; then doctor_ok "zinit"; else doctor_warn "zinit is not installed (${ZINIT_HOME})"; fi
  fi
  if [ "${INSTALL_RBENV}" = "true" ]; then
    if [ ! -d "${RBENV_HOME}" ]; then
      doctor_warn "rbenv is not installed (${RBENV_HOME})"
    elif [ ! -d "${RBENV_HOME}/plugins/ruby-build" ]; then
      doctor_warn "rbenv is installed but ruby-build is missing"
    else
      doctor_ok "rbenv and ruby-build"
    fi
  fi
  if [ "${INSTALL_PYENV}" = "true" ]; then
    if [ -d "${PYENV_HOME}" ]; then doctor_ok "pyenv"; else doctor_warn "pyenv is not installed (${PYENV_HOME})"; fi
  fi
  if [ "${INSTALL_POSH}" = "true" ]; then
    if [ -x "${POSH_HOME}/oh-my-posh" ] || (( $+commands[oh-my-posh] )); then
      doctor_ok "oh-my-posh"
    else
      doctor_warn "oh-my-posh is not installed (${POSH_HOME})"
    fi
  fi
  if [ "${INSTALL_P10K}" = "true" ]; then
    if [ -f "${P10K_INIT}" ]; then doctor_ok "powerlevel10k config ${P10K_INIT}"; else doctor_warn "powerlevel10k config ${P10K_INIT} is missing"; fi
  fi
  if [ "${INSTALL_OZSH}" = "true" ]; then
    if [ -d "${ZOSH_HOME}" ]; then doctor_ok "oh-my-zsh"; else doctor_warn "oh-my-zsh is not installed (${ZOSH_HOME})"; fi
  fi
  if [ "${INSTALL_ZOXIDE}" = "true" ]; then
    if (( $+commands[zoxide] )); then
      doctor_ok "zoxide"
    else
      doctor_warn "zoxide is not installed (it is in the package lists, -P installs the packages, or install just it with your package manager)"
    fi
  fi
  # Only the tools that have been asked for (INSTALL_<NAME>=true, --tool)
  for DOCTOR_TOOL in fnm rustup uv mise; do
    DOCTOR_WANTED="INSTALL_${(U)DOCTOR_TOOL}"
    if [ "${(P)DOCTOR_WANTED}" = "true" ]; then
      case "${DOCTOR_TOOL}" in
        fnm)    DOCTOR_PATH="${FNM_HOME}/fnm" ;;
        rustup) DOCTOR_PATH="${CARGO_HOME:-${HOME_DIR}/.cargo}/bin/rustup" ;;
        uv)     DOCTOR_PATH="${UV_BIN_DIR}/uv" ;;
        mise)   DOCTOR_PATH="${MISE_BIN}" ;;
      esac
      if [ -x "${DOCTOR_PATH}" ] || (( $+commands[${DOCTOR_TOOL}] )); then
        doctor_ok "${DOCTOR_TOOL}"
      else
        doctor_warn "${DOCTOR_TOOL} is wanted but not installed (${DOCTOR_PATH})"
      fi
    fi
  done
}

doctor_fonts () {
  if [ ! "${INSTALL_FONTS}" = "true" ]; then
    return
  fi
  print -r -- "Fonts"
  DOCTOR_FONT=""
  for DOCTOR_DIR in "${HOME_DIR}/Library/Fonts" /Library/Fonts "${HOME_DIR}/.local/share/fonts" "${HOME_DIR}/.fonts" /usr/share/fonts /usr/local/share/fonts; do
    if [ -d "${DOCTOR_DIR}" ]; then
      DOCTOR_MATCH=( ${DOCTOR_DIR}/**/*[Nn]erd*(N[1]) )
      if (( ${#DOCTOR_MATCH} )); then
        DOCTOR_FONT="${DOCTOR_MATCH[1]}"
        break
      fi
    fi
  done
  if [ -n "${DOCTOR_FONT}" ]; then
    doctor_ok "a Nerd Font is installed (${DOCTOR_FONT:t})"
  else
    doctor_warn "no Nerd Font found, prompt icons won't display (it is installed when fonts are checked)"
  fi
}

doctor_backups () {
  print -r -- "Backups"
  zmodload -F zsh/stat b:zstat 2> /dev/null
  DOCTOR_BACKUPS=( ${WORK_DIR}/.zshrc.*(N) )
  if (( ${#DOCTOR_BACKUPS} > DOCTOR_MAX_BACKUPS )); then
    DOCTOR_OLDEST=""
    if (( $+builtins[zstat] )); then
      zstat -A DOCTOR_TIMES +mtime ${DOCTOR_BACKUPS}
      DOCTOR_TIMES=( ${(on)DOCTOR_TIMES} )
      DOCTOR_OLDEST=", the oldest is $(( (EPOCHSECONDS - DOCTOR_TIMES[1]) / 86400 )) days old"
    fi
    doctor_warn "${#DOCTOR_BACKUPS} .zshrc backups in ${WORK_DIR}${DOCTOR_OLDEST} (each --install adds one, remove the ones you don't need)"
  else
    doctor_ok "${#DOCTOR_BACKUPS} .zshrc backups"
  fi
}

doctor_state () {
  print -r -- "State"
  if is_osx; then
    DOCTOR_STAMP="${WORK_DIR}/defaults.stamp"
    if [ -f "${DOCTOR_STAMP}" ]; then
      zmodload -F zsh/stat b:zstat 2> /dev/null
      zstat -A DOCTOR_TIMES +mtime "${DOCTOR_STAMP}"
      doctor_ok "OS X defaults were last applied $(( (EPOCHSECONDS - DOCTOR_TIMES[1]) / 86400 )) days ago"
    else
      doctor_warn "OS X defaults have not been applied yet (they are on the next login, or run --defaults)"
    fi
  fi
  DOCTOR_CACHE=( ${WORK_DIR}/cache/*(N) )
  doctor_ok "${#DOCTOR_CACHE} cached init scripts"
  # The directories this script adds to PATH whether or not they exist aren't worth a warning
  DOCTOR_OWN=( /usr/local/bin /usr/local/sbin /opt/local/bin /opt/local/sbin "${HOME_DIR}/.local/bin" "${HOME_DIR}/.cargo/bin" "${GO_HOME}" )
  DOCTOR_MISSING=()
  for DOCTOR_DIR in ${path}; do
    if [ ! -d "${DOCTOR_DIR}" ] && (( ! ${DOCTOR_OWN[(Ie)${DOCTOR_DIR}]} )); then
      DOCTOR_MISSING+=( "${DOCTOR_DIR}" )
    fi
  done
  if (( ${#DOCTOR_MISSING} )); then
    doctor_warn "${#DOCTOR_MISSING} PATH entries don't exist (${(j:, :)DOCTOR_MISSING[1,3]}$( (( ${#DOCTOR_MISSING} > 3 )) && print -r -- ', ...' ))"
  else
    doctor_ok "every PATH entry exists"
  fi
}

run_doctor () {
  DOCTOR_OK=0
  DOCTOR_WARN=0
  DOCTOR_FAIL=0
  print -r -- "ussuri ${SCRIPT_VERSION} doctor (${OS_NAME}${LSB_ID:+, ${LSB_ID}})"
  doctor_shell
  doctor_tools
  doctor_install
  doctor_config
  doctor_dotfiles
  doctor_lock
  doctor_components
  doctor_fonts
  doctor_backups
  doctor_state
  print
  print -r -- "${DOCTOR_OK} ok, ${DOCTOR_WARN} warnings, ${DOCTOR_FAIL} failures"
  (( DOCTOR_FAIL == 0 ))
}

# Set defaults

set_defaults () {
  set_env "WORK_DIR" "${HOME_DIR}/.${SCRIPT_NAME}"
  check_dir_exists   "${WORK_DIR}/files"
  set_all_defaults
  if [ "${DO_INSTALL}" = "false" ]; then
    if is_osx; then
      set_osx_defaults
    fi
    if is_linux; then
      set_linux_defaults
    fi
  fi
}

# Check defaults

check_defaults () {
  if is_osx; then
    check_osx_defaults
  fi
  if is_linux; then
    check_linux_defaults
  fi
}

# Check packages

check_package_config () {
  have_lock || return
  if is_osx; then
    check_osx_packages
  fi
  if is_linux; then
    check_linux_packages
  fi
}

# Check CPPFLAGS

check_cppflags_config () {
  for CHECK_DIR in "/usr" "/usr/local" "/usr/local/share" "/opt/local" \
    "/opt/local/share" "/opt/homebrew" "/usr/local/homebrew"; do
    if [ -d "${CHECK_DIR}/include" ]; then
      exp_env "CPPFLAGS" "${CHECK_DIR}/include" 
    fi
  done
}

# Check LDFAGS

check_ldflags_config () {
  for CHECK_DIR in "/usr" "/usr/local" "/usr/local/share" "/opt/local" \
    "/opt/local/share" "/opt/homebrew" "/usr/local/homebrew"; do
    if [ -d "${CHECK_DIR}/lib" ]; then
      exp_env "LDFLAGS" "${CHECK_DIR}/lib" 
    fi
  done
}

# Check PKGCONFIG

check_pkgconfig_config () {
  for CHECK_DIR in "/usr" "/usr/local" "/usr/local/share" "/opt/local" \
    "/opt/local/share" "/opt/homebrew" "/usr/local/homebrew"; do
    if [ -d "${CHECK_DIR}/pkgconfig" ]; then
      exp_env "PKG_CONFIG_PATH" "${CHECK_DIR}/pkgconfig" 
    fi
    if [ -d "${CHECK_DIR}/lib/pkgconfig" ]; then
      exp_env "PKG_CONFIG_PATH" "${CHECK_DIR}/lib/pkgconfig" 
    fi
  done
}

# Check brew config

check_brew_config () {
  if is_osx; then
    setup_brew_env
  fi
}

if [[ ! "${CALLER}" =~ "X11|Antigravity" ]]; then

  # Handle install mode

  if (( ${ARGS[(Ie)-I]} || ${ARGS[(Ie)--install]} )); then
    DO_INSTALL="true"
  else
    set_env "DO_INSTALL" "false"
  fi

  # Set verbose early so it applies while parsing

  if (( ${ARGS[(Ie)-v]} || ${ARGS[(Ie)--verbose]} )); then
    DO_VERBOSE="true"
  else
    set_env "DO_VERBOSE" "false"
  fi

  verbose_message "Instantiated by ${CALLER} on ${DATE} by ${MY_USERNAME}@${HOSTNAME}"

  # If given no command arguments run as a normal login script
  # Otherwise handle commandline argument
  # Arguments are parsed before set_defaults so switches (e.g. --dryrun) are
  # known before anything with side effects runs, and set_env won't override them

  if (( $# )); then

    # Long switches are translated to their short form, then zparseopts validates everything
    # (unknown switches, switches missing their value) and returns the switches in order, so the
    # case below only has to know the short forms. The value after a switch that takes one is
    # left alone, even if it looks like a switch.

    typeset -A LONG_SWITCHES=(
      --doall -A        --build -b         --compile -b       --confirm -c
      --check -C        --debug -d         --default -D       --defaults -D
      --changes -e      --changelog -e     --font -f          --fonts -f
      --force -F        --gopath -g        --gohome -g        --help -h
      --usage -h        --inline -i        --install -I       --location -l
      --startdir -l     --notheme -n       --manager -m       --plugin -m
      --noenv -N        --ohmyposh -o      --posh -o          --ohmyzsh -O
      --zosh -O         --package -P       --packages -P      --pyenv -p
      --rbenv -r        --sudoers -s       --sudoersentry -S  --test -t
      --dryrun -t       --p10k -T          --update -U        --verbose -v
      --version -V      --zinit -z         --zshtheme -Z
      --doctor -x       --config -k        --dotfiles -L
      --unlink -u       --profile -M       --backups -B
      --rollback -R     --uninstall -X     --drift -G
      --tool -W
    )
    SWITCHES=()
    SWITCH_VALUE="false"
    for (( ARG_INDEX = 1; ARG_INDEX <= $#; ARG_INDEX++ )); do
      ARG="${@[ARG_INDEX]}"
      if [ "${SWITCH_VALUE}" = "true" ]; then
        SWITCHES+=( "${ARG}" )
        SWITCH_VALUE="false"
        continue
      fi
      ARG="${LONG_SWITCHES[${ARG}]:-${ARG}}"
      SWITCHES+=( "${ARG}" )
      case "${ARG}" in
        -g|-l|-m|-M|-S|-W|-Z)
          SWITCH_VALUE="true"
          ;;
        -R)
          # Which backup to roll back to is optional, no value means the newest
          if [[ -z "${@[ARG_INDEX+1]}" || "${@[ARG_INDEX+1]}" == -* ]]; then
            SWITCHES+=( 1 )
          else
            SWITCH_VALUE="true"
          fi
          ;;
      esac
    done
    set -- "${SWITCHES[@]}"
    if ! zparseopts -D -F -a OPTS -- A b B c C d D e f F g: G h i I k l: L M: n m: N o O P p r R: s S: t T u U v V W: x X z Z: || (( $# )); then
      print_help
      release_lock
      exit 1
    fi
    while (( ${#OPTS} )); do
      case "${OPTS[1]}" in
        -A)
          DO_BUILD="true"
          DO_DEFAULTS_CHECK="true"
          DEFAULTS_EXPLICIT="true"
          DO_FONTS_CHECK="true"
          DO_ZSH_THEME="true"
          DO_ZINIT_CHECK="true"
          DO_P10K_CHECK="true"
          DO_RBENV_CHECK="true"
          DO_PYENV_CHECK="true"
          DO_PACKAGE_CHECK="true"
          PACKAGE_EXPLICIT="true"
          DO_FONTS_CHECK="true"
          DO_POSH_CHECK="true"
          DO_ENV_SETUP="true"
          shift OPTS
          ;;
        -b)
          DO_BUILD="true"
          shift OPTS
          ;;
        -c)
          DO_CONFIRM="true"
          shift OPTS
          ;;
        -C)
          DO_VERSION_CHECK="true"
          shift OPTS
          ;;
        -d)
          DO_DEBUG="true"
          shift OPTS
          ;;
        -D)
          DO_DEFAULTS_CHECK="true"
          DEFAULTS_EXPLICIT="true"
          shift OPTS
          ;;
        -e)
          print_changelog
          shift OPTS
          release_lock
          exit
          ;;
        -f)
          DO_FONTS_CHECK="true"
          shift OPTS
          ;;
        -F)
          DO_FORCE="true"
          shift OPTS
          ;;
        -g)
          GO_HOME="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -h)
          DO_HELP="true"
          shift OPTS
          ;;
        -i)
          set_inline_defaults
          shift OPTS
          ;;
        -I)
          DO_INSTALL="true"
          shift OPTS
          ;;
        -k)
          DO_CONFIG="true"
          shift OPTS
          ;;
        -L)
          DO_DOTFILES_CHECK="true"
          shift OPTS
          ;;
        -M)
          DOTFILES_PROFILE="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -u)
          DO_UNLINK="true"
          shift OPTS
          ;;
        -W)
          case "${OPTS[2]}" in
            fnm|rustup|uv|mise)
              typeset -g "INSTALL_${(U)OPTS[2]}=true"
              DO_TOOLS_CHECK="true"
              DO_BUILD="true"
              DO_ENV_SETUP="true"
              ;;
            *)
              print -r -- "Unknown tool '${OPTS[2]}', choose from fnm, rustup, uv or mise"
              release_lock
              exit 1
              ;;
          esac
          shift 2 OPTS
          ;;
        -G)
          DO_DRIFT="true"
          shift OPTS
          ;;
        -B)
          DO_BACKUPS="true"
          shift OPTS
          ;;
        -R)
          DO_ROLLBACK="true"
          ROLLBACK_TARGET="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -X)
          DO_UNINSTALL="true"
          shift OPTS
          ;;
        -l)
          START_DIR="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -n)
          DO_ZSH_THEME="false"
          shift OPTS
          ;;
        -m)
          PLUGIN_MANAGER="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -N)
          DO_ENV_SETUP="false"
          shift OPTS
          ;;
        -o)
          DO_FONTS_CHECK="true"
          DO_POSH_CHECK="true"
          shift OPTS
          ;;
        -O)
          DO_FONTS_CHECK="true"
          DO_ZOSH_CHECK="true"
          shift OPTS
          ;;
        -P)
          DO_PACKAGE_CHECK="true"
          PACKAGE_EXPLICIT="true"
          shift OPTS
          ;;
        -p)
          DO_BUILD="true"
          DO_PYENV_CHECK="true"
          INSTALL_PYENV="true"
          DO_ENV_SETUP="true"
          shift OPTS
          ;;
        -r)
          DO_BUILD="true"
          DO_RBENV_CHECK="true"
          INSTALL_RBENV="true"
          DO_ENV_SETUP="true"
          shift OPTS
          ;;
        -s)
          DO_SUDOERS_CHECK="true"
          shift OPTS
          ;;
        -S)
          SUDOERS_ENTRY="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -t)
          DO_DRYRUN="true"
          shift OPTS
          ;;
        -T)
          DO_P10K_CHECK="true"
          shift OPTS
          ;;
        -U)
          DO_UPDATE_CHECK="true"
          shift OPTS
          ;;
        -v)
          DO_VERBOSE="true"
          shift OPTS
          ;;
        -V)
          DO_VERSION="true"
          shift OPTS
          ;;
        -x)
          DO_DOCTOR="true"
          shift OPTS
          ;;
        -z)
          DO_ZINIT_CHECK="true"
          shift OPTS
          ;;
        -Z)
          ZSH_THEME="${OPTS[2]}"
          shift 2 OPTS
          ;;
        *)
          print_help
          release_lock
          exit
          ;;
      esac
    done
  else
    set_inline_defaults
  fi

  # Set defaults (does not override anything set above)

  set_defaults

  # Incrementally append and hare history between sessions

  # History: keep a lot more than the system default (macOS gives 2000, a bare zsh 30) and leave out
  # the noise: repeats, commands typed with a leading space (a way to keep one out of history),
  # and stray blanks. HISTFILE is chosen if nothing has, as without one nothing is saved.
  # DO_HISTORY=false leaves all of this to the system, HISTORY_SIZE changes the size

  if [ "${DO_HISTORY}" = "true" ]; then
    HISTSIZE="${HISTORY_SIZE}"
    SAVEHIST="${HISTORY_SIZE}"
    HISTFILE="${HISTFILE:-${ZDOTDIR:-${HOME_DIR}}/.zsh_history}"
    setopt hist_ignore_dups
    setopt hist_ignore_space
    setopt hist_find_no_dups
    setopt hist_reduce_blanks
  fi
  if [ "${SHARE_HISTORY}" = "true" ]; then
    setopt inc_append_history
    setopt share_history
  fi

  # Handle dryrun

  if [ "${DO_DRYRUN}" = "true" ]; then
    handle_output "Running without executing commands" "info"
  fi

  # Set debug

  if [ "${DO_DEBUG}" = "true" ]; then
    set -x
  fi

  # Print help

  if [ "${DO_HELP}" = "true" ]; then
    print_help
    release_lock
    exit
  fi

  # Print version

  if [ "${DO_VERSION}" = "true" ]; then
    echo "${SCRIPT_VERSION}"
    release_lock
    exit
  fi

  # Do the doctor (read only)

  if [ "${DO_DOCTOR}" = "true" ]; then
    run_doctor
    DOCTOR_STATUS=$?
    release_lock
    exit ${DOCTOR_STATUS}
  fi

  # Do the drift report (read only)

  if [ "${DO_DRIFT}" = "true" ]; then
    run_drift
    DRIFT_STATUS=$?
    release_lock
    exit ${DRIFT_STATUS}
  fi

  # Do config

  if [ "${DO_CONFIG}" = "true" ]; then
    init_config
    release_lock
    exit
  fi

  # Set Go PATH

  if [ -d "$GO_HOME" ]; then
    exp_env "PATH"    "${GO_HOME}"
    set_env "GOPATH"  "${GO_HOME}"  
  fi

  # Do sudoers

  if [ "${DO_SUDOERS_CHECK}" = "true" ]; then
    check_sudoers_config
  fi

  # Do install

  if [ "${DO_INSTALL}" = "true" ]; then
    DO_ENV_SETUP="false"
    do_install "" "set"
    release_lock
    exit
  fi

  # Do check defaults

  if [ "${DO_DEFAULTS_CHECK}" = "true" ]; then
    check_defaults
  fi

  # Do backups, rollback and uninstall

  if [ "${DO_BACKUPS}" = "true" ] || [ "${DO_ROLLBACK}" = "true" ] || [ "${DO_UNINSTALL}" = "true" ]; then
    BACKUP_STATUS=0
    if [ "${DO_BACKUPS}" = "true" ]; then
      print_backups || BACKUP_STATUS=1
    fi
    if [ "${DO_ROLLBACK}" = "true" ]; then
      do_rollback "${ROLLBACK_TARGET}" || BACKUP_STATUS=1
    fi
    if [ "${DO_UNINSTALL}" = "true" ]; then
      do_uninstall || BACKUP_STATUS=1
    fi
    release_lock
    exit ${BACKUP_STATUS}
  fi

  # Do dotfiles

  if [ "${DO_UNLINK}" = "true" ]; then
    dotfiles_unlink
    release_lock
    exit
  fi
  if [ "${DO_DOTFILES_CHECK}" = "true" ]; then
    check_dotfiles_config
  fi

  # Do check for updates

  if [ "${DO_UPDATE_CHECK}" = "true" ] || [ "${DO_VERSION_CHECK}" = "true" ]; then
    if [ "${DO_UPDATE_CHECK}" = "true" ]; then
      update_script
    else
      check_for_update
    fi
    release_lock
    exit
  fi

  # Handle brew config

  if is_osx; then
    if [ "${DO_BREW_CHECK}" = "true" ]; then
      check_brew_config
    fi
  fi

  # Do package check

  if [ "${DO_PACKAGE_CHECK}" = "true" ]; then
    check_package_config
  fi

  # Do font(s) check

  if [ "${DO_FONTS_CHECK}" = "true" ]; then
    check_fonts_config
  fi

  if [ "${DO_POSH_CHECK}" = "true" ]; then
    check_posh_config
  fi

  # Do zinit checks

  if [ "${DO_ZINIT_CHECK}" = "true" ]; then
    check_zinit_config
  fi

  # Do pyenv checks

  if [ "${DO_PYENV_CHECK}" = "true" ]; then
    check_pyenv_config
  fi

  # Do rbenv checks

  if [ "${DO_RBENV_CHECK}" = "true" ]; then
    check_rbenv_config
  fi

  # Do language and tool managers (fnm, rustup, uv, mise)

  if [ "${DO_TOOLS_CHECK}" = "true" ]; then
    check_tools_config
  fi

  # Do zoxide (after the plugin lists, which provide compdef for its completions)

  if [ "${DO_ZOXIDE_CHECK}" = "true" ]; then
    check_zoxide_config
  fi

  # Do Powerlevel10k config

  if [ "${DO_P10K_CHECK}" = "true" ]; then
    check_p10k_config
  fi

  # Do oh-my-zsh config

  if [ "${DO_ZOSH_CHECK}" = "true" ]; then
    check_zosh_config
  fi

  # Handle zsh theme

  if [ "${DO_ZSH_THEME}" = "false" ]; then
    ZSH_THEME=""
  fi

  if [ ! "${START_DIR}" = "none" ] && [ ! "${START_DIR}" = "" ]; then
    if [ -d "${START_DIR}" ]; then
      cd "${START_DIR}" || return
    fi
  fi

  # Update package list

  if [ "${DO_UPDATE_LIST}" = "true" ]; then
    update_package_list
  fi

  # Remove lock file

  release_lock

  # Do LDFLAGS check

  if [ "${DO_LDFLAGS_CHECK}" = "true" ]; then
    check_ldflags_config
  fi

  # Do PKGCONFIG check

  if [ "${DO_PKGCONFIG_CHECK}" = "true" ]; then
    check_pkgconfig_config
  fi

  # Do CPPFLAGS check

  if [ "${DO_CPPFLAGS_CHECK}" = "true" ]; then
    check_cppflags_config
  fi

  # Change to start directory

  if [ "${START_DIR}" = "none" ] || [ "${START_DIR}" = "" ]; then
    cd "${INIT_DIR}"
  else
    if [ -d "${START_DIR}" ]; then
      cd "${START_DIR}"
    else
      cd "${INIT_DIR}"
    fi
  fi
else
  release_lock
fi

# Set prompt

if [ "${MY_USERID}" = "0" ]; then
  export PS1="%n@%m %1#:"
else
  export PS1="%n@%m %1~:"
fi
