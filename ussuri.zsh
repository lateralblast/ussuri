#!/usr/bin/env zsh
#
# Version: 1.9.1
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
STARTUP_T0="${EPOCHREALTIME}"
# Where the time goes before the login steps: a mark is a label and the time, added inline (no function, no fork) and
# shown by --timing as the time since the one before. The label names what ran since it
STARTUP_MARKS=()
if (( $+builtins[strftime] )); then
  strftime -s DATE '%a %d %b %Y %T %Z' "${EPOCHSECONDS}"
else
  DATE=$( date )
fi

# A profile or machine name becomes part of a file path (profiles/<name>/...), so one that could point
# somewhere else (a slash, or starting with a dot as in ..) is refused rather than used

check_layer_name () {
  local value="${(P)1}"
  if [[ "${value}" == */* || "${value}" == .* ]]; then
    echo "Warning:        Ignoring ${1}='${value}': a profile or machine name can't contain / or start with a dot"
    typeset -g "${1}="
  fi
}

# Your own additions to a list or plugin file, in layers that updates and --install never overwrite, in the
# directory of the file it adds to. For files/packages/macos.brew (extension brew) and files/zinit (zsh):
#
#   local.<ext>                               every machine
#   profiles/<PROFILE>/local.<ext>            machines using that profile (-M, or PROFILE)
#   hosts/<MACHINE>/local.<ext>               just that machine (MACHINE, the short hostname by default)
#
# Later layers win. Sets LOCAL_LAYERS to the ones that exist. A profile or machine that is not set has no layer.
# With a third argument "layers" the first, every machine one, is left out (the config has its own file for that:
# local_layer_files "${CONFIG_FILE:h}" config layers gives profiles/<PROFILE>/local.config and hosts/<MACHINE>/local.config)

local_layer_files () {
  LOCAL_LAYERS=()
  local candidates=( "$1/local.$2" ) f
  if [ "$3" = "layers" ]; then
    candidates=()
  fi
  if [ -n "${PROFILE}" ]; then
    candidates+=( "$1/profiles/${PROFILE}/local.$2" )
  fi
  if [ -n "${MACHINE}" ]; then
    candidates+=( "$1/hosts/${MACHINE}/local.$2" )
  fi
  for f in "${candidates[@]}"; do
    if [ -f "${f}" ]; then
      LOCAL_LAYERS+=( "${f}" )
    fi
  done
}

# One step of a login. With --timing it is timed, otherwise this is the call and nothing else (no process, one
# function call), so the steps of the login can be wrapped without costing anything: phase NAME COMMAND [ARGS]

phase () {
  if [[ "${DO_TIMING}" != "true" ]]; then
    "${@[2,-1]}"
    return
  fi
  local started="${EPOCHREALTIME}" result
  "${@[2,-1]}"
  result=$?
  TIMING_NAMES+=( "$1" )
  TIMING_SECONDS+=( $(( EPOCHREALTIME - started )) )
  return ${result}
}

# The report of --timing: each step of the login that ran, in milliseconds on the shell's own clock, what the
# steps do not account for (reading the config, the switches, the defaults, the lock), the total, and the slowest

print_timing () {
  [[ "${DO_TIMING}" == "true" ]] || return 0
  if [[ -z "${STARTUP_T0}" ]]; then
    print -r -- "--timing needs the zsh/datetime module, which is not available"
    return 1
  fi
  local total=$(( (EPOCHREALTIME - STARTUP_T0) * 1000 )) steps=0 ms slowest="" slowest_ms=-1 i mark at
  local prev="${STARTUP_T0}" zinit_ms=0 line_sum=0
  local -a lines
  print -r -- "Startup timing (milliseconds, from the start of the script)"
  # The time before the login steps, in the pieces the marks cut it into
  for mark in "${STARTUP_MARKS[@]}"; do
    at="${mark##*|}"
    ms=$(( (at - prev) * 1000 ))
    prev="${at}"
    steps=$(( steps + ms ))
    printf '  %-26s %8.1f\n' "${mark%%|*}" "${ms}"
    if (( ms > slowest_ms )); then
      slowest="${mark%%|*}"
      slowest_ms=${ms}
    fi
  done
  for (( i = 1; i <= ${#TIMING_NAMES}; i++ )); do
    ms=$(( TIMING_SECONDS[i] * 1000 ))
    steps=$(( steps + ms ))
    [[ "${TIMING_NAMES[i]}" == zinit ]] && zinit_ms=${ms}
    printf '  %-26s %8.1f\n' "${TIMING_NAMES[i]}" "${ms}"
    if (( ms > slowest_ms )); then
      slowest="${TIMING_NAMES[i]}"
      slowest_ms=${ms}
    fi
  done
  printf '  %-26s %8.1f\n' "everything else" $(( total - steps ))
  printf '  %-26s %8.1f\n' "total" "${total}"
  if [[ -n "${slowest}" ]]; then
    printf 'Slowest: %s (%.1f ms)\n' "${slowest}" "${slowest_ms}"
  fi
  # Inside the zinit step: each line of the plugin lists, slowest first, and what is left over (zinit itself starting)
  if (( ${#TIMING_LINES} )); then
    for (( i = 1; i <= ${#TIMING_LINES}; i++ )); do
      ms=$(( TIMING_LINE_SECONDS[i] * 1000 ))
      line_sum=$(( line_sum + ms ))
      lines+=( "$( printf '%09.3f %s' "${ms}" "${TIMING_LINES[i]}" )" )
    done
    print
    print -r -- "Inside the zinit step, by line of the plugin lists (slowest first, the 8 slowest of ${#TIMING_LINES})"
    lines=( ${(On)lines} )
    for mark in "${(@)lines[1,8]}"; do
      printf '  %-34s %8.1f\n' "${${mark#* }[1,34]}" "$(( ${mark%% *} ))"
    done
    printf '  %-34s %8.1f\n' "all the lines" "${line_sum}"
    printf '  %-34s %8.1f\n' "zinit starting, reading the lists" $(( zinit_ms - line_sum ))
  fi
  print -r -- "Plugins that zinit defers (turbo mode) load after the prompt and are not counted. Run it again for the cost of a normal login: the first run does the one off work."
}

if [[ ! "${CALLER}" =~ "X11|Antigravity" ]]; then

  # Optional user settings (see --config), e.g. DO_VERBOSE=true. Sourced before anything reads
  # these variables, so it wins over the environment, and command line switches win over it

  CONFIG_FILE="${USSURI_CONFIG:-${HOME_DIR}/.ussuri/config}"
  if [ -r "${CONFIG_FILE}" ]; then
    source "${CONFIG_FILE}"
  fi

  # Settings for one profile or machine, on top of the config (and under the command line): the files
  # profiles/<PROFILE>/local.config and hosts/<MACHINE>/local.config next to it, sourced in that order. PROFILE
  # and MACHINE are the ones the environment or the config set (-M and -H come too late for this), and there is
  # no layer for a profile that is not set. Two file checks and no processes when there are none

  MACHINE="${MACHINE:-${HOST%%.*}}"
  check_layer_name "PROFILE"
  check_layer_name "MACHINE"
  local_layer_files "${CONFIG_FILE:h}" "config" "layers"
  CONFIG_LAYER_FILES=( "${LOCAL_LAYERS[@]}" )
  for CONFIG_LAYER in "${CONFIG_LAYER_FILES[@]}"; do
    if [ -r "${CONFIG_LAYER}" ]; then
      source "${CONFIG_LAYER}"
    fi
  done

  STARTUP_MARKS+=( "config files|${EPOCHREALTIME}" )

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
  [ "${DO_DOCTOR}" = "true" ] || [ "${DO_DRIFT}" = "true" ] || [ "${DO_PROMPT_PREVIEW}" = "true" ]
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

# The prompt engine: which of powerlevel10k (p10k), oh-my-posh (posh) or neither (none) is installed,
# set up and loaded. Two engines at once both hook every prompt and fight over it, and oh-my-posh's
# init alone costs a few hundred milliseconds on every login, so there is only ever one.
# Set PROMPT_ENGINE (for example in the config), or use -E for one run

prompt_engine_is () {
  [ "${PROMPT_ENGINE}" = "$1" ]
}

resolve_prompt_engine () {
  PROMPT_ENGINE="${PROMPT_ENGINE:-p10k}"
  case "${PROMPT_ENGINE}" in
    p10k|posh|none)
      ;;
    *)
      echo "Warning:        Unknown prompt engine '${PROMPT_ENGINE}' (choose p10k, posh or none), using p10k"
      PROMPT_ENGINE="p10k"
      ;;
  esac
  # What each engine's install and login setup default to (no forking: this runs on every login)
  PROMPT_WANT_POSH="false"
  PROMPT_WANT_P10K="false"
  if [ "${PROMPT_ENGINE}" = "posh" ]; then
    PROMPT_WANT_POSH="true"
  fi
  if [ "${PROMPT_ENGINE}" = "p10k" ]; then
    PROMPT_WANT_P10K="true"
  fi
  # -A, -o, -T and -E ask for the engine's setup to be done this run, whichever engine it is
  if [ "${DO_PROMPT_CHECK}" = "true" ]; then
    DO_POSH_CHECK="${PROMPT_WANT_POSH}"
    DO_P10K_CHECK="${PROMPT_WANT_P10K}"
  fi
}

# A two line powerlevel10k prompt: a configurable line above the one you have. PROMPT_TOP_ELEMENTS (default:
# "context os_version cpu_arch": user@hostname, the OS version, the architecture) are the p10k segments on the left of the top line, and
# PROMPT_TOP_RIGHT_ELEMENTS (default: date, the day and date, "Fri 30 Oct 2026"; "none" for nothing) on its right. Your line, with its right hand segments, stays
# as it is below. A segment moved to the top line is taken off the bottom one, so it isn't shown twice, and
# context is made visible whatever the user (p10k hides it for a default user). It is done after your
# ~/.p10k.zsh is read, so it works on top of whatever that holds, even one made by p10k configure. A config that
# already has more than one line is yours and is left alone. PROMPT_TWO_LINE=false turns it off

# macos_version, linux_version and os_version are segments of our own: "macOS 15.1", "Ubuntu 24.04 LTS", and
# whichever of the two this machine is. Read from the system version file (macOS) or os-release (Linux) with zsh
# builtins (no sw_vers or lsb_release, so no fork), once, here, not on every prompt. A segment shows nothing on a
# machine the other kind

define_os_version_segments () {
  setopt localoptions extendedglob
  local mac_file="${MACOS_VERSION_FILE:-/System/Library/CoreServices/SystemVersion.plist}"
  local linux_file="${OS_RELEASE_FILE:-/etc/os-release}"
  local text rest name="" version="" line
  typeset -g MACOS_VERSION_TEXT="" LINUX_VERSION_TEXT=""
  if [[ -r "${mac_file}" ]]; then
    text="$(<${mac_file})"
    if [[ "${text}" == *"<key>ProductVersion</key>"* ]]; then
      rest="${text#*<key>ProductVersion</key>}"; rest="${rest#*<string>}"; version="${rest%%</string>*}"
    fi
    if [[ "${text}" == *"<key>ProductName</key>"* ]]; then
      rest="${text#*<key>ProductName</key>}"; rest="${rest#*<string>}"; name="${rest%%</string>*}"
    fi
    [[ -n "${version}" ]] && MACOS_VERSION_TEXT="${name:-macOS} ${version}"
  fi
  if [[ -r "${linux_file}" ]]; then
    name=""; version=""
    for line in "${(@f)$(<${linux_file})}"; do
      case "${line}" in
        PRETTY_NAME=*) LINUX_VERSION_TEXT="${(Q)${line#PRETTY_NAME=}}" ;;
        NAME=*)        name="${(Q)${line#NAME=}}" ;;
        VERSION_ID=*)  version="${(Q)${line#VERSION_ID=}}" ;;
      esac
    done
    [[ -z "${LINUX_VERSION_TEXT}" && -n "${name}" ]] && LINUX_VERSION_TEXT="${name}${version:+ ${version}}"
  fi
  typeset -g OS_VERSION_TEXT="${MACOS_VERSION_TEXT:-${LINUX_VERSION_TEXT}}"
  prompt_macos_version () {
    [[ -n "${MACOS_VERSION_TEXT}" ]] && p10k segment -f "${POWERLEVEL9K_MACOS_VERSION_FOREGROUND:-250}" -t "${MACOS_VERSION_TEXT}"
  }
  prompt_linux_version () {
    [[ -n "${LINUX_VERSION_TEXT}" ]] && p10k segment -f "${POWERLEVEL9K_LINUX_VERSION_FOREGROUND:-250}" -t "${LINUX_VERSION_TEXT}"
  }
  prompt_os_version () {
    [[ -n "${OS_VERSION_TEXT}" ]] && p10k segment -f "${POWERLEVEL9K_OS_VERSION_FOREGROUND:-250}" -t "${OS_VERSION_TEXT}"
  }
}

apply_prompt_top_line () {
  setopt localoptions extendedglob
  [ "${PROMPT_TWO_LINE}" = "true" ] || return 0
  prompt_engine_is p10k || return 0
  local -a top=() top_right=() moved bottom_left bottom_right
  local name
  # Segment names go into p10k's lists, so only plain names are accepted
  for name in ${=PROMPT_TOP_ELEMENTS}; do
    [[ "${name}" == none ]] && continue
    if [[ "${name}" == [A-Za-z0-9_]## ]]; then
      top+=( "${name}" )
    else
      echo "Warning:        Ignoring '${name}' in PROMPT_TOP_ELEMENTS: a segment name is letters, digits and underscores"
    fi
  done
  for name in ${=PROMPT_TOP_RIGHT_ELEMENTS}; do
    [[ "${name}" == none ]] && continue
    if [[ "${name}" == [A-Za-z0-9_]## ]]; then
      top_right+=( "${name}" )
    else
      echo "Warning:        Ignoring '${name}' in PROMPT_TOP_RIGHT_ELEMENTS: a segment name is letters, digits and underscores"
    fi
  done
  (( ${#top} + ${#top_right} )) || return 0
  if (( ${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[(Ie)newline]} || ${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[(Ie)newline]} )); then
    verbose_message "The p10k config already has more than one line, leaving it as it is"
    return 0
  fi
  moved=( "${top[@]}" "${top_right[@]}" )
  bottom_left=( ${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS:|moved} )
  bottom_right=( ${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS:|moved} )
  # An explicit newline in both lists puts the right hand segments of each line on their own line
  POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( "${top[@]}" newline "${bottom_left[@]}" )
  POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=( "${top_right[@]}" newline "${bottom_right[@]}" )
  # p10k's own date segment shows 05.02. by default: the day and date is what the top line is for, unless the config chose a format
  if (( ${moved[(Ie)date]} )) && [[ -z "${POWERLEVEL9K_DATE_FORMAT}" ]]; then
    typeset -g POWERLEVEL9K_DATE_FORMAT='%D{%a %d %b %Y}'
  fi
  # p10k's own date colour is dark and cannot be read on the prompt's background (238); the same light grey as os_version
  if (( ${moved[(Ie)date]} )) && [[ -z "${POWERLEVEL9K_DATE_FOREGROUND}" ]]; then
    typeset -g POWERLEVEL9K_DATE_FOREGROUND=250
  fi
  if (( ${moved[(Ie)macos_version]} + ${moved[(Ie)linux_version]} + ${moved[(Ie)os_version]} )); then
    define_os_version_segments
  fi
  if (( ${moved[(Ie)context]} )); then
    typeset -g POWERLEVEL9K_CONTEXT_DEFAULT_CONTENT_EXPANSION='${P9K_CONTENT}'
    typeset -g POWERLEVEL9K_CONTEXT_SUDO_CONTENT_EXPANSION='${P9K_CONTENT}'
  fi
  # p10k is loaded already when the plugin was, and has read the config before this: tell it to read it again
  if (( $+functions[p10k] )); then
    p10k reload
  fi
}

# Looking at the prompt without opening a shell: --prompt-preview, and the checks --doctor makes. The layout is worked
# out the way a login does it (the config's own p10k file read, then apply_prompt_top_line), in a subshell so nothing
# leaks. For each segment: the text it would show (for the ones whose text is known without a prompt), its colours, the
# contrast between them (the WCAG ratio, from the xterm 256 colour table; under 3 is hard to read), and whether
# powerlevel10k has a segment of that name at all (its source is searched, so a typo or an old p10k is found)

# A colour as three 0-255 numbers in COLOR_RGB: a number 0-255 (the xterm table), #rrggbb, or one of p10k's names.
# Empty if it is none of those

color_rgb () {
  setopt localoptions extendedglob
  local c="${(L)1}" n r
  local -a levels=( 0 95 135 175 215 255 )
  local -a basic=( "0 0 0" "128 0 0" "0 128 0" "128 128 0" "0 0 128" "128 0 128" "0 128 128" "192 192 192" "128 128 128" "255 0 0" "0 255 0" "255 255 0" "0 0 255" "255 0 255" "0 255 255" "255 255 255" )
  COLOR_RGB=()
  COLOR_INDEX=""
  case "${c}" in
    black) c=0 ;; red) c=1 ;; green) c=2 ;; yellow) c=3 ;; blue) c=4 ;; magenta) c=5 ;; cyan) c=6 ;; white) c=7 ;; grey|gray) c=8 ;;
  esac
  if [[ "${c}" == '#'[0-9a-f](#c6) ]]; then
    COLOR_RGB=( $(( 16#${c[2,3]} )) $(( 16#${c[4,5]} )) $(( 16#${c[6,7]} )) )
  elif [[ "${c}" == <0-255> ]]; then
    n=$(( c ))
    COLOR_INDEX="${n}"
    if (( n < 16 )); then
      COLOR_RGB=( ${=basic[n+1]} )
    elif (( n < 232 )); then
      n=$(( n - 16 ))
      COLOR_RGB=( ${levels[n/36+1]} ${levels[(n%36)/6+1]} ${levels[n%6+1]} )
    else
      r=$(( 8 + (n - 232) * 10 ))
      COLOR_RGB=( ${r} ${r} ${r} )
    fi
  fi
}

# The contrast ratio of two colours (1 to 21) in COLOR_CONTRAST, empty if either is not a colour we can work out

color_contrast () {
  local -a w=( 0.2126 0.7152 0.0722 ) lum=( 0 0 )
  local -F v
  local which i
  COLOR_CONTRAST=""
  for which in 1 2; do
    color_rgb "${@[which]}"
    (( ${#COLOR_RGB} == 3 )) || return 1
    for i in 1 2 3; do
      v=$(( ${COLOR_RGB[i]} / 255.0 ))
      if (( v <= 0.03928 )); then v=$(( v / 12.92 )); else v=$(( ((v + 0.055) / 1.055) ** 2.4 )); fi
      lum[which]=$(( lum[which] + w[i] * v ))
    done
  done
  printf -v COLOR_CONTRAST '%.1f' $(( (lum[1] > lum[2] ? lum[1] + 0.05 : lum[2] + 0.05) / (lum[1] > lum[2] ? lum[2] + 0.05 : lum[1] + 0.05) ))
}

# The terminal escape for a foreground and a background colour (what a swatch is drawn with)

color_escape () {
  local out="" c kind=38
  for c in "$1" "$2"; do
    color_rgb "${c}"
    if [[ -n "${COLOR_INDEX}" ]]; then
      out+=$'\e'"[${kind};5;${COLOR_INDEX}m"
    elif (( ${#COLOR_RGB} == 3 )); then
      out+=$'\e'"[${kind};2;${COLOR_RGB[1]};${COLOR_RGB[2]};${COLOR_RGB[3]}m"
    fi
    kind=48
  done
  print -rn -- "${out}"
}

# The text a segment shows, where it can be known without a prompt, in PSEG_TEXT

prompt_segment_text () {
  local f
  case "$1" in
    context)       PSEG_TEXT="${USER:-${LOGNAME}}@${HOST%%.*}" ;;
    os_version)    PSEG_TEXT="${OS_VERSION_TEXT}" ;;
    macos_version) PSEG_TEXT="${MACOS_VERSION_TEXT}" ;;
    linux_version) PSEG_TEXT="${LINUX_VERSION_TEXT}" ;;
    cpu_arch)      PSEG_TEXT="${CPUTYPE}" ;;
    date)          f="${POWERLEVEL9K_DATE_FORMAT}"; [[ -n "${f}" ]] || f='%D{%d.%m.}'; PSEG_TEXT="${(%)f}" ;;
    time)          f="${POWERLEVEL9K_TIME_FORMAT}"; [[ -n "${f}" ]] || f='%D{%H:%M:%S}'; PSEG_TEXT="${(%)f}" ;;
    os_icon)       PSEG_TEXT="(icon)" ;;
    *)             PSEG_TEXT="(when there is something to show)" ;;
  esac
}

# Is there a segment of this name? 0 yes, 1 no, 2 can't tell (powerlevel10k's source is not here). One of ours, or a
# prompt_<name> function in your p10k config, counts; the rest are looked for in p10k's source

prompt_segment_known () {
  local f
  if [[ -n "${functions[prompt_${1}]}" ]]; then
    return 0
  fi
  if [[ -z "${PSEG_SOURCE_TEXT+x}" ]]; then
    typeset -g PSEG_SOURCE_TEXT=""
    for f in "${P10K_HOME}/internal/p10k.zsh" "${ZINIT_HOME}/plugins/romkatv---powerlevel10k/internal/p10k.zsh"; do
      if [[ -r "${f}" ]]; then
        PSEG_SOURCE_TEXT="$(<${f})"
        break
      fi
    done
  fi
  [[ -n "${PSEG_SOURCE_TEXT}" ]] || return 2
  [[ "${PSEG_SOURCE_TEXT}" == *$'\n'"prompt_${1}()"* || "${PSEG_SOURCE_TEXT}" == *$'\n'"function prompt_${1}()"* ]]
}

# One row per segment, tab separated: line (top or bottom), side, segment, text, foreground, background, contrast and a
# verdict: ok, low (hard to read), same (the same colour as the background), default (a colour p10k picks) or unknown
# (no such segment). Printed from a subshell

prompt_layout_report () {
  (
    prompt_engine_is p10k || exit 0
    [[ -r "${P10K_INIT}" ]] && source "${P10K_INIT}" > /dev/null 2>&1
    apply_prompt_top_line > /dev/null 2>&1
    local -a left=( ${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS} ) right=( ${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS} )
    local row line side name base up fg bg verdict known idx
    print -r -- "background"$'\t'"${POWERLEVEL9K_BACKGROUND}"
    for side in left right; do
      local -a names=( ${(P)side} )
      idx=${names[(i)newline]}
      for (( i = 1; i <= ${#names}; i++ )); do
        name="${names[i]}"
        [[ "${name}" == newline ]] && continue
        line="bottom"
        (( i < idx )) && line="top"
        (( idx > ${#names} )) && line="bottom"
        base="${${name%%:*}%_joined}"
        up="${(U)base}"
        fg="${(P)${:-POWERLEVEL9K_${up}_FOREGROUND}}"
        bg="${(P)${:-POWERLEVEL9K_${up}_BACKGROUND}}"
        [[ -z "${bg}" ]] && bg="${POWERLEVEL9K_BACKGROUND}"
        # Ours are drawn with this colour when the config has not chosen one
        [[ "${base}" == (os|macos|linux)_version && -z "${fg}" ]] && fg=250
        prompt_segment_text "${base}"
        COLOR_CONTRAST=""
        verdict="ok"
        if [[ -z "${fg}" ]]; then
          verdict="default"
        else
          color_contrast "${fg}" "${bg}"
          if [[ -n "${COLOR_CONTRAST}" ]]; then
            (( COLOR_CONTRAST < 1.5 )) && verdict="same"
            (( COLOR_CONTRAST >= 1.5 && COLOR_CONTRAST < 3 )) && verdict="low"
          fi
        fi
        prompt_segment_known "${base}"
        [[ $? -eq 1 ]] && verdict="unknown"
        print -r -- "${line}"$'\t'"${side}"$'\t'"${name}"$'\t'"${PSEG_TEXT}"$'\t'"${fg}"$'\t'"${bg}"$'\t'"${COLOR_CONTRAST}"$'\t'"${verdict}"
      done
    done
  )
}

print_prompt_preview () {
  if ! prompt_engine_is p10k; then
    print -r -- "The prompt engine is ${PROMPT_ENGINE}: there is no powerlevel10k layout to preview"
    return 0
  fi
  local -a rows=( "${(@f)$( prompt_layout_report )}" ) cols
  local row side pad esc reset="" colour="false" back="" bottom_left="" bottom_right="" hard="" tops=0
  cols=( "${(@ps:\t:)rows[1]}" )
  back="${cols[2]}"
  [[ -t 1 && -z "${NO_COLOR}" ]] && colour="true"
  [[ "${colour}" == true ]] && reset=$'\e[0m'
  print -r -- "Prompt preview: powerlevel10k, $( [ "${PROMPT_TWO_LINE}" = "true" ] && print -r "two lines" || print -r "one line" ), background ${back:-not set}"
  print -r -- "(${P10K_INIT}; PROMPT_TOP_ELEMENTS=${PROMPT_TOP_ELEMENTS:-none}, PROMPT_TOP_RIGHT_ELEMENTS=${PROMPT_TOP_RIGHT_ELEMENTS:-none})"
  print
  print -r -- "Top line"
  for row in "${rows[@]:1}"; do
    cols=( "${(@ps:\t:)row}" )
    if [[ "${cols[1]}" == bottom ]]; then
      [[ "${cols[2]}" == left ]] && bottom_left+=" ${cols[3]}" || bottom_right+=" ${cols[3]}"
      [[ "${cols[8]}" == (low|same|unknown) ]] && hard+=" ${cols[3]}${${cols[7]:+ (${cols[7]})}:-}${${${cols[8]}:#low}:+ ${cols[8]}}"
      continue
    fi
    tops=$(( tops + 1 ))
    pad="${(r:26:)cols[4]}"
    esc=""
    [[ "${colour}" == true ]] && esc="$( color_escape "${cols[5]}" "${cols[6]}" )"
    printf '  %-6s %-14s %s%s%s  fg %-4s on %-4s %-15s %s\n' "${cols[2]}" "${cols[3]}" "${esc}" "${pad}" "${reset}" "${cols[5]:--}" "${cols[6]:--}" "${${cols[7]:+contrast ${cols[7]}}:-}" "${cols[8]}"
  done
  (( tops )) || print -r -- "  (nothing: the prompt has no top line)"
  print
  print -r -- "Bottom line (your ~/.p10k.zsh, left)${bottom_left:-: nothing}"
  [[ -n "${bottom_right}" ]] && print -r -- "                          (right)${bottom_right}"
  [[ -n "${hard}" ]] && print -r -- "  hard to read or unknown in it:${hard}"
  print
  print -r -- "Verdicts: ok is readable, low is under 3:1 contrast, same is the background's own colour, default is a colour"
  print -r -- "powerlevel10k picks, unknown is a name powerlevel10k has no segment for. Text in brackets shows when there is something."
}

# Key bindings for zsh-history-substring-search (called from the plugin lists in files/zinit):
# Up and Down search history for what has been typed so far. Terminals send different codes for
# the arrow keys depending on keypad mode (zsh switches to "application mode" while editing),
# so the usual ones are bound as well as the one terminfo names. A key whose widget isn't there
# (the plugin didn't load) is left alone

bind_history_search () {
  zmodload zsh/terminfo 2> /dev/null
  typeset -g HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
  # atuin, when it was given the arrow keys (ATUIN_BIND_UP=true), has them: binding them here would undo that
  [[ "${INSTALL_ATUIN}" == true && "${ATUIN_BIND_UP}" == true ]] && return 0
  local key
  for key in '^[[A' '^[OA' "${terminfo[kcuu1]}"; do
    [[ -n "${key}" ]] && bindkey "${key}" history-substring-search-up 2> /dev/null
  done
  for key in '^[[B' '^[OB' "${terminfo[kcud1]}"; do
    [[ -n "${key}" ]] && bindkey "${key}" history-substring-search-down 2> /dev/null
  done
  return 0
}

# Put the directory of ussuri's own completion on the fpath, ahead of compinit (which the plugin lists run later, or
# oh-my-zsh does). Nothing is run or forked: one directory test and an array assignment, with no repeats

add_completions_dir () {
  typeset -gU fpath
  if [[ -d "${WORK_DIR}/files/completions" ]]; then
    fpath=( "${WORK_DIR}/files/completions" ${fpath} )
  fi
  return 0
}

# Keep zsh-you-should-use quiet about the aliases a snippet adds (the plugin lists use these around
# common-aliases, which has dozens of short ones that would be mentioned all the time): mark_aliases notes
# the aliases there are, and ignore_new_aliases adds every alias and global alias that has appeared since to
# YSU_IGNORED_ALIASES and YSU_IGNORED_GLOBAL_ALIASES, which the plugin reads each time it checks a command.
# They can wrap any snippet or plugin in your own local.zsh

typeset -ga ALIASES_MARK GALIASES_MARK

mark_aliases () {
  ALIASES_MARK=( ${(k)aliases} )
  GALIASES_MARK=( ${(k)galiases} )
}

ignore_new_aliases () {
  local -a now
  now=( ${(k)aliases} )
  YSU_IGNORED_ALIASES+=( ${now:|ALIASES_MARK} )
  now=( ${(k)galiases} )
  YSU_IGNORED_GLOBAL_ALIASES+=( ${now:|GALIASES_MARK} )
  return 0
}

# common-aliases makes rm, cp and mv ask before overwriting (alias rm="rm -i"). The plugin lists call this after
# it to take those three back to the plain commands; an alias that is not exactly that (yours) is left alone.
# To have the questions back, add the aliases to your local.zsh (or ~/.zshrc.local), after the snippet

plain_file_aliases () {
  local cmd
  for cmd in rm cp mv; do
    [[ "${aliases[${cmd}]}" == "${cmd} -i" ]] && unalias ${cmd}
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

run_settings_drift () {
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

# Print names wrapped to about 100 columns, indented

print_wrapped_names () {
  local out="    " name
  for name in "$@"; do
    if (( ${#out} + ${#name} + 1 > 100 )); then
      print -r -- "${out}"
      out="    "
    fi
    out+="${name} "
  done
  print -r -- "${out}"
}

# One group of the package report. $1 is what the things are called (formulae, casks, taps, packages),
# $2 and $3 the words for the two states (not installed / installed, or not added / added), and
# REQUIRED, INSTALLED and EXPLICIT (arrays set by the caller) the names in your lists, what is
# there, and which of what is there you chose yourself rather than as a dependency. ALSO_LISTED is
# names that count as listed when looking for extras (a cask named in the formula list is not an extra
# cask). Names are compared without a tap prefix, and in lower case for taps.
# Adds to PKGDRIFT_MISSING and PKGDRIFT_EXTRA

package_drift_group () {
  local label="$1" absent="$2" present="$3" name
  local missing=() extra=() required_short=( ${(@)REQUIRED:t} ${(@)ALSO_LISTED:t} ) installed_short=( ${(@)INSTALLED:t} )
  if [ "${PKGDRIFT_LOWER}" = "true" ]; then
    required_short=( ${(@L)required_short} )
    installed_short=( ${(@L)installed_short} )
  fi
  for name in "${REQUIRED[@]}"; do
    if (( ! ${installed_short[(Ie)${${name:t}:l}]} )) && [ "${PKGDRIFT_LOWER}" = "true" ]; then
      missing+=( "${name}" )
    elif (( ! ${installed_short[(Ie)${name:t}]} )) && [ ! "${PKGDRIFT_LOWER}" = "true" ]; then
      missing+=( "${name}" )
    fi
  done
  for name in "${EXPLICIT[@]}"; do
    if [ "${PKGDRIFT_LOWER}" = "true" ]; then
      (( ${required_short[(Ie)${name:t:l}]} )) || extra+=( "${name}" )
    else
      (( ${required_short[(Ie)${name:t}]} )) || extra+=( "${name}" )
    fi
  done
  if (( ${#missing} )); then
    print -r -- "  ${label} ${absent} (${#missing}):"
    print_wrapped_names "${(@o)missing}"
  fi
  if (( ${#extra} )); then
    print -r -- "  ${label} ${present} but not in your lists (${#extra}):"
    print_wrapped_names "${(@o)extra}"
  fi
  # Kept for --adopt, one name to a line, by the kind of package (taps, formulae, casks or packages)
  (( ${#extra} )) && PKGDRIFT_EXTRAS[${label}]="${(pj:\n:)${(@o)extra}}"
  PKGDRIFT_MISSING=$(( PKGDRIFT_MISSING + ${#missing} ))
  PKGDRIFT_EXTRA=$(( PKGDRIFT_EXTRA + ${#extra} ))
}

# Compare what is installed with your package lists (all their layers): read only, from live queries to
# the package manager, never the cached lists. What is in a list but not installed is drift (-P would install
# it). What is installed because you chose it (brew leaves and casks, apt-mark showmanual, pacman -Qe...) but is
# in no list is only shown, as that is what you would add to a local list to keep it. Returns 1 for drift,
# 2 if there is nothing to compare with

typeset -gA PKGDRIFT_EXTRAS

run_package_drift () {
  PKGDRIFT_MISSING=0
  PKGDRIFT_EXTRA=0
  PKGDRIFT_EXTRAS=()
  PKGDRIFT_LOWER="false"
  local brew_cmd=""
  if is_osx; then
    brew_cmd="${commands[brew]}"
    if [ -z "${brew_cmd}" ]; then
      find_brew
      brew_cmd="${BREW_BIN}"
    fi
    if [ -z "${brew_cmd}" ]; then
      print -r -- "Package drift isn't available: Homebrew is not installed, so there is nothing to compare"
      return 2
    fi
    print -r -- "Packages (brew)"
    local REQUIRED INSTALLED EXPLICIT ALSO_LISTED formula_list cask_list everything
    read_required_list "${REQUIRED_FILE}"
    formula_list=( "${REQUIRED_LIST[@]}" )
    read_required_list "${REQUIRED_FILE:r}.cask"
    cask_list=( "${REQUIRED_LIST[@]}" )
    # brew install falls back to a cask for a name that is not a formula, and -P counts either as installed,
    # so a name in the formula list that is installed as a cask is neither missing nor an extra cask
    everything=( ${(f)"$( "${brew_cmd}" list 2> /dev/null )"} )
    read_required_list "${REQUIRED_FILE:r}.tap"
    REQUIRED=( "${REQUIRED_LIST[@]}" )
    INSTALLED=( ${(f)"$( "${brew_cmd}" tap 2> /dev/null )"} )
    EXPLICIT=( "${INSTALLED[@]}" )
    ALSO_LISTED=()
    PKGDRIFT_LOWER="true"
    package_drift_group "taps" "not added" "added"
    PKGDRIFT_LOWER="false"
    REQUIRED=( "${formula_list[@]}" )
    INSTALLED=( "${everything[@]}" )
    EXPLICIT=( ${(f)"$( "${brew_cmd}" leaves 2> /dev/null )"} )
    ALSO_LISTED=( "${cask_list[@]}" )
    package_drift_group "formulae" "not installed" "installed"
    REQUIRED=( "${cask_list[@]}" )
    EXPLICIT=( ${(f)"$( "${brew_cmd}" list --cask 2> /dev/null )"} )
    ALSO_LISTED=( "${formula_list[@]}" )
    package_drift_group "casks" "not installed" "installed"
  elif is_linux; then
    if [ -z "${PKG_MANAGER}" ]; then
      print -r -- "Package drift isn't available: Linux distribution '${LSB_ID:-unknown}' has no supported package manager"
      return 2
    fi
    if (( ! $+commands[${PKG_TOOL}] )); then
      print -r -- "Package drift isn't available: ${PKG_TOOL} is not installed"
      return 2
    fi
    print -r -- "Packages (${PKG_MANAGER})"
    local REQUIRED INSTALLED EXPLICIT ALSO_LISTED
    ALSO_LISTED=()
    read_required_list "${REQUIRED_FILE}"
    REQUIRED=( "${REQUIRED_LIST[@]}" )
    INSTALLED=( ${(f)"$( eval "${PKG_LIST_CMD}" 2> /dev/null )"} )
    EXPLICIT=( ${(f)"$( eval "${PKG_MANUAL_CMD:-${PKG_LIST_CMD}}" 2> /dev/null )"} )
    package_drift_group "packages" "not installed" "installed"
  else
    print -r -- "Package drift isn't available on ${OS_NAME}"
    return 2
  fi
  print
  if (( PKGDRIFT_MISSING )); then
    print -r -- "${PKGDRIFT_MISSING} packages from your lists are not installed (-P installs them)${${PKGDRIFT_EXTRA#0}:+; ${PKGDRIFT_EXTRA} installed ones are not in your lists (shown for information)}"
    return 1
  fi
  print -r -- "Everything in your lists is installed${${PKGDRIFT_EXTRA#0}:+; ${PKGDRIFT_EXTRA} installed ones are not in your lists (shown for information)}"
}

# --drift --adopt: add what is installed but in no list to your local list, the one that --drift said it is
# missing from, asking about each package (y, n, a to add it and all that are left, q to stop; or --yes to add
# them all, --dryrun to see what would be added). The list is local.<ext> next to the shipped one, or with -M or
# -H that profile's or machine's, and is backed up, then replaced in one rename. Nothing is installed or removed

adopt_packages () {
  local label ext dir file tmp name reply everyone="false" stop="false" total=0
  local -a names accepted existing
  if [ -z "${REQUIRED_FILE}" ]; then
    print -r -- "Nothing to adopt: there is no package list for this system"
    return 1
  fi
  layer_choice || return 1
  dir="${REQUIRED_FILE:h}"
  if (( ! ${#PKGDRIFT_EXTRAS} )); then
    print -r -- "Nothing to adopt: everything installed is already in your lists"
    return 0
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] && [ ! "${ASSUME_YES}" = "true" ] && [[ ! -t 0 ]]; then
    print -u2 -r -- "Error:          --adopt asks about each package, so it needs a terminal (or --yes to add them all, --dryrun to see them)"
    return 1
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] && ! have_lock; then
    print -u2 -r -- "Error:          another ussuri run holds the lock (${LOCK_FILE}), try again in a moment"
    return 1
  fi
  print
  for label in taps formulae casks packages; do
    [ "${stop}" = "true" ] && break
    names=( ${(f)PKGDRIFT_EXTRAS[${label}]} )
    (( ${#names} )) || continue
    case "${label}" in
      taps)     ext="tap" ;;
      formulae) ext="brew" ;;
      casks)    ext="cask" ;;
      *)        ext="${REQUIRED_FILE:e}" ;;
    esac
    # The same layout as local_layer_files (which only lists the files that exist)
    case "${LAYER_KIND}" in
      profile) file="${dir}/profiles/${LAYER_NAME}/local.${ext}" ;;
      host)    file="${dir}/hosts/${LAYER_NAME}/local.${ext}" ;;
      *)       file="${dir}/local.${ext}" ;;
    esac
    existing=()
    [ -r "${file}" ] && existing=( "${(@f)$(<${file})}" )
    accepted=()
    for name in "${names[@]}"; do
      # Already there (a name is the whole line)
      (( ${existing[(Ie)${name}]} )) && continue
      if [ "${DO_DRYRUN}" = "true" ]; then
        accepted+=( "${name}" )
      elif [ "${ASSUME_YES}" = "true" ] || [ "${everyone}" = "true" ]; then
        accepted+=( "${name}" )
      else
        reply=""
        read -r "reply?Add ${name} to ${file:t}? [y/n] (a adds all that are left, q stops): "
        case "${reply}" in
          [yY]*) accepted+=( "${name}" ) ;;
          [aA]*) accepted+=( "${name}" ); everyone="true" ;;
          [qQ]*) stop="true"; break ;;
        esac
      fi
    done
    (( ${#accepted} )) || continue
    total=$(( total + ${#accepted} ))
    if [ "${DO_DRYRUN}" = "true" ]; then
      print -r -- "Would add to ${file}: ${accepted[*]}"
      continue
    fi
    tmp="${file}.tmp.$$"
    ADOPT_NEW_LINES=( "${existing[@]}" )
    (( ${#ADOPT_NEW_LINES} == 1 )) && [[ -z "${ADOPT_NEW_LINES[1]}" ]] && ADOPT_NEW_LINES=()
    ADOPT_NEW_LINES+=( "# added by ussuri --drift --adopt, ${DATE}" "${accepted[@]}" )
    execute_command "mkdir -p ${(q)file:h}"
    if [ -e "${file}" ]; then
      backup_user_file "${file}" "packages-${ext}${LAYER_NAME:+-${LAYER_KIND}-${LAYER_NAME}}"
      execute_command "cp -p ${(q)file} ${(q)tmp}"
    fi
    execute_command "write_adopted_lines ${(q)tmp}"
    execute_command "mv -f ${(q)tmp} ${(q)file}"
    if [ -e "${tmp}" ]; then
      rm -f -- "${tmp}"
      print -u2 -r -- "Error:          ${file} was not changed"
      return 1
    fi
    print -r -- "Added to ${file}: ${accepted[*]}"
  done
  if (( total == 0 )); then
    print -r -- "Nothing added"
  elif [ ! "${DO_DRYRUN}" = "true" ]; then
    print -r -- "${total} added. They are installed already, so this only keeps them from being extras: -P installs from the lists on another machine"
  fi
  return 0
}

write_adopted_lines () {
  print -r -l -- "${ADOPT_NEW_LINES[@]}" > "$1"
}

# --drift [settings|packages|all]: what differs from what ussuri would apply or install. Exit status 1 if
# either differs, 0 if neither does, 2 if there was nothing to compare

run_drift () {
  local what="${1:-all}" settings_rc=2 packages_rc=2
  case "${what}" in
    all|settings|packages)
      ;;
    *)
      print -r -- "Unknown drift '${what}': choose settings, packages or all"
      return 2
      ;;
  esac
  if [ "${what}" = "all" ] || [ "${what}" = "settings" ]; then
    [ "${what}" = "all" ] && print -r -- "Settings"
    run_settings_drift
    settings_rc=$?
  fi
  if [ "${what}" = "all" ] || [ "${what}" = "packages" ]; then
    [ "${what}" = "all" ] && print
    run_package_drift
    packages_rc=$?
  fi
  (( settings_rc == 1 || packages_rc == 1 )) && return 1
  (( settings_rc == 0 || packages_rc == 0 )) && return 0
  return 2
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
    if [ "${DO_CONFIRM}" = "true" ] && [ ! "${ASSUME_YES}" = "true" ]; then
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
  # The name includes the command, so the same tool run with different options (atuin's flags) has a cache for each
  CACHE_KEY="${CACHE_CMD//[^[:alnum:]]/_}"
  CACHE_FILE="${CACHE_DIR}/${CACHE_BIN//\//_}-${CACHE_KEY[1,120]}.zsh"
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
  # USSURI_OS_REL overrides the kernel release, so the tests behave the same on any host
  OS_REL="${USSURI_OS_REL}"
  if [ -z "${OS_REL}" ]; then
    OS_REL=$( uname -r )
  fi
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
  set_env "TAPS_FILE"         "${WORK_DIR}/brew.taps"
  set_env "REQUIRED_FILE"     "${WORK_DIR}/files/packages/macos.brew"
  if [ "${DO_INSTALL}" = "false" ]; then
    if [ ! -f "${REQUIRED_FILE}" ]; then
      copy_support_files
    fi
  fi
}

# Read the required package list (one package per line, ignoring blank lines and comments)
# Only called when the list is processed, not on every shell

# The files that make up a package list, in order: the shipped one, then the local layers on top of it.
# Sets PACKAGE_LAYERS to the ones that exist

package_layer_files () {
  PACKAGE_LAYERS=()
  if [ -f "$1" ]; then
    PACKAGE_LAYERS+=( "$1" )
  fi
  local_layer_files "${1:h}" "${1:e}"
  PACKAGE_LAYERS+=( "${LOCAL_LAYERS[@]}" )
}

# Read a package list (default: this system's) into REQUIRED_LIST: one package per line, ignoring blank
# lines and comments, layer by layer, without repeats. A line !name takes a package out of what the
# earlier layers added (matched exactly, not as a pattern), and a later layer can put it back

read_required_list () {
  setopt localoptions extendedglob
  REQUIRED_LIST=()
  package_layer_files "${1:-${REQUIRED_FILE}}"
  local file line name i
  for file in "${PACKAGE_LAYERS[@]}"; do
    for line in ${${(f)"$(<${file})"}:#(\#*|[[:space:]]#)}; do
      if [[ "${line}" == '!'* ]]; then
        name="${line#!}"
        while (( i = ${REQUIRED_LIST[(Ie)${name}]} )); do
          REQUIRED_LIST[i]=()
        done
      else
        REQUIRED_LIST+=( "${line}" )
      fi
    done
  done
  REQUIRED_LIST=( ${(u)REQUIRED_LIST} )
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
      PKG_MANUAL_CMD="apt-mark showmanual"
      PKG_PREPARE="apt-get update"
      PKG_INSTALL="apt install -y"
      # -y answers apt's own questions, but not debconf's dialogs (configuring a package), which
      # --yes turns off too. env, as sudo would otherwise drop the variable
      if [ "${ASSUME_YES}" = "true" ]; then
        PKG_INSTALL="env DEBIAN_FRONTEND=noninteractive apt install -y"
      fi
      ;;
    pacman)
      PKG_TOOL="pacman"
      PKG_LIST_NAME="arch.pacman"
      if [ "${OS_ID}" = "endeavouros" ]; then
        PKG_LIST_NAME="endeavouros.pacman"
      fi
      PKG_LIST_CMD="pacman -Q | awk '{ print \$1 }'"
      PKG_MANUAL_CMD="pacman -Qqe"
      # Not -Sy: syncing the database without upgrading is an unsupported partial upgrade on Arch
      PKG_INSTALL="pacman --noconfirm --needed -S"
      ;;
    dnf)
      PKG_TOOL="dnf"
      PKG_LIST_NAME="fedora.dnf"
      PKG_LIST_CMD="rpm -qa --qf '%{NAME}\\n'"
      PKG_MANUAL_CMD="dnf repoquery --userinstalled --queryformat '%{name}\\n'"
      PKG_INSTALL="dnf install -y"
      ;;
    apk)
      PKG_TOOL="apk"
      PKG_LIST_NAME="alpine.apk"
      PKG_LIST_CMD="apk info"
      # What you asked for is in the world file, with any version constraint (curl=8.0, foo>1)
      PKG_MANUAL_CMD="sed 's/[=<>~].*//' \"\${APK_WORLD_FILE:-/etc/apk/world}\""
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
  resolve_prompt_engine
  set_env "PROMPT_ENGINE"       "${PROMPT_ENGINE}"
  set_env "PROMPT_TWO_LINE"     "true"
  set_env "PROMPT_TOP_ELEMENTS" "context os_version cpu_arch"
  set_env "PROMPT_TOP_RIGHT_ELEMENTS" "date"
  set_env "INSTALL_POSH"        "${PROMPT_WANT_POSH}"
  set_env "INSTALL_OZSH"        "false"
  set_env "INSTALL_FONTS"       "true"
  set_env "INSTALL_P10K"        "${PROMPT_WANT_P10K}"
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
  set_env "DO_PROMPT_PREVIEW"   "false"
  set_env "DO_EXPORT"           "false"
  set_env "DO_IMPORT"           "false"
  set_env "DO_CONFIG"           "false"
  set_env "DO_DOTFILES_CHECK"   "false"
  set_env "DO_UNLINK"           "false"
  set_env "DO_BACKUPS"          "false"
  set_env "DO_DEFAULTS_UNDO"    "false"
  set_env "JOURNAL_FILE"        "${WORK_DIR}/defaults.journal"
  set_env "DO_DRIFT"            "false"
  set_env "DO_GNOME_DEFAULTS"   "false"
  set_env "DO_TOOLS_CHECK"      "false"
  set_env "DO_ZOXIDE_CHECK"     "false"
  set_env "INSTALL_ZOXIDE"      "true"
  set_env "INSTALL_FNM"         "false"
  set_env "INSTALL_RUSTUP"      "false"
  set_env "INSTALL_UV"          "false"
  set_env "INSTALL_MISE"        "false"
  set_env "INSTALL_ATUIN"       "false"
  set_env "ATUIN_BIND_UP"       "false"
  set_env "ATUIN_IMPORT"        "true"
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
  set_env "DOTFILES_REPO"       ""
  set_env "DOTFILES_REF"        ""
  # One profile and machine name for dotfiles, packages and plugins. DOTFILES_PROFILE and DOTFILES_HOST
  # (the older names) still override them for dotfiles alone
  set_env "PROFILE"             ""
  set_env "MACHINE"             "${HOST%%.*}"
  check_layer_name "PROFILE"
  check_layer_name "MACHINE"
  set_env "DOTFILES_PROFILE"    "${PROFILE}"
  set_env "DOTFILES_HOST"       "${MACHINE}"
  check_layer_name "DOTFILES_PROFILE"
  check_layer_name "DOTFILES_HOST"
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
  set_env "ASSUME_YES"          "false"
  set_env "UPDATE_HINT"         "false"
  set_env "SCRIPT_URL"          "https://raw.githubusercontent.com/lateralblast/ussuri/refs/heads/main/ussuri.zsh"
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
  resolve_prompt_engine
  set_env "INSTALL_POSH"        "${PROMPT_WANT_POSH}"
  set_env "INSTALL_OZSH"        "false"
  set_env "INSTALL_FONTS"       "true"
  set_env "INSTALL_P10K"        "${PROMPT_WANT_P10K}"
  set_env "DO_DEFAULTS_CHECK"   "true"
  set_env "DO_PACKAGE_CHECK"    "false"
  set_env "DO_ZINIT_CHECK"      "true"
  set_env "DO_PYENV_CHECK"      "true"
  set_env "DO_RBENV_CHECK"      "true"
  set_env "DO_TOOLS_CHECK"      "true"
  set_env "DO_ZOXIDE_CHECK"     "true"
  set_env "DO_FONTS_CHECK"      "true"
  set_env "DO_POSH_CHECK"       "${PROMPT_WANT_POSH}"
  set_env "DO_ZOSH_CHECK"       "false"
  set_env "DO_P10K_CHECK"       "${PROMPT_WANT_P10K}"
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
  # Local: these used to be globals, so every message overwrote the TYPE a caller had set (which
  # made check_osx_package install casks, the Nerd Font included, as plain formulae)
  local MESSAGE="$1"
  local TYPE="$2"
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
      if [[ "${DO_TIMING}" == "true" ]]; then
        timed_plugin_line "${LINE}"
      else
        execute_command "${LINE}"
      fi
    fi
  done
}

# --timing: run one line of a plugin list and note how long it took, named by the plugin it loads when it can be told

timed_plugin_line () {
  local started="${EPOCHREALTIME}" name="${1[1,40]}"
  [[ "$1" =~ 'zinit (light|snippet|load) ([^ ;]+)' ]] && name="${match[2]}"
  execute_command "$1"
  TIMING_LINES+=( "${name}" )
  TIMING_LINE_SECONDS+=( $(( EPOCHREALTIME - started )) )
}

# Help information. One row of the help: the short switch (if it has one), the long one with its value, what it does and, if it has
# one, what it is now (the default for a login or the value from your config and the switches before --help).
# printf is a builtin, so the columns line up without starting anything

help_row () {
  local flags
  if [[ -n "$1" ]]; then
    flags="$1, $2"
  else
    flags="    $2"
  fi
  if [[ -n "$4" ]]; then
    printf '  %-31s %-46s (default: %s)\n' "${flags}" "$3" "$4"
  else
    printf '  %-31s %s\n' "${flags}" "$3"
  fi
}

help_heading () {
  printf '\n%s\n' "$1"
}

help_value () {
  printf '  %-26s %s\n' "$1" "$2"
}

print_help () {
  set_defaults
  printf '\nUsage: %s [OPTIONS...]\n\n' "${SCRIPT_FILE}"
  print -r -- "With no switches it runs as a login script. With switches it is a command line tool"
  print -r -- "that does only what you ask. A default on a row is the current value of what the switch"
  print -r -- "sets: from your config or the environment, or the built in one."

  help_heading "Look, without changing anything"
  help_row "-h" "--help"           "Print this usage"
  help_row "-V" "--version"        "Print the version"
  help_row "-e" "--changelog"      "Print the changelog"
  help_row "-x" "--doctor"         "Check the environment (read only)"
  help_row "-Y" "--fix"            "With --doctor: repair the safe problems"
  help_row "-G" "--drift [WHAT]"   "Report drift: settings, packages or all"
  help_row "-a" "--adopt"          "With --drift: add installed packages to your list"
  help_row "-j" "--timing"         "Run as a login and time each step of it"
  help_row ""   "--prompt-preview" "Show the prompt's top line, colours and checks"

  help_heading "Install, update and undo"
  help_row "-I" "--install"        "Install as ~/.zshrc (the old one is kept)"
  help_row "-U" "--update"         "Update the script and its files"          "${DO_UPDATE_CHECK}"
  help_row "-C" "--check"          "Check for a newer version"                "${DO_VERSION_CHECK}"
  help_row "-B" "--backups"        "List the .zshrc backups"
  help_row "-R" "--rollback [N|update]" "Restore .zshrc backup N, or undo --update"  "newest"
  help_row "-X" "--uninstall"      "Restore the .zshrc from before ussuri"
  help_row "-J" "--defaults-undo [N|list]" "Undo a run of defaults changes"   "newest"
  help_row "-u" "--unlink"         "Unlink the dotfiles"

  help_heading "Settings (${CONFIG_FILE})"
  help_row "-k" "--config"         "Create the config file"
  help_row ""   "--set NAME VALUE" "Save a setting, for every new shell"
  help_row ""   "--unset NAME"     "Remove a setting"
  help_row ""   "--get [NAME]"     "Show a setting (or all) and where it is from"
  help_row "-K" "--edit"           "Edit the config in \$EDITOR, checked first"
  help_row "-M" "--profile NAME"   "Profile; with --set/--unset/--edit its file"  "${PROFILE:-none}"
  help_row "-H" "--host NAME"      "Machine; with --set/--unset/--edit its file"  "${MACHINE}"
  help_row ""   "--export [FILE]"  "Write your config, local lists and dotfiles to FILE"
  help_row ""   "--import FILE"    "Read them back (on a new machine); keeps what it replaces"

  help_heading "Set up"
  help_row "-A" "--doall"          "Do everything that is enabled"
  help_row "-i" "--inline"         "Use the login (inline) defaults"
  help_row "-b" "--build"          "Build sources"                            "${DO_BUILD}"
  help_row "-D" "--defaults"       "Set the system defaults"                  "${DO_DEFAULTS_CHECK}"
  help_row "-E" "--prompt NAME"    "Prompt engine: p10k, posh or none"        "${PROMPT_ENGINE}"
  help_row "-f" "--fonts"          "Install the fonts"                        "${DO_FONTS_CHECK}"
  help_row "-L" "--dotfiles"       "Link the dotfiles"                        "${DO_DOTFILES_CHECK}"
  help_row "-m" "--manager NAME"   "Plugin manager: zinit or oh-my-zsh"       "${PLUGIN_MANAGER}"
  help_row "-n" "--notheme"        "Do not use a zsh theme"
  help_row "-N" "--noenv"          "Do not set up the tools' environment"
  help_row "-o" "--ohmyposh"       "Install oh my posh"                       "${DO_POSH_CHECK}"
  help_row "-O" "--ohmyzsh"        "Install oh my zsh"                        "${DO_ZOSH_CHECK}"
  help_row "-p" "--pyenv"          "Do the pyenv check"                       "${DO_PYENV_CHECK}"
  help_row "-P" "--packages"       "Do the packages check"                    "${DO_PACKAGE_CHECK}"
  help_row "-r" "--rbenv"          "Do the rbenv check"                       "${DO_RBENV_CHECK}"
  help_row "-s" "--sudoers"        "Do the sudoers check"                     "${DO_SUDOERS_CHECK}"
  help_row "-S" "--sudoersentry ENTRY" "Set the sudoers entry"                    "${SUDOERS_ENTRY}"
  help_row "-T" "--p10k"           "Do the p10k config"                       "${DO_P10K_CHECK}"
  help_row "-W" "--tool NAME"      "Install fnm, rustup, uv, mise or atuin"
  help_row "-z" "--zinit"          "Do the zinit check"                       "${DO_ZINIT_CHECK}"
  help_row "-Z" "--zshtheme NAME"  "Set the zsh theme"                        "${ZSH_THEME}"
  help_row "-g" "--gopath DIR"     "Set GOPATH"                               "${GO_HOME}"
  help_row "-l" "--location DIR"   "Set the start directory"                  "${START_DIR}"

  help_heading "How it runs"
  help_row "-t" "--dryrun"         "Show the commands, run none"              "${DO_DRYRUN}"
  help_row "-v" "--verbose"        "Verbose output"                           "${DO_VERBOSE}"
  help_row "-c" "--confirm"        "Confirm each command"                     "${DO_CONFIRM}"
  help_row "-y" "--yes"            "Answer yes, no prompts"                   "${ASSUME_YES}"
  help_row "-d" "--debug"          "Debug output (set -x)"                    "${DO_DEBUG}"
  help_row "-F" "--force"          "Force: clear the lock, ignore the stamps" "${DO_FORCE}"

  print
  print -r -- "Short switches can be bundled (-vt). Several have other long names, listed in the README."
  SET_ENV_FORCE="true" set_inline_defaults
  help_heading "What a login does with no switches"
  help_value "Build"               "${DO_BUILD}"
  help_value "Confirm"             "${DO_CONFIRM}"
  help_value "Update check"        "${DO_UPDATE_CHECK}"
  help_value "Debug"               "${DO_DEBUG}"
  help_value "Verbose"             "${DO_VERBOSE}"
  help_value "Defaults check"      "${DO_DEFAULTS_CHECK}"
  help_value "Fonts check"         "${DO_FONTS_CHECK}"
  help_value "Package check"       "${DO_PACKAGE_CHECK}"
  help_value "zinit check"         "${DO_ZINIT_CHECK}"
  help_value "pyenv check"         "${DO_PYENV_CHECK}"
  help_value "rbenv check"         "${DO_RBENV_CHECK}"
  help_value "p10k check"          "${DO_P10K_CHECK}"
  help_value "oh-my-posh check"    "${DO_POSH_CHECK}"
  help_value "oh-my-zsh check"     "${DO_ZOSH_CHECK}"
  help_value "Sudoers check"       "${DO_SUDOERS_CHECK}"
  help_value "PKGCONFIG check"     "${DO_PKGCONFIG_CHECK}"
  help_value "CPPFLAGS check"      "${DO_CPPFLAGS_CHECK}"
  help_value "LDFLAGS check"       "${DO_LDFLAGS_CHECK}"
  help_value "Plugin manager"      "${PLUGIN_MANAGER}"
  help_value "Start directory"     "${START_DIR}"
  print
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
  CURRENT=$( ls -aOl "${FILE}" 2> /dev/null | sed -n 2p | awk '{print $5}' )
  # ls -O (the file flags) is BSD only. Where it can't be read there is nothing to compare, which is
  # not a setting that differs
  if [ -z "${CURRENT}" ]; then
    verbose_message "The flags of ${FILE} can't be read here, skipping" "warn"
    return
  fi
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

# The defaults journal: ~/.ussuri/defaults.journal. Every setting the script changes is recorded as one
# tab separated line (run, domain, key, previous type, previous value, value set), each field quoted
# with ${(q)} so any value is stored on one line and read back with ${(Q)}, never with eval. A run
# is one apply. Entries are only written once a read back shows the write took effect, so a write
# that was declined (--confirm), refused or ignored by the system leaves nothing to undo.
# --defaults-undo reverts a run: UNDONE lines mark the runs already reverted.

journal_field () {
  print -r -- "${(q)1}"
}

journal_unfield () {
  print -r -- "${(Q)1}"
}

journal_default () {
  [ "${DO_DRYRUN}" = "true" ] && return 0
  JOURNAL_NOW=$( defaults read "$1" "$2" 2> /dev/null ) || return 0
  [ "${JOURNAL_NOW}" = "$5" ] || return 0
  check_dir_exists "${JOURNAL_FILE:h}"
  print -r -- "${DATE_SUFFIX}"$'\t'"${(q)1}"$'\t'"${(q)2}"$'\t'"${(q)3}"$'\t'"${(q)4}"$'\t'"${(q)5}" >> "${JOURNAL_FILE}"
}

# Read the journal into JOURNAL_ENTRIES (lines), JOURNAL_ORDER (run ids, oldest first), JOURNAL_COUNT
# (settings per run) and JOURNAL_ACTIVE (the runs not yet undone). Fails if there are no runs

read_journal () {
  JOURNAL_ORDER=()
  JOURNAL_ACTIVE=()
  JOURNAL_ENTRIES=()
  typeset -gA JOURNAL_COUNT JOURNAL_DONE
  JOURNAL_COUNT=()
  JOURNAL_DONE=()
  [ -f "${JOURNAL_FILE}" ] || return 1
  local line fields run
  for line in ${(f)"$(<${JOURNAL_FILE})"}; do
    [[ "${line}" == \#* ]] && continue
    fields=( "${(@ps:\t:)line}" )
    if [ "${fields[1]}" = "UNDONE" ]; then
      JOURNAL_DONE[${fields[2]}]=1
      continue
    fi
    run="${fields[1]}"
    if (( ! ${+JOURNAL_COUNT[${run}]} )); then
      JOURNAL_ORDER+=( "${run}" )
      JOURNAL_COUNT[${run}]=0
    fi
    JOURNAL_COUNT[${run}]=$(( JOURNAL_COUNT[${run}] + 1 ))
    JOURNAL_ENTRIES+=( "${line}" )
  done
  for run in "${JOURNAL_ORDER[@]}"; do
    (( ${+JOURNAL_DONE[${run}]} )) || JOURNAL_ACTIVE+=( "${run}" )
  done
  (( ${#JOURNAL_ORDER} ))
}

# A run id is the date the apply started, as dd_mm_yyyy_HH_MM_SS

journal_when () {
  print -r -- "${1[7,10]}-${1[4,5]}-${1[1,2]} ${1[12,13]}:${1[15,16]}:${1[18,19]}"
}

print_journal_runs () {
  local i n=1
  if ! read_journal || (( ! ${#JOURNAL_ACTIVE} )); then
    print -r -- "Nothing to undo: no settings have been changed by ${SCRIPT_NAME} (since the journal was added in 1.5.7), or they have all been undone"
    return 1
  fi
  print -r -- "  #  Saved                Changed"
  for (( i = ${#JOURNAL_ACTIVE}; i >= 1; i-- )); do
    printf '%3d  %s  %d settings\n' "${n}" "$( journal_when "${JOURNAL_ACTIVE[i]}" )" "${JOURNAL_COUNT[${JOURNAL_ACTIVE[i]}]}"
    n=$(( n + 1 ))
  done
  print -r -- "Undo one with --defaults-undo N (1 is the newest). --dryrun shows what it would do."
}

# Revert a run of the journal (the newest by default, or the Nth newest). A setting is only reverted if
# it still has the value the script gave it: one you changed yourself since is left alone and reported

do_defaults_undo () {
  local target="${1:-1}" run i line fields dom key otype oval nval cur when restore_word="Restored"
  if ! is_osx; then
    print -r -- "Undoing defaults is only available on OS X (the journal is of defaults writes)"
    return 2
  fi
  if [ "${target}" = "list" ]; then
    print_journal_runs
    return
  fi
  if ! read_journal || (( ! ${#JOURNAL_ACTIVE} )); then
    print_journal_runs
    return 1
  fi
  if [[ "${target}" != <-> ]] || (( target < 1 || target > ${#JOURNAL_ACTIVE} )); then
    print -r -- "There is no run '${target}' to undo (see --defaults-undo list)"
    return 1
  fi
  run="${JOURNAL_ACTIVE[-target]}"
  when=$( journal_when "${run}" )
  [ "${DO_DRYRUN}" = "true" ] && restore_word="Would restore"
  UNDO_TOTAL=0
  UNDO_DONE=0
  UNDO_SKIPPED=0
  for (( i = ${#JOURNAL_ENTRIES}; i >= 1; i-- )); do
    line="${JOURNAL_ENTRIES[i]}"
    fields=( "${(@ps:\t:)line}" )
    [ "${fields[1]}" = "${run}" ] || continue
    dom="${(Q)fields[2]}"
    key="${(Q)fields[3]}"
    otype="${(Q)fields[4]}"
    oval="${(Q)fields[5]}"
    nval="${(Q)fields[6]}"
    UNDO_TOTAL=$(( UNDO_TOTAL + 1 ))
    cur=$( defaults read "${dom}" "${key}" 2> /dev/null )
    if (( $? )); then
      if [ "${otype}" = "__unset__" ]; then
        UNDO_DONE=$(( UNDO_DONE + 1 ))
      else
        print -r -- "  skipped ${dom} ${key}: no longer set (it was set to ${nval})"
        UNDO_SKIPPED=$(( UNDO_SKIPPED + 1 ))
      fi
      continue
    fi
    if [ ! "${cur}" = "${nval}" ]; then
      print -r -- "  skipped ${dom} ${key}: changed since (now ${cur}, it was set to ${nval})"
      UNDO_SKIPPED=$(( UNDO_SKIPPED + 1 ))
      continue
    fi
    case "${otype}" in
      __unset__)
        execute_command "defaults delete ${(q)dom} ${(q)key}"
        ;;
      boolean)
        if [ "${oval}" = "1" ]; then
          execute_command "defaults write ${(q)dom} ${(q)key} -bool true"
        else
          execute_command "defaults write ${(q)dom} ${(q)key} -bool false"
        fi
        ;;
      integer)
        execute_command "defaults write ${(q)dom} ${(q)key} -int ${(q)oval}"
        ;;
      float)
        execute_command "defaults write ${(q)dom} ${(q)key} -float ${(q)oval}"
        ;;
      string)
        execute_command "defaults write ${(q)dom} ${(q)key} -string ${(q)oval}"
        ;;
      *)
        print -r -- "  skipped ${dom} ${key}: its previous value was of type ${otype}, which can't be restored here (it is now ${cur})"
        UNDO_SKIPPED=$(( UNDO_SKIPPED + 1 ))
        continue
        ;;
    esac
    UNDO_DONE=$(( UNDO_DONE + 1 ))
    [[ "${dom}" =~ "finder" ]] && set_env "RESTART_FINDER" "true" "force"
    [[ "${dom}" =~ "dock" ]] && set_env "RESTART_DOCK" "true" "force"
  done
  print -r -- "${restore_word} ${UNDO_DONE} of ${UNDO_TOTAL} settings from the run of ${when}${${UNDO_SKIPPED#0}:+; ${UNDO_SKIPPED} skipped}"
  # With --confirm some may have been declined, so the run is left to be undone again
  if [ ! "${DO_DRYRUN}" = "true" ] && [ ! "${DO_CONFIRM}" = "true" ]; then
    print -r -- "UNDONE"$'\t'"${run}" >> "${JOURNAL_FILE}"
  fi
  restart_osx_services
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
    # What it was (type and value, or not set) is kept so --defaults-undo can put it back
    D_OLD_TYPE="__unset__"
    if (( ! D_STATUS )); then
      D_OLD_TYPE=$( defaults read-type "${D_DOMAIN}" "${D_PARAM}" 2> /dev/null )
      D_OLD_TYPE="${${D_OLD_TYPE#Type is }:-unknown}"
    fi
    execute_command "defaults write ${(q)D_DOMAIN} ${(q)D_PARAM} -${D_TYPE} ${(q)D_VALUE}"
    journal_default "${D_DOMAIN}" "${D_PARAM}" "${D_OLD_TYPE}" "${D_CURRENT}" "${D_CHECK}"
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
      # Your own plugins: files/zinit/local.zsh (and the profile and machine layers), same format, run after
      # the shipped list and never overwritten by updates or --install. (It runs after the shipped list's completions step,
      # so a plugin that only ships completion files may need a restart to pick them up)
      local_layer_files "${WORK_DIR}/files/zinit" "zsh"
      for ZINIT_LOCAL in "${LOCAL_LAYERS[@]}"; do
        verbose_message "Loading your plugins from ${ZINIT_LOCAL}"
        execute_from_file "${ZINIT_LOCAL}"
      done
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

# atuin: searchable shell history (Ctrl-R), kept in a local database. Off unless INSTALL_ATUIN=true or
# --tool atuin, because it records every command you run. It is installed only through a package manager
# where atuin's own documentation lists one (Homebrew, pacman, nix): its official install script signs you
# up to Atuin Cloud, so it is never run. Sync is never set up: ussuri does not register, log in or sync,
# so history stays on this machine until you do that yourself (atuin register / atuin login). The init
# output goes through the init cache, with a cache for each flag set. The up arrow stays with history
# substring search unless ATUIN_BIND_UP=true. Existing history is imported once when building.

atuin_install () {
  if is_osx; then
    check_osx_package "atuin"
  elif [ "${PKG_MANAGER}" = "pacman" ] || [ "${PKG_MANAGER}" = "nix" ]; then
    check_linux_package "atuin"
  else
    notice_message "atuin has no package for ${PKG_MANAGER:-this system} in its documentation: install it with 'cargo install atuin --locked' (see https://docs.atuin.sh) and ussuri will set it up"
  fi
}

check_atuin_config () {
  verbose_message "Configuring atuin"
  if (( ! $+commands[atuin] )) && have_lock; then
    atuin_install
    hash -r 2> /dev/null
  fi
  if (( ! $+commands[atuin] )); then
    verbose_message "atuin is not installed"
    return
  fi
  if [ "${DO_ENV_SETUP}" = "true" ]; then
    ATUIN_ARGS=""
    if [ ! "${ATUIN_BIND_UP}" = "true" ]; then
      ATUIN_ARGS=" --disable-up-arrow"
    fi
    execute_command "cached_eval ${(q)commands[atuin]} \"${(q)commands[atuin]} init zsh${ATUIN_ARGS}\""
    if [ "${DO_BUILD}" = "true" ] && [ "${ATUIN_IMPORT}" = "true" ] && have_lock && [ ! -e "${WORK_DIR}/atuin.imported" ]; then
      execute_command "atuin import auto && touch ${(q)WORK_DIR}/atuin.imported" "show"
    fi
  fi
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
  if [ "${INSTALL_ATUIN}" = "true" ]; then
    check_atuin_config
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
          execute_command "apply_prompt_top_line" "show"
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
      execute_command "apply_prompt_top_line" "show"
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
    execute_command "brew tap 2> /dev/null | sort > ${(q)TAPS_FILE}"
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
  TAPS_LIST=()
  if [ -f "${INSTALLED_FILE}" ]; then
    INSTALLED_LIST=( ${(f)"$(<${INSTALLED_FILE})"} )
  fi
  # Taps are shown by brew in lower case
  if [ -n "${TAPS_FILE}" ] && [ -f "${TAPS_FILE}" ]; then
    TAPS_LIST=( ${(L)${(f)"$(<${TAPS_FILE})"}} )
  fi
  INSTALLED_LOADED="true"
}

tap_installed () {
  if [ ! "${INSTALLED_LOADED}" = "true" ]; then
    load_installed_list
  fi
  (( ${TAPS_LIST[(Ie)${(L)1}]} ))
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
    elif is_osx && [ ! -f "${TAPS_FILE}" ]; then
      # An install from before taps were checked has no list of them yet: write just that
      execute_command "brew tap 2> /dev/null | sort > ${(q)TAPS_FILE}"
      INSTALLED_LOADED="false"
    fi
  fi
}

# Package list change detection
# Manual runs (-P/-A) always process the list, login runs only when the list has changed
# (a checksum is used rather than file age so a copied file with an old mtime isn't missed)

package_list_changed () {
  PACKAGE_STAMP="${WORK_DIR}/${1:t}.sum"
  package_layer_files "$1"
  (( ${#PACKAGE_LAYERS} )) || return 1
  # Every layer is in the checksum, so adding a package to your own list is noticed, and so is switching
  # to a profile (added only when there is one, so the checksums of existing installs don't change)
  PACKAGE_SUM=$( { cat "${PACKAGE_LAYERS[@]}" 2> /dev/null; [ -n "${PROFILE}" ] && print -r -- "profile:${PROFILE}"; } | cksum )
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
    ${1:-package_installed} "${PACKAGE}" || return 1
  done
  return 0
}

# Process the required package list using the given per package check function
# The stamp is only saved once everything is installed so failed installs are retried

# Process one package list: PROCESS_FUNCTION is run for each package, LIST_FILE is the shipped list
# (default: this system's) and LOOKUP says whether something is already there (default: package_installed).
# The stamp is only saved once everything is there, so failed installs are retried

process_package_list () {
  CHECK_FUNCTION="$1"
  PROCESS_FILE="${2:-${REQUIRED_FILE}}"
  PROCESS_LOOKUP="${3:-package_installed}"
  package_list_changed "${PROCESS_FILE}" || return 0
  read_required_list "${PROCESS_FILE}"
  update_package_list
  for PACKAGE in "${REQUIRED_LIST[@]}"; do
    ${CHECK_FUNCTION} "${PACKAGE}" ""
  done
  update_package_list
  if all_packages_installed "${PROCESS_LOOKUP}"; then
    execute_command "echo ${(q)PACKAGE_SUM} > ${(q)PACKAGE_STAMP}"
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

# Restart what a settings change needs restarting to show (flags are set as settings change)

restart_osx_services () {
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
  restart_osx_services
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
  local PACKAGE_TYPE="$2"
  have_lock || return
  verbose_message "Configuring OS X package \"${PACKAGE}\""
  [ "${INSTALL_BREW}" = "true" ] || return
  if [ ! -f "${INSTALLED_FILE}" ]; then
    update_package_list
  fi
  package_installed "${PACKAGE}" && return
  notice_message "Installing package ${PACKAGE}"
  if [ "${PACKAGE_TYPE}" = "cask" ]; then
    execute_command "brew install --cask ${(q)PACKAGE}" "show"
  else
    execute_command "brew install ${(q)PACKAGE}" "show"
  fi
  DO_UPDATE_LIST="true"
}

# Check OSX tap (a brew tap, added before the formulae and casks so a formula from one can be found)

check_osx_tap () {
  PACKAGE="$1"
  have_lock || return
  verbose_message "Configuring brew tap \"${PACKAGE}\""
  [ "${INSTALL_BREW}" = "true" ] || return
  if [ ! -f "${TAPS_FILE}" ]; then
    update_package_list
  fi
  tap_installed "${PACKAGE}" && return
  notice_message "Adding tap ${PACKAGE}"
  execute_command "brew tap ${(q)PACKAGE}" "show"
  DO_UPDATE_LIST="true"
}

# Check OSX cask (an application or font, installed with brew install --cask)

check_osx_cask () {
  check_osx_package "$1" "cask"
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
        # NONINTERACTIVE=1 stops the installer waiting for RETURN. It still needs sudo to work
        BREW_INSTALL_ENV=""
        if [ "${ASSUME_YES}" = "true" ]; then
          BREW_INSTALL_ENV="NONINTERACTIVE=1 "
        fi
        execute_command "${BREW_INSTALL_ENV}fetch_and_run ${(q)BREW_INSTALL_URL} ${(q)BREW_INSTALL_SHA256}" "show"
      fi
      setup_brew_env
    else
      if [ "${DO_ENV_SETUP}" = "true" ]; then
        verbose_message "Configuring brew environment"
        execute_command "cached_eval ${(q)BREW_TEST} \"${(q)BREW_TEST} shellenv\""
      fi
    fi
    # Taps first, then formulae, then casks. Each list has its own stamp, and the lists are
    # macos.tap, macos.brew and macos.cask (plus your local.tap, local.brew and local.cask)
    process_package_list "check_osx_tap" "${REQUIRED_FILE:r}.tap" "tap_installed"
    process_package_list "check_osx_package" "${REQUIRED_FILE}"
    process_package_list "check_osx_cask" "${REQUIRED_FILE:r}.cask"
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

# Download the release archive into DIR and unpack it there, refusing one that could write
# outside it. Sets UPDATE_SRC to the unpacked top directory.
# Returns 0 on success, 1 if it can't be fetched or unpacked (the script alone can still be
# updated), 2 if it must be refused (a checksum that doesn't match, unsafe paths)

fetch_update_archive () {
  UPDATE_SRC=""
  UPDATE_ARCHIVE="$1/release.tgz"
  fetch_url "${UPDATE_URL}" > "${UPDATE_ARCHIVE}" || return 1
  [ -s "${UPDATE_ARCHIVE}" ] || return 1
  if [ -n "${UPDATE_SHA256}" ]; then
    UPDATE_SUM=$( sha256_of "${UPDATE_ARCHIVE}" )
    if [ ! "${UPDATE_SUM}" = "${(L)UPDATE_SHA256}" ]; then
      echo "Warning:        Checksum mismatch for ${UPDATE_URL} (expected ${UPDATE_SHA256}, got ${UPDATE_SUM}), not updating"
      return 2
    fi
  fi
  if tar -tzf "${UPDATE_ARCHIVE}" 2> /dev/null | grep -q -E '^/|(^|/)\.\.(/|$)'; then
    echo "Warning:        ${UPDATE_URL} has unsafe paths in it, not updating"
    return 2
  fi
  mkdir "$1/src" && tar -xzf "${UPDATE_ARCHIVE}" -C "$1/src" 2> /dev/null || return 1
  UPDATE_TOPS=( $1/src/*(/N) )
  (( ${#UPDATE_TOPS} == 1 )) && [ -f "${UPDATE_TOPS[1]}/ussuri.zsh" ] || return 1
  UPDATE_SRC="${UPDATE_TOPS[1]}"
}

# Bring ~/.ussuri/files up to date with the release's files/. New files are added, changed ones
# replaced, and a file that is replaced is first copied to ~/.ussuri/files.bak/<date>/ so an edit
# of yours is never lost. Files only you have (local.*) are never touched, nothing is deleted

sync_support_files () {
  setopt localoptions nullglob
  SYNC_SRC="$1"
  SYNC_BACKUP="${WORK_DIR}/files.bak/${DATE_SUFFIX}"
  SYNC_NEW=0
  SYNC_CHANGED=0
  for SYNC_FILE in ${SYNC_SRC}/**/*(D.N); do
    SYNC_REL="${SYNC_FILE#${SYNC_SRC}/}"
    SYNC_TARGET="${WORK_DIR}/files/${SYNC_REL}"
    if [ -f "${SYNC_TARGET}" ]; then
      cmp -s "${SYNC_FILE}" "${SYNC_TARGET}" && continue
      [[ "${SYNC_FILE:t}" == local.* ]] && continue
      check_dir_exists "${SYNC_BACKUP}/${SYNC_REL:h}"
      execute_command "cp -p ${(q)SYNC_TARGET} ${(q)SYNC_BACKUP}/${(q)SYNC_REL}"
      SYNC_CHANGED=$(( SYNC_CHANGED + 1 ))
    else
      SYNC_NEW=$(( SYNC_NEW + 1 ))
    fi
    check_dir_exists "${SYNC_TARGET:h}"
    execute_command "cp ${(q)SYNC_FILE} ${(q)SYNC_TARGET}"
  done
  if (( SYNC_NEW + SYNC_CHANGED )) && [ ! "${DO_DRYRUN}" = "true" ]; then
    notice_message "Updated $(( SYNC_NEW + SYNC_CHANGED )) supporting files (${SYNC_NEW} new, ${SYNC_CHANGED} replaced${${SYNC_CHANGED#0}:+, the old copies are in ${SYNC_BACKUP}})"
  fi
}

# Update script
# Downloads the release (the script and its files/), checks the script parses and is the version
# expected, backs up the current script, replaces it and then brings the supporting files up to
# date. If the archive can't be fetched the script alone is updated. Everything goes through
# execute_command so --dryrun and --confirm are honoured. UPDATE_URL points somewhere else, and
# UPDATE_SHA256 pins the archive's checksum and SCRIPT_SHA256 the script's (a mismatch refuses the update)

update_script () {
  have_lock || return
  verbose_message "Checking for updates"
  set_env "SCRIPT_URL" "https://raw.githubusercontent.com/lateralblast/ussuri/refs/heads/main/ussuri.zsh"
  set_env "UPDATE_URL" "https://github.com/lateralblast/ussuri/archive/refs/heads/main.tar.gz"
  compare_versions "${SCRIPT_URL}" "^# Version"
  [ "${VERSION_STATE}" = "older" ] || return 0
  UPDATE_DIR=$( mktemp -d ) || return 1
  UPDATE_NEW="${UPDATE_DIR}/ussuri.zsh"
  fetch_update_archive "${UPDATE_DIR}"
  case $? in
    0)
      UPDATE_NEW="${UPDATE_SRC}/ussuri.zsh"
      ;;
    2)
      rm -rf "${UPDATE_DIR:?}"
      return 1
      ;;
    *)
      echo "Warning:        Could not fetch ${UPDATE_URL}: the script alone will be updated, the supporting files were not updated"
      UPDATE_SRC=""
      fetch_url "${SCRIPT_URL}" > "${UPDATE_NEW}"
      ;;
  esac
  # The script itself is checked on its own too, whichever way it was fetched: UPDATE_SHA256 pins the whole archive,
  # SCRIPT_SHA256 pins just the script, and its checksum is always shown so it can be compared with a published one
  UPDATE_NEW_SUM=$( sha256_of "${UPDATE_NEW}" )
  if [ -n "${SCRIPT_SHA256}" ] && [ ! "${UPDATE_NEW_SUM}" = "${(L)SCRIPT_SHA256}" ]; then
    echo "Warning:        Checksum mismatch for the downloaded script (expected ${SCRIPT_SHA256}, got ${UPDATE_NEW_SUM:-none}), not updating"
    rm -rf "${UPDATE_DIR:?}"
    return 1
  fi
  if zsh -n "${UPDATE_NEW}" 2> /dev/null && grep -q "^# Version: ${REMOTE_VERSION}$" "${UPDATE_NEW}"; then
    verbose_message "${SCRIPT_FILE} to version ${REMOTE_VERSION} (sha256 ${UPDATE_NEW_SUM})" "replace"
    check_dir_exists "${WORK_DIR}"
    execute_command "cp ${(q)SCRIPT_FILE} ${(q)WORK_DIR}/${SCRIPT_NAME}.zsh.${DATE_SUFFIX} && cp ${(q)UPDATE_NEW} ${(q)SCRIPT_FILE}.new && mv ${(q)SCRIPT_FILE}.new ${(q)SCRIPT_FILE}"
    [ "${DO_DRYRUN}" = "true" ] || notice_message "Updated ${SCRIPT_FILE} to version ${REMOTE_VERSION} (script sha256 ${UPDATE_NEW_SUM})"
    if [ -n "${UPDATE_SRC}" ] && [ -d "${UPDATE_SRC}/files" ]; then
      sync_support_files "${UPDATE_SRC}/files"
    fi
  else
    echo "Warning:        Downloaded script failed validation (it does not parse, or is not version ${REMOTE_VERSION}), not updating"
  fi
  rm -rf "${UPDATE_DIR:?}"
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
  # Without a host name this would be the hosts directory itself, and so every machine's files
  if [ -n "${DOTFILES_HOST}" ]; then
    DOT_LAYERS+=( "${DOTFILES_DIR}/hosts/${DOTFILES_HOST}" )
  fi
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

# DOTFILES_REPO: keep the dotfiles directory as a clone of a git repository (its layout is the one above: common/,
# profiles/<name>/, hosts/<name>/), so a new machine gets them with one setting. It is opt-in, and it is the one thing
# here that runs code you did not write on every machine, so: only https, ssh and file URLs are accepted (not git's ext
# transports, which run commands), a clone is never pulled over local changes or a different remote, only a
# fast forward is taken (DOTFILES_REF pins a branch, tag or commit instead), and nothing is prompted for in the
# background. On a login it is the update hint's pattern: at most once a day, a detached background job with its
# output discarded, the stamp touched first, nothing printed (the result is in ~/.ussuri/dotfiles.sync, which --doctor
# reads). --dotfiles does the same in the foreground first, so you see what it says. New files are linked by --dotfiles,
# links to files that were already there pick up the change by themselves

dotfiles_repo_url_ok () {
  setopt localoptions extendedglob
  [[ "$1" == (https://|ssh://|file://|git@)[A-Za-z0-9._/:@~%+=,-]## ]]
}

dotfiles_repo_sync () {
  setopt localoptions nullglob
  local url="${DOTFILES_REPO}" dir="${DOTFILES_DIR}" ref="${DOTFILES_REF}" remote
  local -a entries=()
  local env="GIT_ALLOW_PROTOCOL=https:ssh:file"
  if ! dotfiles_repo_url_ok "${url}"; then
    print -r -- "DOTFILES_REPO is not an https://, ssh:// or file:// URL (or git@host:path): ${url}"
    return 1
  fi
  [[ "${INTERACTIVE_SYNC}" == true ]] || env+=" GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND=${(q)GIT_SSH_COMMAND:-ssh -o BatchMode=yes}"
  [ -d "${dir}" ] && entries=( ${dir}/*(D) )
  if [ ! -e "${dir}" ] || { [ -d "${dir}" ] && (( ! ${#entries} )); }; then
    execute_command "${env} git_clone ${(q)url} ${(q)dir} ${(q)ref}" || return 1
    [ -d "${dir}/.git" ] || [ "${DO_DRYRUN}" = "true" ] || { print -r -- "could not clone ${url}"; return 1; }
    print -r -- "$( [ "${DO_DRYRUN}" = "true" ] && print -rn "would clone" || print -rn "cloned" ) ${url}${ref:+ at ${ref}}"
    return 0
  fi
  if [ ! -d "${dir}/.git" ]; then
    print -r -- "${dir} is not a clone, leaving it alone (move it aside, or point DOTFILES_DIR elsewhere)"
    return 1
  fi
  remote=$( git -C "${dir}" remote get-url origin 2> /dev/null )
  if [ ! "${remote}" = "${url}" ]; then
    print -r -- "${dir} is a clone of ${remote:-something else}, not ${url}: leaving it alone"
    return 1
  fi
  if [ -n "$( git -C "${dir}" status --porcelain 2> /dev/null )" ]; then
    print -r -- "${dir} has changes that are not committed, not pulling over them"
    return 1
  fi
  if [ -n "${ref}" ]; then
    execute_command "${env} git -C ${(q)dir} fetch --quiet --tags origin && git -C ${(q)dir} checkout --quiet ${(q)ref}" || { print -r -- "could not fetch and check out ${ref}"; return 1; }
    print -r -- "$( [ "${DO_DRYRUN}" = "true" ] && print -rn "would be" || print -rn "now" ) at ${ref}"
  else
    execute_command "${env} git -C ${(q)dir} fetch --quiet origin && git -C ${(q)dir} merge --ff-only --quiet FETCH_HEAD" || { print -r -- "could not fast forward (the local copy has commits of its own, or the fetch failed)"; return 1; }
    print -r -- "$( [ "${DO_DRYRUN}" = "true" ] && print -rn "would be up to date" || print -rn "up to date" ) with ${url}"
  fi
}

# Runs in the background: do the sync and keep its result (one line: seconds since the epoch, ok or failed, what happened)

dotfiles_repo_sync_background () {
  local msg result="ok"
  msg=$( INTERACTIVE_SYNC=false dotfiles_repo_sync 2>&1 ) || result="failed"
  print -r -- "${EPOCHSECONDS} ${result} ${msg//$'\n'/ }" >| "${WORK_DIR}/dotfiles.sync.$$" && mv -f "${WORK_DIR}/dotfiles.sync.$$" "${WORK_DIR}/dotfiles.sync"
}

check_dotfiles_sync () {
  [ -n "${DOTFILES_REPO}" ] || return 0
  have_lock || return 0
  if (( ${#ARGS} )); then
    return 0
  fi
  [[ -o interactive ]] || return 0
  local recent
  recent=( ${WORK_DIR}/dotfiles.sync.stamp(Nmh-24) )
  (( ${#recent} )) && return 0
  : >| "${WORK_DIR}/dotfiles.sync.stamp"
  ( dotfiles_repo_sync_background ) < /dev/null > /dev/null 2>&1 &!
}

check_dotfiles_config () {
  if [ -n "${DOTFILES_REPO}" ] && (( ${#ARGS} )); then
    local synced
    synced=$( INTERACTIVE_SYNC=true dotfiles_repo_sync 2>&1 ) && notice_message "dotfiles: ${synced}" || print -u2 -r -- "Warning:        dotfiles: ${synced}"
  fi
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

print_update_backups () {
  list_update_backups
  if (( ${#UPDATE_BACKUPS} )); then
    print -r -- "--update kept ${#UPDATE_BACKUPS} earlier script(s): --rollback update puts the newest back, with the files it replaced."
  fi
}

print_backups () {
  list_backups
  if (( ! ${#BACKUPS} )); then
    print -r -- "No backups in ${WORK_DIR}"
    print_update_backups
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
  print_update_backups
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
  if [[ "$1" == update ]]; then
    do_rollback_update
    return
  fi
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

# --rollback update: undo the last --update. It kept the script it replaced as ~/.ussuri/ussuri.zsh.<date>, and the
# supporting files it replaced in ~/.ussuri/files.bak/<date>/ (the same date), so both are put back. A file the update
# added is left where it is, since nothing recorded which files were new. The script it replaces is kept first, so the
# rollback can itself be undone. SCRIPT_FILE is the script that --update replaced, whichever way it was run

list_update_backups () {
  UPDATE_BACKUPS=( ${WORK_DIR}/${SCRIPT_NAME}.zsh.[0-9][0-9]_[0-9][0-9]_[0-9][0-9][0-9][0-9]_*(N.om) )
}

do_rollback_update () {
  local old stamp saved dir rel replaced=0
  list_update_backups
  if (( ! ${#UPDATE_BACKUPS} )); then
    print -r -- "No copies of an earlier script in ${WORK_DIR}, --update has not replaced this one"
    return 1
  fi
  old="${UPDATE_BACKUPS[1]}"
  if ! is_ussuri_script "${old}" || ! zsh -n "${old}" 2> /dev/null; then
    print -r -- "${old:t} is not a script that parses, not restoring it"
    return 1
  fi
  if [ -f "${SCRIPT_FILE}" ] && cmp -s "${old}" "${SCRIPT_FILE}"; then
    print -r -- "${SCRIPT_FILE} is already the same as ${old:t}"
    return 0
  fi
  stamp="${old:t}"
  stamp="${stamp#${SCRIPT_NAME}.zsh.}"
  saved="${WORK_DIR}/${SCRIPT_NAME}.zsh.${DATE_SUFFIX}"
  [ -e "${saved}" ] && saved="${saved}_1"
  execute_command "cp ${(q)SCRIPT_FILE} ${(q)saved} && cp ${(q)old} ${(q)SCRIPT_FILE}.new && mv ${(q)SCRIPT_FILE}.new ${(q)SCRIPT_FILE}"
  dir="${WORK_DIR}/files.bak/${stamp}"
  if [ -d "${dir}" ]; then
    for rel in ${dir}/**/*(DN.); do
      rel="${rel#${dir}/}"
      check_dir_exists "${WORK_DIR}/files/${rel:h}"
      execute_command "cp -p ${(q)dir}/${(q)rel} ${(q)WORK_DIR}/files/${(q)rel}"
      replaced=$(( replaced + 1 ))
    done
  fi
  if [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would restore ${old:t} as ${SCRIPT_FILE} and put back ${replaced} supporting files from files.bak/${stamp}"
  else
    print -r -- "Restored ${old:t} as ${SCRIPT_FILE} and put back ${replaced} supporting files (the script it replaced is in ${saved})"
  fi
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

# --export and --import: your setup in one file, for a new machine (or a backup). The bundle (a .tgz) holds what is
# yours and nothing the release owns or the machine made: the config and its profile and host layers, the local plugin
# and package lists (and their layers), the dotfiles directory and your ~/.p10k.zsh. Not the caches, stamps, backups,
# journals or the shipped files. A MANIFEST says what made it. It can hold things you would not post (your config
# values, your dotfiles), so it is written readable by you alone, and --import only takes names from that list
# (no absolute paths, no .., no links, nothing outside it) and keeps a copy of whatever it replaces

bundle_files () {
  setopt localoptions nullglob extendedglob
  local f
  BUNDLE_FILES=()
  for f in ${WORK_DIR}/config ${WORK_DIR}/{profiles,hosts}/**/*(D.) ${WORK_DIR}/files/**/local.*(D.) \
           ${WORK_DIR}/files/*/{profiles,hosts}/**/*(D.) ${WORK_DIR}/dotfiles/**/*(D.); do
    [[ -f "${f}" && ! -L "${f}" ]] || continue
    [[ "${f:t}" == *.(tmp|edit|rejected|broken)* ]] && continue
    BUNDLE_FILES+=( "${f#${WORK_DIR}/}" )
  done
  BUNDLE_FILES=( ${(ou)BUNDLE_FILES} )
}

# Copy what goes in the bundle, under the names it has inside it, into a directory

bundle_stage () {
  local stage="$1" rel
  for rel in "${BUNDLE_FILES[@]}"; do
    mkdir -p "${stage}/${rel:h}" && cp -p "${WORK_DIR}/${rel}" "${stage}/${rel}" || return 1
  done
  if [ -f "${P10K_INIT}" ]; then
    mkdir -p "${stage}/HOME" && cp -p "${P10K_INIT}" "${stage}/HOME/.p10k.zsh" || return 1
  fi
  local count=${#BUNDLE_FILES}
  [ -f "${P10K_INIT}" ] && count=$(( count + 1 ))
  {
    print -r -- "ussuri-export 1"
    print -r -- "version ${SCRIPT_VERSION}"
    print -r -- "date ${DATE_SUFFIX}"
    print -r -- "machine ${MACHINE}"
    print -r -- "profile ${PROFILE:-none}"
    print -r -- "files ${count}"
  } > "${stage}/MANIFEST"
}

export_bundle () {
  local out="$1" stage
  local -a tops
  [[ "${out}" == ":default:" ]] && out="${PWD}/${SCRIPT_NAME}-export-${MACHINE}-${DATE_SUFFIX}.tgz"
  [[ "${out}" == */* ]] || out="${PWD}/${out}"
  if [ -e "${out}" ] && [ ! "${DO_FORCE}" = "true" ]; then
    print -u2 -r -- "Error:          ${out} already exists (--force replaces it)"
    return 1
  fi
  bundle_files
  if (( ! ${#BUNDLE_FILES} )) && [ ! -f "${P10K_INIT}" ]; then
    print -u2 -r -- "Error:          nothing of yours to export in ${WORK_DIR} (no config, layers, local lists or dotfiles)"
    return 1
  fi
  if [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would write ${out} with ${#BUNDLE_FILES} files from ${WORK_DIR}$( [ -f "${P10K_INIT}" ] && print -rn -- " and ${P10K_INIT}" ):"
    (( ${#BUNDLE_FILES} )) && print -rl -- "  ${(@)BUNDLE_FILES}"
    return 0
  fi
  stage=$( mktemp -d ) || return 1
  if ! bundle_stage "${stage}"; then
    rm -rf "${stage:?}"
    print -u2 -r -- "Error:          could not collect the files"
    return 1
  fi
  tops=( ${stage}/*(N:t) )
  execute_command "COPYFILE_DISABLE=1 tar -czf ${(q)out} -C ${(q)stage} ${(j: :)${(@q)tops}}"
  rm -rf "${stage:?}"
  if [ ! -s "${out}" ]; then
    rm -f "${out}"
    print -u2 -r -- "Error:          ${out} was not written"
    return 1
  fi
  chmod 600 "${out}"
  print -r -- "Wrote ${out} (${#BUNDLE_FILES} files from ${WORK_DIR}${${P10K_INIT:+ and your p10k config}}). It may hold private settings and dotfiles: keep it to yourself."
  print -r -- "On the new machine: install ussuri, then ${SCRIPT_NAME}.zsh --import ${out:t}, then --dotfiles to link the dotfiles."
}

# Is this a name a bundle may hold? The list is the one above; anything else, however it is spelt, is refused

bundle_path_ok () {
  local name="${1%/}"
  [[ "${name}" == /* || "${name}" == ".." || "${name}" == ../* || "${name}" == */../* || "${name}" == */.. ]] && return 1
  name="${name#./}"
  case "${name}" in
    MANIFEST|config|HOME/.p10k.zsh) return 0 ;;
    profiles/*|hosts/*|dotfiles/*) return 0 ;;
    files/*/local.*|files/*/profiles/*|files/*/hosts/*) return 0 ;;
    profiles|hosts|dotfiles|files|HOME|files/*|HOME/*) [[ "$2" == dir ]] && return 0 ;;
  esac
  return 1
}

import_bundle () {
  local archive="$1" line name type tmp rel target backup new=0 changed=0 same=0 file idx=0 verb info
  local -a names manifest
  if [ ! -f "${archive}" ]; then
    print -u2 -r -- "Error:          ${archive} is not a file"
    return 1
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] && ! have_lock; then
    print -u2 -r -- "Error:          another ussuri run holds the lock (${LOCK_FILE}), try again in a moment"
    return 1
  fi
  names=( "${(@f)$( tar -tzf "${archive}" 2> /dev/null )}" )
  if (( ! ${#names} )) || [[ -z "${names[1]}" ]]; then
    print -u2 -r -- "Error:          ${archive} is not a gzipped tar file"
    return 1
  fi
  # Every entry must be a plain file or directory with an allowed name
  while IFS= read -r line; do
    type="${line[1]}"
    name="${names[++idx]}"
    if [[ "${type}" != [-d] || "${line}" == *" link to "* || "${line}" == *" -> "* ]]; then
      print -u2 -r -- "Error:          ${archive} has an entry that is not a plain file or directory (${name}), not importing it"
      return 1
    fi
    if ! bundle_path_ok "${name}" "$( [[ "${type}" == d ]] && print dir )"; then
      print -u2 -r -- "Error:          ${archive} has a name that does not belong in a bundle (${name}), not importing it"
      return 1
    fi
  done < <( tar -tvzf "${archive}" 2> /dev/null )
  if (( ${#names} != idx )); then
    print -u2 -r -- "Error:          could not read ${archive}'s contents, not importing it"
    return 1
  fi
  tmp=$( mktemp -d ) || return 1
  if ! tar -xzf "${archive}" -C "${tmp}" 2> /dev/null || [ ! -f "${tmp}/MANIFEST" ] || [[ "$(<${tmp}/MANIFEST)" != "ussuri-export 1"* ]]; then
    rm -rf "${tmp:?}"
    print -u2 -r -- "Error:          ${archive} is not a ussuri export (no MANIFEST)"
    return 1
  fi
  backup="${WORK_DIR}/import.bak/${DATE_SUFFIX}"
  for file in ${tmp}/**/*(D.N); do
    rel="${file#${tmp}/}"
    [[ "${rel}" == MANIFEST ]] && continue
    if [[ "${rel}" == HOME/.p10k.zsh ]]; then
      target="${P10K_INIT}"
    else
      target="${WORK_DIR}/${rel}"
    fi
    if [ -f "${target}" ]; then
      if cmp -s "${file}" "${target}"; then
        same=$(( same + 1 ))
        continue
      fi
      check_dir_exists "${backup}/${rel:h}"
      execute_command "cp -p ${(q)target} ${(q)backup}/${(q)rel}"
      changed=$(( changed + 1 ))
    else
      new=$(( new + 1 ))
    fi
    check_dir_exists "${target:h}"
    execute_command "cp -p ${(q)file} ${(q)target}"
    [[ "${rel}" == (config|*/local.config) ]] && execute_command "chmod 600 ${(q)target}"
  done
  manifest=( "${(@f)$(<${tmp}/MANIFEST)}" )
  info="${${(M)manifest:#version *}[1]#version } from ${${(M)manifest:#machine *}[1]#machine }"
  verb="Imported"
  [ "${DO_DRYRUN}" = "true" ] && verb="Would import"
  print -r -- "${verb} ${archive:t} (version ${info}): ${new} new, ${changed} replaced, ${same} already the same"
  (( changed )) && [ ! "${DO_DRYRUN}" = "true" ] && print -r -- "The ${changed} files it replaced are in ${backup}"
  rm -rf "${tmp:?}"
  [ "${DO_DRYRUN}" = "true" ] || print -r -- "Next: ${SCRIPT_NAME}.zsh --dotfiles to link the dotfiles, --doctor to check the setup."
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
#UPDATE_HINT=true           # once a day, in the background, check GitHub for a newer version and say so at the next prompt
#PROMPT_ENGINE=p10k         # p10k (powerlevel10k), posh (oh-my-posh) or none: only one is installed and loaded
#PROMPT_TWO_LINE=false      # p10k: false keeps a single line prompt (the default is a line above yours)
#PROMPT_TOP_ELEMENTS="context os_version cpu_arch"  # p10k segments on the left of the top line: user@hostname, the OS version ("macOS 15.1"), the architecture
#PROMPT_TOP_RIGHT_ELEMENTS="date"                   # p10k segments on the right of the top line: the day and date, "Fri 30 Oct 2026" (none for nothing)
#ASSUME_YES=true            # never prompt: no debconf dialogs, Homebrew installer unattended, --confirm answered yes
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

# atuin: searchable shell history. Off by default as it records every command. Never synced by ussuri
#INSTALL_ATUIN=true
#ATUIN_BIND_UP=true         # let atuin have the up arrow (default: history substring search keeps it)
#ATUIN_IMPORT=false         # do not import existing history when building

# Versions built by --rbenv and --pyenv (default is the latest stable)
#RUBY_VER=3.4.2
#PYTHON_VER=3.13.1

# Dotfiles (see --dotfiles): layers in ~/.ussuri/dotfiles/{common,profiles/<name>,hosts/<host>}
#DO_DOTFILES_CHECK=true     # link them on every login, not just with --dotfiles
#DOTFILES_REPO=             # a git URL (https, ssh or file) to keep the dotfiles directory a clone of: pulled once a day in the background, and by --dotfiles
#DOTFILES_REF=              # a branch, tag or commit of it to stay on (empty: fast forward the one cloned)
#PROFILE=work               # profile: adds profiles/work/ on top of common, for dotfiles, packages and plugins
#MACHINE=mybox              # machine name for hosts/mybox/ (default is the short hostname)

# Your own plugins and packages go in files, not in the shipped lists (updates and --install replace those):
#   ~/.ussuri/files/zinit/local.zsh        zinit lines, same format as zinit.zsh, run after it
#   ~/.ussuri/files/packages/local.brew    one package per line (local.apt, local.pacman, local.dnf, local.apk, local.nix)
# --update checks the release against UPDATE_SHA256 and the script in it against SCRIPT_SHA256, if you set them, and fetches it from UPDATE_URL
#UPDATE_SHA256=
#SCRIPT_SHA256=

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

# Change a setting in the config file (--set, --unset, --get). The config is what the script sources at the
# top of every login, so a setting saved there applies from the next shell with no edit to the script (which
# --update replaces). Names are the settings the template lists (--force allows any other upper case name),
# a value is written quoted and is never evaluated here, and the file is replaced with one rename so a shell
# starting at that moment reads the old file or the new one, never half of one

typeset -ga CONFIG_NEW_LINES CONFIG_PRESET
typeset -gA CONFIG_EXAMPLE

# The settings the template lists, with the example value it shows for each

load_config_names () {
  local line
  CONFIG_EXAMPLE=()
  for line in "${(@f)$( print_config_template )}"; do
    if [[ "${line}" =~ '^#?([A-Z][A-Z0-9_]*)=([^ #]*)' ]]; then
      CONFIG_EXAMPLE[${match[1]}]="${match[2]}"
    fi
  done
}

# Is this a setting name we will write, and a value it accepts? Prints why not

check_config_setting () {
  local name="$1" value="$2" example
  if [[ ! "${name}" =~ '^[A-Z][A-Z0-9_]*$' ]]; then
    print -u2 -r -- "Error:          '${name}' is not a setting name (upper case letters, digits and underscores)"
    return 1
  fi
  [ "${DO_FORCE}" = "true" ] && return 0
  if (( ! ${+CONFIG_EXAMPLE[${name}]} )); then
    print -u2 -r -- "Error:          '${name}' is not a setting ussuri knows (--config lists them, --force sets it anyway)"
    return 1
  fi
  example="${CONFIG_EXAMPLE[${name}]}"
  if [[ "${name}" == PROMPT_ENGINE && ! "${value}" == (p10k|posh|none) ]]; then
    print -u2 -r -- "Error:          PROMPT_ENGINE is p10k, posh or none, not '${value}'"
    return 1
  fi
  if [[ "${example}" == (true|false) && ! "${value}" == (true|false) ]]; then
    print -u2 -r -- "Error:          ${name} is true or false, not '${value}'"
    return 1
  fi
  return 0
}

write_config_lines () {
  print -r -l -- "${CONFIG_NEW_LINES[@]}" > "$1"
}

# Keep the newest ten copies of the config from before a change

# Which layer -M and -H ask for: the main one, or that profile's, or that machine's. Sets LAYER_KIND (base, profile or
# host) and LAYER_NAME, and refuses both at once or a name that was refused as unusable (check_layer_name emptied it)

layer_choice () {
  LAYER_KIND="base"
  LAYER_NAME=""
  if [ "${PROFILE_SWITCH}" = "true" ] && [ "${MACHINE_SWITCH}" = "true" ]; then
    print -u2 -r -- "Error:          choose one of --profile and --host: a change goes in one file"
    return 1
  fi
  if [ "${PROFILE_SWITCH}" = "true" ]; then
    if [ -z "${PROFILE}" ]; then
      print -u2 -r -- "Error:          that profile name is not usable"
      return 1
    fi
    LAYER_KIND="profile"
    LAYER_NAME="${PROFILE}"
  elif [ "${MACHINE_SWITCH}" = "true" ]; then
    if [ -z "${MACHINE}" ]; then
      print -u2 -r -- "Error:          that machine name is not usable"
      return 1
    fi
    LAYER_KIND="host"
    LAYER_NAME="${MACHINE}"
  fi
  return 0
}

# Which file --set, --unset and --edit change: the config, or with -M NAME the one for that profile, or with -H NAME
# the one for that machine, in the places local_layer_files finds them (it only lists the ones that exist, so the
# path is built here, in the same layout). Sets CONFIG_TARGET, and CONFIG_TARGET_LABEL for names and messages

config_target () {
  CONFIG_TARGET="${CONFIG_FILE}"
  CONFIG_TARGET_LABEL="config"
  layer_choice || return 1
  case "${LAYER_KIND}" in
    profile)
      CONFIG_TARGET="${CONFIG_FILE:h}/profiles/${LAYER_NAME}/local.config"
      CONFIG_TARGET_LABEL="config-profile-${LAYER_NAME}"
      ;;
    host)
      CONFIG_TARGET="${CONFIG_FILE:h}/hosts/${LAYER_NAME}/local.config"
      CONFIG_TARGET_LABEL="config-host-${LAYER_NAME}"
      ;;
  esac
  return 0
}

# The text a new profile or machine file starts with (the main config starts from the template)

config_layer_header () {
  print -r -- "# ussuri settings for ${CONFIG_TARGET_LABEL#config-}"
  print -r -- "#"
  print -r -- "# Sourced as zsh after ${CONFIG_FILE}, so these win over it, and the command line wins over these."
  print -r -- "# It is read for the profile or machine the environment or the config names (PROFILE, MACHINE)."
}

# Copy a file of yours to ~/.ussuri before it is changed, as <label>.<date>, and keep the newest ten of that label

backup_user_file () {
  local source="$1" label="$2" backup n=0 old
  backup="${WORK_DIR}/${label}.${DATE_SUFFIX}"
  while [ -e "${backup}" ]; do
    n=$(( n + 1 ))
    backup="${WORK_DIR}/${label}.${DATE_SUFFIX}_${n}"
  done
  verbose_message "${source} to ${backup}" "save"
  execute_command "cp -p ${(q)source} ${(q)backup}"
  # Only the backups themselves (the label, a date and perhaps a number), not a .rejected, .broken or temp file beside them
  old=( ${WORK_DIR}/${label}.[0-9][0-9]_[0-9][0-9]_[0-9][0-9][0-9][0-9]_*(Nom[11,-1]) )
  if (( ${#old} )) && [ ! "${DO_DRYRUN}" = "true" ]; then
    rm -f -- "${old[@]}"
  fi
}

backup_config () {
  backup_user_file "${CONFIG_TARGET}" "${CONFIG_TARGET_LABEL}"
}

config_get () {
  local name="$1" file="${CONFIG_FILE}" value layer where=""
  local -a lines=()
  if [[ ! "${name}" =~ '^[A-Z][A-Z0-9_]*$' ]]; then
    print -u2 -r -- "Error:          '${name}' is not a setting name (upper case letters, digits and underscores)"
    return 1
  fi
  value="${(P)name}"
  # The last of the config and its layers to set it is the one that counts
  for layer in "${file}" "${CONFIG_LAYER_FILES[@]}"; do
    lines=()
    [ -r "${layer}" ] && lines=( "${(@f)$(<${layer})}" )
    (( ${lines[(I)${name}=*]} )) && where="${layer}"
  done
  if [ -n "${where}" ]; then
    print -r -- "${name}=${(q)value}  (config: ${where})"
  elif (( ${CONFIG_PRESET[(Ie)${name}]} )); then
    print -r -- "${name}=${(q)value}  (environment)"
  elif [ -n "${value}" ]; then
    print -r -- "${name}=${(q)value}  (default)"
  else
    print -r -- "${name} is not set"
  fi
}

# --get with no name: every setting the template lists, and any other the config sets, with its value and
# where that comes from

config_get_all () {
  local line name file result=0
  local -a names=( ${(ko)CONFIG_EXAMPLE} )
  for file in "${CONFIG_FILE}" "${CONFIG_LAYER_FILES[@]}"; do
    [ -r "${file}" ] || continue
    for line in "${(@f)$(<${file})}"; do
      [[ "${line}" =~ '^([A-Z][A-Z0-9_]*)=' ]] && names+=( "${match[1]}" )
    done
  done
  for name in ${(u)names}; do
    config_get "${name}" || result=1
  done
  return ${result}
}

# Apply every --set and --unset to the config in one go (one backup, one write)

config_edit () {
  local file="${CONFIG_TARGET}" arg name value quoted line i changed="false"
  local -a lines=() before removed
  load_config_names
  if [ -e "${file}" ]; then
    if [ ! -f "${file}" ] || [ ! -w "${file}" ] || [ ! -r "${file}" ]; then
      print -u2 -r -- "Error:          ${file} is not a file you can read and write"
      return 1
    fi
    lines=( "${(@f)$(<${file})}" )
    (( ${#lines} == 1 )) && [[ -z "${lines[1]}" ]] && lines=()
  elif [ "${CONFIG_TARGET}" = "${CONFIG_FILE}" ]; then
    lines=( "${(@f)$( print_config_template )}" )
    changed="true"
  else
    lines=( "${(@f)$( config_layer_header )}" )
    changed="true"
  fi
  before=( "${lines[@]}" )
  for arg in "${CONFIG_SETS[@]}"; do
    if [[ "${arg}" != *=* ]]; then
      print -u2 -r -- "Error:          --set needs a name and a value: --set ${arg} VALUE (--unset ${arg} removes it)"
      return 1
    fi
    name="${arg%%=*}"
    value="${arg#*=}"
    check_config_setting "${name}" "${value}" || return 1
    if [[ "${value}" == *$'\n'* ]]; then
      print -u2 -r -- "Error:          the value of ${name} has a line break in it"
      return 1
    fi
    quoted="${(q)value}"
    [[ "${quoted}" == *\\* ]] && quoted="${(qq)value}"
    line="${name}=${quoted}"
    # The last active line is the one that counts when the file is sourced, so it is the one replaced. Failing
    # that the line goes in under the commented example, so the explanation stays with it, or at the end
    i=${lines[(I)${name}=*]}
    if (( i )); then
      lines[i]="${line}"
    else
      i=${lines[(i)\#${name}=*]}
      if (( i <= ${#lines} )); then
        lines[i+1,i]=( "${line}" )
      else
        lines+=( "${line}" )
      fi
    fi
    print -r -- "${name}=${quoted} will be saved in ${file}"
  done
  for name in "${CONFIG_UNSETS[@]}"; do
    if [[ ! "${name}" =~ '^[A-Z][A-Z0-9_]*$' ]]; then
      print -u2 -r -- "Error:          '${name}' is not a setting name (upper case letters, digits and underscores)"
      return 1
    fi
    removed=( "${(@M)lines:#${name}=*}" )
    lines=( "${(@)lines:#${name}=*}" )
    if (( ${#removed} )); then
      print -r -- "${name} will be removed from ${file}"
    else
      print -r -- "${name} is not set in ${file}"
    fi
  done
  [[ "${(F)lines}" == "${(F)before}" && "${changed}" == false ]] && {
    print -r -- "Nothing to change in ${file}"
    return 0
  }
  if [ ! "${DO_DRYRUN}" = "true" ] && ! have_lock; then
    print -u2 -r -- "Error:          another ussuri run holds the lock (${LOCK_FILE}), try again in a moment"
    return 1
  fi
  check_dir_exists "${file:h}"
  [ -e "${file}" ] && backup_config
  CONFIG_NEW_LINES=( "${lines[@]}" )
  local tmp="${file}.tmp.$$"
  [ -e "${file}" ] && execute_command "cp -p ${(q)file} ${(q)tmp}"
  execute_command "write_config_lines ${(q)tmp}"
  execute_command "mv -f ${(q)tmp} ${(q)file}"
  if [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would write ${file}"
  elif [ -e "${tmp}" ]; then
    rm -f -- "${tmp}"
    print -u2 -r -- "Error:          ${file} was not changed"
    return 1
  else
    print -r -- "Saved in ${file}, it applies to new shells (run exec zsh to start one in this window)"
  fi
  return 0
}

# --edit: change a copy in $VISUAL, $EDITOR or vi, and keep it only if it is valid zsh, so a slip never leaves
# every new shell with a broken config. Names that are not settings ussuri knows are reported (they work, but
# may be a typo). The file that was there is backed up first, and a rejected edit is left next to it as .rejected

edit_config () {
  local file="${CONFIG_TARGET}" editor="${VISUAL:-${EDITOR:-vi}}" tmp="${CONFIG_TARGET}.edit.$$" line name
  local -a lines=()
  load_config_names
  if [ -e "${file}" ] && { [ ! -f "${file}" ] || [ ! -r "${file}" ] || [ ! -w "${file}" ]; }; then
    print -u2 -r -- "Error:          ${file} is not a file you can read and write"
    return 1
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] && ! have_lock; then
    print -u2 -r -- "Error:          another ussuri run holds the lock (${LOCK_FILE}), try again in a moment"
    return 1
  fi
  check_dir_exists "${file:h}"
  if [ -e "${file}" ]; then
    execute_command "cp -p ${(q)file} ${(q)tmp}"
  elif [ "${file}" = "${CONFIG_FILE}" ]; then
    execute_command "print_config_template > ${(q)tmp}"
  else
    execute_command "config_layer_header > ${(q)tmp}"
  fi
  # The editor is yours (it may have arguments), the file is quoted
  execute_command "${editor} ${(q)tmp}" "show"
  if [ "${DO_DRYRUN}" = "true" ]; then
    print -r -- "Would edit ${file} with ${editor}"
    return 0
  fi
  if [ ! -e "${tmp}" ]; then
    print -u2 -r -- "Error:          ${editor} did not leave a file to keep, ${file} is unchanged"
    return 1
  fi
  if [ -e "${file}" ] && cmp -s "${file}" "${tmp}"; then
    rm -f -- "${tmp}"
    print -r -- "No changes to ${file}"
    return 0
  fi
  if ! zsh -n "${tmp}" 2> /dev/null; then
    mv -f -- "${tmp}" "${file}.rejected"
    print -u2 -r -- "Error:          the edit has a syntax error, so ${file} is unchanged. Your edit is in ${file}.rejected: fix it and copy it over"
    return 1
  fi
  lines=( "${(@f)$(<${tmp})}" )
  for line in "${lines[@]}"; do
    if [[ "${line}" =~ '^([A-Z][A-Z0-9_]*)=' ]]; then
      name="${match[1]}"
      (( ${+CONFIG_EXAMPLE[${name}]} )) || print -r -- "Note:           ${name} is not a setting ussuri lists (a typo? --config shows the ones it knows)"
    fi
  done
  [ -e "${file}" ] && backup_config
  execute_command "mv -f ${(q)tmp} ${(q)file}"
  print -r -- "Saved ${file}, it applies to new shells (run exec zsh to start one in this window)"
  return 0
}

run_config_commands () {
  local name result=0
  load_config_names
  for name in "${CONFIG_GETS[@]}"; do
    if [[ "${name}" == all ]]; then
      config_get_all || result=1
    else
      config_get "${name}" || result=1
    fi
  done
  if (( ${#CONFIG_SETS} + ${#CONFIG_UNSETS} )) || [ "${DO_CONFIG_EDIT}" = "true" ]; then
    config_target || return 1
  fi
  if (( ${#CONFIG_SETS} + ${#CONFIG_UNSETS} )); then
    config_edit || result=1
  fi
  if [ "${DO_CONFIG_EDIT}" = "true" ]; then
    edit_config || result=1
  fi
  return ${result}
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

# A problem --doctor --fix can repair: what to do (kind), how bad it was (warn or fail, which count goes down when it
# is repaired), what it is done to (arg, and arg2 for the backup that replaces a broken file) and a sentence for it.
# Only things that are small, local and reversible are listed: permissions, a missing p10k config copied from files,
# temp files an interrupted --set or --edit left, and a broken config put back from its newest valid backup (the broken
# one is kept beside it). Nothing is installed, deleted from your files, or fetched

doctor_fixable () {
  DOCTOR_FIX_KIND+=( "$1" )
  DOCTOR_FIX_SEV+=( "$2" )
  DOCTOR_FIX_ARG+=( "$3" )
  DOCTOR_FIX_ARG2+=( "$4" )
  DOCTOR_FIX_TEXT+=( "$5" )
}

# The label a config file's backups have: config, or config-profile-<name>, or config-host-<name>

config_backup_label () {
  case "${1:h:h:t}/${1:h:t}" in
    profiles/*) print -r -- "config-profile-${1:h:t}" ;;
    hosts/*)    print -r -- "config-host-${1:h:t}" ;;
    *)          print -r -- "config" ;;
  esac
}

# The newest backup of a config file that is valid zsh, in DOCTOR_BACKUP_FOUND (empty if none)

doctor_valid_backup () {
  local candidate
  DOCTOR_BACKUP_FOUND=""
  for candidate in ${WORK_DIR}/$( config_backup_label "$1" ).[0-9][0-9]_[0-9][0-9]_[0-9][0-9][0-9][0-9]_*(Nom); do
    if zsh -n "${candidate}" 2> /dev/null; then
      DOCTOR_BACKUP_FOUND="${candidate}"
      return 0
    fi
  done
  return 1
}

# One config file (the config or a layer): valid zsh, not writable by others, no temp files left over

doctor_config_file () {
  local file="$1"
  if zsh -n "${file}" 2> /dev/null; then
    doctor_ok "${file} is valid"
  else
    doctor_fail "${file} has a syntax error (it is sourced on every shell)"
    if doctor_valid_backup "${file}"; then
      doctor_fixable "restore" "fail" "${file}" "${DOCTOR_BACKUP_FOUND}" "put the newest valid backup (${DOCTOR_BACKUP_FOUND:t}) back as ${file:t}, keeping the broken one as ${file:t}.broken"
    fi
  fi
  # It is executed, so anyone who can write to it can run commands as you
  DOCTOR_WRITABLE=( ${file}(Nf:go+w:) )
  if (( ${#DOCTOR_WRITABLE} )); then
    doctor_warn "${file} is writable by others, and it is executed on every shell (chmod go-w it)"
    doctor_fixable "chmod" "warn" "${file}" "" "make ${file:t} not writable by others"
  fi
  # A temp copy is only there between the write and the rename of --set, --edit or --adopt: one that is 10 minutes old was left by a run that died
  DOCTOR_LEFTOVER=( ${file}.tmp.*(Nmm+10) )
  for DOCTOR_TMP in "${DOCTOR_LEFTOVER[@]}"; do
    doctor_warn "${DOCTOR_TMP} was left by a --set or --edit that did not finish"
    doctor_fixable "remove" "warn" "${DOCTOR_TMP}" "" "remove the leftover ${DOCTOR_TMP:t}"
  done
}

# Whether a fix worked, checked afterwards rather than trusted

doctor_fix_worked () {
  case "$1" in
    chmod)   DOCTOR_STILL=( ${2}(Nf:go+w:) ); (( ! ${#DOCTOR_STILL} )) ;;
    restore) zsh -n "$2" 2> /dev/null ;;
    p10k)    [ -f "$2" ] ;;
    remove)  [ ! -e "$2" ] ;;
  esac
}

apply_doctor_fixes () {
  local i kind arg arg2 sev text fixed=0 failed=0
  if (( ! ${#DOCTOR_FIX_KIND} )); then
    print -r -- "Nothing to repair"
    return
  fi
  if [ ! "${DO_DRYRUN}" = "true" ] && ! have_lock; then
    print -u2 -r -- "Error:          another ussuri run holds the lock (${LOCK_FILE}), try again in a moment"
    return
  fi
  print -r -- "Repairing"
  for (( i = 1; i <= ${#DOCTOR_FIX_KIND}; i++ )); do
    kind="${DOCTOR_FIX_KIND[i]}"; sev="${DOCTOR_FIX_SEV[i]}"; arg="${DOCTOR_FIX_ARG[i]}"; arg2="${DOCTOR_FIX_ARG2[i]}"; text="${DOCTOR_FIX_TEXT[i]}"
    if [ "${DO_DRYRUN}" = "true" ]; then
      print -r -- "  would ${text}"
      continue
    fi
    case "${kind}" in
      chmod)
        execute_command "chmod go-w ${(q)arg}"
        ;;
      restore)
        # The copy is made first, so a failed copy leaves the broken file where it was
        execute_command "cp -p ${(q)arg2} ${(q)arg}.restore.$$ && mv -f ${(q)arg} ${(q)arg}.broken && mv -f ${(q)arg}.restore.$$ ${(q)arg}"
        ;;
      p10k)
        execute_command "cp ${(q)arg2} ${(q)arg}"
        ;;
      remove)
        execute_command "rm -f -- ${(q)arg}"
        ;;
    esac
    if doctor_fix_worked "${kind}" "${arg}"; then
      print -r -- "  fixed  ${text}"
      fixed=$(( fixed + 1 ))
      if [ "${sev}" = "fail" ]; then
        DOCTOR_FAIL=$(( DOCTOR_FAIL - 1 ))
      else
        DOCTOR_WARN=$(( DOCTOR_WARN - 1 ))
      fi
      DOCTOR_OK=$(( DOCTOR_OK + 1 ))
    else
      print -r -- "  NOT fixed  ${text}"
      failed=$(( failed + 1 ))
    fi
  done
  if [ ! "${DO_DRYRUN}" = "true" ]; then
    print
    print -r -- "${fixed} repaired${${failed#0}:+, ${failed} not repaired}"
    print -r -- "${DOCTOR_OK} ok, ${DOCTOR_WARN} warnings, ${DOCTOR_FAIL} failures"
  fi
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
  setopt localoptions extendedglob
  doctor_ok "profile: ${PROFILE:-none}"
  doctor_ok "machine: ${MACHINE}"
  local_layer_files "${WORK_DIR}/files/zinit" "zsh"
  for DOCTOR_FILE in "${LOCAL_LAYERS[@]}"; do
    DOCTOR_LINES=( ${${(f)"$(<${DOCTOR_FILE})"}:#(\#*|[[:space:]]#)} )
    doctor_ok "local plugin list ${DOCTOR_FILE#${WORK_DIR}/files/}: ${#DOCTOR_LINES} lines"
  done
  if [ -n "${REQUIRED_FILE}" ]; then
    local_layer_files "${REQUIRED_FILE:h}" "${REQUIRED_FILE:e}"
    for DOCTOR_FILE in "${LOCAL_LAYERS[@]}"; do
      DOCTOR_LINES=( ${${(f)"$(<${DOCTOR_FILE})"}:#(\#*|[[:space:]]#)} )
      doctor_ok "local package list ${DOCTOR_FILE#${WORK_DIR}/files/}: ${#DOCTOR_LINES} lines"
    done
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

# The settings for the profile and machine (profiles/<PROFILE>/local.config, hosts/<MACHINE>/local.config) are
# sourced on every shell like the config is, so they get the same checks

doctor_config_layers () {
  local layer
  for layer in "${CONFIG_LAYER_FILES[@]}"; do
    doctor_config_file "${layer}"
  done
}

doctor_config () {
  print -r -- "Config"
  if [ ! -e "${CONFIG_FILE}" ]; then
    doctor_ok "no config file, the defaults are used (--config creates one)"
    doctor_config_layers
    return
  fi
  doctor_config_file "${CONFIG_FILE}"
  doctor_config_layers
}

doctor_dotfiles_repo () {
  [ -n "${DOTFILES_REPO}" ] || return 0
  local line epoch result msg age
  print -r -- "Dotfiles repository"
  if ! dotfiles_repo_url_ok "${DOTFILES_REPO}"; then
    doctor_fail "DOTFILES_REPO is not an https://, ssh:// or file:// URL (or git@host:path), so it is not used: ${DOTFILES_REPO}"
    return
  fi
  if [ ! -f "${WORK_DIR}/dotfiles.sync" ]; then
    doctor_ok "${DOTFILES_REPO} (not synced yet: a login does it once a day in the background, --dotfiles does it now)"
    return
  fi
  line=$(<"${WORK_DIR}/dotfiles.sync")
  epoch="${line%% *}"
  result="${${line#* }%% *}"
  msg="${${line#* }#* }"
  age="some time ago"
  [[ "${epoch}" == <-> ]] && age="$(( (EPOCHSECONDS - epoch) / 3600 )) hours ago"
  if [ "${result}" = "ok" ]; then
    doctor_ok "${DOTFILES_REPO}: ${msg} (${age})"
  else
    doctor_warn "${DOTFILES_REPO}: the last sync failed (${age}): ${msg}"
  fi
}

doctor_dotfiles () {
  doctor_dotfiles_repo
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

# The segments on the top line (the ones these settings choose): a name that is not a segment, a colour that can't be
# read on the background, a word that isn't a segment name at all. The bottom line is your p10k config's, and is only
# listed by --prompt-preview

doctor_prompt_segments () {
  setopt localoptions extendedglob
  local word row bad=0 checked=0
  local -a cols
  for word in ${=PROMPT_TOP_ELEMENTS} ${=PROMPT_TOP_RIGHT_ELEMENTS}; do
    [[ "${word}" == none || "${word}" == [A-Za-z0-9_]## ]] && continue
    doctor_warn "'${word}' in PROMPT_TOP_ELEMENTS or PROMPT_TOP_RIGHT_ELEMENTS is not a segment name (letters, digits and underscores), it is ignored"
    bad=1
  done
  [ -r "${P10K_INIT}" ] || return
  for row in "${(@f)$( prompt_layout_report )}"; do
    cols=( "${(@ps:\t:)row}" )
    [[ "${cols[1]}" == top ]] || continue
    checked=$(( checked + 1 ))
    case "${cols[8]}" in
      unknown)
        doctor_warn "top line segment '${cols[3]}' is not one this powerlevel10k has (a typo, or an older powerlevel10k): it shows nothing"
        bad=1
        ;;
      low|same)
        doctor_warn "top line segment '${cols[3]}' is hard to read: foreground ${cols[5]} on ${cols[6]}, contrast ${cols[7]} to 1 (3 or more is readable): set POWERLEVEL9K_${(U)${cols[3]%%:*}%_JOINED}_FOREGROUND (--prompt-preview shows them)"
        bad=1
        ;;
    esac
  done
  (( bad || ! checked )) || doctor_ok "top line segments exist and are readable (--prompt-preview shows them)"
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
  doctor_ok "prompt engine: ${PROMPT_ENGINE}"
  if prompt_engine_is p10k; then
    if [ "${PROMPT_TWO_LINE}" = "true" ]; then
      doctor_ok "two line prompt, top line: ${PROMPT_TOP_ELEMENTS:-nothing}${PROMPT_TOP_RIGHT_ELEMENTS:+ (right: ${PROMPT_TOP_RIGHT_ELEMENTS})}"
      doctor_prompt_segments
    else
      doctor_ok "single line prompt (PROMPT_TWO_LINE=false)"
    fi
  fi
  if { [ "${DO_POSH_CHECK}" = "true" ] && [ ! "${PROMPT_ENGINE}" = "posh" ]; } || { [ "${DO_P10K_CHECK}" = "true" ] && [ ! "${PROMPT_ENGINE}" = "p10k" ]; }; then
    doctor_warn "two prompt engines are switched on (the engine is ${PROMPT_ENGINE}, but DO_POSH_CHECK or DO_P10K_CHECK is set for the other): both hook every prompt and fight over it"
  fi
  if [ "${INSTALL_POSH}" = "true" ]; then
    if [ -x "${POSH_HOME}/oh-my-posh" ] || (( $+commands[oh-my-posh] )); then
      doctor_ok "oh-my-posh"
    else
      doctor_warn "oh-my-posh is not installed (${POSH_HOME})"
    fi
  fi
  if [ "${INSTALL_P10K}" = "true" ]; then
    if [ -f "${P10K_INIT}" ]; then
      doctor_ok "powerlevel10k config ${P10K_INIT}"
    else
      doctor_warn "powerlevel10k config ${P10K_INIT} is missing"
      if [ -f "${SOURCE_P10K_INIT}" ]; then
        doctor_fixable "p10k" "warn" "${P10K_INIT}" "${SOURCE_P10K_INIT}" "copy ${SOURCE_P10K_INIT} to ${P10K_INIT}"
      fi
    fi
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
  for DOCTOR_TOOL in fnm rustup uv mise atuin; do
    DOCTOR_WANTED="INSTALL_${(U)DOCTOR_TOOL}"
    if [ "${(P)DOCTOR_WANTED}" = "true" ]; then
      case "${DOCTOR_TOOL}" in
        fnm)    DOCTOR_PATH="${FNM_HOME}/fnm" ;;
        rustup) DOCTOR_PATH="${CARGO_HOME:-${HOME_DIR}/.cargo}/bin/rustup" ;;
        uv)     DOCTOR_PATH="${UV_BIN_DIR}/uv" ;;
        mise)   DOCTOR_PATH="${MISE_BIN}" ;;
        atuin)  DOCTOR_PATH="atuin (brew, pacman or nix install atuin, or cargo install atuin --locked)" ;;
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
    if [ "${UPDATE_HINT}" = "true" ]; then
      DOCTOR_LATEST=""
      if [ -f "${WORK_DIR}/update.latest" ]; then
        DOCTOR_LATEST=$(<"${WORK_DIR}/update.latest")
      fi
      if [[ "${DOCTOR_LATEST}" == [0-9].[0-9].[0-9] ]] && (( ${DOCTOR_LATEST//./} > ${SCRIPT_VERSION//./} )); then
        doctor_warn "${DOCTOR_LATEST} is available (this is ${SCRIPT_VERSION}): run ${SCRIPT_NAME}.zsh --update"
      elif [ -f "${WORK_DIR}/update.check" ]; then
        doctor_ok "update hint is on, the latest known version is ${DOCTOR_LATEST:-not known yet}"
      else
        doctor_ok "update hint is on, not checked yet (the next login does it)"
      fi
    fi
    if read_journal && (( ${#JOURNAL_ACTIVE} )); then
      DOCTOR_RUN_WORD="runs"
      (( ${#JOURNAL_ACTIVE} == 1 )) && DOCTOR_RUN_WORD="run"
      doctor_ok "${#JOURNAL_ACTIVE} ${DOCTOR_RUN_WORD} of OS X defaults can be undone (--defaults-undo list)"
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
  DOCTOR_FIX_KIND=()
  DOCTOR_FIX_SEV=()
  DOCTOR_FIX_ARG=()
  DOCTOR_FIX_ARG2=()
  DOCTOR_FIX_TEXT=()
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
  if [ "${DO_FIX}" = "true" ]; then
    print
    apply_doctor_fixes
  elif (( ${#DOCTOR_FIX_KIND} )); then
    print -r -- "${#DOCTOR_FIX_KIND} of these can be repaired safely: ${SCRIPT_NAME}.zsh --doctor --fix (add --dryrun to see them first)"
  fi
  (( DOCTOR_FAIL == 0 ))
}

# The update hint (UPDATE_HINT=true, off by default as it contacts GitHub from your shell). At most once a
# day a check runs in the background (a disowned job with its output detached, so a login never waits for
# it) and records the latest version in ~/.ussuri/update.latest. When that is newer than this script a one
# line hint is shown, at most once a day, at the first prompt rather than during startup (output during
# startup upsets powerlevel10k's instant prompt). The stamp is touched before the check starts, so several
# shells opened together start one check. On a normal login this is two glob qualifiers on the stamp files
# and one small file read: no forks and no waiting

show_update_hint () {
  print -r -- "${UPDATE_HINT_TEXT}"
  precmd_functions=( ${precmd_functions:#show_update_hint} )
}

# Runs in the background: ask for the latest version and keep it only if it looks like one

update_hint_fetch () {
  local remote
  if (( $+commands[curl] )); then
    remote=$( curl -fsS -m 15 "${SCRIPT_URL}" 2> /dev/null | grep -m1 '^# Version:' )
  elif (( $+commands[wget] )); then
    remote=$( wget -qO- -T 15 "${SCRIPT_URL}" 2> /dev/null | grep -m1 '^# Version:' )
  fi
  remote="${remote#\# Version: }"
  [[ "${remote}" == [0-9].[0-9].[0-9] ]] || return 1
  print -r -- "${remote}" >| "${WORK_DIR}/update.latest.$$" && mv -f "${WORK_DIR}/update.latest.$$" "${WORK_DIR}/update.latest"
}

check_update_hint () {
  [ "${UPDATE_HINT}" = "true" ] || return 0
  (( ${#ARGS} )) && return 0
  [[ -o interactive ]] || return 0
  local latest="" recent
  if [ -f "${WORK_DIR}/update.latest" ]; then
    latest=$(<"${WORK_DIR}/update.latest")
  fi
  # Versions are compared with the dots removed, as everywhere else (each part is a single digit)
  if [[ "${latest}" == [0-9].[0-9].[0-9] ]] && (( ${latest//./} > ${SCRIPT_VERSION//./} )); then
    recent=( ${WORK_DIR}/update.hinted(Nmh-24) )
    if (( ! ${#recent} )); then
      UPDATE_HINT_TEXT="${SCRIPT_NAME} ${latest} is available (this is ${SCRIPT_VERSION}): run ${SCRIPT_NAME}.zsh --update  (UPDATE_HINT=false turns this off)"
      precmd_functions+=( show_update_hint )
      : >| "${WORK_DIR}/update.hinted"
    fi
  fi
  recent=( ${WORK_DIR}/update.check(Nmh-24) )
  if (( ! ${#recent} )); then
    : >| "${WORK_DIR}/update.check"
    ( update_hint_fetch ) < /dev/null > /dev/null 2>&1 &!
  fi
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

STARTUP_MARKS+=( "defining functions|${EPOCHREALTIME}" )

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

  CONFIG_SETS=()
  CONFIG_UNSETS=()
  CONFIG_GETS=()
  DO_CONFIG_EDIT="false"
  DO_TIMING="false"
  TIMING_NAMES=()
  TIMING_SECONDS=()
  TIMING_LINES=()
  TIMING_LINE_SECONDS=()
  DO_ADOPT="false"
  DO_FIX="false"
  PROFILE_SWITCH="false"
  MACHINE_SWITCH="false"

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
      --tool -W         --yes -y           --assume-yes -y
      --prompt -E       --engine -E        --defaults-undo -J
      --assumeyes -y
      --set -Q          --unset -q         --get -w
      --host -H         --edit -K
      --adopt -a        --fix -Y
      --timing -j
      --prompt-preview -4
      --export -2       --import -3
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
        -g|-l|-m|-M|-S|-W|-E|-Z|-q|-H|-3)
          SWITCH_VALUE="true"
          ;;
        -2)
          # Where to write the bundle is optional, no value means a name made from the machine and the date
          if [[ -z "${@[ARG_INDEX+1]}" || "${@[ARG_INDEX+1]}" == -* ]]; then
            SWITCHES+=( ":default:" )
          else
            SWITCH_VALUE="true"
          fi
          ;;
        -w)
          # Which setting is optional, no name means all of them
          if [[ -z "${@[ARG_INDEX+1]}" || "${@[ARG_INDEX+1]}" == -* ]]; then
            SWITCHES+=( all )
          else
            SWITCH_VALUE="true"
          fi
          ;;
        -Q)
          # --set NAME VALUE (or NAME=VALUE): the two words travel on as one NAME=VALUE value
          if [[ "${@[ARG_INDEX+1]}" =~ '^[A-Za-z0-9_]+=' ]]; then
            SWITCHES+=( "${@[ARG_INDEX+1]}" )
            (( ARG_INDEX += 1 ))
          elif (( ARG_INDEX + 2 <= $# )); then
            SWITCHES+=( "${@[ARG_INDEX+1]}=${@[ARG_INDEX+2]}" )
            (( ARG_INDEX += 2 ))
          else
            SWITCH_VALUE="true"
          fi
          ;;
        -G)
          # What to report on is optional, no value means everything
          if [[ -z "${@[ARG_INDEX+1]}" || "${@[ARG_INDEX+1]}" == -* ]]; then
            SWITCHES+=( all )
          else
            SWITCH_VALUE="true"
          fi
          ;;
        -R|-J)
          # Which backup (or run of defaults) is optional, no value means the newest
          if [[ -z "${@[ARG_INDEX+1]}" || "${@[ARG_INDEX+1]}" == -* ]]; then
            SWITCHES+=( 1 )
          else
            SWITCH_VALUE="true"
          fi
          ;;
      esac
    done
    set -- "${SWITCHES[@]}"
    if ! zparseopts -D -F -a OPTS -- a A b B c C d D e E: f F g: G: h H: i I j J: k K l: L M: n m: N o O P p q+: Q+: r R: s S: t T u U v V w+: W: x X y Y z Z: 2: 3: 4 || (( $# )); then
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
          DO_PROMPT_CHECK="true"
          DO_RBENV_CHECK="true"
          DO_PYENV_CHECK="true"
          DO_PACKAGE_CHECK="true"
          PACKAGE_EXPLICIT="true"
          DO_FONTS_CHECK="true"
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
        -Q)
          CONFIG_SETS+=( "${OPTS[2]}" )
          shift 2 OPTS
          ;;
        -q)
          CONFIG_UNSETS+=( "${OPTS[2]}" )
          shift 2 OPTS
          ;;
        -w)
          CONFIG_GETS+=( "${OPTS[2]}" )
          shift 2 OPTS
          ;;
        -M)
          PROFILE="${OPTS[2]}"
          PROFILE_SWITCH="true"
          shift 2 OPTS
          ;;
        -H)
          MACHINE="${OPTS[2]}"
          MACHINE_SWITCH="true"
          shift 2 OPTS
          ;;
        -K)
          DO_CONFIG_EDIT="true"
          shift OPTS
          ;;
        -a)
          DO_ADOPT="true"
          shift OPTS
          ;;
        -j)
          DO_TIMING="true"
          set_inline_defaults
          shift OPTS
          ;;
        -Y)
          DO_FIX="true"
          shift OPTS
          ;;
        -u)
          DO_UNLINK="true"
          shift OPTS
          ;;
        -y)
          ASSUME_YES="true"
          shift OPTS
          ;;
        -W)
          case "${OPTS[2]}" in
            fnm|rustup|uv|mise|atuin)
              typeset -g "INSTALL_${(U)OPTS[2]}=true"
              DO_TOOLS_CHECK="true"
              DO_BUILD="true"
              DO_ENV_SETUP="true"
              ;;
            *)
              print -r -- "Unknown tool '${OPTS[2]}', choose from fnm, rustup, uv, mise or atuin"
              release_lock
              exit 1
              ;;
          esac
          shift 2 OPTS
          ;;
        -G)
          DO_DRIFT="true"
          DRIFT_WHAT="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -B)
          DO_BACKUPS="true"
          shift OPTS
          ;;
        -J)
          DO_DEFAULTS_UNDO="true"
          DEFAULTS_UNDO_TARGET="${OPTS[2]}"
          shift 2 OPTS
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
          PROMPT_ENGINE="posh"
          DO_PROMPT_CHECK="true"
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
          PROMPT_ENGINE="p10k"
          DO_PROMPT_CHECK="true"
          shift OPTS
          ;;
        -E)
          PROMPT_ENGINE="${OPTS[2]}"
          DO_PROMPT_CHECK="true"
          shift 2 OPTS
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
        -4)
          DO_PROMPT_PREVIEW="true"
          shift OPTS
          ;;
        -2)
          DO_EXPORT="true"
          EXPORT_TARGET="${OPTS[2]}"
          shift 2 OPTS
          ;;
        -3)
          DO_IMPORT="true"
          IMPORT_TARGET="${OPTS[2]}"
          shift 2 OPTS
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
    # --get tells a value somebody set from one the defaults below fill in, so note what is set before them
    if (( ${#CONFIG_GETS} )); then
      CONFIG_PRESET=( ${(k)parameters} )
    fi
  else
    set_inline_defaults
  fi

  STARTUP_MARKS+=( "arguments|${EPOCHREALTIME}" )

  # Set defaults (does not override anything set above)

  set_defaults
  STARTUP_MARKS+=( "set_defaults|${EPOCHREALTIME}" )

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

  # --adopt and --fix modify --drift and --doctor, and mean nothing without them

  if [ "${DO_ADOPT}" = "true" ] && [ ! "${DO_DRIFT}" = "true" ]; then
    print -u2 -r -- "Error:          --adopt goes with --drift (--drift packages --adopt)"
    release_lock
    exit 1
  fi
  if [ "${DO_FIX}" = "true" ] && [ ! "${DO_DOCTOR}" = "true" ]; then
    print -u2 -r -- "Error:          --fix goes with --doctor (--doctor --fix)"
    release_lock
    exit 1
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

  # Show the prompt layout (read only)

  if [ "${DO_PROMPT_PREVIEW}" = "true" ]; then
    print_prompt_preview
    release_lock
    exit
  fi

  # Write or read a bundle of your setup

  if [ "${DO_EXPORT}" = "true" ] || [ "${DO_IMPORT}" = "true" ]; then
    BUNDLE_STATUS=0
    if [ "${DO_EXPORT}" = "true" ] && [ "${DO_IMPORT}" = "true" ]; then
      print -u2 -r -- "Error:          --export and --import are two jobs, run one at a time"
      BUNDLE_STATUS=1
    elif [ "${DO_EXPORT}" = "true" ]; then
      export_bundle "${EXPORT_TARGET}" || BUNDLE_STATUS=1
    else
      import_bundle "${IMPORT_TARGET}" || BUNDLE_STATUS=1
    fi
    release_lock
    exit ${BUNDLE_STATUS}
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
    run_drift "${DRIFT_WHAT}"
    DRIFT_STATUS=$?
    if [ "${DO_ADOPT}" = "true" ]; then
      if [ "${DRIFT_WHAT}" = "settings" ]; then
        print -u2 -r -- "Error:          --adopt is for packages: --drift packages --adopt"
        DRIFT_STATUS=1
      else
        adopt_packages || DRIFT_STATUS=1
      fi
    fi
    release_lock
    exit ${DRIFT_STATUS}
  fi

  # Do config

  if [ "${DO_CONFIG}" = "true" ]; then
    init_config
    release_lock
    exit
  fi

  # Do --set, --unset and --get

  if (( ${#CONFIG_SETS} + ${#CONFIG_UNSETS} + ${#CONFIG_GETS} )) || [ "${DO_CONFIG_EDIT}" = "true" ]; then
    run_config_commands
    CONFIG_STATUS=$?
    release_lock
    exit ${CONFIG_STATUS}
  fi

  # Completion for this script's own switches and settings (files/completions/_ussuri). It only has to be on
  # the fpath before compinit runs, which the plugin lists do after this

  add_completions_dir

  STARTUP_MARKS+=( "history, completion dir|${EPOCHREALTIME}" )

  # Set Go PATH

  if [ -d "$GO_HOME" ]; then
    exp_env "PATH"    "${GO_HOME}"
    set_env "GOPATH"  "${GO_HOME}"  
  fi

  # Do sudoers

  if [ "${DO_SUDOERS_CHECK}" = "true" ]; then
    phase sudoers check_sudoers_config
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
    phase defaults check_defaults
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

  # Do list or undo of the defaults the script has changed

  if [ "${DO_DEFAULTS_UNDO}" = "true" ]; then
    do_defaults_undo "${DEFAULTS_UNDO_TARGET}"
    UNDO_STATUS=$?
    release_lock
    exit ${UNDO_STATUS}
  fi

  # Do dotfiles

  if [ "${DO_UNLINK}" = "true" ]; then
    dotfiles_unlink
    release_lock
    exit
  fi
  if [ "${DO_DOTFILES_CHECK}" = "true" ]; then
    phase dotfiles check_dotfiles_config
  fi
  phase dotfiles-sync check_dotfiles_sync

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
      phase brew check_brew_config
    fi
  fi

  # Do package check

  if [ "${DO_PACKAGE_CHECK}" = "true" ]; then
    phase packages check_package_config
  fi

  # Do font(s) check

  if [ "${DO_FONTS_CHECK}" = "true" ]; then
    phase fonts check_fonts_config
  fi

  if [ "${DO_POSH_CHECK}" = "true" ]; then
    phase posh check_posh_config
  fi

  # Do zinit checks

  if [ "${DO_ZINIT_CHECK}" = "true" ]; then
    phase zinit check_zinit_config
  fi

  # Do pyenv checks

  if [ "${DO_PYENV_CHECK}" = "true" ]; then
    phase pyenv check_pyenv_config
  fi

  # Do rbenv checks

  if [ "${DO_RBENV_CHECK}" = "true" ]; then
    phase rbenv check_rbenv_config
  fi

  # Do language and tool managers (fnm, rustup, uv, mise, atuin)

  if [ "${DO_TOOLS_CHECK}" = "true" ]; then
    phase tools check_tools_config
  fi

  # Do zoxide (after the plugin lists, which provide compdef for its completions)

  if [ "${DO_ZOXIDE_CHECK}" = "true" ]; then
    phase zoxide check_zoxide_config
  fi

  # Do Powerlevel10k config

  if [ "${DO_P10K_CHECK}" = "true" ]; then
    phase p10k check_p10k_config
  fi

  # Do oh-my-zsh config

  if [ "${DO_ZOSH_CHECK}" = "true" ]; then
    phase zosh check_zosh_config
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
    phase package-list update_package_list
  fi

  # Remove lock file

  release_lock

  # Do LDFLAGS check

  if [ "${DO_LDFLAGS_CHECK}" = "true" ]; then
    phase ldflags check_ldflags_config
  fi

  # Do PKGCONFIG check

  if [ "${DO_PKGCONFIG_CHECK}" = "true" ]; then
    phase pkgconfig check_pkgconfig_config
  fi

  # Do CPPFLAGS check

  if [ "${DO_CPPFLAGS_CHECK}" = "true" ]; then
    phase cppflags check_cppflags_config
  fi

  # Say if there is a newer version (off unless UPDATE_HINT=true)

  phase update-hint check_update_hint

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

  # --timing: the report, last, so it covers everything above

  print_timing
else
  release_lock
fi

# Set prompt

if [ "${MY_USERID}" = "0" ]; then
  export PS1="%n@%m %1#:"
else
  export PS1="%n@%m %1~:"
fi
