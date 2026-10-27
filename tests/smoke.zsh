#!/usr/bin/env zsh
#
# Smoke tests for ussuri.zsh
#
# Usage: zsh tests/smoke.zsh [test-name-filter]
#
# Everything runs in a throwaway $HOME with stubbed commands (defaults, brew, sudo, rbenv...)
# and against a copy of the script whose Homebrew location points at a stub brew, so nothing
# here touches the real system. Add a test by writing a function called test_<something>.

ROOT="${0:A:h:h}"
SRC="${ROOT}/ussuri.zsh"
TMP=$( mktemp -d )
trap 'rm -rf "${TMP}"' EXIT

# As the script does at its top level (a typeset inside a function would only be local)

typeset -U path

# The OS and kernel the sandbox pretends to be, so the tests behave the same on any host (a test that is
# about Linux sets USSURI_OS=linux itself). TEST_PATH_PREFIX goes in front of the sandbox's PATH, for
# trying another userland, e.g. GNU tools on a Mac: TEST_PATH_PREFIX=/opt/homebrew/opt/coreutils/libexec/gnubin:
TEST_OS_ENV=( USSURI_OS="${TEST_OS:-darwin}" USSURI_OS_REL="${TEST_OS_REL:-27.2.0}" )

STUBS="${TMP}/stubs"
LOG="${TMP}/calls.log"
SCRIPT="${TMP}/ussuri.zsh"
PASS=0
FAIL=0
EXTRA_ENV=()

# Output helpers

ok () {
  print -r -- "  ok    $1"
  PASS=$(( PASS + 1 ))
}

bad () {
  print -r -- "  FAIL  $1${2:+ ($2)}"
  FAIL=$(( FAIL + 1 ))
}

check () {
  if [[ "$2" == "$3" ]]; then
    ok "$1"
  else
    bad "$1" "got [$2], expected [$3]"
  fi
}

# Number of files matching a glob pattern

nfiles () {
  local f
  f=( ${~1}(N) )
  print -r -- "${#f}"
}

# Number of logged calls starting with the given text

calls () {
  local n
  n=$( grep -c "^$1" "${LOG}" 2> /dev/null )
  print -r -- "${n:-0}"
}

# Stubs

stub () {
  print -r -- "#!/bin/sh" > "${STUBS}/$1"
  print -r -- "$2" >> "${STUBS}/$1"
  chmod +x "${STUBS}/$1"
}

make_stubs () {
  mkdir -p "${STUBS}" "${TMP}/brew/bin"
  : > "${TMP}/installed.txt"
  : > "${TMP}/taps.txt"
  : > "${TMP}/casks.txt"
  : > "${TMP}/leaves.txt"
  stub defaults "echo \"defaults \$*\" >> ${LOG}; [ \"\$1\" = write ] && exit 0; exit 1"
  stub chflags  "echo \"chflags \$*\" >> ${LOG}"
  stub killall  "echo \"killall \$*\" >> ${LOG}"
  # brew: list is the installed formulae and casks together (installed.txt), list --cask the casks alone
  # (casks.txt), leaves the top level formulae (leaves.txt), tap the taps (taps.txt)
  cat > "${STUBS}/brew" << 'EOF'
#!/bin/sh
echo "brew $*" >> __LOG__
case "$1 $2" in
  "list --cask") cat __TMP__/casks.txt; exit 0 ;;
  "list --formula") cat __TMP__/installed.txt; exit 0 ;;
esac
# plain "brew list" is the formulae and the casks together, as the real one is
[ "$1" = list ] && { cat __TMP__/installed.txt; cat __TMP__/casks.txt; }
[ "$1" = leaves ] && cat __TMP__/leaves.txt
[ "$1" = tap ] && [ -z "$2" ] && cat __TMP__/taps.txt
[ "$1" = shellenv ] && echo 'export HOMEBREW_PREFIX=/stub'
exit 0
EOF
  sed -i.bak "s#__LOG__#${LOG}#; s#__TMP__#${TMP}#g" "${STUBS}/brew"
  chmod +x "${STUBS}/brew"
  stub sudo     "echo \"sudo \$*\" >> ${LOG}; case \"\$1\" in -n) exit 1;; visudo) shift; [ -x /usr/sbin/visudo ] && exec /usr/sbin/visudo \"\$@\";; install) cp \"\$4\" ${TMP}/sudoers.out; chmod \"\$3\" ${TMP}/sudoers.out;; esac; exit 0"
  stub rbenv    "echo \"rbenv \$*\" >> ${LOG}; [ \"\$1\" = init ] && printf 'export RBENV_SHELL=zsh\ncommand rbenv rehash 2>/dev/null || true\n'; exit 0"
  # What real pyenv prints for "init -", including the line that forks bash to tidy PATH
  cat > "${TMP}/pyenv.init" << 'EOF'
PATH="$(bash --norc -ec 'IFS=:; paths=($PATH); 
for i in ${!paths[@]}; do 
if [[ ${paths[i]} == "''/x/.pyenv/shims''" ]]; then unset '\''paths[i]'\''; 
fi; done; 
echo "${paths[*]}"')"
export PATH="/x/.pyenv/shims:${PATH}"
export PYENV_SHELL=zsh
command pyenv rehash 2>/dev/null || true
EOF
  stub pyenv    "echo \"pyenv \$*\" >> ${LOG}; [ \"\$1\" = init ] && cat ${TMP}/pyenv.init; exit 0"
  # zoxide init prints the same text every time; this one sets a variable so a test can see it was used
  stub zoxide "echo \"zoxide \$*\" >> ${LOG}; [ \"\$1\" = init ] && printf 'export ZOXIDE_INIT_RAN=1\\n__zoxide_z () { :; }\\n'; exit 0"
  stub oh-my-posh "echo \"oh-my-posh \$*\" >> ${LOG}; exit 0"
  cp "${TMP}/stubs/brew" "${TMP}/brew/bin/brew"
  # Point the copy of the script at the stub brew. If the pattern goes missing the real brew
  # could be used, so refuse to run rather than carry on.
  sed "s#/opt/homebrew/bin/brew /usr/local/homebrew/bin/brew /usr/local/bin/brew#${TMP}/brew/bin/brew#" "${SRC}" > "${SCRIPT}"
  if ! grep -q "${TMP}/brew/bin/brew" "${SCRIPT}"; then
    print -r -- "Cannot point the script at the stub brew (brew candidate list changed?), refusing to run"
    exit 2
  fi
}

# Fresh sandbox home with everything an inline (login) run expects to already be present,
# so it never tries to clone or install anything

new_home () {
  H="${TMP}/${HOME_NAME:-home}"
  rm -rf "${H}"
  mkdir -p "${H}/Library" "${H}/.ussuri/files" "${H}/.zinit" "${H}/.rbenv/bin" "${H}/.pyenv/bin" "${H}/.oh-my-posh"
  cp -R "${ROOT}/files/"* "${H}/.ussuri/files/"
  cp "${ROOT}/files/p10k/p10k.zsh" "${H}/.p10k.zsh"
  print -r -- 'zinit () { :; }' > "${H}/.zinit/zinit.zsh"
  print -r -- 'font-fira-code-nerd-font' > "${TMP}/installed.txt"
  : > "${TMP}/taps.txt"; : > "${TMP}/casks.txt"; : > "${TMP}/leaves.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  : > "${LOG}"
}

# Run the script in the sandbox. PATH deliberately leaves out /opt/homebrew

run () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" zsh "${SCRIPT}" "$@"
}

# Run with a time limit (for anything that could hang)

run_limited () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" perl -e 'alarm 15; exec @ARGV' zsh "${SCRIPT}" "$@"
}

# Pull a function out of the script so it can be tested on its own

load_function () {
  eval "$( sed -n "/^$1 () {/,/^}/p" "${SRC}" )"
}

# Run the script on a pseudo terminal, answering every y/n prompt with the given answer

run_on_tty () {
  local answer="$1"
  shift
  python3 - "${answer}" env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm "${TEST_OS_ENV[@]}" \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    zsh "${SCRIPT}" "$@" << 'EOF'
import os, pty, select, sys, time
answer = (sys.argv[1] + "\n").encode()
argv = sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
seen = b""
deadline = time.time() + 30
while time.time() < deadline:
    ready, _, _ = select.select([fd], [], [], 0.5)
    if not ready:
        continue
    try:
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    seen += data
    if b"[y/n]" in data:
        os.write(fd, answer)
sys.stdout.write(seen.decode("utf-8", "replace"))
os.waitpid(pid, 0)
EOF
}

# A sandbox home that looks like a complete, healthy install (the doctor should find nothing wrong)

healthy_home () {
  new_home
  cp "${SCRIPT}" "${H}/.zshrc"
  mkdir -p "${H}/.zinit" "${H}/.rbenv/plugins/ruby-build" "${H}/.pyenv" "${H}/.oh-my-posh" "${H}/Library/Fonts"
  print -r -- "#!/bin/sh" > "${H}/.oh-my-posh/oh-my-posh"; chmod +x "${H}/.oh-my-posh/oh-my-posh"
  : > "${H}/Library/Fonts/FiraCodeNerdFont-Regular.ttf"
  : > "${H}/.ussuri/defaults.stamp"
}

# Dotfiles laid out in layers: common, a named profile, and a specific host

make_dotfiles () {
  local d="${H}/.ussuri/dotfiles"
  mkdir -p "${d}/common/.config/app" "${d}/profiles/work" "${d}/hosts/box/.config/app"
  print -r -- "common gitconfig" > "${d}/common/.gitconfig"
  print -r -- "common app"       > "${d}/common/.config/app/conf"
  print -r -- "work gitconfig"   > "${d}/profiles/work/.gitconfig"
  print -r -- "box app"          > "${d}/hosts/box/.config/app/conf"
  print -r -- "only on box"      > "${d}/hosts/box/.hostonly"
  : > "${d}/common/.DS_Store"
}

# Backups of ~/.zshrc the way --install makes them, with known ages (oldest first)

make_backups () {
  local d="${H}/.ussuri"
  printf '%s\n' "# my original zshrc" > "${d}/.zshrc.01_01_2026_10_00_00"
  printf '%s\n' "# Version: 1.0.0" 'SCRIPT_NAME="ussuri"' > "${d}/.zshrc.02_02_2026_10_00_00"
  printf '%s\n' "# Version: 1.2.0" 'SCRIPT_NAME="ussuri"' > "${d}/.zshrc.03_03_2026_10_00_00"
  touch -t 202601011000 "${d}/.zshrc.01_01_2026_10_00_00"
  touch -t 202602021000 "${d}/.zshrc.02_02_2026_10_00_00"
  touch -t 202603031000 "${d}/.zshrc.03_03_2026_10_00_00"
  printf '%s\n' "# Version: 1.4.2" 'SCRIPT_NAME="ussuri"' > "${H}/.zshrc"
}

# A defaults stub that remembers what is written to it, so what was applied can be read back
# (the plain stub forgets everything, so every setting looks unset)

use_stateful_defaults () {
  DEFAULTS_DB="${TMP}/defaults.db"
  : > "${DEFAULTS_DB}"
  stub defaults "echo \"defaults \$*\" >> ${LOG}
db=${DEFAULTS_DB}
case \"\$1\" in
  read)
    v=\$( grep -F \"\$2|\$3|\" \"\$db\" | tail -1 )
    [ -z \"\$v\" ] && exit 1
    printf '%s\\n' \"\${v#\$2|\$3|}\"; exit 0 ;;
  write)
    v=\"\$5\"; [ \"\$v\" = true ] && v=1; [ \"\$v\" = false ] && v=0
    echo \"\$2|\$3|\$v\" >> \"\$db\"; exit 0 ;;
esac
exit 1"
}

use_plain_defaults () {
  stub defaults "echo \"defaults \$*\" >> ${LOG}; [ \"\$1\" = write ] && exit 0; exit 1"
}

# A gsettings stub with a remembered state. Keys not in the state do not exist (as on a desktop without them).
# State lines are schema|key|value, values written the way gsettings prints them (true, 'text', uint32 250)

use_gsettings () {
  GSETTINGS_DB="${TMP}/gsettings.db"
  : > "${GSETTINGS_DB}"
  stub gsettings "echo \"gsettings \$*\" >> ${LOG}
db=${GSETTINGS_DB}
case \"\$1\" in
  get)
    v=\$( grep -F \"\$2|\$3|\" \"\$db\" | tail -1 )
    [ -z \"\$v\" ] && exit 1
    printf '%s\\n' \"\${v#\$2|\$3|}\"; exit 0 ;;
  set)
    old=\$( grep -F \"\$2|\$3|\" \"\$db\" | tail -1 )
    pre=''; case \"\${old#\$2|\$3|}\" in 'uint32 '*) pre='uint32 ';; esac
    grep -v -F \"\$2|\$3|\" \"\$db\" > \"\$db.n\"; mv \"\$db.n\" \"\$db\"
    echo \"\$2|\$3|\$pre\$4\" >> \"\$db\"; exit 0 ;;
esac
exit 1"
}

# Fill the state with every key the script knows, all with a wrong value (or with the right one)

seed_gsettings () {
  local line schema key value WRONG="$1"
  grep -E '^  set_linux_default ' "${SRC}" | while read -r line; do
    eval "set -- ${line#set_linux_default }"
    schema="$1"; key="$2"; value="$3"
    if [[ "${WRONG}" == wrong ]]; then
      case "${value}" in true) value=false;; false) value=true;; uint32*) value="uint32 1";; *) value="'wrong'";; esac
    fi
    print -r -- "${schema}|${key}|${value}" >> "${GSETTINGS_DB}"
  done
}

# Stubs for every Linux package manager, logging what they are asked to do

make_linux_stubs () {
  local c
  for c in apt apt-get pacman dnf apk nix; do
    stub "${c}" "echo \"${c} \$*\" >> ${LOG}; exit 0"
  done
  stub dpkg "echo \"dpkg \$*\" >> ${LOG}; printf 'ii  git  1.0 all x\\n'"
  stub rpm  "echo \"rpm \$*\" >> ${LOG}; printf 'git\\n'"
  # the explicitly installed packages (${TMP}/manual.txt, one per line), for the drift report
  stub apt-mark "echo \"apt-mark \$*\" >> ${LOG}; cat ${TMP}/manual.txt 2> /dev/null; exit 0"
  stub pacman "echo \"pacman \$*\" >> ${LOG}; case \"\$1\" in -Q) printf 'git 1.0\\n';; -Qqe) cat ${TMP}/manual.txt 2> /dev/null;; esac; exit 0"
  stub dnf "echo \"dnf \$*\" >> ${LOG}; [ \"\$1\" = repoquery ] && cat ${TMP}/manual.txt 2> /dev/null; exit 0"
  stub apk "echo \"apk \$*\" >> ${LOG}; [ \"\$1\" = info ] && printf 'git\\n'; exit 0"
}

# The stubs make_linux_stubs adds, taken away again so one test's package managers aren't there for the next

remove_linux_stubs () {
  local c
  for c in apt apt-get pacman dnf apk nix dpkg rpm; do
    rm -f "${STUBS}/${c}"
  done
}

# Run the package check (-P) as the given distro, with an installed list that has only git

linux_packages () {
  local manager="$1" osid="$2" like="$3" listfile="$4"
  new_home
  print -r -- "ID=${osid}" > "${TMP}/os-release"
  [[ -n "${like}" ]] && print -r -- "ID_LIKE=\"${like}\"" >> "${TMP}/os-release"
  print -r -- "git" > "${H}/.ussuri/${manager}.list"
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" )
  : > "${LOG}"
  run -P > /dev/null 2>&1
  EXTRA_ENV=()
}

# Local stand-ins for the four tool installers. Each logs how it was called (arguments and the
# environment variable it cares about) and creates a stub of the tool where the real one would go

make_tool_installers () {
  local d="${TMP}/tools" f
  mkdir -p "${d}"
  # The tools the installers drop in place. __LOG__ is replaced with the log file when they are made
  cat > "${d}/fnm.stub" << 'EOF'
#!/bin/sh
echo "fnm $*" >> __LOG__
[ "$1" = env ] && echo "export FNM_ENV_RAN=1"
exit 0
EOF
  cat > "${d}/rustup.stub" << 'EOF'
#!/bin/sh
echo "rustup $*" >> __LOG__
exit 0
EOF
  cat > "${d}/uv.stub" << 'EOF'
#!/bin/sh
echo "uv $*" >> __LOG__
exit 0
EOF
  cat > "${d}/mise.stub" << 'EOF'
#!/bin/sh
echo "mise $*" >> __LOG__
[ "$1" = activate ] && echo "export MISE_ACTIVATED=1"
exit 0
EOF
  for f in fnm rustup uv mise; do
    sed "s#__LOG__#${LOG}#" "${d}/${f}.stub" > "${d}/${f}.tool"
  done
  # The installers: log how they were called, then put the tool where the real one would go
  cat > "${d}/fnm.sh" << EOF
#!/bin/sh
echo "installer fnm \$*" >> ${LOG}
dir=; while [ \$# -gt 0 ]; do [ "\$1" = --install-dir ] && dir=\$2; shift; done
mkdir -p "\$dir"; cp ${d}/fnm.tool "\$dir/fnm"; chmod +x "\$dir/fnm"
EOF
  cat > "${d}/rustup.sh" << EOF
#!/bin/sh
echo "installer rustup \$*" >> ${LOG}
mkdir -p "${H}/.cargo/bin"; cp ${d}/rustup.tool "${H}/.cargo/bin/rustup"; chmod +x "${H}/.cargo/bin/rustup"
EOF
  cat > "${d}/uv.sh" << EOF
#!/bin/sh
echo "installer uv no_modify_path=\${UV_NO_MODIFY_PATH:-unset}" >> ${LOG}
mkdir -p "${H}/.local/bin"; cp ${d}/uv.tool "${H}/.local/bin/uv"; chmod +x "${H}/.local/bin/uv"
EOF
  cat > "${d}/mise.sh" << EOF
#!/bin/sh
echo "installer mise path=\${MISE_INSTALL_PATH:-unset}" >> ${LOG}
dest="\${MISE_INSTALL_PATH:-${H}/.local/bin/mise}"
mkdir -p "\$(dirname "\$dest")"; cp ${d}/mise.tool "\$dest"; chmod +x "\$dest"
EOF
  TOOL_ENV=( FNM_INSTALL_URL="file://${d}/fnm.sh" RUSTUP_INSTALL_URL="file://${d}/rustup.sh" UV_INSTALL_URL="file://${d}/uv.sh" MISE_INSTALL_URL="file://${d}/mise.sh" )
}

# Source the script as a login shell would and print the history state it leaves behind
# (options only exist in the shell that sets them, so they have to be read back from inside it)

history_state () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1
print -r -- "size=${HISTSIZE} save=${SAVEHIST} file=${HISTFILE} dups=${options[histignoredups]} space=${options[histignorespace]} find=${options[histfindnodups]} blanks=${options[histreducebLanks]:-${options[histreduceblanks]}} share=${options[sharehistory]}"' zsh "${SCRIPT}"
}

# Source the script as a login shell and say which prompt engine's setup ran (the sandbox p10k config
# sets a variable when it is sourced, and the oh-my-posh stub logs its init)

prompt_state () {
  print -r -- 'export P10K_SOURCED=1' > "${H}/.p10k.zsh"
  : > "${LOG}"
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1; print -r -- "p10k=${P10K_SOURCED:-no} engine=${PROMPT_ENGINE:-unset}"' zsh "${SCRIPT}" > "${TMP}/prompt.out"
  print -r -- "$( cat "${TMP}/prompt.out" ) posh=$( calls 'oh-my-posh init zsh' )"
}

# A release the way GitHub serves one: a tarball with one top directory holding the script and files/.
# files/zinit/brandnew.zsh is new, files/packages/macos.brew is changed, files/packages/ubuntu.apt is not

make_release () {
  local version="$1" d="${TMP}/rel/ussuri-main"
  rm -rf "${TMP}/rel"
  mkdir -p "${d}/files/zinit" "${d}/files/packages"
  sed "s/^# Version: .*/# Version: ${version}/" "${SCRIPT}" > "${d}/ussuri.zsh"
  print -r -- "# a list that did not exist before" > "${d}/files/zinit/brandnew.zsh"
  cp "${ROOT}/files/packages/macos.brew" "${d}/files/packages/macos.brew"
  print -r -- "a-new-package" >> "${d}/files/packages/macos.brew"
  cp "${ROOT}/files/packages/ubuntu.apt" "${d}/files/packages/ubuntu.apt"
  tar -czf "${TMP}/rel.tgz" -C "${TMP}/rel" ussuri-main
  RELEASE_ENV=( SCRIPT_URL="file://${d}/ussuri.zsh" UPDATE_URL="file://${TMP}/rel.tgz" )
}

# Run -U against the copy of the script in ${TMP}/live (so the real one is not replaced)

run_update () {
  mkdir -p "${TMP}/live"
  cp "${SCRIPT}" "${TMP}/live/ussuri.zsh"
  ( SCRIPT="${TMP}/live/ussuri.zsh"; EXTRA_ENV=( "${RELEASE_ENV[@]}" "${UPDATE_ENV[@]}" ); run -U "$@" 2>&1 )
}

# A defaults stub that remembers types as well as values, and supports read-type and delete, like the
# real one. State lines are domain|key|type|value (type: boolean, integer, float, string, array...).
# Writes to com.apple.addressbook are accepted and silently ignored, as they are on a real Mac where that
# domain doesn't take (an apply must not claim to have changed it)

use_typed_defaults () {
  DEFAULTS_DB="${TMP}/defaults.db"
  : > "${DEFAULTS_DB}"
  cat > "${STUBS}/defaults" << 'EOF'
#!/bin/sh
echo "defaults $*" >> __LOG__
db=__DB__
case "$1" in
  read)
    v=$(grep -F "$2|$3|" "$db" | tail -1)
    [ -z "$v" ] && exit 1
    rest=${v#"$2|$3|"}
    printf '%s\n' "${rest#*|}"; exit 0 ;;
  read-type)
    v=$(grep -F "$2|$3|" "$db" | tail -1)
    [ -z "$v" ] && exit 1
    rest=${v#"$2|$3|"}
    echo "Type is ${rest%%|*}"; exit 0 ;;
  write)
    [ "$2" = com.apple.addressbook ] && exit 0
    val=$5
    case "$4" in
      -bool) tn=boolean; [ "$val" = true ] && val=1; [ "$val" = false ] && val=0 ;;
      -int) tn=integer ;;
      -float) tn=float ;;
      *) tn=string ;;
    esac
    grep -v -F "$2|$3|" "$db" > "$db.n"; mv "$db.n" "$db"
    echo "$2|$3|$tn|$val" >> "$db"; exit 0 ;;
  delete)
    grep -v -F "$2|$3|" "$db" > "$db.n"; mv "$db.n" "$db"; exit 0 ;;
esac
exit 1
EOF
  sed -i.bak "s#__LOG__#${LOG}#; s#__DB__#${DEFAULTS_DB}#" "${STUBS}/defaults"
  chmod +x "${STUBS}/defaults"
  # the Transmission blocklist URL is checked before it is written: keep that off the network
  : | gzip -c > "${TMP}/blocklist.gz"
  UNDO_ENV=( TRANSMISSION_BLOCKLIST_URL="file://${TMP}/blocklist.gz" )
}

# Settings that differ from what the script wants, of different types, to be restored later

seed_defaults () {
  printf '%s\n' \
    "com.apple.dock|tilesize|integer|48" \
    "com.apple.finder|ShowPathbar|boolean|0" \
    "com.apple.screencapture|type|string|jpg" \
    "com.apple.dock|autohide-time-modifier|float|0.25" \
    "com.apple.screencapture|location|string|it's \"quoted\" here" >> "${DEFAULTS_DB}"
}

journal_lines () {
  grep -c -v -E '^(#|UNDONE|$)' "${H}/.ussuri/defaults.journal" 2> /dev/null || print 0
}

# Source the script as an interactive login shell would and report the update hint's state. -i because the
# hint is only for interactive shells. The remote the check fetches is a stub curl serving ${TMP}/remote-script

hint_state () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" zsh -i -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1
print -r -- "hook=${+precmd_functions[(r)show_update_hint]}"' zsh "${SCRIPT}" 2> /dev/null
}

# A curl that logs its calls and serves a script with the given version (optionally slowly, or garbage)

make_hint_remote () {
  local version="$1"
  if [[ "${version}" == garbage ]]; then
    print -r -- "<html>not found</html>" > "${TMP}/remote-script"
  else
    printf '%s\n' '#!/usr/bin/env zsh' '#' "# Version: ${version}" '#' > "${TMP}/remote-script"
  fi
  # Only the hint's own request (curl -fsS -m 15 URL) gets the script or the delay: applying the defaults
  # also uses curl, to check the Transmission blocklist URL, and that must neither wait nor be counted
  stub curl "echo \"curl \$*\" >> ${LOG}; if [ \"\$1\" = -fsS ]; then [ -n \"\${CURL_DELAY}\" ] && sleep \${CURL_DELAY}; cat ${TMP}/remote-script; fi; exit 0"
}

# Wait (up to five seconds) for the background check to write its answer

wait_for_latest () {
  local i
  for i in {1..25}; do
    [[ -f "${H}/.ussuri/update.latest" ]] && return 0
    sleep 0.2
  done
  return 1
}

# Run the script as a login shell with a p10k config like the shipped one (a single line prompt) and a p10k
# that logs what it is told, and report what the layout ended up as

layout_state () {
  cat > "${H}/.p10k.zsh" << EOF
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( os_icon dir vcs )
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=( status time context )
typeset -g POWERLEVEL9K_CONTEXT_{DEFAULT,SUDO}_CONTENT_EXPANSION=
p10k () { print -r -- "p10k \$*" >> ${LOG}; }
EOF
  : > "${LOG}"
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" "${TEST_OS_ENV[@]}" "${EXTRA_ENV[@]}" \
    zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1
print -r -- "left=${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]} | right=${POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[*]} | context=${POWERLEVEL9K_CONTEXT_DEFAULT_CONTENT_EXPANSION:-hidden}"' zsh "${SCRIPT}"
}

# Tests

test_syntax () {
  zsh -n "${SRC}" && ok "script parses" || bad "script parses"
  check "stub brew is what runs, not the real one" "$( env -i PATH="${TEST_PATH_PREFIX}${STUBS}:/usr/bin:/bin" sh -c 'command -v brew' )" "${STUBS}/brew"
}

test_version () {
  new_home
  check "--version prints only the version" "$( run --version 2>&1 )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
}

test_dryrun_is_dry () {
  new_home
  run --dryrun > /dev/null 2>&1
  check "--dryrun writes no defaults" "$( calls 'defaults write' )" "0"
  check "--dryrun leaves no lock" "$( [[ -e "${H}/.ussuri.lock" ]] && echo yes || echo no )" "no"
  run --help > /dev/null 2>&1
  run --version > /dev/null 2>&1
  check "--help/--version write no defaults" "$( calls 'defaults write' )" "0"
  check "--help/--version leave no lock" "$( [[ -e "${H}/.ussuri.lock" ]] && echo yes || echo no )" "no"
}

test_no_stray_files () {
  new_home
  rm -rf "${H}/.ussuri"
  local before after
  before=$( ls "${ROOT}" | tr '\n' ' ' )
  ( cd "${ROOT}" && run --dryrun > /dev/null 2>&1 )
  after=$( ls "${ROOT}" | tr '\n' ' ' )
  check "files/ is not unpacked into the current directory" "${after}" "${before}"
}

test_locking () {
  new_home
  mkdir "${H}/.ussuri.lock"
  run --defaults > /dev/null 2>&1
  check "a held lock blocks changes" "$( calls 'defaults write' )" "0"
  touch -t "$( date -v-20M +%Y%m%d%H%M 2> /dev/null || date -d '20 minutes ago' +%Y%m%d%H%M )" "${H}/.ussuri.lock"
  run --defaults > /dev/null 2>&1
  check "a stale lock is taken over" "$( [[ $( calls 'defaults write' ) -gt 0 ]] && echo yes || echo no )" "yes"
  check "and released afterwards" "$( [[ -e "${H}/.ussuri.lock" ]] && echo no || echo yes )" "yes"
  mkdir "${H}/.ussuri.lock"; : > "${LOG}"
  run --defaults --force > /dev/null 2>&1
  check "--force clears a live lock" "$( [[ $( calls 'defaults write' ) -gt 0 ]] && echo yes || echo no )" "yes"
  rm -rf "${H}/.ussuri.lock"; touch "${H}/.ussuri.lock"; : > "${LOG}"
  run --defaults > /dev/null 2>&1
  check "an old-style lock file is honoured" "$( calls 'defaults write' )" "0"
}

test_switch_values_are_not_switches () {
  new_home
  run --dryrun -S install > /dev/null 2>&1
  check "-S install does not trigger --install" "$( [[ -e "${H}/.zshrc" ]] && echo yes || echo no )" "no"
}

test_defaults_stamp () {
  new_home
  run > /dev/null 2>&1
  check "first login applies defaults" "$( [[ $( calls 'defaults write' ) -gt 0 ]] && echo yes || echo no )" "yes"
  check "and writes a stamp" "$( [[ -f "${H}/.ussuri/defaults.stamp" ]] && echo yes || echo no )" "yes"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "next login does not read a single default" "$( calls 'defaults' )" "0"
  run -D > /dev/null 2>&1
  check "-D forces a reapply" "$( [[ $( calls 'defaults read' ) -gt 0 ]] && echo yes || echo no )" "yes"
}

test_hostile_paths () {
  # A home directory with spaces, quotes and a command substitution in its name must be treated as
  # plain text, never executed
  HOME_NAME="ho me's \$(touch ${TMP}/pwned) \`touch ${TMP}/pwned2\` (x)"
  new_home
  rm -f "${TMP}/pwned" "${TMP}/pwned2"
  print -r -- "# old zshrc" > "${H}/.zshrc"
  run --defaults > /dev/null 2>&1
  run --install > /dev/null 2>&1
  check "nothing in the path was executed" "$( [[ -e "${TMP}/pwned" || -e "${TMP}/pwned2" ]] && echo executed || echo safe )" "safe"
  check "defaults were still applied" "$( [[ $( calls 'defaults write' ) -gt 0 ]] && echo yes || echo no )" "yes"
  check "and the stamp landed in the right place" "$( [[ -f "${H}/.ussuri/defaults.stamp" ]] && echo yes || echo no )" "yes"
  check "--install copied the script to .zshrc" "$( grep -c '^# Version:' "${H}/.zshrc" )" "1"
  unset HOME_NAME
}

test_arguments () {
  new_home
  local out rc
  out=$( run_limited -g 2>&1 ); rc=$?
  check "a switch missing its value ends (no endless loop)" "$( [[ ${rc} -ne 142 && ${rc} -ne 14 ]] && echo ended || echo hung )" "ended"
  check "and is reported as an error" "$( [[ ${rc} -ne 0 ]] && echo error || echo ok )" "error"
  out=$( run_limited --no-such-switch 2>&1 ); rc=$?
  check "an unknown switch prints usage" "$( print -r -- "${out}" | grep -c 'Usage:' )" "1"
  out=$( run_limited stray-argument 2>&1 )
  check "a stray argument prints usage" "$( print -r -- "${out}" | grep -c 'Usage:' )" "1"
  check "long and short forms are equivalent" "$( run --verbose --dryrun --noenv 2>&1 | grep -c 'Running without executing' )" "$( run -v -t -N 2>&1 | grep -c 'Running without executing' )"
  check "short switches can be bundled (-vt)" "$( run -vt 2>&1 | grep -c 'Running without executing' )" "1"
  out=$( run -S "ALL=(ALL) --build" -t -v 2>&1 )
  check "a value that looks like a switch is a value" "$( print -r -- "${out}" | grep -c 'SUDOERS_ENTRY.*--build' )" "0"
  check "switch order is kept (-A then -n)" "$( run -A -n --dryrun --verbose 2>&1 | grep -c 'Usage' )" "0"
  check "--gopath sets GOPATH" "$( mkdir -p "${H}/mygo"; run -g "${H}/mygo" -t -v 2>&1 | grep -c 'GOPATH' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
}

test_installers_and_clones () {
  new_home
  # Functions under test, with the helpers they rely on
  load_function fetch_url
  load_function sha256_of
  load_function notice_message
  load_function fetch_and_run
  load_function git_clone
  handle_output () { :; }
  local dir="${TMP}/inst" marker="${TMP}/ran" good bad
  mkdir -p "${dir}"
  print -r -- 'echo "$@" > '"${marker}" > "${dir}/install.sh"
  good=$( shasum -a 256 "${dir}/install.sh" 2> /dev/null || sha256sum "${dir}/install.sh" )
  good="${good%% *}"
  bad="0000000000000000000000000000000000000000000000000000000000000000"
  rm -f "${marker}"
  fetch_and_run "file://${dir}/install.sh" "${good}" -d /somewhere > /dev/null 2>&1
  check "a pinned installer with the right checksum runs, with its arguments" "$( cat "${marker}" 2> /dev/null )" "-d /somewhere"
  rm -f "${marker}"
  fetch_and_run "file://${dir}/install.sh" "${bad}" > /dev/null 2>&1
  check "a checksum mismatch is refused" "$( [[ -e "${marker}" ]] && echo ran || echo refused )" "refused"
  rm -f "${marker}"
  fetch_and_run "file://${dir}/install.sh" "" > /dev/null 2>&1
  check "an unpinned installer still runs" "$( [[ -e "${marker}" ]] && echo ran || echo refused )" "ran"
  fetch_and_run "file://${dir}/missing.sh" "" > /dev/null 2>&1
  check "a failed download is an error, nothing is run" "$?" "1"
  check "the unpinned installer is announced" "$( fetch_and_run "file://${dir}/install.sh" "" 2>&1 | grep -c 'not pinned' )" "1"
  check "nothing is piped into a shell any more" "$( grep -c -E '\| *(ba)?sh\b|bash -c .*curl' "${SRC}" )" "0"

  # git clones: default is unchanged, a ref pins the checkout
  local repo="${TMP}/repo"
  git init -q "${repo}" && git -C "${repo}" config user.email t@t && git -C "${repo}" config user.name t
  print one > "${repo}/f"; git -C "${repo}" add f; git -C "${repo}" commit -qm one; git -C "${repo}" tag v1
  print two > "${repo}/f"; git -C "${repo}" commit -qam two
  git_clone "file://${repo}" "${TMP}/c1" "" > /dev/null 2>&1
  check "clone without a ref is the latest" "$( cat "${TMP}/c1/f" )" "two"
  git_clone "file://${repo}" "${TMP}/c2" "v1" > /dev/null 2>&1
  check "clone with a ref is pinned to it" "$( cat "${TMP}/c2/f" )" "one"
  git_clone "file://${repo}" "${TMP}/c3" "" 1 > /dev/null 2>&1
  check "clone with a depth is shallow" "$( git -C "${TMP}/c3" rev-list --count HEAD )" "1"
}

test_guards () {
  load_function have_lock
  load_function is_osx
  load_function is_linux
  HOLD_LOCK="true";  have_lock && ok "have_lock when the lock is held" || bad "have_lock when the lock is held"
  HOLD_LOCK="false"; have_lock && bad "no lock" || ok "no lock"
  OS_NAME="Darwin";    is_osx && ! is_linux && ok "Darwin is OS X only" || bad "Darwin is OS X only"
  OS_NAME="Linux";     is_linux && ! is_osx && ok "Linux is Linux only" || bad "Linux is Linux only"
  OS_NAME="GNU/Linux"; is_linux && ok "GNU/Linux (before it is tidied up) is Linux" || bad "GNU/Linux is Linux"
  unset HOLD_LOCK OS_NAME

  # copy_support_files only copies when both ends exist, so tar can never unpack in the wrong place
  load_function copy_support_files
  execute_command () { print -r -- "$1" >> "${TMP}/copy.log"; }
  : > "${TMP}/copy.log"
  SCRIPT_DIR="${ROOT}"; WORK_DIR="${TMP}/nowhere"
  copy_support_files
  check "no copy when the work directory does not exist" "$( wc -l < "${TMP}/copy.log" | tr -d ' ' )" "0"
  mkdir -p "${WORK_DIR}/files"
  copy_support_files
  check "copies when both exist" "$( wc -l < "${TMP}/copy.log" | tr -d ' ' )" "1"
  SCRIPT_DIR="/usr/bin"; : > "${TMP}/copy.log"
  copy_support_files
  check "never copies from /usr/bin" "$( wc -l < "${TMP}/copy.log" | tr -d ' ' )" "0"
  unset SCRIPT_DIR WORK_DIR
  unfunction execute_command
}

test_init_cache_strips_forks () {
  new_home
  run > /dev/null 2>&1
  local cache
  cache=( "${H}"/.ussuri/cache/*pyenv* )
  check "pyenv's bash PATH-dedupe fork is left out of the cache" "$( grep -c 'bash --norc' "${cache[1]}" )" "0"
  check "the rest of the pyenv init is kept" "$( grep -c 'PYENV_SHELL' "${cache[1]}" )" "1"
}

test_zinit_turbo () {
  new_home
  local out
  out=$( run --dryrun --verbose --zinit 2>&1 )
  check "turbo plugin list is the default" "$( print -r -- "${out}" | grep -c 'ZINIT_FILE.*zinit-turbo.zsh' )" "1"
  out=$( EXTRA_ENV=( ZINIT_TURBO=false ); run --dryrun --verbose --zinit 2>&1 )
  check "ZINIT_TURBO=false uses the original list" "$( print -r -- "${out}" | grep -c 'ZINIT_FILE.*/zinit/zinit.zsh' )" "1"
  # Both lists must load the same plugins and snippets, in the same order
  local eager turbo
  eager=$( grep -o 'zinit \(light\|snippet\) [^ ;]*' "${ROOT}/files/zinit/zinit.zsh" | grep -v powerlevel10k | tr '\n' ',' )
  turbo=$( grep -o 'zinit \(light\|snippet\) [^ ;]*' "${ROOT}/files/zinit/zinit-turbo.zsh" | grep -v powerlevel10k | tr '\n' ',' )
  check "turbo loads the same plugins as the eager list, in the same order" "${turbo}" "${eager}"
  check "the prompt is not deferred" "$( grep -c 'wait.*powerlevel10k' "${ROOT}/files/zinit/zinit-turbo.zsh" )" "0"
}

test_zinit_file_missing () {
  new_home
  rm -f "${H}/.ussuri/files/zinit/zinit-turbo.zsh"
  local out
  out=$( run --zinit --dryrun --verbose 2>&1 )
  check "an install without the turbo file falls back to the original list" "$( print -r -- "${out}" | grep -c "source.*zinit/zinit.zsh\|Executing: *zinit light zsh-users/zsh-syntax-highlighting" | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  check "and does not run the (missing) turbo list" "$( print -r -- "${out}" | grep -c 'wait lucid' )" "0"
  # With the repo next to the script, only the one missing file is copied, and a list you have edited is left alone
  mkdir -p "${TMP}/files"; cp -R "${ROOT}/files/"* "${TMP}/files/"
  print -r -- "# my own edited list" > "${H}/.ussuri/files/zinit/zinit.zsh"
  run --zinit > /dev/null 2>&1
  check "the missing turbo file is copied from next to the script" "$( [[ -f "${H}/.ussuri/files/zinit/zinit-turbo.zsh" ]] && echo yes || echo no )" "yes"
  check "an edited list is not overwritten" "$( head -1 "${H}/.ussuri/files/zinit/zinit.zsh" )" "# my own edited list"
  rm -rf "${TMP}/files"
}

test_doctor () {
  healthy_home
  local out rc before after
  before=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  out=$( run --doctor 2>&1 ); rc=$?
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "a healthy install has no failures" "$( print -r -- "${out}" | grep -c 'FAIL' )" "0"
  check "and exits 0" "${rc}" "0"
  check "the summary is printed" "$( print -r -- "${out}" | grep -c -E '[0-9]+ ok, [0-9]+ warning' )" "1"
  check "it changes nothing in the home directory" "${after}" "${before}"
  check "and writes no defaults" "$( calls 'defaults write' )" "0"
  check "and leaves no lock" "$( [[ -e "${H}/.ussuri.lock" ]] && echo yes || echo no )" "no"
  check "--doctor works through its long and short forms" "$( run -x 2>&1 | grep -c -E '[0-9]+ ok, ' )" "1"

  # A broken install is reported, and the doctor does not repair it as a side effect
  rm -rf "${H}/.ussuri/files"
  out=$( run --doctor 2>&1 ); rc=$?
  check "missing support files is a failure" "$( print -r -- "${out}" | grep -c 'FAIL.*files' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  check "and the exit status says so" "$( [[ ${rc} -ne 0 ]] && echo nonzero || echo zero )" "nonzero"
  check "the doctor did not recreate them" "$( [[ -d "${H}/.ussuri/files" ]] && echo recreated || echo still-missing )" "still-missing"
}

test_doctor_warnings () {
  healthy_home
  local out
  rm -f "${H}/Library/Fonts/"*
  out=$( run --doctor 2>&1 )
  check "a missing Nerd Font is a warning" "$( print -r -- "${out}" | grep -c 'warn.*[Ff]ont' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  healthy_home
  local i
  for i in 01 02 03 04 05 06 07 08 09 10 11 12; do : > "${H}/.ussuri/.zshrc.${i}_01_2026_00_00_00"; done
  out=$( run --doctor 2>&1 )
  check "piled up .zshrc backups are a warning" "$( print -r -- "${out}" | grep -c 'warn.*12.*backup' )" "1"
  healthy_home
  print -r -- "# Version: 0.0.1" > "${H}/.zshrc"
  out=$( run --doctor 2>&1 )
  check "an out of date ~/.zshrc is a warning" "$( print -r -- "${out}" | grep -c 'warn.*0.0.1' )" "1"
  healthy_home
  mkdir "${H}/.ussuri.lock"
  out=$( run --doctor 2>&1 )
  check "a held lock is a warning" "$( print -r -- "${out}" | grep -c 'warn.*lock' )" "1"
  healthy_home
  rm -rf "${H}/.rbenv"
  out=$( run --doctor 2>&1 )
  check "a missing component is reported" "$( print -r -- "${out}" | grep -c 'rbenv' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  healthy_home
  out=$( EXTRA_ENV=( PATH_ADD=1 ); run --doctor 2>&1 )
  check "the report names the OS" "$( print -r -- "${out}" | head -1 | grep -c 'doctor' )" "1"
}

test_config () {
  new_home
  local cfg="${H}/.ussuri/config" out
  check "no config file is fine" "$( run --help 2>&1 | grep -c 'Build sources.*false' )" "1"
  print -r -- 'DO_BUILD=true' > "${cfg}"
  check "a setting in the config changes the default" "$( run --help 2>&1 | grep -c 'Build sources.*true' )" "1"
  print -r -- 'GO_HOME=/somewhere/go' > "${cfg}"
  check "including settings the script assigns itself (GO_HOME)" "$( run --help 2>&1 | grep -c 'Set GOPATH.*/somewhere/go' )" "1"
  print -r -- 'ZSH_THEME=from-config' > "${cfg}"
  check "the config beats the built in default" "$( run --help 2>&1 | grep -c 'from-config' )" "1"
  check "a command line switch beats the config" "$( run -Z from-switch --help 2>&1 | grep -c 'from-switch' )" "1"
  print -r -- 'DO_CACHE_INIT=false' > "${cfg}"
  run > /dev/null 2>&1
  check "behaviour settings work on a login run (init cache off)" "$( nfiles "${H}/.ussuri/cache/*" )" "0"
  rm -f "${cfg}"
  print -r -- 'ZSH_THEME=from-elsewhere' > "${TMP}/other.conf"
  check "USSURI_CONFIG points at another file" "$( EXTRA_ENV=( USSURI_CONFIG="${TMP}/other.conf" ); run --help 2>&1 | grep -c 'from-elsewhere' )" "1"
  print -r -- 'if [ then' > "${cfg}"
  out=$( run --version 2>&1 )
  check "a broken config does not stop the script" "$( print -r -- "${out}" | tail -1 )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
}

test_config_command () {
  new_home
  local cfg="${H}/.ussuri/config" out
  rm -f "${cfg}"
  run --config --dryrun > /dev/null 2>&1
  check "--config --dryrun creates nothing" "$( [[ -e "${cfg}" ]] && echo created || echo not-created )" "not-created"
  out=$( run --config 2>&1 )
  check "--config creates the template" "$( [[ -f "${cfg}" ]] && echo yes || echo no )" "yes"
  check "and says where it is" "$( print -r -- "${out}" | grep -c "${cfg}" | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  check "the template is valid zsh" "$( zsh -n "${cfg}" && echo valid || echo invalid )" "valid"
  check "and changes nothing until you uncomment something" "$( grep -c -v -E '^[[:space:]]*(#|$)' "${cfg}" )" "0"
  print -r -- "DO_BUILD=true" >> "${cfg}"
  run --config > /dev/null 2>&1
  check "running it again does not overwrite your config" "$( grep -c 'DO_BUILD=true' "${cfg}" )" "1"
  check "the shipped long and short switches are the same" "$( run -k 2>&1 | grep -c 'exists' )" "1"
}

test_doctor_config () {
  healthy_home
  local cfg="${H}/.ussuri/config" out
  out=$( run --doctor 2>&1 )
  check "doctor is fine with no config" "$( print -r -- "${out}" | grep -c 'FAIL' )" "0"
  print -r -- 'DO_BUILD=true' > "${cfg}"; chmod 600 "${cfg}"
  out=$( run --doctor 2>&1 )
  check "doctor reports a good config" "$( print -r -- "${out}" | grep -c 'ok.*config' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  print -r -- 'if [ then' > "${cfg}"
  out=$( run --doctor 2>&1 )
  check "doctor fails a config with a syntax error" "$( print -r -- "${out}" | grep -c 'FAIL.*config' )" "1"
  print -r -- 'DO_BUILD=true' > "${cfg}"; chmod 666 "${cfg}"
  out=$( run --doctor 2>&1 )
  check "doctor warns about a config anyone can write (it is executed)" "$( print -r -- "${out}" | grep -c 'warn.*writable' )" "1"
}

test_dotfiles_layers () {
  new_home; make_dotfiles
  EXTRA_ENV=( DOTFILES_HOST=box )
  run -L -M work > /dev/null 2>&1
  check "the profile overrides common" "$( cat "${H}/.gitconfig" )" "work gitconfig"
  check "the host overrides common, in a subdirectory" "$( cat "${H}/.config/app/conf" )" "box app"
  check "a host only file is linked" "$( cat "${H}/.hostonly" )" "only on box"
  check "they are symlinks into the dotfiles directory" "$( [[ -L "${H}/.gitconfig" && "$( readlink "${H}/.gitconfig" )" == "${H}/.ussuri/dotfiles/profiles/work/.gitconfig" ]] && echo yes || echo no )" "yes"
  check ".DS_Store is not linked" "$( [[ -e "${H}/.DS_Store" || -L "${H}/.DS_Store" ]] && echo linked || echo ignored )" "ignored"
  new_home; make_dotfiles
  EXTRA_ENV=()
  run -L > /dev/null 2>&1
  check "without a profile or host layer, common is used" "$( cat "${H}/.gitconfig" ) / $( cat "${H}/.config/app/conf" )" "common gitconfig / common app"
  new_home; make_dotfiles
  EXTRA_ENV=( DOTFILES_HOST=other )
  run -L > /dev/null 2>&1
  check "another host does not get box's files" "$( [[ -e "${H}/.hostonly" ]] && echo linked || echo absent )" "absent"
  EXTRA_ENV=()
}

test_dotfiles_safety () {
  new_home; make_dotfiles
  EXTRA_ENV=( DOTFILES_HOST=box )
  print -r -- "my precious gitconfig" > "${H}/.gitconfig"
  run -L > /dev/null 2>&1
  local backed
  backed=( "${H}"/.ussuri/dotfile-backups/*/.gitconfig(N) )
  check "an existing file is backed up before it is replaced" "$( cat "${backed[1]}" 2> /dev/null )" "my precious gitconfig"
  check "and then linked" "$( cat "${H}/.gitconfig" )" "common gitconfig"
  local before after
  before=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  run -L > /dev/null 2>&1
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "a second run changes nothing (no more backups)" "${after}" "${before}"
  # A link that points somewhere else is replaced, and the old link is kept in the backup
  rm "${H}/.hostonly"; ln -s /nonexistent/elsewhere "${H}/.hostonly"
  run -L > /dev/null 2>&1
  check "a link pointing elsewhere is replaced" "$( cat "${H}/.hostonly" )" "only on box"
  new_home; make_dotfiles
  run -L --dryrun > /dev/null 2>&1
  check "--dryrun changes nothing" "$( [[ -e "${H}/.gitconfig" || -L "${H}/.gitconfig" ]] && echo linked || echo untouched )" "untouched"
  new_home
  run > /dev/null 2>&1
  check "dotfiles are not touched by an ordinary login run" "$( ls "${H}/.ussuri/dotfile-backups" 2> /dev/null | wc -l | tr -d ' ' )" "0"
  new_home; make_dotfiles
  print -r -- "DO_DOTFILES_CHECK=true" > "${H}/.ussuri/config"
  run > /dev/null 2>&1
  check "unless the config turns it on for logins" "$( cat "${H}/.gitconfig" 2> /dev/null )" "common gitconfig"
  EXTRA_ENV=()
}

test_dotfiles_unlink () {
  new_home; make_dotfiles
  EXTRA_ENV=( DOTFILES_HOST=box )
  run -L > /dev/null 2>&1
  ln -s /somewhere/else "${H}/.mine"
  print -r -- "a real file" > "${H}/.real"
  run --unlink > /dev/null 2>&1
  check "--unlink removes the links it made" "$( [[ -L "${H}/.gitconfig" || -L "${H}/.hostonly" ]] && echo left || echo removed )" "removed"
  check "but not other symlinks" "$( [[ -L "${H}/.mine" ]] && echo kept || echo removed )" "kept"
  check "and not real files" "$( cat "${H}/.real" )" "a real file"
  check "the dotfiles themselves are untouched" "$( cat "${H}/.ussuri/dotfiles/common/.gitconfig" )" "common gitconfig"
  EXTRA_ENV=()
}

test_dotfiles_hostile_names () {
  new_home
  local d="${H}/.ussuri/dotfiles/common" cwd="${TMP}/cwd"
  mkdir -p "${d}/dir with space" "${cwd}"
  # The payloads are relative paths, so if one ran it would leave a marker in the directory we run from
  print -r -- "x" > "${d}/dir with space/file \$(touch pwned1)'s \`touch pwned2\`"
  ( cd "${cwd}" && run -L > /dev/null 2>&1 )
  check "odd file names are linked as plain text" "$( ls "${H}/dir with space" | wc -l | tr -d ' ' )" "1"
  check "and nothing in them is executed" "$( [[ -e "${cwd}/pwned1" || -e "${cwd}/pwned2" ]] && echo executed || echo safe )" "safe"
  ( cd "${cwd}" && run --unlink > /dev/null 2>&1 )
  check "and they unlink just as cleanly" "$( ls "${H}/dir with space" 2> /dev/null | wc -l | tr -d ' ' )" "0"
}

test_doctor_dotfiles () {
  healthy_home; make_dotfiles
  local out
  out=$( EXTRA_ENV=( DOTFILES_HOST=box ); run --doctor 2>&1 )
  check "doctor reports dotfiles that are not linked yet" "$( print -r -- "${out}" | grep -c 'warn.*dotfile' )" "1"
  ( EXTRA_ENV=( DOTFILES_HOST=box ); run -L > /dev/null 2>&1 )
  out=$( EXTRA_ENV=( DOTFILES_HOST=box ); run --doctor 2>&1 )
  check "and is happy once they are" "$( print -r -- "${out}" | grep -c 'ok.*dotfiles are linked' )" "1"
  check "with no failures" "$( print -r -- "${out}" | grep -c 'FAIL' )" "0"
  rm -f "${H}/.gitconfig"; print -r -- "mine" > "${H}/.gitconfig"
  out=$( EXTRA_ENV=( DOTFILES_HOST=box ); run --doctor 2>&1 )
  check "doctor flags a real file standing in the way" "$( print -r -- "${out}" | grep -c 'warn.*in the way' )" "1"
}

test_backups_and_rollback () {
  new_home; make_backups
  local out
  out=$( run --backups 2>&1 )
  check "--backups lists newest first" "$( print -r -- "${out}" | grep -E '^ +[0-9]+ ' | awk '{print $1":"$NF}' | tr '\n' ' ' )" "1:.zshrc.03_03_2026_10_00_00 2:.zshrc.02_02_2026_10_00_00 3:.zshrc.01_01_2026_10_00_00 "
  check "with the version of each ussuri backup" "$( print -r -- "${out}" | grep -c '1.2.0' )" "1"
  check "and saying which one is not ussuri" "$( print -r -- "${out}" | grep -E '^ +3 ' | grep -c 'other' )" "1"
  run --rollback --dryrun > /dev/null 2>&1
  check "--rollback --dryrun changes nothing" "$( head -1 "${H}/.zshrc" )" "# Version: 1.4.2"
  run --rollback > /dev/null 2>&1
  check "--rollback restores the newest backup" "$( head -1 "${H}/.zshrc" )" "# Version: 1.2.0"
  check "and keeps what it replaced, so a rollback can be undone" "$( grep -l 'Version: 1.4.2' "${H}"/.ussuri/.zshrc.* 2> /dev/null | wc -l | tr -d ' ' )" "1"
  new_home; make_backups
  run --rollback 3 > /dev/null 2>&1
  check "--rollback N restores that backup" "$( head -1 "${H}/.zshrc" )" "# my original zshrc"
  new_home; make_backups
  run --rollback .zshrc.02_02_2026_10_00_00 > /dev/null 2>&1
  check "--rollback accepts a backup's name" "$( head -1 "${H}/.zshrc" )" "# Version: 1.0.0"
  out=$( run --rollback 9 2>&1 ); local rc=$?
  check "a backup that does not exist is an error, and nothing changes" "$( [[ ${rc} -ne 0 ]] && head -1 "${H}/.zshrc" | grep -c 'Version: 1.0.0' )" "1"
  out=$( run --rollback 1 -v 2>&1 )
  check "a switch after --rollback is still a switch" "$( print -r -- "${out}" | grep -c 'Information' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  new_home
  out=$( run --rollback 2>&1 ); rc=$?
  check "with no backups it says so and fails" "${rc}:$( print -r -- "${out}" | grep -c 'No backups' )" "1:1"
}

test_uninstall () {
  new_home; make_backups
  run --uninstall > /dev/null 2>&1
  check "--uninstall goes back to the .zshrc from before ussuri (skipping newer ussuri ones)" "$( head -1 "${H}/.zshrc" )" "# my original zshrc"
  check "and keeps the ussuri one it replaced" "$( grep -l 'Version: 1.4.2' "${H}"/.ussuri/.zshrc.* 2> /dev/null | wc -l | tr -d ' ' )" "1"
  check "and leaves ~/.ussuri alone" "$( [[ -d "${H}/.ussuri/files" ]] && echo kept || echo removed )" "kept"
  local out; out=$( run --uninstall 2>&1 )
  check "running it again says there is nothing to do" "$( print -r -- "${out}" | grep -c 'not ussuri' )" "1"
  new_home; make_backups
  rm "${H}/.ussuri/.zshrc.01_01_2026_10_00_00"
  run --uninstall > /dev/null 2>&1
  check "if you had no .zshrc before, ussuri's is moved aside" "$( [[ -e "${H}/.zshrc" ]] && echo present || echo gone )" "gone"
  check "and not lost" "$( grep -l 'Version: 1.4.2' "${H}"/.ussuri/.zshrc.* 2> /dev/null | wc -l | tr -d ' ' )" "1"
  new_home; make_backups
  run --uninstall --dryrun > /dev/null 2>&1
  check "--uninstall --dryrun changes nothing" "$( head -1 "${H}/.zshrc" )" "# Version: 1.4.2"
}

test_install_backups_are_unique () {
  new_home
  print -r -- "# one" > "${H}/.zshrc"
  run --install > /dev/null 2>&1
  print -r -- "# two" > "${H}/.zshrc"
  run --install > /dev/null 2>&1
  check "two installs in the same second keep both backups" "$( cat "${H}"/.ussuri/.zshrc.* 2> /dev/null | grep -c '^# \(one\|two\)$' )" "2"
}

test_drift () {
  new_home
  local out rc total
  # The settings at the top level of their functions, plus the Transmission blocklist URL which
  # sits inside an if (and not the one for old OS X versions, which doesn't apply here)
  total=$(( $( grep -c '^  set_osx_default ' "${SRC}" ) + 1 ))
  # Nothing applied yet: every setting differs
  local before after
  before=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  out=$( run --drift settings 2>&1 ); rc=$?
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "with nothing applied every setting is reported" "$( print -r -- "${out}" | grep -c -E '^ +[A-Za-z].* -> ' )" "${total}"
  check "the summary says how many differ, out of how many were checked" "$( print -r -- "${out}" | grep -c -E "^${total} of [0-9]+ settings differ" )" "1"
  check "and the exit status says there is drift" "${rc}" "1"
  check "--drift writes nothing" "$( calls 'defaults write' )" "0"
  check "and changes nothing in the home directory" "${after}" "${before}"
  use_stateful_defaults
  new_home; : > "${LOG}"
  run --defaults > /dev/null 2>&1
  out=$( run --drift settings 2>&1 ); rc=$?
  check "after applying the defaults there is no drift" "${rc}" "0"
  check "and it says so" "$( print -r -- "${out}" | grep -c 'match' )" "1"
  # Change one value, remove another and flip a boolean behind its back
  grep -v '^com.apple.dock|autohide-delay|' "${DEFAULTS_DB}" > "${DEFAULTS_DB}.new"; mv "${DEFAULTS_DB}.new" "${DEFAULTS_DB}"
  sed -i.bak 's/^com.apple.dock|tilesize|.*/com.apple.dock|tilesize|48/; s/^com.apple.finder|ShowPathbar|.*/com.apple.finder|ShowPathbar|0/' "${DEFAULTS_DB}"
  out=$( run --drift settings 2>&1 ); rc=$?
  check "exactly the three changed settings are reported" "$( print -r -- "${out}" | grep -c -E '^ +[A-Za-z].* -> ' )" "3"
  check "a changed value shows what it is and what it should be" "$( print -r -- "${out}" | grep -c -E 'tilesize +48 -> 32' )" "1"
  check "a missing one says it is not set" "$( print -r -- "${out}" | grep -c -E 'autohide-delay +\(not set\) -> 0.2' )" "1"
  check "a boolean is shown as true/false, not 1/0" "$( print -r -- "${out}" | grep -c -E 'ShowPathbar +false -> true' )" "1"
  check "settings are grouped under their domain" "$( print -r -- "${out}" | grep -c -E '^com\.apple\.(dock|finder)$' )" "2"
  check "the exit status is 1" "${rc}" "1"
  out=$( run --drift settings 2>&1 )
  check "it points at the way to fix it" "$( print -r -- "${out}" | grep -c -- '--defaults' )" "1"
  : > "${LOG}"
  run --drift settings > /dev/null 2>&1
  check "drift never writes, even when there is some" "$( calls 'defaults write' )" "0"
  check "and --defaults then fixes exactly those" "$( run --defaults > /dev/null 2>&1; run --drift settings > /dev/null 2>&1; echo $? )" "0"
  use_plain_defaults
}

test_linux_defaults () {
  use_gsettings
  new_home
  local keys out rc
  keys=$( grep -c -E '^  set_linux_default ' "${SRC}" )
  check "the script has a list of GNOME settings" "$( [[ ${keys} -ge 10 ]] && echo yes || echo no )" "yes"
  EXTRA_ENV=( USSURI_OS=linux DBUS_SESSION_BUS_ADDRESS=unix:path=/x )
  # Seed with a wrong value everywhere, except one key that this desktop does not have
  seed_gsettings wrong
  grep -v '^org.gnome.nautilus.preferences|default-folder-viewer|' "${GSETTINGS_DB}" > "${GSETTINGS_DB}.n"; mv "${GSETTINGS_DB}.n" "${GSETTINGS_DB}"
  : > "${LOG}"
  run --defaults > /dev/null 2>&1
  check "--defaults sets every setting that is wrong" "$( calls 'gsettings set' )" "$(( keys - 1 ))"
  check "and skips the one this desktop does not have" "$( grep -c 'gsettings set.*default-folder-viewer' "${LOG}" | awk '{print ($1 > 0) ? "set" : "skipped"}' )" "skipped"
  check "a string setting is passed with its quotes" "$( grep 'button-layout' "${LOG}" | grep -c "'appmenu:minimize,maximize,close'" )" "1"
  check "and a number without its type prefix" "$( grep 'repeat-interval' "${LOG}" | grep -c 'repeat-interval 30$' )" "1"
  check "a stamp is written" "$( [[ -f "${H}/.ussuri/defaults.stamp" ]] && echo yes || echo no )" "yes"
  : > "${LOG}"
  run --defaults > /dev/null 2>&1
  check "applying again changes nothing" "$( calls 'gsettings set' )" "0"
  out=$( run --drift settings 2>&1 ); rc=$?
  check "and there is no drift" "${rc}" "0"
  EXTRA_ENV=()
}

test_linux_defaults_drift () {
  use_gsettings
  new_home
  EXTRA_ENV=( USSURI_OS=linux DBUS_SESSION_BUS_ADDRESS=unix:path=/x )
  seed_gsettings
  sed -i.bak "s/^org.gnome.desktop.peripherals.keyboard|repeat-interval|.*/org.gnome.desktop.peripherals.keyboard|repeat-interval|uint32 99/; s/^org.gtk.Settings.FileChooser|show-hidden|.*/org.gtk.Settings.FileChooser|show-hidden|false/" "${GSETTINGS_DB}"
  : > "${LOG}"
  local out rc
  out=$( run --drift settings 2>&1 ); rc=$?
  check "drift reports the two changed settings" "$( print -r -- "${out}" | grep -c -E '^ +[a-z-]+ +.* -> ' )" "2"
  check "showing actual and expected" "$( print -r -- "${out}" | grep -c -E 'repeat-interval +uint32 99 -> uint32 30' )" "1"
  check "grouped under their schema" "$( print -r -- "${out}" | grep -c -E '^org\.gnome\.desktop\.peripherals\.keyboard$' )" "1"
  check "with exit status 1" "${rc}" "1"
  check "and it writes nothing" "$( calls 'gsettings set' )" "0"
  # Not a GNOME session
  EXTRA_ENV=( USSURI_OS=linux )
  out=$( run --drift settings 2>&1 ); rc=$?
  check "without a desktop session it says so rather than reading nothing" "$( print -r -- "${out}" | grep -c -i 'no desktop session\|not available' )" "1"
  check "with exit status 2" "${rc}" "2"
  : > "${LOG}"
  run --defaults > /dev/null 2>&1
  check "and --defaults does not write to a throwaway settings store" "$( calls 'gsettings set' )" "0"
  EXTRA_ENV=()
}

test_linux_defaults_on_login () {
  use_gsettings
  new_home
  EXTRA_ENV=( USSURI_OS=linux DBUS_SESSION_BUS_ADDRESS=unix:path=/x )
  seed_gsettings
  sed -i.bak "s/^org.gtk.Settings.FileChooser|show-hidden|.*/org.gtk.Settings.FileChooser|show-hidden|false/" "${GSETTINGS_DB}"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "a login run leaves GNOME settings alone by default" "$( calls 'gsettings set' )" "0"
  EXTRA_ENV=( USSURI_OS=linux DBUS_SESSION_BUS_ADDRESS=unix:path=/x DO_GNOME_DEFAULTS=true )
  run > /dev/null 2>&1
  check "DO_GNOME_DEFAULTS=true applies them on login" "$( calls 'gsettings set' )" "1"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "once, then the stamp keeps later logins quiet" "$( calls 'gsettings' )" "0"
  EXTRA_ENV=( USSURI_OS=linux DBUS_SESSION_BUS_ADDRESS=unix:path=/x )
  check "the OS override does not leak into other tests" "$( EXTRA_ENV=(); run --help 2>&1 | grep -c 'Usage' )" "1"
  EXTRA_ENV=()
}

test_package_managers () {
  make_linux_stubs
  local pkg
  # Every manager installs a package from its own list, with its own command
  linux_packages apt ubuntu "" ubuntu.apt
  check "apt: the package index is refreshed once" "$( calls 'sudo apt-get update' )" "1"
  check "apt: a missing package is installed with sudo apt install -y" "$( grep -c '^sudo apt install -y ansible$' "${LOG}" )" "1"
  check "apt: an installed one is not" "$( grep -c 'apt install -y git$' "${LOG}" )" "0"
  linux_packages apt linuxmint "ubuntu debian" ubuntu.apt
  check "a Debian derivative (Mint) uses apt" "$( grep -c '^sudo apt install -y ansible$' "${LOG}" )" "1"
  linux_packages pacman arch "" arch.pacman
  check "pacman: --needed -S, not -Sy" "$( grep -c '^sudo pacman --noconfirm --needed -S ansible$' "${LOG}" )" "1"
  linux_packages pacman manjaro "arch" arch.pacman
  check "an Arch derivative (Manjaro) uses pacman" "$( grep -c '^sudo pacman --noconfirm --needed -S ansible$' "${LOG}" )" "1"
  linux_packages dnf fedora "" fedora.dnf
  check "dnf: a missing package is installed with sudo dnf install -y" "$( grep -c '^sudo dnf install -y ansible$' "${LOG}" )" "1"
  linux_packages dnf rocky "rhel centos fedora" fedora.dnf
  check "a Red Hat derivative (Rocky) uses dnf" "$( grep -c '^sudo dnf install -y ansible$' "${LOG}" )" "1"
  linux_packages apk alpine "" alpine.apk
  check "apk: the index is updated first" "$( grep -n -E '^sudo apk (update|add)' "${LOG}" | head -1 | grep -c 'apk update' )" "1"
  check "apk: a missing package is added with sudo apk add" "$( grep -c '^sudo apk add ansible$' "${LOG}" )" "1"
  linux_packages nix nixos "" nix.nix
  check "nix: no sudo, installed from nixpkgs" "$( grep -c '^nix profile install nixpkgs#ansible$' "${LOG}" )" "1"
  check "nix: and never run through sudo" "$( grep -c '^sudo.*nix' "${LOG}" )" "0"
  linux_packages nix ubuntu "" nix.nix
  : > "${LOG}"
  new_home; print -r -- "git" > "${H}/.ussuri/nix.list"
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" PKG_MANAGER=nix )
  run -P > /dev/null 2>&1
  EXTRA_ENV=()
  check "PKG_MANAGER=nix on Ubuntu uses nix" "$( grep -c '^nix profile install nixpkgs#ansible$' "${LOG}" )" "1"
  # An unsupported distro does nothing, quietly
  linux_packages x opensuse-leap "suse" x
  check "an unsupported distro installs nothing" "$( grep -c -E 'install|add' "${LOG}" )" "0"
}

test_package_lists () {
  local f
  for f in ubuntu.apt arch.pacman endeavouros.pacman fedora.dnf alpine.apk nix.nix; do
    check "files/packages/${f} exists and is not empty" "$( [[ -s "${ROOT}/files/packages/${f}" ]] && echo yes || echo no )" "yes"
  done
  check "package names have no stray spaces or blank lines" "$( grep -c -E '^[[:space:]]*$|[[:space:]]$|^[[:space:]]' "${ROOT}"/files/packages/{fedora.dnf,alpine.apk,nix.nix} | grep -v ':0' | wc -l | tr -d ' ' )" "0"
}

test_installed_list_commands () {
  make_linux_stubs
  local row manager osid like want
  for row in 'apt ubuntu  dpkg' 'pacman arch  pacman' 'dnf fedora  rpm' 'apk alpine  apk' 'nix nixos  nix'; do
    set -- ${=row}
    manager="$1"; osid="$2"; want="$3"
    new_home
    print -r -- "ID=${osid}" > "${TMP}/os-release"
    rm -f "${H}/.ussuri/${manager}.list"
    EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" )
    : > "${LOG}"
    run -P > /dev/null 2>&1
    EXTRA_ENV=()
    check "${manager}: the installed list is built with ${want}" "$( grep -c "^${want} " "${LOG}" | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  done
}

test_nix_list_parsing () {
  new_home
  print -r -- "ID=nixos" > "${TMP}/os-release"
  rm -f "${H}/.ussuri/nix.list"
  # The format nix profile list prints from Nix 2.20
  cat > "${TMP}/nix.new" << 'EOF'
Name:               hello
Flake attribute:    legacyPackages.x86_64-linux.hello
Original flake URL: flake:nixpkgs
Store paths:        /nix/store/abc-hello-2.12

Name:               ripgrep
Flake attribute:    legacyPackages.x86_64-linux.ripgrep
Store paths:        /nix/store/def-ripgrep-14
EOF
  # And the older one
  cat > "${TMP}/nix.old" << 'EOF'
0 flake:nixpkgs#legacyPackages.x86_64-linux.hello github:NixOS/nixpkgs/abc#legacyPackages.x86_64-linux.hello /nix/store/abc-hello-2.12
1 flake:nixpkgs#legacyPackages.x86_64-linux.ripgrep github:NixOS/nixpkgs/abc#legacyPackages.x86_64-linux.ripgrep /nix/store/def-ripgrep-14
EOF
  local fmt
  for fmt in new old; do
    stub nix "echo \"nix \$*\" >> ${LOG}; [ \"\$1 \$2\" = 'profile list' ] && cat ${TMP}/nix.${fmt}; exit 0"
    rm -f "${H}/.ussuri/nix.list"
    EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" )
    run -P > /dev/null 2>&1
    EXTRA_ENV=()
    check "nix profile list (${fmt} format) gives the package names" "$( tr '\n' ' ' < "${H}/.ussuri/nix.list" )" "hello ripgrep "
  done
  stub nix "echo \"nix \$*\" >> ${LOG}; exit 0"
}

test_doctor_package_manager () {
  healthy_home
  print -r -- "ID=fedora" > "${TMP}/os-release"
  local out
  out=$( EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); run --doctor 2>&1 )
  check "doctor fails when the distro's package manager is missing" "$( print -r -- "${out}" | grep -c 'FAIL.*dnf' )" "1"
  make_linux_stubs
  out=$( EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); run --doctor 2>&1 )
  check "and is happy when it is there" "$( print -r -- "${out}" | grep -c 'ok.*dnf (dnf' )" "1"
  print -r -- "ID=opensuse-leap" > "${TMP}/os-release"
  out=$( EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); run --doctor 2>&1 )
  check "an unsupported distro is a warning, not a failure" "$( print -r -- "${out}" | grep -c "warn.*isn't supported" )" "1"
}

test_tools_switch () {
  new_home; make_tool_installers
  local out rc
  out=$( run -W bogus 2>&1 ); rc=$?
  check "an unknown tool is an error that names the choices" "${rc}:$( print -r -- "${out}" | grep -c 'fnm, rustup, uv or mise' )" "1:1"
  out=$( run -W 2>&1 ); rc=$?
  check "--tool without a name is an error" "$( [[ ${rc} -ne 0 ]] && echo error || echo ok )" "error"
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  out=$( run -W uv --dryrun --verbose 2>&1 )
  check "--dryrun shows the install without doing it" "$( print -r -- "${out}" | grep -c 'Executing:.*fetch_and_run.*uv.sh' )" "1"
  check "and runs nothing" "$( grep -c '^installer' "${LOG}" )" "0"
  check "tools are off by default: an ordinary login installs none" "$( run > /dev/null 2>&1; grep -c '^installer' "${LOG}" )" "0"
  EXTRA_ENV=()
}

test_tool_fnm () {
  new_home; make_tool_installers
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  run -W fnm > /dev/null 2>&1
  check "fnm: the installer gets the install dir and --skip-shell" "$( grep '^installer fnm' "${LOG}" )" "installer fnm --install-dir ${H}/.local/share/fnm --skip-shell"
  check "fnm: its env is set up in the shell" "$( grep -c '^fnm env --use-on-cd --shell zsh' "${LOG}" )" "1"
  : > "${LOG}"
  run -W fnm > /dev/null 2>&1
  check "fnm: once installed it is not installed again" "$( grep -c '^installer' "${LOG}" )" "0"
  check "fnm: but its env is still set up" "$( grep -c '^fnm env' "${LOG}" )" "1"
  : > "${LOG}"
  EXTRA_ENV=( "${TOOL_ENV[@]}" FNM_NODE=22 )
  run -W fnm > /dev/null 2>&1
  check "FNM_NODE installs that Node and makes it the default" "$( grep -E '^fnm (install|default) 22$' "${LOG}" | tr '\n' ',' )" "fnm install 22,fnm default 22,"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "a login does not touch node versions (that is for --tool/--build)" "$( grep -c -E '^fnm (install|default)' "${LOG}" )" "0"
  EXTRA_ENV=()
}

test_tool_rustup () {
  new_home; make_tool_installers
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  run -W rustup > /dev/null 2>&1
  check "rustup: installed non-interactively, leaving shell files alone" "$( grep '^installer rustup' "${LOG}" )" "installer rustup -y --no-modify-path"
  : > "${LOG}"
  run -W rustup > /dev/null 2>&1
  check "rustup: not installed twice" "$( grep -c '^installer' "${LOG}" )" "0"
  EXTRA_ENV=( "${TOOL_ENV[@]}" RUSTUP_TOOLCHAIN_WANTED=nightly )
  run -W rustup > /dev/null 2>&1
  check "a wanted toolchain is installed and made the default" "$( grep -E '^rustup (toolchain install|default) nightly' "${LOG}" | tr '\n' ',' )" "rustup toolchain install nightly,rustup default nightly,"
  EXTRA_ENV=()
}

test_tool_uv () {
  new_home; make_tool_installers
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  run -W uv > /dev/null 2>&1
  check "uv: the installer is told not to edit your shell files" "$( grep '^installer uv' "${LOG}" )" "installer uv no_modify_path=1"
  check "uv: that setting does not leak into the shell afterwards" "$( env -i HOME="${H}" zsh -c 'echo ${UV_NO_MODIFY_PATH:-unset}' )" "unset"
  : > "${LOG}"
  EXTRA_ENV=( "${TOOL_ENV[@]}" UV_PYTHON=3.13 )
  run -W uv > /dev/null 2>&1
  check "UV_PYTHON installs that Python" "$( grep -c '^uv python install 3.13$' "${LOG}" )" "1"
  EXTRA_ENV=()
}

test_tool_mise () {
  new_home; make_tool_installers
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  run -W mise > /dev/null 2>&1
  check "mise: installed where we say, not wherever it likes" "$( grep '^installer mise' "${LOG}" )" "installer mise path=${H}/.local/bin/mise"
  check "mise: activated in the shell" "$( grep -c '^mise activate zsh' "${LOG}" )" "1"
  : > "${LOG}"
  run -W mise > /dev/null 2>&1
  check "mise: activation is cached, so the second run does not run mise" "$( grep -c '^mise activate' "${LOG}" )" "0"
  EXTRA_ENV=( "${TOOL_ENV[@]}" MISE_TOOLS="node@lts python@3.13" )
  run -W mise > /dev/null 2>&1
  check "MISE_TOOLS are installed as global tools" "$( grep -c '^mise use --global node@lts python@3.13$' "${LOG}" )" "1"
  EXTRA_ENV=()
}

test_tools_from_config () {
  new_home; make_tool_installers
  print -r -- 'INSTALL_FNM=true' > "${H}/.ussuri/config"
  EXTRA_ENV=( "${TOOL_ENV[@]}" )
  run > /dev/null 2>&1
  check "INSTALL_FNM=true in the config installs fnm on a login run" "$( grep -c '^installer fnm' "${LOG}" )" "1"
  check "and sets it up" "$( grep -c '^fnm env' "${LOG}" )" "1"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "later logins just set it up" "$( grep -c '^installer' "${LOG}" )/$( grep -c '^fnm env' "${LOG}" )" "0/1"
  new_home; make_tool_installers
  local good
  print -r -- 'INSTALL_FNM=true' > "${H}/.ussuri/config"
  EXTRA_ENV=( "${TOOL_ENV[@]}" FNM_INSTALL_SHA256=0000000000000000000000000000000000000000000000000000000000000000 )
  run > /dev/null 2>&1
  check "a wrong FNM_INSTALL_SHA256 refuses the installer" "$( [[ -x "${H}/.local/share/fnm/fnm" ]] && echo installed || echo refused )" "refused"
  EXTRA_ENV=()
}

test_doctor_tools () {
  healthy_home
  print -r -- 'INSTALL_FNM=true' > "${H}/.ussuri/config"
  local out
  out=$( run --doctor 2>&1 )
  check "doctor notes a tool that is wanted but not installed" "$( print -r -- "${out}" | grep -c 'warn.*fnm' )" "1"
  mkdir -p "${H}/.local/share/fnm"; print -r -- '#!/bin/sh' > "${H}/.local/share/fnm/fnm"; chmod +x "${H}/.local/share/fnm/fnm"
  out=$( run --doctor 2>&1 )
  check "and is happy once it is" "$( print -r -- "${out}" | grep -c 'ok.*fnm' )" "1"
  rm "${H}/.ussuri/config"
  out=$( run --doctor 2>&1 )
  check "and says nothing about tools you have not asked for" "$( print -r -- "${out}" | grep -c -E 'fnm|rustup|mise|uv ' )" "0"
}

test_transmission_blocklist () {
  check "the default blocklist is HTTPS" "$( grep -c -E 'set_env +"TRANSMISSION_BLOCKLIST_URL" +"https://' "${SRC}" )" "1"
  check "and the dead bitsurge.net list is no longer used as a URL" "$( grep -c 'bitsurge.net/public' "${SRC}" )" "0"
  new_home; use_stateful_defaults
  gzip -c < /dev/null > "${TMP}/blocklist.gz"
  local db="${DEFAULTS_DB}" out
  EXTRA_ENV=( TRANSMISSION_BLOCKLIST_URL="file://${TMP}/blocklist.gz" )
  run --defaults > /dev/null 2>&1
  check "a reachable blocklist URL is written" "$( grep -c "^org.m0k.transmission|BlocklistURL|file://${TMP}/blocklist.gz$" "${db}" )" "1"
  # A dead URL must not replace what is there, and must be reported
  new_home; use_stateful_defaults
  print -r -- "org.m0k.transmission|BlocklistURL|https://still.working/list.gz" >> "${db}"
  EXTRA_ENV=( TRANSMISSION_BLOCKLIST_URL="file://${TMP}/does-not-exist.gz" )
  out=$( run --defaults 2>&1 )
  check "an unreachable one is not written over the existing setting" "$( grep -c 'BlocklistURL|https://still.working/list.gz$' "${db}" )" "1"
  check "and it is reported without needing --verbose" "$( print -r -- "${out}" | grep -c 'not reachable' )" "1"
  check "the other Transmission settings are still applied" "$( grep -c '^org.m0k.transmission|BlocklistNew|1$' "${db}" )" "1"
  # Already set: no need to go to the network at all
  new_home; use_stateful_defaults
  print -r -- "org.m0k.transmission|BlocklistURL|file://${TMP}/does-not-exist.gz" >> "${db}"
  out=$( run --defaults 2>&1 )
  check "a setting that already matches is not checked" "$( print -r -- "${out}" | grep -c 'not reachable' )" "0"
  EXTRA_ENV=()
  # It can be set in the config
  new_home; use_stateful_defaults
  print -r -- "TRANSMISSION_BLOCKLIST_URL=file://${TMP}/blocklist.gz" > "${H}/.ussuri/config"
  run --defaults > /dev/null 2>&1
  check "TRANSMISSION_BLOCKLIST_URL can come from the config" "$( grep -c "BlocklistURL|file://${TMP}/blocklist.gz$" "${db}" )" "1"
  # Drift shows the old dead URL as drift to the new one
  new_home; use_stateful_defaults
  print -r -- "org.m0k.transmission|BlocklistURL|http://john.bitsurge.net/public/biglist.p2p.gz" >> "${db}"
  out=$( run --drift settings 2>&1 )
  check "--drift shows the old URL moving to the new one" "$( print -r -- "${out}" | grep -c -E 'BlocklistURL +http://john.bitsurge.net.* -> https://list.iblocklist.com' )" "1"
  use_plain_defaults
}

test_conditional_snippets () {
  new_home
  # A zinit that records what it is asked to load
  print -r -- "zinit () { print -r -- \"zinit \$*\" >> ${LOG}; }" > "${H}/.zinit/zinit.zsh"
  local turbo row osid like want
  for turbo in true false; do
    # OS release (ID|ID_LIKE|expected) on Linux, and macOS with no override
    for row in 'arch||yes' 'endeavouros|arch|yes' 'manjaro|arch|yes' 'ubuntu||no' 'fedora||no' 'debian||no'; do
      osid="${row%%|*}"; want="${row##*|}"; like="${${row#*|}%%|*}"
      print -r -- "ID=${osid}" > "${TMP}/os-release"
      [[ -n "${like}" ]] && print -r -- "ID_LIKE=\"${like}\"" >> "${TMP}/os-release"
      : > "${LOG}"
      EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ZINIT_TURBO="${turbo}" )
      run --zinit > /dev/null 2>&1
      check "turbo=${turbo}: archlinux snippet on ${osid}${like:+ (like ${like})}" "$( grep -c 'snippet OMZP::archlinux' "${LOG}" | awk '{print ($1 > 0) ? "yes" : "no"}' )" "${want}"
    done
    : > "${LOG}"
    EXTRA_ENV=( ZINIT_TURBO="${turbo}" )
    run --zinit > /dev/null 2>&1
    check "turbo=${turbo}: not loaded on macOS" "$( grep -c 'OMZP::archlinux' "${LOG}" )" "0"
    check "turbo=${turbo}: the other snippets still load on macOS" "$( grep -c -E 'snippet OMZP::(git|sudo|aws|kubectl|kubectx|command-not-found)$' "${LOG}" )" "6"
  done
  EXTRA_ENV=()
  check "an unconditional archlinux line is gone from both lists" "$( grep -c -E '^zinit( ice[^;]*;)? *zinit snippet OMZP::archlinux|^zinit snippet OMZP::archlinux' "${ROOT}"/files/zinit/zinit.zsh "${ROOT}"/files/zinit/zinit-turbo.zsh | grep -v ':0' | wc -l | tr -d ' ' )" "0"
}

test_os_is_like () {
  load_function os_is_like
  OS_ID="arch"; OS_LIKE=""; os_is_like arch && ok "arch is arch" || bad "arch is arch"
  OS_ID="manjaro"; OS_LIKE="arch"; os_is_like arch && ok "manjaro is like arch" || bad "manjaro is like arch"
  OS_ID="linuxmint"; OS_LIKE="ubuntu debian"; os_is_like debian && ok "mint is like debian" || bad "mint is like debian"
  OS_ID="ubuntu"; OS_LIKE="debian"; os_is_like arch && bad "ubuntu is not arch" || ok "ubuntu is not arch"
  OS_ID=""; OS_LIKE=""; os_is_like arch && bad "no OS_ID is not arch" || ok "no OS_ID (macOS) is not arch"
  OS_ID="archery"; OS_LIKE="archive"; os_is_like arch && bad "a name containing arch is not arch" || ok "a name containing arch is not arch"
  unset OS_ID OS_LIKE
}

test_history () {
  new_home
  local state
  state=$( history_state )
  check "the history size is raised from the system default" "$( print -r -- "${state}" | sed -E 's/.*size=([0-9]+).*/\1/' )" "50000"
  check "and so is the number saved" "$( print -r -- "${state}" | sed -E 's/.*save=([0-9]+).*/\1/' )" "50000"
  check "consecutive duplicates are not recorded" "$( print -r -- "${state}" | grep -c 'dups=on' )" "1"
  check "commands with a leading space are not recorded" "$( print -r -- "${state}" | grep -c 'space=on' )" "1"
  check "searching skips duplicates" "$( print -r -- "${state}" | grep -c 'find=on' )" "1"
  check "extra blanks are removed" "$( print -r -- "${state}" | grep -c 'blanks=on' )" "1"
  check "history is still shared between shells" "$( print -r -- "${state}" | grep -c 'share=on' )" "1"
  check "a history file is chosen, as without one nothing is saved" "$( print -r -- "${state}" | grep -c "file=${H}/.zsh_history" )" "1"
  EXTRA_ENV=( HISTFILE=/somewhere/else/hist )
  check "an existing HISTFILE is respected" "$( history_state | grep -c 'file=/somewhere/else/hist' )" "1"
  EXTRA_ENV=()
  print -r -- "HISTORY_SIZE=1234" > "${H}/.ussuri/config"
  state=$( history_state )
  check "HISTORY_SIZE in the config sets both" "$( print -r -- "${state}" | grep -c 'size=1234 save=1234' )" "1"
  print -r -- "DO_HISTORY=false" > "${H}/.ussuri/config"
  state=$( history_state )
  check "DO_HISTORY=false leaves the system settings alone" "$( print -r -- "${state}" | grep -c -E 'size=50000|dups=on|space=on' )" "0"
  print -r -- "SHARE_HISTORY=false" > "${H}/.ussuri/config"
  state=$( history_state )
  check "SHARE_HISTORY=false still turns sharing off" "$( print -r -- "${state}" | grep -c 'share=on' )" "0"
  check "and the other history settings still apply" "$( print -r -- "${state}" | grep -c 'dups=on' )" "1"
  rm -f "${H}/.ussuri/config"
  check "the history settings are not applied by --help or --version" "$( run --version 2>&1 | wc -l | tr -d ' ' )" "1"
}

test_history_substring_search () {
  local list name
  for name in zinit.zsh zinit-turbo.zsh; do
    list="${ROOT}/files/zinit/${name}"
    check "${name}: loads zsh-history-substring-search" "$( grep -c 'zinit light zsh-users/zsh-history-substring-search' "${list}" )" "1"
    check "${name}: after zsh-syntax-highlighting, as its README requires" "$( grep -o 'zinit \(light\|snippet\) [^ ;]*' "${list}" | grep -n -E 'zsh-syntax-highlighting|zsh-history-substring-search' | cut -d: -f2 | awk '{print $3}' | tr '\n' ' ' )" "zsh-users/zsh-syntax-highlighting zsh-users/zsh-history-substring-search "
    check "${name}: binds the keys" "$( grep -c 'bind_history_search' "${list}" )" "1"
  done
  check "turbo: binds the keys once the plugin has loaded, not before (the widgets don't exist until then)" "$( grep -c -E 'ice wait lucid atload"bind_history_search"; zinit light zsh-users/zsh-history-substring-search' "${ROOT}/files/zinit/zinit-turbo.zsh" )" "1"
  check "eager: binds on the line after the plugin" "$( grep -A1 'zinit light zsh-users/zsh-history-substring-search' "${ROOT}/files/zinit/zinit.zsh" | tail -1 )" "bind_history_search"
}

test_bind_history_search () {
  zle -N history-substring-search-up true 2> /dev/null
  zle -N history-substring-search-down true 2> /dev/null
  load_function bind_history_search
  bind_history_search
  local bound
  bound=$( bindkey | grep history-substring-search )
  check "Up is bound in both keypad modes" "$( print -r -- "${bound}" | grep -c -E '"\^\[(\[|O)A" history-substring-search-up' )" "2"
  check "and Down" "$( print -r -- "${bound}" | grep -c -E '"\^\[(\[|O)B" history-substring-search-down' )" "2"
  check "duplicates in history are skipped, to match hist_find_no_dups" "${HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE}" "1"
  check "it succeeds even if a widget is missing (plugin did not load)" "$( zsh -c 'eval "$(sed -n "/^bind_history_search () {/,/^}/p" "$1")"; bind_history_search 2> /dev/null; echo $?' zsh "${SRC}" )" "0"
  unset HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE
}

test_forgit () {
  local list name rename names=( ga gbd gbl gcb gcf gclean gco gcp gd glo grb grh grs gss gsw gwt )
  for name in zinit.zsh zinit-turbo.zsh; do
    list="${ROOT}/files/zinit/${name}"
    check "${name}: loads wfxr/forgit" "$( grep -c 'zinit light wfxr/forgit' "${list}" )" "1"
    check "${name}: renames its clashing aliases first (forgit reads the variables as it loads)" "$( grep -n -E '^export forgit_|zinit light wfxr/forgit' "${list}" | cut -d: -f1 | paste -sd' ' - | awk '{print ($1 < $2) ? "before" : "after"}' )" "before"
    rename=$( grep -E '^export forgit_' "${list}" )
    check "${name}: renames all 16 aliases that clash with the git snippet" "$( print -r -- "${rename}" | grep -o 'forgit_[a-z_]*=' | wc -l | tr -d ' ' )" "16"
    check "${name}: every new name starts with fg, which no git snippet alias does" "$( print -r -- "${rename}" | grep -o 'forgit_[a-z_]*=[a-z]*' | grep -v -c -E '=fg[a-z]+$' )" "0"
    check "${name}: git snippet is loaded as before" "$( grep -c 'snippet OMZP::git' "${list}" )" "1"
  done
  # The aliases that clash, from the git snippet, and what they are renamed to
  local a
  for a in ${names}; do
    check "turbo: forgit's ${a} is renamed to f${a}" "$( grep -c -E "^export .*=f${a}( |\$)" "${ROOT}/files/zinit/zinit-turbo.zsh" )" "1"
  done
  check "both lists rename them the same way" "$( grep -E '^export forgit_' "${ROOT}/files/zinit/zinit.zsh" )" "$( grep -E '^export forgit_' "${ROOT}/files/zinit/zinit-turbo.zsh" )"
  check "turbo: the last line is still the one that runs compinit after everything else" "$( tail -1 "${ROOT}/files/zinit/zinit-turbo.zsh" | grep -c 'compinit' )" "1"
}

test_zoxide () {
  new_home
  local f state
  for f in macos.brew ubuntu.apt arch.pacman endeavouros.pacman fedora.dnf alpine.apk nix.nix; do
    check "zoxide is in files/packages/${f}" "$( grep -c '^zoxide$' "${ROOT}/files/packages/${f}" )" "1"
  done
  run > /dev/null 2>&1
  check "a login runs zoxide init once to build the cache" "$( calls 'zoxide init zsh' )" "1"
  check "the cache holds its output" "$( cat "${H}"/.ussuri/cache/*zoxide* 2> /dev/null | grep -c 'ZOXIDE_INIT_RAN' )" "1"
  : > "${LOG}"
  run > /dev/null 2>&1
  check "later logins do not run zoxide at all" "$( calls 'zoxide' )" "0"
  state=$( env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm PATH="${TEST_PATH_PREFIX}${STUBS}:/usr/bin:/bin:/usr/sbin:/sbin" zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1; print -r -- "ran=${ZOXIDE_INIT_RAN:-no} fn=${+functions[__zoxide_z]}"' zsh "${SCRIPT}" )
  check "and a login shell ends up with what init defines (from the cache)" "${state}" "ran=1 fn=1"
  EXTRA_ENV=( INSTALL_ZOXIDE=false ); : > "${LOG}"
  run > /dev/null 2>&1
  EXTRA_ENV=()
  check "INSTALL_ZOXIDE=false skips it" "$( calls 'zoxide' )" "0"
  EXTRA_ENV=( DO_CACHE_INIT=false ); : > "${LOG}"
  run > /dev/null 2>&1; run > /dev/null 2>&1
  EXTRA_ENV=()
  check "DO_CACHE_INIT=false runs init every time" "$( calls 'zoxide init zsh' )" "2"
  check "a manual run (-N, no environment setup) does not touch it" "$( : > "${LOG}"; run -N > /dev/null 2>&1; calls 'zoxide' )" "0"
}

test_zoxide_missing () {
  new_home
  rm "${STUBS}/zoxide"
  local out
  out=$( run 2>&1 ); local rc=$?
  check "without zoxide a login is silent and succeeds" "${rc}:${#out}" "0:0"
  check "and builds no cache" "$( nfiles "${H}/.ussuri/cache/*zoxide*" )" "0"
  out=$( run --doctor 2>&1 )
  check "doctor says it is missing and how to get it" "$( print -r -- "${out}" | grep -c 'warn.*zoxide.*not installed' )" "1"
  stub zoxide "echo \"zoxide \$*\" >> ${LOG}; [ \"\$1\" = init ] && printf 'export ZOXIDE_INIT_RAN=1\\n__zoxide_z () { :; }\\n'; exit 0"
  out=$( run --doctor 2>&1 )
  check "and is happy once it is there" "$( print -r -- "${out}" | grep -c 'ok.*zoxide' )" "1"
  EXTRA_ENV=( INSTALL_ZOXIDE=false )
  out=$( run --doctor 2>&1 )
  EXTRA_ENV=()
  check "doctor says nothing when you have turned it off" "$( print -r -- "${out}" | grep -c zoxide )" "0"
}

test_zoxide_completion () {
  load_function register_zoxide_completion
  local calls=()
  compdef () { calls+=( "$*" ) }
  # Both zoxide's completion function and compdef exist: registered for z
  __zoxide_z_complete () { :; }
  register_zoxide_completion
  check "registers zoxide's completion for z once compdef exists" "${calls[*]}" "__zoxide_z_complete z"
  # zoxide not set up: nothing, and no error
  unfunction __zoxide_z_complete
  calls=()
  register_zoxide_completion; local rc=$?
  check "does nothing without zoxide, and succeeds" "${#calls}:${rc}" "0:0"
  # compdef not there yet (compinit has not run): nothing, and no error
  unfunction compdef
  __zoxide_z_complete () { :; }
  register_zoxide_completion; rc=$?
  check "does nothing before compinit, and succeeds" "${rc}" "0"
  unfunction __zoxide_z_complete
  check "turbo: the completion is registered right after compinit, in the same step" "$( tail -1 "${ROOT}/files/zinit/zinit-turbo.zsh" | grep -c 'compinit.*zinit cdreplay -q; register_zoxide_completion"' )" "1"
}

test_assume_yes () {
  make_linux_stubs
  local sw
  # apt: -y is always passed, but debconf dialogs can still prompt, so --yes also turns them off
  linux_packages apt ubuntu "" ubuntu.apt
  check "without --yes apt is run as before" "$( grep -c '^sudo apt install -y ansible$' "${LOG}" )" "1"
  for sw in -y --yes --assume-yes; do
    new_home
    print -r -- "ID=ubuntu" > "${TMP}/os-release"; print -r -- "git" > "${H}/.ussuri/apt.list"
    EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); : > "${LOG}"
    run -P ${sw} > /dev/null 2>&1
    EXTRA_ENV=()
    check "${sw}: apt gets no debconf dialogs" "$( grep -c '^sudo env DEBIAN_FRONTEND=noninteractive apt install -y ansible$' "${LOG}" )" "1"
  done
  new_home
  print -r -- "ID=arch" > "${TMP}/os-release"; print -r -- "git" > "${H}/.ussuri/pacman.list"
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); : > "${LOG}"
  run -P -y > /dev/null 2>&1
  EXTRA_ENV=()
  check "pacman is unchanged by --yes (it never prompts)" "$( grep -c '^sudo pacman --noconfirm --needed -S ansible$' "${LOG}" )" "1"
  check "-y takes no value, so a switch after it is still a switch" "$( run -y -v --version 2>&1 | tail -1 )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
  new_home
  print -r -- "ASSUME_YES=true" > "${H}/.ussuri/config"
  print -r -- "ID=ubuntu" > "${TMP}/os-release"; print -r -- "git" > "${H}/.ussuri/apt.list"
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); : > "${LOG}"
  run -P > /dev/null 2>&1
  EXTRA_ENV=()
  check "ASSUME_YES=true in the config does the same without the switch" "$( grep -c 'DEBIAN_FRONTEND=noninteractive apt install -y ansible$' "${LOG}" )" "1"
}

test_assume_yes_confirm () {
  command -v python3 > /dev/null 2>&1 || { print "  skip  assume-yes confirm (no python3)"; return }
  new_home
  run_limited --defaults --confirm < /dev/null > /dev/null 2>&1
  check "--confirm with no terminal and no --yes runs nothing" "$( calls 'defaults write' )" "0"
  : > "${LOG}"
  run_limited --defaults --confirm --yes < /dev/null > /dev/null 2>&1
  check "--yes answers the --confirm prompts, even with no terminal" "$( [[ $( calls 'defaults write' ) -gt 100 ]] && echo yes || echo no )" "yes"
  new_home; : > "${LOG}"
  local out
  out=$( run_on_tty n --defaults --confirm --yes 2>&1 )
  check "and on a terminal it does not ask" "$( print -r -- "${out}" | grep -c '\[y/n\]' )" "0"
  check "while still running everything" "$( [[ $( calls 'defaults write' ) -gt 100 ]] && echo yes || echo no )" "yes"
}

test_assume_yes_homebrew_installer () {
  new_home
  # No brew anywhere, so the script has to run the installer. The stand-in installer records whether
  # it was told to be non-interactive, then provides a brew so the run can carry on
  rm "${STUBS}/brew" "${TMP}/brew/bin/brew"
  local inst="${TMP}/brew-install.sh"
  cat > "${inst}" << EOF
#!/bin/sh
echo "installer noninteractive=\${NONINTERACTIVE:-unset}" >> ${LOG}
mkdir -p ${TMP}/brew/bin
printf '#!/bin/sh\nexit 0\n' > ${TMP}/brew/bin/brew; chmod +x ${TMP}/brew/bin/brew
EOF
  EXTRA_ENV=( BREW_INSTALL_URL="file://${inst}" ); : > "${LOG}"
  run -P > /dev/null 2>&1
  check "without --yes the Homebrew installer is left to ask" "$( grep '^installer' "${LOG}" )" "installer noninteractive=unset"
  rm -f "${TMP}/brew/bin/brew"; : > "${LOG}"
  run -P -y > /dev/null 2>&1
  EXTRA_ENV=()
  check "with --yes it is told not to (NONINTERACTIVE=1)" "$( grep '^installer' "${LOG}" )" "installer noninteractive=1"
  check "and that does not leak into the shell afterwards" "$( env -i HOME="${H}" zsh -c 'echo ${NONINTERACTIVE:-unset}' )" "unset"
  # put the stubs back for the tests that follow
  make_stubs
}

test_prompt_engine () {
  new_home
  check "the default is powerlevel10k alone: its config is used, oh-my-posh is not set up" "$( prompt_state )" "p10k=1 engine=p10k posh=0"
  print -r -- "PROMPT_ENGINE=posh" > "${H}/.ussuri/config"
  check "PROMPT_ENGINE=posh: oh-my-posh only" "$( prompt_state )" "p10k=no engine=posh posh=1"
  print -r -- "PROMPT_ENGINE=none" > "${H}/.ussuri/config"
  check "PROMPT_ENGINE=none: neither" "$( prompt_state )" "p10k=no engine=none posh=0"
  print -r -- "PROMPT_ENGINE=starship" > "${H}/.ussuri/config"
  local out
  out=$( EXTRA_ENV=(); run 2>&1 )
  check "an unknown engine falls back to p10k and says so" "$( prompt_state ) / $( print -r -- "${out}" | grep -c "Unknown prompt engine 'starship'" )" "p10k=1 engine=p10k posh=0 / 1"
  rm -f "${H}/.ussuri/config"
  EXTRA_ENV=( PROMPT_ENGINE=posh )
  check "it can come from the environment too" "$( prompt_state )" "p10k=no engine=posh posh=1"
  EXTRA_ENV=()
}

test_prompt_engine_installs () {
  new_home
  rm -rf "${H}/.oh-my-posh"
  local inst="${TMP}/posh-install.sh"
  print -r -- "echo installer-ran >> ${LOG}; mkdir -p ${H}/.oh-my-posh" > "${inst}"
  EXTRA_ENV=( POSH_INSTALL_URL="file://${inst}" ); : > "${LOG}"
  run > /dev/null 2>&1
  check "powerlevel10k users never get oh-my-posh installed" "$( grep -c installer-ran "${LOG}" )" "0"
  EXTRA_ENV=( POSH_INSTALL_URL="file://${inst}" PROMPT_ENGINE=posh ); : > "${LOG}"
  run > /dev/null 2>&1
  check "but it is installed when it is the engine" "$( grep -c installer-ran "${LOG}" )" "1"
  EXTRA_ENV=()
}

test_prompt_engine_switches () {
  new_home
  local sw
  for sw in -E --prompt --engine; do
    EXTRA_ENV=(); : > "${LOG}"
    run ${sw} posh > /dev/null 2>&1
    check "${sw} posh sets up oh-my-posh for that run" "$( calls 'oh-my-posh init zsh' )" "1"
  done
  : > "${LOG}"; run -o > /dev/null 2>&1
  check "-o still installs and sets up oh-my-posh" "$( calls 'oh-my-posh init zsh' )" "1"
  : > "${LOG}"; run -T > /dev/null 2>&1
  check "-T does the p10k setup and not oh-my-posh" "$( calls 'oh-my-posh' )" "0"
  : > "${LOG}"; run -A --dryrun > /dev/null 2>&1
  check "-A (do all) follows the engine: no oh-my-posh for a p10k user" "$( calls 'oh-my-posh' )" "0"
  : > "${LOG}"; run -A -E posh > /dev/null 2>&1
  check "-A -E posh: oh-my-posh, whatever order they are given in" "$( calls 'oh-my-posh init zsh' )" "1"
  : > "${LOG}"; run -E posh -A > /dev/null 2>&1
  check "-E posh -A: the same" "$( calls 'oh-my-posh init zsh' )" "1"
  check "-E without a name is an error" "$( run -E > /dev/null 2>&1; echo $? | awk '{print ($1 != 0) ? "error" : "ok"}' )" "error"
}

test_prompt_engine_in_lists () {
  new_home
  print -r -- "zinit () { print -r -- \"zinit \$*\" >> ${LOG}; }" > "${H}/.zinit/zinit.zsh"
  local turbo engine
  for turbo in true false; do
    for engine in p10k posh none; do
      : > "${LOG}"
      EXTRA_ENV=( ZINIT_TURBO="${turbo}" PROMPT_ENGINE="${engine}" )
      run --zinit > /dev/null 2>&1
      check "turbo=${turbo} engine=${engine}: powerlevel10k plugin $( [[ ${engine} == p10k ]] && echo loads || echo is not loaded )" "$( grep -c 'zinit light romkatv/powerlevel10k' "${LOG}" )" "$( [[ ${engine} == p10k ]] && echo 1 || echo 0 )"
    done
  done
  EXTRA_ENV=()
}

test_doctor_prompt_engine () {
  healthy_home
  local out
  out=$( run --doctor 2>&1 )
  check "doctor names the engine" "$( print -r -- "${out}" | grep -c 'ok.*prompt engine: p10k' )" "1"
  check "and does not ask for oh-my-posh when it is not the engine" "$( print -r -- "${out}" | grep -c 'oh-my-posh' )" "0"
  rm -rf "${H}/.oh-my-posh"
  mv "${STUBS}/oh-my-posh" "${TMP}/omp.stub"
  EXTRA_ENV=( PROMPT_ENGINE=posh )
  out=$( run --doctor 2>&1 )
  mv "${TMP}/omp.stub" "${STUBS}/oh-my-posh"
  check "with posh as the engine a missing oh-my-posh is reported" "$( print -r -- "${out}" | grep -c 'warn.*oh-my-posh' )" "1"
  EXTRA_ENV=( DO_POSH_CHECK=true )
  out=$( run --doctor 2>&1 )
  check "doctor warns when oh-my-posh is switched on alongside p10k (two prompts fighting)" "$( print -r -- "${out}" | grep -c 'warn.*two prompt engines' )" "1"
  EXTRA_ENV=()
}

test_update_files () {
  new_home; make_release 9.9.9; UPDATE_ENV=()
  local out live="${TMP}/live/ussuri.zsh" files="${H}/.ussuri/files"
  print -r -- "my own list" > "${files}/zinit/local.zsh"
  print -r -- "my own package" > "${files}/packages/local.brew"
  out=$( run_update )
  check "the script is replaced" "$( grep -m1 '^# Version:' "${live}" | awk '{print $3}' )" "9.9.9"
  check "a file that is new in the release is added" "$( cat "${files}/zinit/brandnew.zsh" 2> /dev/null )" "# a list that did not exist before"
  check "a changed list is updated" "$( grep -c '^a-new-package$' "${files}/packages/macos.brew" )" "1"
  local kept
  kept=( "${H}"/.ussuri/files.bak/*/packages/macos.brew(N) )
  check "and the copy it replaced is kept, not lost" "$( grep -c '^a-new-package$' "${kept[1]}" 2> /dev/null )" "0"
  check "an unchanged list is not touched or backed up" "$( ls "${H}"/.ussuri/files.bak/*/packages/ubuntu.apt 2> /dev/null | wc -l | tr -d ' ' )" "0"
  check "your local files are never touched" "$( cat "${files}/zinit/local.zsh" "${files}/packages/local.brew" | tr '\n' ',' )" "my own list,my own package,"
  check "it says what it did" "$( print -r -- "${out}" | grep -c -E 'Updated [0-9]+ supporting files' )" "1"
}

test_update_dryrun () {
  new_home; make_release 9.9.9; UPDATE_ENV=()
  local before after out
  before=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  out=$( run_update --dryrun )
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "--dryrun changes nothing in the home directory" "${after}" "${before}"
  check "nor the script" "$( grep -m1 '^# Version:' "${TMP}/live/ussuri.zsh" | awk '{print $3}' )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
}

test_update_refusals () {
  local out ver
  ver=$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )
  # An archive that tries to write outside the target
  new_home; make_release 9.9.9; UPDATE_ENV=()
  python3 - "${TMP}/rel.tgz" << 'EOF'
import sys, tarfile, io
with tarfile.open(sys.argv[1], 'w:gz') as t:
    for name in ('ussuri-main/ussuri.zsh', '../escaped'):
        data = b'# Version: 9.9.9\n'
        i = tarfile.TarInfo(name); i.size = len(data); t.addfile(i, io.BytesIO(data))
EOF
  out=$( run_update )
  check "an archive with a path that escapes is refused" "$( print -r -- "${out}" | grep -c -i 'unsafe' )" "1"
  check "and nothing is changed" "$( grep -m1 '^# Version:' "${TMP}/live/ussuri.zsh" | awk '{print $3}' )" "${ver}"
  check "and nothing was written outside" "$( [[ -e "${TMP}/escaped" || -e "${TMP}/../escaped" ]] && echo written || echo safe )" "safe"
  # A script that does not parse
  new_home; make_release 9.9.9; UPDATE_ENV=()
  print -r -- 'if [ then' >> "${TMP}/rel/ussuri-main/ussuri.zsh"
  tar -czf "${TMP}/rel.tgz" -C "${TMP}/rel" ussuri-main
  out=$( run_update )
  check "a release whose script does not parse is refused" "$( print -r -- "${out}" | grep -c 'failed validation' )" "1"
  check "with the files left alone too" "$( [[ -e "${H}/.ussuri/files/zinit/brandnew.zsh" ]] && echo changed || echo untouched )" "untouched"
  # A pinned checksum that does not match
  new_home; make_release 9.9.9
  UPDATE_ENV=( UPDATE_SHA256=0000000000000000000000000000000000000000000000000000000000000000 )
  out=$( run_update )
  check "a wrong UPDATE_SHA256 is refused" "$( print -r -- "${out}" | grep -c -i 'checksum' )" "1"
  check "and nothing is changed" "$( grep -m1 '^# Version:' "${TMP}/live/ussuri.zsh" | awk '{print $3}' )" "${ver}"
  # The right one
  local good
  good=$( shasum -a 256 "${TMP}/rel.tgz" 2> /dev/null || sha256sum "${TMP}/rel.tgz" )
  UPDATE_ENV=( UPDATE_SHA256="${good%% *}" )
  out=$( run_update )
  check "the right UPDATE_SHA256 is accepted" "$( grep -m1 '^# Version:' "${TMP}/live/ussuri.zsh" | awk '{print $3}' )" "9.9.9"
  UPDATE_ENV=()
}

test_update_archive_missing () {
  new_home; make_release 9.9.9
  RELEASE_ENV=( SCRIPT_URL="file://${TMP}/rel/ussuri-main/ussuri.zsh" UPDATE_URL="file://${TMP}/no-such.tgz" ); UPDATE_ENV=()
  local out
  out=$( run_update )
  check "if the archive can't be fetched the script alone is still updated" "$( grep -m1 '^# Version:' "${TMP}/live/ussuri.zsh" | awk '{print $3}' )" "9.9.9"
  check "and it says the files were not" "$( print -r -- "${out}" | grep -c -i 'supporting files were not updated' )" "1"
}

test_local_zinit () {
  new_home
  print -r -- "zinit () { print -r -- \"zinit \$*\" >> ${LOG}; }" > "${H}/.zinit/zinit.zsh"
  printf '%s\n' '# my extras' 'zinit light someone/their-plugin' > "${H}/.ussuri/files/zinit/local.zsh"
  : > "${LOG}"
  run --zinit > /dev/null 2>&1
  check "plugins in zinit/local.zsh are loaded" "$( grep -c 'zinit light someone/their-plugin' "${LOG}" )" "1"
  check "after the shipped list, not before" "$( grep -n -E 'zsh-syntax-highlighting|their-plugin' "${LOG}" | sed -E 's/.*(zsh-syntax-highlighting|their-plugin).*/\1/' | tr '\n' ' ' )" "zsh-syntax-highlighting their-plugin "
  rm "${H}/.ussuri/files/zinit/local.zsh"; : > "${LOG}"
  run --zinit > /dev/null 2>&1
  check "without the file nothing extra happens" "$( grep -c 'their-plugin' "${LOG}" )" "0"
}

test_local_packages () {
  new_home
  grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew" > "${TMP}/installed.txt"
  print -r -- "my-extra-tool" > "${H}/.ussuri/files/packages/local.brew"
  printf '%s\n' "# a comment" "ansible" >> "${H}/.ussuri/files/packages/local.brew"
  print -r -- "git" > "${H}/.ussuri/brew.list"; cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  local out
  out=$( run -P --dryrun --verbose 2>&1 | grep -E 'Executing: +brew install' | sed 's/.*install //' | sort | tr '\n' ' ' )
  check "packages in packages/local.<ext> are added to the shipped list" "${out}" "ansible autoconf my-extra-tool "
  : > "${LOG}"
  cp "${ROOT}/files/packages/macos.brew" "${H}/.ussuri/brew.list"; print -r -- "my-extra-tool" >> "${H}/.ussuri/brew.list"
  run -P > /dev/null 2>&1
  check "once everything is installed a stamp is saved" "$( [[ -f "${H}/.ussuri/macos.brew.sum" ]] && echo stamped || echo none )" "stamped"
  : > "${LOG}"
  print -r -- "another-new-tool" >> "${H}/.ussuri/files/packages/local.brew"
  EXTRA_ENV=( DO_PACKAGE_CHECK=true )
  run --verbose 2>&1 | grep -c 'Installing package another-new-tool' | awk '{print ($1 > 0) ? "yes" : "no"}' > "${TMP}/relogin"
  EXTRA_ENV=()
  check "a login notices the local list changed (it is part of the checksum)" "$( cat "${TMP}/relogin" )" "yes"
}

test_doctor_local () {
  healthy_home
  local out
  out=$( run --doctor 2>&1 )
  check "doctor says nothing about local files when there are none" "$( print -r -- "${out}" | grep -c -i 'local' )" "0"
  printf '%s\n' "zinit light a/b" "zinit light c/d" > "${H}/.ussuri/files/zinit/local.zsh"
  printf '%s\n' "x" "y" "z" > "${H}/.ussuri/files/packages/local.brew"
  out=$( run --doctor 2>&1 )
  check "doctor counts the extra plugin lines" "$( print -r -- "${out}" | grep -c 'ok.*local plugin list.*2' )" "1"
  check "and the extra packages" "$( print -r -- "${out}" | grep -c 'ok.*local package list.*3' )" "1"
}

test_journal_encoding () {
  load_function journal_field
  load_function journal_unfield
  local v enc
  for v in "plain" "with space" "it's \"quoted\"" $'tab\there' $'new\nline' 'back\slash $HOME `x`' "unicode é 日本" "" "|pipe|" "~tilde" "#hash"; do
    enc=$( journal_field "${v}" )
    check "round trip [${v//$'\n'/\\n}]" "$( journal_unfield "${enc}" )" "${v}"
    [[ "${enc}" == *$'\t'* || "${enc}" == *$'\n'* ]] && bad "an encoded field has a tab or newline in it: ${enc}"
  done
}

test_defaults_journal () {
  new_home; use_typed_defaults; seed_defaults
  sort "${DEFAULTS_DB}" > "${TMP}/before.txt"
  : > "${LOG}"
  EXTRA_ENV=( "${UNDO_ENV[@]}" )
  run --defaults > /dev/null 2>&1
  local writes noop
  writes=$( calls 'defaults write' )
  noop=$( grep -c 'defaults write com.apple.addressbook' "${LOG}" )
  check "the journal records exactly the writes that took effect" "$( journal_lines )" "$(( writes - noop ))"
  check "and not the one that was silently ignored (it never changed anything)" "$( grep -c 'addressbook' "${H}/.ussuri/defaults.journal" )" "0"
  local out
  out=$( run --defaults-undo list 2>&1 )
  check "the run is listed, with how many settings it changed" "$( print -r -- "${out}" | grep -c -E "^ +1 +[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9:]{8} +$(( writes - noop )) settings" )" "1"
  : > "${LOG}"; sort "${DEFAULTS_DB}" > "${TMP}/applied.txt"
  run --defaults > /dev/null 2>&1
  check "a second apply with nothing to change adds nothing" "$( journal_lines )" "$(( writes - noop ))"
  EXTRA_ENV=()
  use_plain_defaults
}

test_defaults_undo () {
  new_home; use_typed_defaults; seed_defaults
  sort "${DEFAULTS_DB}" > "${TMP}/before.txt"
  EXTRA_ENV=( "${UNDO_ENV[@]}" )
  run --defaults > /dev/null 2>&1
  : > "${LOG}"
  run --defaults-undo > /dev/null 2>&1
  sort "${DEFAULTS_DB}" > "${TMP}/after.txt"
  check "undo puts every setting back exactly as it was (value, type and unset)" "$( diff "${TMP}/before.txt" "${TMP}/after.txt" > /dev/null && echo identical || echo DIFFERENT )" "identical"
  check "settings that were not set before are deleted, not written as empty" "$( [[ $( calls 'defaults delete' ) -gt 90 ]] && echo yes || echo no )" "yes"
  check "a bool that was off is written back as a bool" "$( grep -c 'defaults write com.apple.finder ShowPathbar -bool false' "${LOG}" )" "1"
  check "an integer as an integer, a float as a float, a string with quotes intact" "$( grep -c -E 'tilesize -int 48|autohide-time-modifier -float 0.25|location -string' "${LOG}" )" "3"
  check "the Dock is restarted so the old settings show" "$( calls 'killall Dock' )" "1"
  local out
  out=$( run --defaults-undo 2>&1 ); local rc=$?
  check "the run is then marked as undone, so a second undo has nothing left" "${rc}:$( print -r -- "${out}" | grep -c 'Nothing to undo' )" "1:1"
  EXTRA_ENV=()
  use_plain_defaults
}

test_defaults_undo_changed_since () {
  new_home; use_typed_defaults; seed_defaults
  EXTRA_ENV=( "${UNDO_ENV[@]}" )
  run --defaults > /dev/null 2>&1
  # you change two settings yourself after the script applied them
  sed -i.bak 's/^com.apple.dock|tilesize|integer|.*/com.apple.dock|tilesize|integer|99/; s/^com.apple.finder|ShowPathbar|boolean|.*/com.apple.finder|ShowPathbar|boolean|0/' "${DEFAULTS_DB}"
  local out
  out=$( run --defaults-undo 2>&1 )
  check "a setting you changed since is left alone" "$( grep -c '^com.apple.dock|tilesize|integer|99$' "${DEFAULTS_DB}" )" "1"
  check "and the script says which ones and why" "$( print -r -- "${out}" | grep -c -E 'skipped.*tilesize.*changed since' )" "1"
  check "the rest are restored" "$( grep -c '^com.apple.screencapture|type|string|jpg$' "${DEFAULTS_DB}" )" "1"
  check "the summary counts what was skipped" "$( print -r -- "${out}" | grep -c -E 'Restored [0-9]+ of [0-9]+ settings.*2 skipped' )" "1"
  EXTRA_ENV=()
  use_plain_defaults
}

test_defaults_undo_runs () {
  new_home; use_typed_defaults; seed_defaults
  EXTRA_ENV=( "${UNDO_ENV[@]}" )
  run --defaults > /dev/null 2>&1
  sleep 1
  # something changes a setting, and a later apply puts it back: a second run in the journal
  sed -i.bak 's/^com.apple.dock|tilesize|integer|.*/com.apple.dock|tilesize|integer|40/' "${DEFAULTS_DB}"
  run --defaults > /dev/null 2>&1
  local out
  out=$( run --defaults-undo list 2>&1 )
  check "two runs are listed, newest first" "$( print -r -- "${out}" | grep -c -E '^ +[12] +[0-9]{4}-' )" "2"
  run --defaults-undo > /dev/null 2>&1
  check "undo goes back one run (the newest)" "$( grep -c '^com.apple.dock|tilesize|integer|40$' "${DEFAULTS_DB}" )" "1"
  check "and the other run is still there to undo" "$( run --defaults-undo list 2>&1 | grep -c -E '^ +1 +[0-9]{4}-' )" "1"
  # a number picks an older run
  new_home; use_typed_defaults; seed_defaults
  run --defaults > /dev/null 2>&1; sleep 1
  sed -i.bak 's/^com.apple.dock|tilesize|integer|.*/com.apple.dock|tilesize|integer|40/' "${DEFAULTS_DB}"
  run --defaults > /dev/null 2>&1
  run --defaults-undo 2 > /dev/null 2>&1
  check "a number picks an older run: --defaults-undo 2 undoes the first one" "$( grep -c '^com.apple.screencapture|type|string|jpg$' "${DEFAULTS_DB}" )" "1"
  check "-J is the short form, and a switch after it is still a switch" "$( run -J list -v 2>&1 | grep -c -E 'Information' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  EXTRA_ENV=()
  use_plain_defaults
}

test_defaults_undo_safety () {
  new_home; use_typed_defaults; seed_defaults
  EXTRA_ENV=( "${UNDO_ENV[@]}" )
  local out rc
  out=$( run --defaults-undo 2>&1 ); rc=$?
  check "with no journal it says so and fails" "${rc}:$( print -r -- "${out}" | grep -c 'Nothing to undo' )" "1:1"
  run --defaults --dryrun > /dev/null 2>&1
  check "--dryrun apply records nothing" "$( [[ -e "${H}/.ussuri/defaults.journal" ]] && echo journal || echo none )" "none"
  command -v python3 > /dev/null 2>&1 && {
    run_on_tty n --defaults --confirm > /dev/null 2>&1
    check "declining every --confirm prompt records nothing (nothing was written)" "$( journal_lines )" "0"
  }
  run --defaults > /dev/null 2>&1
  sort "${DEFAULTS_DB}" > "${TMP}/applied.txt"; : > "${LOG}"
  run --defaults-undo --dryrun > /dev/null 2>&1
  sort "${DEFAULTS_DB}" > "${TMP}/after_dry.txt"
  check "--defaults-undo --dryrun changes nothing" "$( diff "${TMP}/applied.txt" "${TMP}/after_dry.txt" > /dev/null && echo identical || echo DIFFERENT )" "identical"
  check "and does not mark the run undone, so it can still be undone" "$( run --defaults-undo list 2>&1 | grep -c -E '^ +1 +[0-9]{4}-' )" "1"
  # a previous value that cannot be restored (an array): reported, and left as it is
  new_home; use_typed_defaults
  print -r -- "com.apple.dock|tilesize|array|(1,2)" >> "${DEFAULTS_DB}"
  run --defaults > /dev/null 2>&1
  out=$( run --defaults-undo 2>&1 )
  check "a value that was not a simple type is reported as not restorable" "$( print -r -- "${out}" | grep -c -E 'skipped.*tilesize.*array' )" "1"
  check "and left as the script set it" "$( grep -c '^com.apple.dock|tilesize|integer|32$' "${DEFAULTS_DB}" )" "1"
  EXTRA_ENV=()
  use_plain_defaults
}

test_doctor_defaults_journal () {
  healthy_home; use_typed_defaults; seed_defaults
  local out
  out=$( EXTRA_ENV=( "${UNDO_ENV[@]}" ); run --doctor 2>&1 )
  check "doctor says nothing about undo before anything was applied" "$( print -r -- "${out}" | grep -c -i 'undo' )" "0"
  ( EXTRA_ENV=( "${UNDO_ENV[@]}" ); run --defaults > /dev/null 2>&1 )
  out=$( EXTRA_ENV=( "${UNDO_ENV[@]}" ); run --doctor 2>&1 )
  check "doctor tells you a run can be undone" "$( print -r -- "${out}" | grep -c 'ok.*1 run.*can be undone' )" "1"
  use_plain_defaults
}

test_update_hint_off () {
  new_home; make_hint_remote 9.9.9
  : > "${LOG}"
  check "by default no hook, no check" "$( hint_state )" "hook=0"
  check "and no network" "$( calls 'curl -fsS -m' )" "0"
  check "and no files" "$( nfiles "${H}/.ussuri/update.*" )" "0"
  EXTRA_ENV=( UPDATE_HINT=true )
  run --version > /dev/null 2>&1; run -v --dryrun > /dev/null 2>&1
  EXTRA_ENV=()
  check "a manual run never checks, even when it is turned on" "$( calls 'curl -fsS -m' )" "0"
  rm -f "${STUBS}/curl"
}

test_update_hint_cycle () {
  new_home; make_hint_remote 9.9.9
  EXTRA_ENV=( UPDATE_HINT=true )
  : > "${LOG}"
  check "first login: nothing to say yet" "$( hint_state )" "hook=0"
  wait_for_latest
  check "but the check ran, in the background, and wrote what it found" "$( cat "${H}/.ussuri/update.latest" 2> /dev/null )" "9.9.9"
  check "after one request" "$( calls 'curl -fsS -m' )" "1"
  check "and left a stamp" "$( [[ -f "${H}/.ussuri/update.check" ]] && echo yes || echo no )" "yes"
  : > "${LOG}"
  check "next login: the newer version is known, so the hint is queued for the first prompt" "$( hint_state )" "hook=1"
  check "without asking again (the stamp is fresh)" "$( calls 'curl -fsS -m' )" "0"
  check "and the hint is marked as shown today" "$( [[ -f "${H}/.ussuri/update.hinted" ]] && echo yes || echo no )" "yes"
  check "so the login after that is quiet" "$( hint_state )" "hook=0"
  touch -t "$( date -v-2d +%Y%m%d%H%M 2> /dev/null || date -d '2 days ago' +%Y%m%d%H%M )" "${H}/.ussuri/update.hinted"
  check "a day later it is mentioned again" "$( hint_state )" "hook=1"
  touch -t "$( date -v-2d +%Y%m%d%H%M 2> /dev/null || date -d '2 days ago' +%Y%m%d%H%M )" "${H}/.ussuri/update.check"
  : > "${LOG}"; hint_state > /dev/null; sleep 1
  check "and a day later it checks again" "$( calls 'curl -fsS -m' )" "1"
  EXTRA_ENV=()
  rm -f "${STUBS}/curl"
}

test_update_hint_nothing_newer () {
  new_home; make_hint_remote "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
  EXTRA_ENV=( UPDATE_HINT=true )
  hint_state > /dev/null; wait_for_latest
  check "when the remote is the same version there is nothing to say" "$( hint_state )" "hook=0"
  make_hint_remote 0.0.1
  touch -t "$( date -v-2d +%Y%m%d%H%M 2> /dev/null || date -d '2 days ago' +%Y%m%d%H%M )" "${H}/.ussuri/update.check"
  hint_state > /dev/null; sleep 1
  check "or older (a development copy is newer than the release)" "$( hint_state )" "hook=0"
  EXTRA_ENV=()
  rm -f "${STUBS}/curl"
}

test_update_hint_bad_answers () {
  new_home; make_hint_remote 9.9.9
  EXTRA_ENV=( UPDATE_HINT=true )
  hint_state > /dev/null; wait_for_latest
  make_hint_remote garbage
  touch -t "$( date -v-2d +%Y%m%d%H%M 2> /dev/null || date -d '2 days ago' +%Y%m%d%H%M )" "${H}/.ussuri/update.check"
  : > "${LOG}"; hint_state > /dev/null; sleep 1
  check "an answer that isn't a version leaves what was known alone" "$( cat "${H}/.ussuri/update.latest" )" "9.9.9"
  check "and it did ask" "$( calls 'curl -fsS -m' )" "1"
  print -r -- "not a version" > "${H}/.ussuri/update.latest"
  check "a damaged file is ignored, not trusted" "$( hint_state )" "hook=0"
  EXTRA_ENV=()
  rm -f "${STUBS}/curl"
}

test_update_hint_does_not_block () {
  zmodload zsh/datetime 2> /dev/null
  new_home; make_hint_remote 9.9.9
  # A first login applies all the defaults, which is slow and nothing to do with the hint: do that first,
  # so what is timed is a login that does only the hint's work
  hint_state > /dev/null
  EXTRA_ENV=( UPDATE_HINT=true CURL_DELAY=3 )
  local start="${EPOCHREALTIME}" took
  hint_state > /dev/null
  took=$(( EPOCHREALTIME - start ))
  check "a login does not wait for the check (the fetch takes 3s, the login under 1.5s)" "$( (( took < 1.5 )) && echo fast || echo "SLOW ${took}" )" "fast"
  check "and nothing is left holding the terminal's output open (the call returned while it was still running)" "$( [[ -f "${H}/.ussuri/update.latest" ]] && echo already-done || echo still-running )" "still-running"
  wait_for_latest; sleep 4
  check "it finishes on its own afterwards" "$( cat "${H}/.ussuri/update.latest" 2> /dev/null )" "9.9.9"
  EXTRA_ENV=()
  rm -f "${STUBS}/curl"
}

test_show_update_hint () {
  load_function show_update_hint
  UPDATE_HINT_TEXT="ussuri 9.9.9 is available (this is 1.0.0): run ussuri.zsh --update"
  precmd_functions=( other_hook show_update_hint last_hook )
  local out
  out=$( show_update_hint )
  check "the hint says what is available and what to do" "${out}" "ussuri 9.9.9 is available (this is 1.0.0): run ussuri.zsh --update"
  show_update_hint > /dev/null
  check "and it takes itself out of the prompt hooks, leaving the others" "${precmd_functions[*]}" "other_hook last_hook"
  unset UPDATE_HINT_TEXT; precmd_functions=()
}

test_doctor_update_hint () {
  healthy_home
  local out
  out=$( run --doctor 2>&1 )
  check "doctor says nothing when the hint is off" "$( print -r -- "${out}" | grep -c -i 'update' )" "0"
  EXTRA_ENV=( UPDATE_HINT=true )
  out=$( run --doctor 2>&1 )
  check "when it is on and has not checked yet, it says so" "$( print -r -- "${out}" | grep -c 'ok.*update hint is on.*not checked yet' )" "1"
  print -r -- "9.9.9" > "${H}/.ussuri/update.latest"
  out=$( run --doctor 2>&1 )
  check "and warns when a newer version is known" "$( print -r -- "${out}" | grep -c 'warn.*9.9.9 is available' )" "1"
  EXTRA_ENV=()
}

test_casks_and_taps () {
  new_home
  local files="${H}/.ussuri/files/packages"
  printf '%s\n' "# my apps" "some-app" "another-app" > "${files}/local.cask"
  printf '%s\n' "someone/tools" "Other/Repo" > "${files}/local.tap"
  # Everything in the formula list and the font is installed, one of the casks is, and one tap is (in lower case, as brew shows them)
  { cat "${ROOT}/files/packages/macos.brew"; print -r -- "font-fira-code-nerd-font"; print -r -- "another-app"; } > "${TMP}/installed.txt"
  print -r -- "other/repo" > "${TMP}/taps.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"; cp "${TMP}/taps.txt" "${H}/.ussuri/brew.taps"
  : > "${LOG}"
  run -P > /dev/null 2>&1
  check "a cask that is missing is installed as a cask" "$( grep -c '^brew install --cask some-app$' "${LOG}" )" "1"
  check "one that is installed is not" "$( grep -c 'another-app' "${LOG}" )" "0"
  check "a tap that is missing is added" "$( grep -c '^brew tap someone/tools$' "${LOG}" )" "1"
  check "one that is there is not, whatever the case" "$( grep -c -i 'other/repo' "${LOG}" )" "0"
  check "and nothing is installed as a plain formula by mistake" "$( grep -c -E '^brew install [^-]' "${LOG}" )" "0"
  check "taps come first, so a formula from one can be found" "$( grep -n -E '^brew (tap someone|install --cask some)' "${LOG}" | head -1 | grep -c 'tap someone' )" "1"
  check "the lists with something missing are not stamped as done (the one with nothing missing is)" "$( ls "${H}"/.ussuri/macos.*.sum 2> /dev/null | sed 's#.*/##' | tr '\n' ' ' )" "macos.brew.sum "
  # Now everything is there: each list is stamped separately
  { cat "${TMP}/installed.txt"; print -r -- "some-app"; } > "${TMP}/installed2.txt"; cp "${TMP}/installed2.txt" "${TMP}/installed.txt"
  printf '%s\n' "other/repo" "someone/tools" > "${TMP}/taps.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"; cp "${TMP}/taps.txt" "${H}/.ussuri/brew.taps"
  rm -f "${H}"/.ussuri/macos.*.sum
  : > "${LOG}"
  run -P > /dev/null 2>&1
  check "once everything is there nothing is run" "$( grep -c -E '^brew (install|tap [a-z])' "${LOG}" )" "0"
  check "and the formulae, casks and taps each get their own stamp" "$( ls "${H}"/.ussuri/macos.*.sum 2> /dev/null | sed 's#.*/##' | tr '\n' ' ' )" "macos.brew.sum macos.cask.sum macos.tap.sum "
}

test_casks_and_taps_dryrun () {
  new_home
  local files="${H}/.ussuri/files/packages"
  printf '%s\n' "some-app" > "${files}/local.cask"; printf '%s\n' "someone/tools" > "${files}/local.tap"
  local out
  out=$( run -P --dryrun --verbose 2>&1 | grep -E 'Executing: +brew (tap [a-z]|install --cask)' | sed 's/.*Executing: *//' | tr '\n' ',' )
  check "a dry run shows the tap and the cask it would add" "${out}" "brew tap someone/tools,brew install --cask some-app,"
}

test_casks_and_taps_defaults () {
  local f
  for f in macos.cask macos.tap; do
    check "files/packages/${f} ships with nothing to install (examples are comments)" "$( grep -c -v -E '^[[:space:]]*(#|$)' "${ROOT}/files/packages/${f}" )" "0"
  done
  new_home
  rm -f "${H}/.ussuri/files/packages/macos.cask" "${H}/.ussuri/files/packages/macos.tap"
  : > "${LOG}"
  grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew" > "${TMP}/installed.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  local out
  out=$( run -P 2>&1 )
  check "an install from before these lists existed still works, and processes the formulae" "$( grep -c -E '^brew install (ansible|autoconf)$' "${LOG}" )" "2"
  check "without complaint" "$( print -r -- "${out}" | grep -c -i 'error\|no such' )" "0"
}

test_font_is_installed_as_a_cask () {
  new_home
  rm -f "${H}/.ussuri/brew.list"; : > "${TMP}/installed.txt"
  : > "${LOG}"
  run -f > /dev/null 2>&1
  check "the Nerd Font is installed as a cask (it is not a formula, so as a formula it fails)" "$( grep -c '^brew install --cask font-fira-code-nerd-font$' "${LOG}" )" "1"
  check "and not as a plain formula" "$( grep -c '^brew install font-fira-code-nerd-font$' "${LOG}" )" "0"
}

# Lists of the packages `brew install` would be asked for in a dry run, sorted, on one line

dryrun_brew_installs () {
  run -P --dryrun --verbose 2>&1 | grep -E 'Executing: +brew install' | sed 's/.*install //' | sort | tr '\n' ' '
}

# A home where only what the layers add is missing (everything in the shipped list is installed)

layered_home () {
  new_home
  # the shipped formulae and the font (a login also checks the font), so only what a test adds is missing
  { cat "${ROOT}/files/packages/macos.brew"; print -r -- "font-fira-code-nerd-font"; } > "${TMP}/installed.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  LF="${H}/.ussuri/files/packages"
  mkdir -p "${LF}/profiles/work" "${LF}/profiles/home" "${LF}/hosts/box" "${LF}/hosts/other"
}

test_profile_layers () {
  layered_home
  print -r -- "common-extra" > "${LF}/local.brew"
  print -r -- "work-extra"   > "${LF}/profiles/work/local.brew"
  print -r -- "home-extra"   > "${LF}/profiles/home/local.brew"
  print -r -- "box-extra"    > "${LF}/hosts/box/local.brew"
  print -r -- "other-extra"  > "${LF}/hosts/other/local.brew"
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  check "the profile and the machine add to the common list" "$( dryrun_brew_installs )" "box-extra common-extra work-extra "
  EXTRA_ENV=( MACHINE=box )
  check "with no profile only the common and machine lists apply" "$( dryrun_brew_installs )" "box-extra common-extra "
  EXTRA_ENV=( PROFILE=home MACHINE=other )
  check "another profile and machine get theirs, not the first ones" "$( dryrun_brew_installs )" "common-extra home-extra other-extra "
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  print -r -- "work-cask" > "${LF}/profiles/work/local.cask"
  check "casks are layered the same way" "$( run -P --dryrun --verbose 2>&1 | grep -c 'brew install --cask work-cask' )" "1"
  run -P --version > /dev/null 2>&1
  EXTRA_ENV=( PROFILE=work )
  check "-M sets the profile for one run" "$( EXTRA_ENV=( MACHINE=box ); run -M home -P --dryrun --verbose 2>&1 | grep -c 'install home-extra' )" "1"
  EXTRA_ENV=()
}

test_profile_exclusions () {
  layered_home
  grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew" > "${TMP}/installed.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  printf '%s\n' '!ansible' '!not-in-the-list' > "${LF}/profiles/work/local.brew"
  EXTRA_ENV=( MACHINE=box )
  check "without the profile both missing packages are installed" "$( dryrun_brew_installs )" "ansible autoconf "
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  check "a !name line in a profile takes a package out of the list" "$( dryrun_brew_installs )" "autoconf "
  print -r -- "ansible" > "${LF}/hosts/box/local.brew"
  check "and a later layer (the machine) can put it back" "$( dryrun_brew_installs )" "ansible autoconf "
  # names are matched exactly, never as patterns
  print -r -- "g++" > "${LF}/local.brew"; printf '%s\n' '!g*' '!ansible' > "${LF}/profiles/work/local.brew"; : > "${LF}/hosts/box/local.brew"
  check "an exclusion is an exact name, not a pattern (!g* removes nothing)" "$( dryrun_brew_installs )" "autoconf g++ "
  EXTRA_ENV=()
}

test_profile_checksum () {
  layered_home
  print -r -- "work-extra" > "${LF}/profiles/work/local.brew"
  EXTRA_ENV=( MACHINE=box ); : > "${LOG}"
  run -P > /dev/null 2>&1
  check "no profile: the shipped list is complete, so it is stamped" "$( [[ -f "${H}/.ussuri/macos.brew.sum" ]] && echo stamped || echo none )" "stamped"
  : > "${LOG}"
  EXTRA_ENV=( MACHINE=box DO_PACKAGE_CHECK=true )
  run > /dev/null 2>&1
  check "a login with nothing changed installs nothing" "$( grep -c '^brew install' "${LOG}" )" "0"
  EXTRA_ENV=( MACHINE=box DO_PACKAGE_CHECK=true PROFILE=work ); : > "${LOG}"
  run > /dev/null 2>&1
  check "switching to a profile with more packages is noticed on a login, without -P" "$( grep -c '^brew install work-extra$' "${LOG}" )" "1"
  EXTRA_ENV=()
}

test_profile_zinit () {
  new_home
  print -r -- "zinit () { print -r -- \"zinit \$*\" >> ${LOG}; }" > "${H}/.zinit/zinit.zsh"
  local z="${H}/.ussuri/files/zinit"
  mkdir -p "${z}/profiles/work" "${z}/profiles/home" "${z}/hosts/box" "${z}/hosts/other"
  print -r -- "zinit light l/common"  > "${z}/local.zsh"
  print -r -- "zinit light p/work"    > "${z}/profiles/work/local.zsh"
  print -r -- "zinit light p/home"    > "${z}/profiles/home/local.zsh"
  print -r -- "zinit light h/box"     > "${z}/hosts/box/local.zsh"
  print -r -- "zinit light h/other"   > "${z}/hosts/other/local.zsh"
  : > "${LOG}"
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  run --zinit > /dev/null 2>&1
  check "plugins load in layer order: shipped, common, profile, machine" "$( grep -o -E 'zsh-syntax-highlighting|l/common|p/work|h/box' "${LOG}" | tr '\n' ' ' )" "zsh-syntax-highlighting l/common p/work h/box "
  check "and nothing from another profile or machine" "$( grep -c -E 'p/home|h/other' "${LOG}" )" "0"
  EXTRA_ENV=()
}

test_profile_names () {
  layered_home
  mkdir -p "${LF}/etc"
  print -r -- "evil-pkg" > "${LF}/etc/local.brew"
  local out
  for name in '../etc' 'a/b' '.hidden'; do
    EXTRA_ENV=( PROFILE="${name}" MACHINE=box )
    out=$( run -P --dryrun --verbose 2>&1 )
    check "profile '${name}' is refused, with a warning" "$( print -r -- "${out}" | grep -c "Ignoring PROFILE='${name}'" )" "1"
    check "and its path is never read (evil-pkg is not offered)" "$( print -r -- "${out}" | grep -c 'evil-pkg' )" "0"
  done
  EXTRA_ENV=( MACHINE='../etc' PROFILE=work )
  out=$( run -P --dryrun --verbose 2>&1 )
  check "a machine name with .. is refused too" "$( print -r -- "${out}" | grep -c "Ignoring MACHINE='../etc'" )" "1"
  # With no machine name the machine layer must not become the whole hosts/ directory
  print -r -- "box-extra" > "${LF}/hosts/box/local.brew"
  check "and then no machine layer is used (not every machine's)" "$( print -r -- "${out}" | grep -c 'box-extra' )" "0"
  EXTRA_ENV=()
}

test_profile_dotfiles () {
  new_home; make_dotfiles
  EXTRA_ENV=( PROFILE=work DOTFILES_HOST=box )
  run -L > /dev/null 2>&1
  check "dotfiles follow PROFILE" "$( cat "${H}/.gitconfig" 2> /dev/null )" "work gitconfig"
  new_home; make_dotfiles
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  run -L > /dev/null 2>&1
  check "and the machine name (MACHINE) picks the host layer" "$( cat "${H}/.hostonly" 2> /dev/null )" "only on box"
  new_home; make_dotfiles
  mkdir -p "${H}/.ussuri/dotfiles/profiles/home"; print -r -- "home gitconfig" > "${H}/.ussuri/dotfiles/profiles/home/.gitconfig"
  EXTRA_ENV=( PROFILE=work DOTFILES_PROFILE=home MACHINE=nowhere )
  run -L > /dev/null 2>&1
  check "DOTFILES_PROFILE still overrides PROFILE for dotfiles alone" "$( cat "${H}/.gitconfig" 2> /dev/null )" "home gitconfig"
  new_home; make_dotfiles
  EXTRA_ENV=( DOTFILES_HOST='../x' )
  run -L > /dev/null 2>&1
  check "an invalid host never turns the host layer into every host's files" "$( [[ -e "${H}/.hostonly" ]] && echo linked || echo absent )" "absent"
  EXTRA_ENV=()
}

test_profile_update_keeps_layers () {
  new_home; make_release 9.9.9; UPDATE_ENV=()
  local files="${H}/.ussuri/files"
  mkdir -p "${files}/packages/profiles/work" "${files}/zinit/hosts/box"
  print -r -- "mine" > "${files}/packages/profiles/work/local.brew"
  print -r -- "mine too" > "${files}/zinit/hosts/box/local.zsh"
  run_update > /dev/null
  check "an update leaves profile and machine files alone" "$( cat "${files}/packages/profiles/work/local.brew" "${files}/zinit/hosts/box/local.zsh" | tr '\n' ',' )" "mine,mine too,"
}

test_doctor_profile () {
  healthy_home
  local out machine
  machine=$( zsh -c 'print -r -- ${HOST%%.*}' )
  out=$( run --doctor 2>&1 )
  check "doctor shows the machine name, which defaults to the short hostname" "$( print -r -- "${out}" | grep -c "ok.*machine: ${machine}" )" "1"
  check "and no profile" "$( print -r -- "${out}" | grep -c 'ok.*profile: none' )" "1"
  mkdir -p "${H}/.ussuri/files/packages/profiles/work"
  printf '%s\n' "a" "b" > "${H}/.ussuri/files/packages/profiles/work/local.brew"
  EXTRA_ENV=( PROFILE=work )
  out=$( run --doctor 2>&1 )
  EXTRA_ENV=()
  check "doctor names the profile" "$( print -r -- "${out}" | grep -c 'ok.*profile: work' )" "1"
  check "and counts the lines of its package list" "$( print -r -- "${out}" | grep -c 'ok.*local package list.*profiles/work.*2 lines' )" "1"
}

# The text under a label in the drift report: the label's line is followed by one line of names

drift_names () {
  print -r -- "$1" | grep -A1 -F "$2" | tail -1 | sed 's/^ *//; s/ *$//'
}

test_package_drift_macos () {
  layered_home
  local files="${H}/.ussuri/files/packages" out rc
  # ansible and autoconf are not installed, and zzz-extra is installed (a leaf) but not in any list
  { grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew"; print -r -- "font-fira-code-nerd-font"; print -r -- "zzz-extra"; } > "${TMP}/installed.txt"
  printf '%s\n' zzz-extra git > "${TMP}/leaves.txt"
  print -r -- "wanted-app" > "${files}/local.cask"; print -r -- "other-app" > "${TMP}/casks.txt"
  print -r -- "someone/tools" > "${files}/local.tap"; print -r -- "dkorunic/tap" > "${TMP}/taps.txt"
  : > "${LOG}"
  local before after
  before=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  out=$( run --drift packages 2>&1 ); rc=$?
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "formulae in the list that are not installed" "$( drift_names "${out}" 'formulae not installed (2)' )" "ansible autoconf"
  check "formulae installed that are not in any list (leaves only, not dependencies)" "$( drift_names "${out}" 'formulae installed but not in your lists (1)' )" "zzz-extra"
  check "casks in a list that are not installed" "$( drift_names "${out}" 'casks not installed (1)' )" "wanted-app"
  check "casks installed that are not in a list" "$( drift_names "${out}" 'casks installed but not in your lists (1)' )" "other-app"
  check "taps in a list that are not added" "$( drift_names "${out}" 'taps not added (1)' )" "someone/tools"
  check "taps added that are not in a list" "$( drift_names "${out}" 'taps added but not in your lists (1)' )" "dkorunic/tap"
  check "something from the lists is missing, so there is drift" "${rc}" "1"
  check "the summary counts what -P would install, and says the rest is for information" "$( print -r -- "${out}" | grep -c -E '4 packages from your lists are not installed.*3 installed' )" "1"
  check "it changes nothing in the home directory" "${after}" "${before}"
  check "and installs and adds nothing" "$( grep -c -E '^brew (install|tap [a-z])' "${LOG}" )" "0"
  # Only extras: information, not drift
  { cat "${ROOT}/files/packages/macos.brew"; print -r -- "font-fira-code-nerd-font"; print -r -- "zzz-extra"; } > "${TMP}/installed.txt"
  print -r -- "wanted-app" >> "${TMP}/casks.txt"; print -r -- "someone/tools" >> "${TMP}/taps.txt"
  out=$( run --drift packages 2>&1 ); rc=$?
  check "with everything installed and only extras, there is no drift" "${rc}" "0"
  check "but the extras are still shown, to help keep the lists up to date" "$( print -r -- "${out}" | grep -c 'but not in your lists' )" "3"
  check "and it says everything in the lists is in place" "$( print -r -- "${out}" | grep -c -i 'everything in your lists is installed' )" "1"
}

test_package_drift_cask_in_formula_list () {
  layered_home
  # A cask named in the formula list (brew install falls back to the cask), installed as a cask: it is neither
  # a missing formula nor an extra cask. The font is in the cask list and installed, so it is not an extra either
  print -r -- "some-cask-app" >> "${H}/.ussuri/files/packages/macos.brew"
  print -r -- "font-fira-code-nerd-font" > "${H}/.ussuri/files/packages/local.cask"
  { cat "${ROOT}/files/packages/macos.brew"; print -r -- "font-fira-code-nerd-font"; print -r -- "some-cask-app"; } > "${TMP}/installed.txt"
  # as brew list --formula would not show it: only brew list (both) and brew list --cask do
  printf '%s\n' some-cask-app font-fira-code-nerd-font > "${TMP}/casks.txt"
  local out rc
  out=$( run --drift packages 2>&1 ); rc=$?
  check "a cask named in the formula list and installed is not reported missing" "$( print -r -- "${out}" | grep -c 'some-cask-app' )" "0"
  check "so there is nothing to report" "${rc}:$( print -r -- "${out}" | grep -c -i 'everything in your lists is installed' )" "0:1"
}

test_package_drift_layers () {
  layered_home
  grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew" > "${TMP}/installed.txt"; print -r -- "font-fira-code-nerd-font" >> "${TMP}/installed.txt"
  printf '%s\n' '!ansible' "work-only" > "${LF}/profiles/work/local.brew"
  local out
  EXTRA_ENV=( MACHINE=box )
  out=$( run --drift packages 2>&1 )
  check "without a profile both are missing" "$( drift_names "${out}" 'formulae not installed (2)' )" "ansible autoconf"
  EXTRA_ENV=( PROFILE=work MACHINE=box )
  out=$( run --drift packages 2>&1 )
  check "with the profile an excluded package is not missing, and one it adds is" "$( drift_names "${out}" 'formulae not installed (2)' )" "autoconf work-only"
  EXTRA_ENV=()
}

test_package_drift_switch () {
  layered_home
  local out rc
  out=$( run --drift packages 2>&1 ); rc=$?
  check "packages alone does not mention settings" "$( print -r -- "${out}" | grep -c -E 'settings differ|^Settings' )" "0"
  out=$( run --drift settings 2>&1 )
  check "settings alone does not mention packages" "$( print -r -- "${out}" | grep -c '^Packages' )" "0"
  out=$( run --drift 2>&1 ); rc=$?
  check "a bare --drift is both, each under a heading" "$( print -r -- "${out}" | grep -c -E '^(Settings|Packages \(brew\))$' )" "2"
  out=$( run --drift all 2>&1 )
  check "--drift all is the same" "$( print -r -- "${out}" | grep -c -E '^(Settings|Packages \(brew\))$' )" "2"
  check "-G is the short form, and a switch after it is still a switch" "$( run -G -v 2>&1 | grep -c -E '^(Settings|Packages)' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  out=$( run --drift nonsense 2>&1 ); rc=$?
  check "anything else is an error that says what is allowed" "${rc}:$( print -r -- "${out}" | grep -c 'settings, packages or all' )" "2:1"
}

test_package_drift_linux () {
  make_linux_stubs
  local row manager osid list lines out rc
  # Everything the apt list names, as dpkg would show it, to test the no-drift case
  for row in 'apt ubuntu ubuntu.apt' 'pacman arch arch.pacman' 'dnf fedora fedora.dnf' 'apk alpine alpine.apk'; do
    set -- ${=row}; manager="$1"; osid="$2"; list="$3"
    new_home
    print -r -- "ID=${osid}" > "${TMP}/os-release"
    printf '%s\n' git my-manual-pkg > "${TMP}/manual.txt"
    printf '%s\n' git curl "my-manual-pkg=1.2" > "${TMP}/apk-world"
    lines=$( grep -c -v -E '^[[:space:]]*(#|$)' "${ROOT}/files/packages/${list}" )
    EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" APK_WORLD_FILE="${TMP}/apk-world" ); : > "${LOG}"
    out=$( run --drift packages 2>&1 ); rc=$?
    EXTRA_ENV=()
    check "${manager}: the heading names the package manager" "$( print -r -- "${out}" | grep -c "^Packages (${manager})$" )" "1"
    check "${manager}: everything in the list but git (the only one installed) is missing" "$( print -r -- "${out}" | grep -c "not installed ($(( lines - 1 )))" )" "1"
    check "${manager}: an explicitly installed package that is not listed is shown" "$( print -r -- "${out}" | grep -c 'my-manual-pkg' )" "1"
    check "${manager}: there is drift" "${rc}" "1"
    check "${manager}: nothing is installed or run with sudo" "$( grep -c -E '^sudo|^(apt|dnf|pacman|apk) (install|add|-S)' "${LOG}" )" "0"
  done
  # Nothing missing: everything the list names is installed
  new_home; print -r -- "ID=ubuntu" > "${TMP}/os-release"; : > "${TMP}/manual.txt"
  stub dpkg "echo \"dpkg \$*\" >> ${LOG}; sed -e '/^[[:space:]]*#/d;/^[[:space:]]*\$/d;s/^/ii  /;s/\$/  1.0 all x/' ${ROOT}/files/packages/ubuntu.apt"
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" )
  out=$( run --drift packages 2>&1 ); rc=$?
  EXTRA_ENV=()
  check "with everything installed there is no drift" "${rc}:$( print -r -- "${out}" | grep -c -i 'everything in your lists is installed' )" "0:1"
}

test_package_drift_unavailable () {
  make_linux_stubs
  new_home; print -r -- "ID=opensuse-leap" > "${TMP}/os-release"
  local out rc
  EXTRA_ENV=( USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" )
  out=$( run --drift packages 2>&1 ); rc=$?
  check "on a distribution with no supported package manager it says so, and is not drift" "${rc}:$( print -r -- "${out}" | grep -c -i "isn't available" )" "2:1"
  print -r -- "ID=ubuntu" > "${TMP}/os-release"; rm -f "${STUBS}/apt-get"
  out=$( run --drift packages 2>&1 ); rc=$?
  check "when the package manager's own tool is not installed it says which" "${rc}:$( print -r -- "${out}" | grep -c 'apt-get' )" "2:1"
  EXTRA_ENV=()
}

# Run tests/package-names.zsh in the sandbox, with the given extra environment

run_names () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${TEST_PATH_PREFIX}${STUBS}:/usr/bin:/bin:/usr/sbin:/sbin" "${TEST_OS_ENV[@]}" "$@" \
    zsh "${ROOT}/tests/package-names.zsh" 2>&1
}

test_package_names () {
  make_linux_stubs
  new_home
  local list="${ROOT}/files/packages/ubuntu.apt" out rc
  grep -v -E '^[[:space:]]*(#|$)' "${list}" > "${TMP}/known.txt"
  # apt-cache show NAME succeeds for the names in known.txt
  stub apt-cache "grep -q -x -F \"\$2\" ${TMP}/known.txt"
  print -r -- "ID=ubuntu" > "${TMP}/os-release"
  out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
  check "when every name is found it says so and succeeds" "${rc}:$( print -r -- "${out}" | grep -c 'all found' )" "0:1"
  check "and it names the list and the package manager it checked with" "$( print -r -- "${out}" | grep -c '^ubuntu.apt (apt)$' )" "1"
  grep -v -x 'ansible' "${TMP}/known.txt" > "${TMP}/known2.txt"; mv "${TMP}/known2.txt" "${TMP}/known.txt"
  out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
  check "a name that is not in the repositories is reported, and fails" "${rc}:$( print -r -- "${out}" | grep -c 'NOT FOUND ansible$' )" "1:1"
  check "with a count" "$( print -r -- "${out}" | grep -c -E '[0-9]+ names checked, 1 not found' )" "1"
  rm -f "${STUBS}/apt-get"
  out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
  check "without the package manager's own tool there is nothing to check with (status 2)" "${rc}:$( print -r -- "${out}" | grep -c 'apt-get is not installed' )" "2:1"
  print -r -- "ID=opensuse-leap" > "${TMP}/os-release"
  out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
  check "and none on a distribution with no supported manager (status 2)" "${rc}:$( print -r -- "${out}" | grep -c 'No supported package manager' )" "2:1"
}

test_package_names_lists () {
  # Each list is checked with its own manager's lookup: a name present only for the right one is found
  make_linux_stubs
  new_home
  local row manager osid list out rc
  for row in 'pacman arch arch.pacman' 'dnf fedora fedora.dnf' 'apk alpine alpine.apk'; do
    set -- ${=row}; manager="$1"; osid="$2"; list="$3"
    print -r -- "ID=${osid}" > "${TMP}/os-release"
    grep -v -E '^[[:space:]]*(#|$)' "${ROOT}/files/packages/${list}" > "${TMP}/known.txt"
    case "${manager}" in
      pacman) stub pacman "[ \"\$1\" = -Si ] && grep -q -x -F \"\$2\" ${TMP}/known.txt" ;;
      dnf)    stub dnf "[ \"\$2\" = repoquery ] && grep -x -F \"\$3\" ${TMP}/known.txt; exit 0" ;;
      apk)    stub apk "[ \"\$1\" = search ] && grep -x -F \"\$3\" ${TMP}/known.txt | sed 's/\$/-1.0-r0/'; exit 0" ;;
    esac
    out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
    check "${manager}: every name in ${list} is found by ${manager}'s own lookup" "${rc}:$( print -r -- "${out}" | grep -c 'all found' )" "0:1"
    grep -v -x 'git' "${TMP}/known.txt" > "${TMP}/known2.txt"; mv "${TMP}/known2.txt" "${TMP}/known.txt"
    out=$( run_names USSURI_OS=linux OS_RELEASE_FILE="${TMP}/os-release" ); rc=$?
    check "${manager}: and one that is not there is reported" "${rc}:$( print -r -- "${out}" | grep -c 'NOT FOUND git$' )" "1:1"
  done
}

test_package_names_brew () {
  new_home
  # A formula, a cask named in the formula list (found through brew's cask fallback), and a name that exists nowhere
  printf '%s\n' a-formula a-cask-in-the-formula-list nowhere-at-all > "${TMP}/formula-names.txt"
  stub brew "case \"\$2\" in --formula) grep -q -x -F \"\$4\" ${TMP}/known-formulae.txt;; --cask) grep -q -x -F \"\$4\" ${TMP}/known-casks.txt;; esac"
  grep -v -E '^[[:space:]]*(#|$)' "${ROOT}/files/packages/macos.brew" > "${TMP}/known-formulae.txt"
  : > "${TMP}/known-casks.txt"
  local out rc
  out=$( run_names USSURI_OS=darwin ); rc=$?
  check "the Homebrew lists are checked too (formulae, then casks)" "${rc}:$( print -r -- "${out}" | grep -c -E '^macos\.(brew|cask) \(brew' )" "0:2"
  grep -v -x 'xquartz' "${TMP}/known-formulae.txt" > "${TMP}/kf2.txt"; mv "${TMP}/kf2.txt" "${TMP}/known-formulae.txt"
  out=$( run_names USSURI_OS=darwin ); rc=$?
  check "a name that is not a formula is reported" "${rc}:$( print -r -- "${out}" | grep -c 'NOT FOUND xquartz$' )" "1:1"
  print -r -- "xquartz" > "${TMP}/known-casks.txt"
  out=$( run_names USSURI_OS=darwin ); rc=$?
  check "unless it is a cask, which brew install falls back to (as in the shipped list)" "${rc}:$( print -r -- "${out}" | grep -c 'all found' )" "0:1"
  make_stubs
}

test_two_line_prompt () {
  new_home
  check "by default the top line is user@host (the context segment), above the line you have" "$( layout_state )" 'left=context newline os_icon dir vcs | right=newline status time | context=${P9K_CONTENT}'
  check "and p10k is told to reload, once" "$( grep -c '^p10k reload$' "${LOG}" )" "1"
  EXTRA_ENV=( PROMPT_TWO_LINE=false )
  check "PROMPT_TWO_LINE=false leaves the layout alone" "$( layout_state )" "left=os_icon dir vcs | right=status time context | context=hidden"
  EXTRA_ENV=( PROMPT_TOP_ELEMENTS="os_icon context" )
  check "any segments can be on the top line, and move up from the bottom one" "$( layout_state )" 'left=os_icon context newline dir vcs | right=newline status time | context=${P9K_CONTENT}'
  EXTRA_ENV=( PROMPT_TOP_ELEMENTS="os_icon" PROMPT_TOP_RIGHT_ELEMENTS="time" )
  check "the top line can have right hand segments too, and context stays hidden if it is not up there" "$( layout_state )" "left=os_icon newline dir vcs | right=time newline status context | context=hidden"
  EXTRA_ENV=( PROMPT_TOP_ELEMENTS="context" PROMPT_TOP_RIGHT_ELEMENTS="status time" )
  check "a segment is on the top line only, never repeated at the bottom" "$( layout_state | grep -o 'right=.*|' )" 'right=status time newline |'
  local cwd="${TMP}/cwd" out
  mkdir -p "${cwd}"
  EXTRA_ENV=( PROMPT_TOP_ELEMENTS='context $(touch EVIL) dir' )
  out=$( cd "${cwd}" && layout_state )
  check "a name that is not a plain segment name is ignored, and the others are used" "${out}" 'left=context dir newline os_icon vcs | right=newline status time | context=${P9K_CONTENT}'
  check "and nothing in it is executed" "$( [[ -e "${cwd}/EVIL" ]] && echo executed || echo safe )" "safe"
  check "with a warning that says which" "$( cd "${cwd}" && env -i HOME="${H}" USER=tester PATH="${STUBS}:/usr/bin:/bin" "${TEST_OS_ENV[@]}" PROMPT_TOP_ELEMENTS='a;b' zsh -c 'src="$1"; shift; source "${src}" 2>&1' zsh "${SCRIPT}" | grep -c "Ignoring 'a;b'" )" "1"
  EXTRA_ENV=()
}

test_two_line_prompt_leaves_other_setups_alone () {
  new_home
  # A p10k config that already has two lines is the user's own: it is not given a third
  cat > "${H}/.p10k.zsh" << 'EOF'
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( dir newline prompt_char )
typeset -g POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=( status )
EOF
  local out
  out=$( env -i HOME="${H}" USER=tester PATH="${STUBS}:/usr/bin:/bin" "${TEST_OS_ENV[@]}" zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1
print -r -- "left=${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}"' zsh "${SCRIPT}" )
  check "a config that is already more than one line is left alone" "${out}" "left=dir newline prompt_char"
  # Another prompt engine: no p10k config is read at all, so nothing is laid out
  EXTRA_ENV=( PROMPT_ENGINE=posh )
  check "with oh-my-posh as the engine there is no p10k layout" "$( layout_state )" "left= | right= | context=hidden"
  EXTRA_ENV=( PROMPT_ENGINE=none )
  check "or with no prompt engine" "$( layout_state )" "left= | right= | context=hidden"
  EXTRA_ENV=()
}

test_two_line_prompt_dryrun () {
  new_home
  cat > "${H}/.p10k.zsh" << 'EOF'
typeset -g POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( os_icon dir vcs )
EOF
  local out
  out=$( env -i HOME="${H}" USER=tester PATH="${STUBS}:/usr/bin:/bin" "${TEST_OS_ENV[@]}" zsh "${SCRIPT}" -T --dryrun --verbose 2>&1 )
  check "--dryrun shows the layout step without doing it" "$( print -r -- "${out}" | grep -c 'Executing: *apply_prompt_top_line' )" "1"
}

test_apply_prompt_top_line_unit () {
  load_function apply_prompt_top_line
  load_function prompt_engine_is
  local reloads=0
  p10k () { reloads=$(( reloads + 1 )) }
  PROMPT_ENGINE=p10k PROMPT_TWO_LINE=true PROMPT_TOP_ELEMENTS="context" PROMPT_TOP_RIGHT_ELEMENTS=""
  POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( os_icon dir vcs )
  POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=( status time )
  apply_prompt_top_line
  check "the left list gets the top elements, a newline, then what was there" "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}" "context newline os_icon dir vcs"
  apply_prompt_top_line
  check "running it again changes nothing (the layout is already more than one line)" "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}:${reloads}" "context newline os_icon dir vcs:1"
  # a p10k that is not loaded yet: the variables are set and nothing is reloaded
  unfunction p10k
  POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=( dir ); POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=( status )
  apply_prompt_top_line 2> /dev/null
  check "without p10k loaded yet it still sets the layout, for p10k to read when it loads" "${POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[*]}" "context newline dir"
  unset POWERLEVEL9K_LEFT_PROMPT_ELEMENTS POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS PROMPT_ENGINE PROMPT_TWO_LINE PROMPT_TOP_ELEMENTS PROMPT_TOP_RIGHT_ELEMENTS
}

test_doctor_prompt_layout () {
  healthy_home
  local out
  out=$( run --doctor 2>&1 )
  check "doctor says the prompt is two lines, and what is on the top one" "$( print -r -- "${out}" | grep -c 'ok.*two line prompt.*top line: context' )" "1"
  EXTRA_ENV=( PROMPT_TWO_LINE=false )
  out=$( run --doctor 2>&1 )
  check "or that it is one" "$( print -r -- "${out}" | grep -c 'ok.*single line prompt' )" "1"
  EXTRA_ENV=()
}

test_init_cache () {
  new_home
  run > /dev/null 2>&1
  : > "${LOG}"
  run > /dev/null 2>&1
  check "second login does not run rbenv" "$( calls 'rbenv' )" "0"
  check "second login does not run pyenv" "$( calls 'pyenv' )" "0"
  local cache
  cache=( "${H}"/.ussuri/cache/*rbenv* )
  check "rehash is left out of the cache" "$( grep -c rehash "${cache[1]}" )" "0"
  EXTRA_ENV=( DO_CACHE_INIT=false ); : > "${LOG}"
  run > /dev/null 2>&1
  EXTRA_ENV=()
  check "DO_CACHE_INIT=false runs the init command" "$( [[ $( calls 'rbenv init' ) -gt 0 ]] && echo yes || echo no )" "yes"
}

test_exp_env () {
  local saved_path=( "${path[@]}" )
  handle_output () { :; }
  load_function exp_env
  PATH="/usr/local/bin:/bin"
  exp_env PATH /usr/bin
  exp_env PATH /bin
  check "PATH adds new entries once" "${PATH}" "/usr/local/bin:/bin:/usr/bin"
  exp_env PATH /opt/new
  exp_env PATH /opt/new
  check "PATH array gets no duplicates" "${path[(I)/opt/new]}" "$(( ${#path} ))"
  LDFLAGS="-L /usr/local/lib"
  exp_env LDFLAGS /usr/lib
  exp_env LDFLAGS /usr/lib
  check "LDFLAGS is matched by whole entry" "${LDFLAGS}" "-L /usr/local/lib -L /usr/lib"
  unset LDFLAGS
  path=( "${saved_path[@]}" )
}

test_linux_id () {
  verbose_message () { :; }
  load_function set_env
  load_function set_linux_id
  local file="${TMP}/os-release" row want
  # os-release ID, ID_LIKE -> expected LSB_ID and PKG_MANAGER
  for row in \
    'ubuntu||Ubuntu:apt' \
    'debian||Debian:apt' \
    'linuxmint|ubuntu debian|Linuxmint:apt' \
    'pop|ubuntu debian|Pop:apt' \
    'arch||Arch:pacman' \
    'endeavouros|arch|EndeavourOS:pacman' \
    'manjaro|arch|Manjaro:pacman' \
    'fedora||Fedora:dnf' \
    'rocky|rhel centos fedora|Rocky:dnf' \
    'alpine||Alpine:apk' \
    'nixos||Nixos:nix' \
    'opensuse-leap|suse opensuse|Opensuse-Leap:' ; do
    print -r -- "ID=\"${row%%|*}\"" > "${file}"
    local like="${${row#*|}%%|*}"
    [[ -n "${like}" ]] && print -r -- "ID_LIKE=\"${like}\"" >> "${file}"
    want="${row##*|}"
    unset OS_RELEASE_FILE PKG_MANAGER LSB_ID
    OS_RELEASE_FILE="${file}"
    set_linux_id
    check "os-release ${row%%|*}${like:+ (like ${like})}" "${LSB_ID}:${PKG_MANAGER}" "${want}"
  done
  unset OS_RELEASE_FILE PKG_MANAGER LSB_ID
  print -r -- 'ID=ubuntu' > "${file}"
  OS_RELEASE_FILE="${file}" PKG_MANAGER="nix"
  set_linux_id
  check "PKG_MANAGER set beforehand is respected" "${PKG_MANAGER}" "nix"
  unset OS_RELEASE_FILE PKG_MANAGER LSB_ID
}

test_packages () {
  new_home
  grep -v -E '^(ansible|autoconf)$' "${ROOT}/files/packages/macos.brew" > "${TMP}/installed.txt"
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  check "dry run proposes exactly the missing packages" "$( run -P --dryrun --verbose 2>&1 | grep -E 'Executing: +brew install' | sed 's/.*install //' | tr '\n' ' ' )" "ansible autoconf "
  : > "${LOG}"
  run -P > /dev/null 2>&1
  check "installs the missing packages" "$( calls 'brew install' )" "2"
  check "no stamp while the installed list is still incomplete" "$( [[ -f "${H}/.ussuri/macos.brew.sum" ]] && echo stamped || echo none )" "none"
  cp "${ROOT}/files/packages/macos.brew" "${TMP}/installed.txt"
  run -P > /dev/null 2>&1
  check "stamp once everything is installed" "$( [[ -f "${H}/.ussuri/macos.brew.sum" ]] && echo stamped || echo none )" "stamped"
  printf 'hashicorp/tap/terraform\n# comment\n\nfoo\n' > "${H}/.ussuri/files/packages/macos.brew"
  printf 'terraform\nfoo\n' > "${H}/.ussuri/brew.list"
  cp "${H}/.ussuri/brew.list" "${TMP}/installed.txt"
  : > "${LOG}"
  run -P > /dev/null 2>&1
  check "tap prefixes, comments and blank lines are handled" "$( calls 'brew install' )" "0"
}

test_sudoers () {
  new_home
  check "sudoers check is off for manual runs" "$( run --dryrun --verbose 2>&1 | grep -c 'Checking:.*sudoers\|Notice.*sudoers' )" "0"
  [[ -x /usr/sbin/visudo ]] || { print "  skip  sudoers install (no visudo)"; return }
  rm -f "${TMP}/sudoers.out"
  run -s > /dev/null 2>&1
  check "entry is validated and installed" "$( cat "${TMP}/sudoers.out" 2> /dev/null )" "$( id -un ) ALL=(ALL) NOPASSWD:ALL"
  check "with mode 0440" "$( stat -c %a "${TMP}/sudoers.out" 2> /dev/null || stat -f %Lp "${TMP}/sudoers.out" )" "440"
  rm -f "${TMP}/sudoers.out"
  run -s -S 'ALL=(ALL NOPASSWD ALL ((' > /dev/null 2>&1
  check "a malformed entry is rejected before install" "$( [[ -e "${TMP}/sudoers.out" ]] && echo installed || echo rejected )" "rejected"
}

test_updater () {
  new_home
  local live="${TMP}/live" remote="${TMP}/remote"
  mkdir -p "${live}" "${remote}"
  cp "${SCRIPT}" "${live}/ussuri.zsh"
  sed 's/^# Version: .*/# Version: 9.9.9/' "${SCRIPT}" > "${remote}/ussuri.zsh"
  print -r -- "Current Version: 9.9.9" > "${remote}/README.md"
  local out
  out=$( EXTRA_ENV=( README_URL="file://${remote}/README.md" ); SCRIPT="${live}/ussuri.zsh"; run -C 2>&1 )
  check "-C reports a newer remote" "$( print -r -- "${out}" | grep -c 'Remote version: 9.9.9' )" "1"
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" UPDATE_URL="file://${remote}/no-archive.tgz" ); SCRIPT="${live}/ussuri.zsh"; run -U --dryrun > /dev/null 2>&1 )
  check "-U --dryrun does not replace the script" "$( grep -m1 '^# Version:' "${live}/ussuri.zsh" | awk '{print $3}' )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" UPDATE_URL="file://${remote}/no-archive.tgz" ); SCRIPT="${live}/ussuri.zsh"; run -U > /dev/null 2>&1 )
  check "-U replaces it" "$( grep -m1 '^# Version:' "${live}/ussuri.zsh" | awk '{print $3}' )" "9.9.9"
  check "and keeps a backup" "$( nfiles "${H}/.ussuri/ussuri.zsh.*" )" "1"
  cp "${SCRIPT}" "${live}/ussuri.zsh"
  { sed 's/^# Version: .*/# Version: 9.9.9/' "${SCRIPT}"; print 'if [ then'; } > "${remote}/ussuri.zsh"
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" UPDATE_URL="file://${remote}/no-archive.tgz" ); SCRIPT="${live}/ussuri.zsh"; run -U > /dev/null 2>&1 )
  check "a download that does not parse is refused" "$( grep -m1 '^# Version:' "${live}/ussuri.zsh" | awk '{print $3}' )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
}

test_rbenv_pyenv () {
  new_home
  mkdir -p "${H}/.rbenv/versions/3.4.2" "${H}/.pyenv/versions/3.13.1"
  local out
  out=$( cd "${H}" && EXTRA_ENV=( RUBY_VER=3.4.2 PYTHON_VER=3.13.1 ); run -r -p --dryrun --verbose 2>&1 | grep -E 'Executing: +(rbenv|pyenv) (install|global|local)' )
  check "installed versions are set global, never local" "$( print -r -- "${out}" | sed 's/Executing: *//' | sort | tr '\n' ',' )" "pyenv global 3.13.1,rbenv global 3.4.2,"
  check "nothing is written to the working directory" "$( ls -a "${H}" | grep -c -E 'ruby-version|python-version' )" "0"
}

test_confirm () {
  command -v python3 > /dev/null 2>&1 || { print "  skip  confirm (no python3)"; return }
  new_home
  local out
  out=$( run_on_tty n --defaults --confirm 2>&1 )
  check "answering n on a terminal runs nothing" "$( calls 'defaults write' )" "0"
  check "the prompt shows the command even without --verbose" "$( print -r -- "${out}" | grep -c 'Execute: defaults write' | awk '{print ($1 > 0) ? "yes" : "no"}' )" "yes"
  rm -rf "${H}/.ussuri/defaults.stamp"; : > "${LOG}"
  run_on_tty y --defaults --confirm > /dev/null 2>&1
  check "answering y runs it" "$( [[ $( calls 'defaults write' ) -gt 100 ]] && echo yes || echo no )" "yes"
  : > "${LOG}"
  run_limited --defaults --confirm < /dev/null > /dev/null 2>&1
  check "with no terminal it neither hangs nor runs anything" "$( calls 'defaults write' )" "0"
}

# Run

make_stubs
FILTER="$1"
for name in ${(ok)functions[(I)test_*]}; do
  [[ -n "${FILTER}" && "${name}" != *"${FILTER}"* ]] && continue
  remove_linux_stubs
  print -r -- "${name#test_}"
  ${name}
done
print
print -r -- "${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
