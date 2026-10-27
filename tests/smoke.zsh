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
  stub defaults "echo \"defaults \$*\" >> ${LOG}; [ \"\$1\" = write ] && exit 0; exit 1"
  stub chflags  "echo \"chflags \$*\" >> ${LOG}"
  stub killall  "echo \"killall \$*\" >> ${LOG}"
  stub brew     "echo \"brew \$*\" >> ${LOG}; [ \"\$1\" = list ] && cat ${TMP}/installed.txt; [ \"\$1\" = shellenv ] && echo 'export HOMEBREW_PREFIX=/stub'; exit 0"
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
  cp "${TMP}/installed.txt" "${H}/.ussuri/brew.list"
  : > "${LOG}"
}

# Run the script in the sandbox. PATH deliberately leaves out /opt/homebrew

run () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${EXTRA_ENV[@]}" zsh "${SCRIPT}" "$@"
}

# Run with a time limit (for anything that could hang)

run_limited () {
  env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${EXTRA_ENV[@]}" perl -e 'alarm 15; exec @ARGV' zsh "${SCRIPT}" "$@"
}

# Pull a function out of the script so it can be tested on its own

load_function () {
  eval "$( sed -n "/^$1 () {/,/^}/p" "${SRC}" )"
}

# Run the script on a pseudo terminal, answering every y/n prompt with the given answer

run_on_tty () {
  local answer="$1"
  shift
  python3 - "${answer}" env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm \
    PATH="${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
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
    PATH="${STUBS}:${H}/.rbenv/bin:${H}/.pyenv/bin:/usr/bin:/bin:/usr/sbin:/sbin" \
    "${EXTRA_ENV[@]}" zsh -c 'src="$1"; shift; source "${src}" > /dev/null 2>&1
print -r -- "size=${HISTSIZE} save=${SAVEHIST} file=${HISTFILE} dups=${options[histignoredups]} space=${options[histignorespace]} find=${options[histfindnodups]} blanks=${options[histreducebLanks]:-${options[histreduceblanks]}} share=${options[sharehistory]}"' zsh "${SCRIPT}"
}

# Tests

test_syntax () {
  zsh -n "${SRC}" && ok "script parses" || bad "script parses"
  check "stub brew is what runs, not the real one" "$( env -i PATH="${STUBS}:/usr/bin:/bin" sh -c 'command -v brew' )" "${STUBS}/brew"
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
  out=$( run --drift 2>&1 ); rc=$?
  after=$( cd "${H}" && find . | sort | md5 2> /dev/null || find . | sort | md5sum )
  check "with nothing applied every setting is reported" "$( print -r -- "${out}" | grep -c -E '^ +[A-Za-z].* -> ' )" "${total}"
  check "the summary says how many differ, out of how many were checked" "$( print -r -- "${out}" | grep -c -E "^${total} of [0-9]+ settings differ" )" "1"
  check "and the exit status says there is drift" "${rc}" "1"
  check "--drift writes nothing" "$( calls 'defaults write' )" "0"
  check "and changes nothing in the home directory" "${after}" "${before}"
  use_stateful_defaults
  new_home; : > "${LOG}"
  run --defaults > /dev/null 2>&1
  out=$( run --drift 2>&1 ); rc=$?
  check "after applying the defaults there is no drift" "${rc}" "0"
  check "and it says so" "$( print -r -- "${out}" | grep -c 'match' )" "1"
  # Change one value, remove another and flip a boolean behind its back
  grep -v '^com.apple.dock|autohide-delay|' "${DEFAULTS_DB}" > "${DEFAULTS_DB}.new"; mv "${DEFAULTS_DB}.new" "${DEFAULTS_DB}"
  sed -i.bak 's/^com.apple.dock|tilesize|.*/com.apple.dock|tilesize|48/; s/^com.apple.finder|ShowPathbar|.*/com.apple.finder|ShowPathbar|0/' "${DEFAULTS_DB}"
  out=$( run --drift 2>&1 ); rc=$?
  check "exactly the three changed settings are reported" "$( print -r -- "${out}" | grep -c -E '^ +[A-Za-z].* -> ' )" "3"
  check "a changed value shows what it is and what it should be" "$( print -r -- "${out}" | grep -c -E 'tilesize +48 -> 32' )" "1"
  check "a missing one says it is not set" "$( print -r -- "${out}" | grep -c -E 'autohide-delay +\(not set\) -> 0.2' )" "1"
  check "a boolean is shown as true/false, not 1/0" "$( print -r -- "${out}" | grep -c -E 'ShowPathbar +false -> true' )" "1"
  check "settings are grouped under their domain" "$( print -r -- "${out}" | grep -c -E '^com\.apple\.(dock|finder)$' )" "2"
  check "the exit status is 1" "${rc}" "1"
  out=$( run --drift 2>&1 )
  check "it points at the way to fix it" "$( print -r -- "${out}" | grep -c -- '--defaults' )" "1"
  : > "${LOG}"
  run --drift > /dev/null 2>&1
  check "drift never writes, even when there is some" "$( calls 'defaults write' )" "0"
  check "and --defaults then fixes exactly those" "$( run --defaults > /dev/null 2>&1; run --drift > /dev/null 2>&1; echo $? )" "0"
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
  out=$( run --drift 2>&1 ); rc=$?
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
  out=$( run --drift 2>&1 ); rc=$?
  check "drift reports the two changed settings" "$( print -r -- "${out}" | grep -c -E '^ +[a-z-]+ +.* -> ' )" "2"
  check "showing actual and expected" "$( print -r -- "${out}" | grep -c -E 'repeat-interval +uint32 99 -> uint32 30' )" "1"
  check "grouped under their schema" "$( print -r -- "${out}" | grep -c -E '^org\.gnome\.desktop\.peripherals\.keyboard$' )" "1"
  check "with exit status 1" "${rc}" "1"
  check "and it writes nothing" "$( calls 'gsettings set' )" "0"
  # Not a GNOME session
  EXTRA_ENV=( USSURI_OS=linux )
  out=$( run --drift 2>&1 ); rc=$?
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
  out=$( run --drift 2>&1 )
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
  check "no stamp while the installed list is still incomplete" "$( nfiles "${H}/.ussuri/*.sum" )" "0"
  cp "${ROOT}/files/packages/macos.brew" "${TMP}/installed.txt"
  run -P > /dev/null 2>&1
  check "stamp once everything is installed" "$( nfiles "${H}/.ussuri/*.sum" )" "1"
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
  check "with mode 0440" "$( stat -f %Lp "${TMP}/sudoers.out" 2> /dev/null || stat -c %a "${TMP}/sudoers.out" )" "440"
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
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" ); SCRIPT="${live}/ussuri.zsh"; run -U --dryrun > /dev/null 2>&1 )
  check "-U --dryrun does not replace the script" "$( grep -m1 '^# Version:' "${live}/ussuri.zsh" | awk '{print $3}' )" "$( grep -m1 '^# Version:' "${SRC}" | awk '{print $3}' )"
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" ); SCRIPT="${live}/ussuri.zsh"; run -U > /dev/null 2>&1 )
  check "-U replaces it" "$( grep -m1 '^# Version:' "${live}/ussuri.zsh" | awk '{print $3}' )" "9.9.9"
  check "and keeps a backup" "$( nfiles "${H}/.ussuri/ussuri.zsh.*" )" "1"
  cp "${SCRIPT}" "${live}/ussuri.zsh"
  { sed 's/^# Version: .*/# Version: 9.9.9/' "${SCRIPT}"; print 'if [ then'; } > "${remote}/ussuri.zsh"
  ( EXTRA_ENV=( SCRIPT_URL="file://${remote}/ussuri.zsh" ); SCRIPT="${live}/ussuri.zsh"; run -U > /dev/null 2>&1 )
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
  print -r -- "${name#test_}"
  ${name}
done
print
print -r -- "${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
