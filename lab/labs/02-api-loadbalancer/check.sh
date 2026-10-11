#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"

CFG=/etc/haproxy/haproxy.cfg

# Effective config with comments stripped, for the structural checks.
cfg() { sed -e 's/#.*//' -e '/^\s*$/d' "$CFG" 2>/dev/null; }

# Largest timeout <kind> anywhere in the config, in seconds (HAProxy units: ms default, s, m, h, d).
timeout_secs() {
  cfg | awk -v k="$1" '$1=="timeout" && $2==k {
    v=$3; n=v+0; u=v; sub(/^[0-9]+/, "", u)
    s = (u=="" || u=="ms") ? n/1000 : (u=="s") ? n : (u=="m") ? n*60 : (u=="h") ? n*3600 : (u=="d") ? n*86400 : 0
    if (s > max) max = s
  } END { printf "%d", max }'
}

section "service"
check "haproxy installed from the Ubuntu archive" bash -c "dpkg-query -W -f='\${Status}' haproxy | grep -q 'install ok installed'"
check "haproxy enabled" systemctl is-enabled -q haproxy
check "haproxy active" systemctl is-active -q haproxy
check "haproxy -c reports no warnings or alerts" bash -c "out=\$(sudo haproxy -c -f $CFG 2>&1) && ! grep -Eqi '\[(WARNING|ALERT)\]' <<<\"\$out\""

section "frontend"
check "listening on 10.10.10.10:6443" bash -c "ss -Hltn 'sport = :6443' | awk '{print \$4}' | grep -qx '10.10.10.10:6443'"
check "not listening on 0.0.0.0, [::] or the LAN address for 6443" bash -c \
  "ss -Hltn 'sport = :6443' | grep -q . && ! ss -Hltn 'sport = :6443' | awk '{print \$4}' | grep -vqx '10.10.10.10:6443'"
check "TCP mode (TLS passed through)" bash -c "sed 's/#.*//' $CFG | grep -Eq '^\s*mode\s+tcp'"
check "no TLS termination (no 'ssl crt' on a bind line)" bash -c "test -s $CFG && ! grep -E '^\s*bind\b.*\bssl\b' $CFG"

section "backend"
for i in 1 2 3; do
  check "server cp$i -> 10.10.10.1$i:6443" bash -c "sed 's/#.*//' $CFG | grep -Eq '^\s*server\s+cp$i\s+10\.10\.10\.1$i:6443(\s|$)'"
done
check "round-robin balancing" bash -c "sed 's/#.*//' $CFG | grep -Eq '^\s*balance\s+roundrobin'"
check "HTTP health check: GET /readyz" bash -c "sed 's/#.*//' $CFG | grep -Eq '(option\s+httpchk\s+(GET\s+)?/readyz|http-check\s+send\s+meth\s+GET\s+uri\s+/readyz)'"
check "health check expects status 200" bash -c "sed 's/#.*//' $CFG | grep -Eq 'http-check\s+expect\s+status\s+200'"
check "health checks over TLS without verification (check-ssl, verify none)" bash -c \
  "sed 's/#.*//' $CFG | grep -E '^\s*(server|default-server)\b' | grep -w check-ssl | grep -Eq 'verify\s+none'"
check "inter 3s fall 3 rise 2" bash -c "sed 's/#.*//' $CFG | grep -E '^\s*(server|default-server)\b' | grep -Eq 'inter\s+3(s|000)?\b' && sed 's/#.*//' $CFG | grep -E '^\s*(server|default-server)\b' | grep -Eq 'fall\s+3\b' && sed 's/#.*//' $CFG | grep -E '^\s*(server|default-server)\b' | grep -Eq 'rise\s+2\b'"

section "timeouts"
check "timeout client >= 1h" test "$(timeout_secs client)" -ge 3600
check "timeout server >= 1h" test "$(timeout_secs server)" -ge 3600

section "stats"
check "stats CSV at http://10.10.10.10:8404/stats;csv" bash -c "curl -sf --max-time 5 'http://10.10.10.10:8404/stats;csv' | grep -q '^# pxname'"
check "stats lists cp1, cp2 and cp3 in the API backend" bash -c \
  "curl -sf --max-time 5 'http://10.10.10.10:8404/stats;csv' | awk -F, '\$2 ~ /^cp[123]\$/ {print \$2}' | sort -u | paste -sd, | grep -qx 'cp1,cp2,cp3'"
check "stats page served on 10.10.10.10:8404 only" bash -c "ss -Hltn 'sport = :8404' | grep -q . && ! ss -Hltn 'sport = :8404' | awk '{print \$4}' | grep -vqx '10.10.10.10:8404'"

finish
