# Grading helpers for labs/*/check.sh. Sourced after common.sh.
#
#   check "description" <command...>          pass when the command succeeds
#   check_eq "description" <expected> <command...>
#                                              pass when its trimmed stdout == expected
#   check_match "description" <regex> <command...>
#                                              pass when stdout matches the ERE
#   need_cluster                               fetch admin credentials; if the API is
#                                              unreachable every later kc() check fails
#   section "heading"                          group the output
#   finish                                     print the score, save it, exit 0 only on 100%
#
# Checks never abort the script: a grader always reports every requirement.

GRADE_ID=${GRADE_ID:-unknown}
GRADE_PASS=0
GRADE_TOTAL=0
GRADE_FAILED=()
GRADE_QUIET=${GRADE_QUIET:-0}
GRADE_SECTION=""
GRADE_CHECKS=()   # one JSON object per check, for the web console

_say() { (( GRADE_QUIET )) || echo "$@"; }

section() { GRADE_SECTION=$*; _say; _say "${c_bold}$*${c_off}"; }

_record() {
  local ok=$1 desc=$2 detail=${3:-}
  GRADE_TOTAL=$((GRADE_TOTAL + 1))
  GRADE_CHECKS+=("$(jq -nc --arg s "$GRADE_SECTION" --arg d "$desc" --arg x "$detail" --argjson ok "$ok" \
    '{section:$s, desc:$d, ok:($ok == 1), detail:$x}')")
  if (( ok )); then
    GRADE_PASS=$((GRADE_PASS + 1))
    _say "  ${c_green}PASS${c_off} $desc"
  else
    GRADE_FAILED+=("$desc")
    _say "  ${c_red}FAIL${c_off} $desc"
    [[ -n $detail ]] && _say "       ${c_dim}${detail}${c_off}"
  fi
  return 0
}

check() {
  local desc=$1; shift
  if "$@" >/dev/null 2>&1; then _record 1 "$desc"; else _record 0 "$desc"; fi
}

check_eq() {
  local desc=$1 want=$2 got; shift 2
  got=$("$@" 2>/dev/null | sed -e 's/[[:space:]]*$//' -e '/^$/d')
  if [[ $got == "$want" ]]; then _record 1 "$desc"
  else _record 0 "$desc" "expected '${want}', found '${got:-<nothing>}'"; fi
}

check_match() {
  local desc=$1 re=$2 got; shift 2
  got=$("$@" 2>/dev/null)
  if [[ $got =~ $re ]]; then _record 1 "$desc"
  else _record 0 "$desc" "expected match /${re}/, found '$(head -c 160 <<<"${got:-<nothing>}" | tr '\n' ' ')'"; fi
}

need_cluster() {
  if ! grader_kubeconfig; then
    _say "  ${c_yellow}note${c_off} no API server answered; cluster checks will fail"
    GRADER_KUBECONFIG=/dev/null
  fi
}

finish() {
  local pct=0 dir=$LAB_STATE/results
  (( GRADE_TOTAL )) && pct=$(( GRADE_PASS * 100 / GRADE_TOTAL ))
  mkdir -p "$dir"
  printf '%s\n' "${GRADE_CHECKS[@]}" | jq -s --arg id "$GRADE_ID" --argjson pass "$GRADE_PASS" \
    --argjson total "$GRADE_TOTAL" --arg at "$(date -u +%FT%TZ)" \
    '{id:$id, pass:$pass, total:$total, at:$at, failed:[.[] | select(.ok | not) | .desc], checks:.}' \
    >"$dir/$GRADE_ID.json"
  jq -c '{id, pass, total, at}' "$dir/$GRADE_ID.json" >>"$LAB_STATE/history.jsonl"
  _say
  if (( GRADE_PASS == GRADE_TOTAL )); then
    _say "${c_green}${c_bold}$GRADE_ID: $GRADE_PASS/$GRADE_TOTAL checks passed (100%)${c_off}"
    exit 0
  fi
  _say "${c_yellow}${c_bold}$GRADE_ID: $GRADE_PASS/$GRADE_TOTAL checks passed (${pct}%)${c_off}"
  exit 1
}
