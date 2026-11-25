#!/usr/bin/env zsh
#
# Check that the version number follows the numbering standard in CLAUDE.md: X.Y.Z where each of X, Y and Z is a
# single digit 0-9 (after 1.0.9 comes 1.1.0, not 1.0.10), because check_for_update compares versions by stripping
# the dots and comparing the result as an integer. Also checks that the same version is in the script header, in
# README.md (Current Version) and as the newest CHANGELOG.md entry, that the entries are all valid and newest first,
# that each date is YYYY-MM-DD, and that the newest entry has at least one section. Offline, so tests/smoke.zsh runs it.
#
# Usage: zsh tests/version.zsh [-v]
# Exit status: 0 if every check passes, 1 if not

ROOT="${0:A:h:h}"
VERBOSE=0
[[ "$1" == "-v" ]] && VERBOSE=1
FAIL=0
PASS=0

# CHANGELOG entries that broke the rule before it was checked. Do not add to this list: fix the number of a new release instead
LEGACY_VERSIONS=( 1.0.10 1.0.11 1.0.12 )

fail () {
  print -r -- "FAIL  $*"
  FAIL=$(( FAIL + 1 ))
}

pass () {
  PASS=$(( PASS + 1 ))
  (( VERBOSE )) && print -r -- "ok    $*"
  return 0
}

# A version is valid when it is X.Y.Z with each part a single digit
valid_version () {
  [[ "$1" =~ '^[0-9]\.[0-9]\.[0-9]$' ]]
}

# The number that check_for_update compares: the dots removed
version_number () {
  print -r -- "${1//./}"
}

# Self-check: the rule itself is right, so the checks below mean something
for v in 0.0.0 1.0.9 1.1.0 9.9.9; do
  valid_version "${v}" && pass "self-check accepts ${v}" || fail "self-check: ${v} should be valid"
done
for v in 1.0.10 1.10.0 10.0.0 1.0 1.0.0.0 v1.0.0 1.0.0-rc1 ""; do
  valid_version "${v}" && fail "self-check: ${v} should be invalid" || pass "self-check rejects '${v}'"
done
(( $(version_number 1.0.9) < $(version_number 1.1.0) )) && pass "1.0.9 orders before 1.1.0" || fail "self-check: 1.0.9 should order before 1.1.0"

# The script header
header=$( awk '/^# Version: /{ print $3; exit }' "${ROOT}/ussuri.zsh" )
if [[ -z "${header}" ]]; then
  fail "ussuri.zsh has no '# Version:' header"
  print
  print -r -- "${PASS} passed, ${FAIL} failed"
  exit 1
fi
valid_version "${header}" && pass "ussuri.zsh header ${header} is X.Y.Z, single digits" || fail "ussuri.zsh header ${header} breaks the numbering standard (each part one digit 0-9)"

# README.md
readme=$( grep -m1 '^Current Version: ' "${ROOT}/README.md" | sed 's/^Current Version: //' )
if [[ "${readme}" == "${header}" ]]; then
  pass "README.md Current Version matches ${header}"
else
  fail "README.md Current Version is '${readme}', the script header is ${header}"
fi

# CHANGELOG.md: every version heading, newest first, each valid and dated
typeset -a heads
heads=( ${(f)"$( grep -E '^## \[' "${ROOT}/CHANGELOG.md" )"} )
if (( ${#heads} == 0 )); then
  fail "CHANGELOG.md has no version headings"
fi

prev=""
newest=""
for h in "${heads[@]}"; do
  if [[ "${h}" =~ '^## \[([^]]+)\] - ([0-9][0-9][0-9][0-9])-([0-9][0-9])-([0-9][0-9])$' ]]; then
    v="${match[1]}"
    if [[ "${v}" == "Unreleased" ]]; then
      continue
    fi
    # 1.0.10 to 1.0.12 were released with a two-digit part, which the rule now forbids. They are not renumbered,
    # as that would change the release record. The checks below skip them (their dates are still checked).
    if (( ${LEGACY_VERSIONS[(Ie)${v}]} )); then
      pass "CHANGELOG.md entry [${v}] predates the rule and is exempt"
      continue
    fi
    if ! valid_version "${v}"; then
      fail "CHANGELOG.md entry [${v}] breaks the numbering standard (each part one digit 0-9)"
      continue
    fi
    if (( ${match[3]} < 1 || ${match[3]} > 12 || ${match[4]} < 1 || ${match[4]} > 31 )); then
      fail "CHANGELOG.md entry [${v}] has an impossible date ${match[2]}-${match[3]}-${match[4]}"
    fi
    if [[ -n "${prev}" ]] && (( $(version_number "${v}") >= $(version_number "${prev}") )); then
      fail "CHANGELOG.md entry [${v}] is not older than [${prev}]: entries must be newest first"
    fi
    [[ -z "${newest}" ]] && newest="${v}"
    prev="${v}"
  else
    fail "CHANGELOG.md heading is not '## [X.Y.Z] - YYYY-MM-DD': ${h}"
  fi
done

if [[ -n "${newest}" ]]; then
  [[ "${newest}" == "${header}" ]] && pass "newest CHANGELOG.md entry is ${header}" || fail "newest CHANGELOG.md entry is [${newest}], the script header is ${header}"
  # The newest entry has at least one section (### Added, ### Changed, ...)
  sections=$( awk -v want="## [${newest}]" '
      index($0, want) == 1 { inside = 1; next }
      /^## \[/ && inside { exit }
      inside && /^### / { n++ }
      END { print n + 0 }' "${ROOT}/CHANGELOG.md" )
  (( sections > 0 )) && pass "the ${newest} entry has ${sections} section(s)" || fail "the ${newest} entry has no ### section"
fi

print
print -r -- "${PASS} passed, ${FAIL} failed"
(( FAIL == 0 ))
