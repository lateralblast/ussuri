#!/usr/bin/env zsh
#
# Make an export bundle (what --export writes) from a scratch home holding a few settings, so the same bundle can be
# made on any system. CI makes one on the Ubuntu runner (GNU tar) and imports it on macOS (test_import_linux_bundle).
# Nothing here touches your home: the scratch home is removed when it finishes.
#
# Usage: zsh tests/make-bundle.zsh OUTFILE

ROOT="${0:A:h:h}"
OUT="${1:?usage: zsh tests/make-bundle.zsh OUTFILE}"
H=$( mktemp -d ) || exit 1

mkdir -p "${H}/.zinit" "${H}/.ussuri/files" "${H}/.ussuri/profiles/work" "${H}/.ussuri/hosts/box" "${H}/.ussuri/files/packages"
cp -R "${ROOT}/files/"* "${H}/.ussuri/files/"
cp "${ROOT}/files/p10k/p10k.zsh" "${H}/.p10k.zsh"
print -r -- "PROMPT_TOP_ELEMENTS='context'" > "${H}/.ussuri/config"
print -r -- "DO_VERBOSE=false" > "${H}/.ussuri/profiles/work/local.config"
print -r -- "MACHINE_VAR=1" > "${H}/.ussuri/hosts/box/local.config"
print -r -- "my own package" > "${H}/.ussuri/files/packages/local.brew"
print -r -- "my own plugin" > "${H}/.ussuri/files/zinit/local.zsh"

env -i HOME="${H}" USER=tester LOGNAME=tester TERM=xterm PATH="${PATH}" zsh "${ROOT}/ussuri.zsh" --export "${OUT}"
rc=$?
rm -rf "${H}"
exit ${rc}
