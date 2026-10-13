#!/bin/bash
# Check that every documentation link in tools/references.py resolves (HTTP 200).
cd "$(dirname "$0")" || exit 1
check() { c=$(curl -sL -o /dev/null -w '%{http_code}' --max-time 20 -A 'Mozilla/5.0 (cka-lab link check)' "$1"); [ "$c" = 200 ] && echo ok || echo "BROKEN $c $1"; }
export -f check
python3 -c 'import references; print("\n".join(sorted({u.split("#")[0] for r in references.REFS.values() for _, u in r})))' |
  xargs -P 8 -I{} bash -c 'check "$@"' _ {} | sort | uniq -c | tee /dev/stderr | grep -q BROKEN && exit 1
exit 0
