#!/usr/bin/env zsh
#
# Check that every package named in the shipped package lists exists in this system's package
# repositories. Nothing is installed: each name is only looked up. It is how the lists for apt,
# pacman, dnf, apk and Homebrew are kept honest, as a name that doesn't exist only shows up when -P
# fails to install it.
#
# Usage: zsh tests/package-names.zsh [-v]
#
# Needs a fresh package index (apt-get update, pacman -Sy, apk update), which the CI jobs do first. The system
# is worked out the way ussuri.zsh does it (its own functions are used), so USSURI_OS and OS_RELEASE_FILE
# work here too.
#
# Exit status: 0 if every name was found, 1 if some were not, 2 if there was nothing to check with.

ROOT="${0:A:h:h}"
VERBOSE="false"
[[ "$1" == "-v" ]] && VERBOSE="true"
setopt extendedglob

# The script's own detection, so the two can't drift apart
for f in set_env verbose_message set_linux_id set_pkg_manager; do
  eval "$( sed -n "/^${f} () {/,/^}/p" "${ROOT}/ussuri.zsh" )"
done

# The names in a shipped list: one per line, comments and blank lines ignored, !exclusions ignored
read_names () {
  print -rl -- ${${(f)"$(<${1})"}:#(\#*|[[:space:]]#|\!*)}
}

# Does this system's package manager know the name? (nothing is installed)
package_exists () {
  case "${CHECK_MANAGER}" in
    apt)    apt-cache show "$1" > /dev/null 2>&1 ;;
    pacman) pacman -Si "$1" > /dev/null 2>&1 ;;
    dnf)    # By name, or by what it provides: wget is provided by wget1-wget or wget2-wget, and dnf install takes either
            [[ -n "$( dnf -q repoquery "$1" 2> /dev/null )" || -n "$( dnf -q repoquery --whatprovides "$1" 2> /dev/null )" ]] ;;
    apk)    [[ -n "$( apk search -e "$1" 2> /dev/null )" ]] ;;
    brew)   brew info --formula --json=v2 "$1" > /dev/null 2>&1 || brew info --cask --json=v2 "$1" > /dev/null 2>&1 ;;
    brew-cask) brew info --cask --json=v2 "$1" > /dev/null 2>&1 ;;
    *)      return 2 ;;
  esac
}

typeset -a LISTS    # file:manager pairs to check
if [[ "${USSURI_OS:-${OSTYPE}}" == darwin* ]]; then
  (( $+commands[brew] )) || { print "Homebrew is not installed, nothing to check with"; exit 2 }
  LISTS=( "${ROOT}/files/packages/macos.brew:brew" "${ROOT}/files/packages/macos.cask:brew-cask" )
else
  OS_NAME="Linux"
  set_linux_id
  set_pkg_manager
  if [[ -z "${PKG_MANAGER}" || -z "${PKG_TOOL}" ]]; then
    print "No supported package manager here (distribution '${LSB_ID:-unknown}'), nothing to check with"
    exit 2
  fi
  if (( ! $+commands[${PKG_TOOL}] )); then
    print "${PKG_TOOL} is not installed, nothing to check with"
    exit 2
  fi
  if [[ "${PKG_MANAGER}" == nix ]]; then
    print "nix has no cheap name lookup, not checked"
    exit 2
  fi
  LISTS=( "${ROOT}/files/packages/${PKG_LIST_NAME}:${PKG_MANAGER}" )
fi

checked=0
unknown=()
for pair in "${LISTS[@]}"; do
  file="${pair%%:*}"
  CHECK_MANAGER="${pair##*:}"
  [[ -f "${file}" ]] || continue
  print -r -- "${file:t} (${CHECK_MANAGER})"
  for name in ${(f)"$( read_names "${file}" )"}; do
    checked=$(( checked + 1 ))
    if package_exists "${name:t}"; then
      [[ "${VERBOSE}" == true ]] && print -r -- "  ok       ${name}"
    else
      print -r -- "  NOT FOUND ${name}"
      unknown+=( "${file:t}: ${name}" )
    fi
  done
done

print
if (( ${#unknown} )); then
  print -r -- "${checked} names checked, ${#unknown} not found"
  exit 1
fi
print -r -- "${checked} names checked, all found"
