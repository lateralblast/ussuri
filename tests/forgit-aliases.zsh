#!/usr/bin/env zsh
#
# Check that the forgit aliases renamed in files/zinit/*.zsh are exactly the ones that clash with
# the Oh My Zsh git snippet. Needs the network (it reads both from GitHub), so it is not part of
# tests/smoke.zsh: run it now and then, or when forgit or the git snippet is updated.
#
# Usage: zsh tests/forgit-aliases.zsh
# Exit status: 0 if the renames are exactly right, 1 if not, 2 if the upstream files can't be read

ROOT="${0:A:h:h}"
FORGIT_URL="https://raw.githubusercontent.com/wfxr/forgit/master/forgit.plugin.zsh"
OMZ_URL="https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/plugins/git/git.plugin.zsh"

forgit_src=$( curl -fsSL -m 30 "${FORGIT_URL}" ) || { print "Could not read ${FORGIT_URL}"; exit 2 }
omz_src=$( curl -fsSL -m 30 "${OMZ_URL}" ) || { print "Could not read ${OMZ_URL}"; exit 2 }

# forgit: default alias name for each variable, from lines like  forgit_add="${forgit_add:-ga}"
typeset -A forgit_alias
local line var name
for line in ${(f)forgit_src}; do
  if [[ "${line}" =~ 'forgit_([a-z_]+)=.*:-([a-zA-Z]+)' ]]; then
    forgit_alias[${match[1]}]="${match[2]}"
  fi
done

# Oh My Zsh git: every alias name
typeset -A omz_alias
for line in ${(f)omz_src}; do
  if [[ "${line}" =~ '^alias ([^=]+)=' ]]; then
    omz_alias[${match[1]}]=1
  fi
done

# What the lists rename: forgit_<var>=<new name>
local list expected actual result=0
for list in zinit.zsh zinit-turbo.zsh; do
  typeset -A renamed
  renamed=()
  for line in ${(f)"$( grep -E '^export forgit_' "${ROOT}/files/zinit/${list}" )"}; do
    for pair in ${=line#export }; do
      renamed[${${pair%%=*}#forgit_}]="${pair#*=}"
    done
  done
  expected=()
  for var name in ${(kv)forgit_alias}; do
    (( ${+omz_alias[${name}]} )) && expected+=( "${var}" )
  done
  actual=( ${(k)renamed} )
  print -r -- "${list}: forgit has ${#forgit_alias} aliases, ${#expected} clash with the git snippet, ${#actual} are renamed"
  local missing=( ${expected:|actual} ) extra=( ${actual:|expected} )
  if (( ${#missing} )); then
    print -r -- "  NOT renamed but they clash: ${(j: :)${(o)missing}} (add forgit_<name>=fg<alias> to the list)"
    result=1
  fi
  if (( ${#extra} )); then
    print -r -- "  renamed but they no longer clash: ${(j: :)${(o)extra}}"
    result=1
  fi
  # A new name must not itself clash with a git snippet alias
  for var name in ${(kv)renamed}; do
    if (( ${+omz_alias[${name}]} )); then
      print -r -- "  the new name ${name} (for forgit_${var}) clashes with a git snippet alias"
      result=1
    fi
  done
done
(( result == 0 )) && print "OK: the renames are exactly the aliases that clash"
exit ${result}
