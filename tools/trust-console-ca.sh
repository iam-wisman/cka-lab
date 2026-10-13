#!/bin/bash
# Trust the Kubernetes Playgrounds console CA on this machine, so https://<jump>/
# opens without a certificate warning. Run it yourself: it changes your trust store.
#
#   tools/trust-console-ca.sh [path/to/console-ca.crt]     (sudo is asked for)
#   tools/trust-console-ca.sh --remove
#
# The CA is made by infra/install-lab.sh and can only vouch for private addresses and
# *.cka.lab (X.509 name constraints), so trusting it doesn't let it impersonate real sites.
set -euo pipefail
CRT=${1:-$HOME/.local/share/cka-lab/console-ca.crt}
NAME=kubernetes-playgrounds-ca
remove=0; [[ ${1:-} == --remove ]] && { remove=1; CRT=$HOME/.local/share/cka-lab/console-ca.crt; }
[[ $remove == 1 || -f $CRT ]] || { echo "no CA at $CRT (run infra/install-lab.sh first)" >&2; exit 1; }
if (( ! remove )); then
  openssl x509 -in "$CRT" -noout -ext nameConstraints | grep -q 'Permitted' || { echo "refusing: $CRT has no name constraints" >&2; exit 1; }
  echo "Trusting: $(openssl x509 -in "$CRT" -noout -subject)"
  echo "SHA-256:  $(openssl x509 -in "$CRT" -noout -fingerprint -sha256 | cut -d= -f2)"
fi

case $(uname -s) in
  Darwin)
    if (( remove )); then sudo security delete-certificate -c "Kubernetes Playgrounds local CA" /Library/Keychains/System.keychain
    else sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CRT"; fi ;;
  Linux)
    if command -v trust >/dev/null && [[ -d /etc/ca-certificates/trust-source ]]; then     # Arch, Fedora (p11-kit)
      if (( remove )); then sudo rm -f "/etc/ca-certificates/trust-source/anchors/$NAME.crt"; sudo trust extract-compat
      else sudo install -m 644 "$CRT" "/etc/ca-certificates/trust-source/anchors/$NAME.crt"; sudo trust extract-compat; fi
    elif [[ -d /usr/local/share/ca-certificates ]]; then                                  # Debian, Ubuntu
      if (( remove )); then sudo rm -f "/usr/local/share/ca-certificates/$NAME.crt"
      else sudo install -m 644 "$CRT" "/usr/local/share/ca-certificates/$NAME.crt"; fi
      sudo update-ca-certificates --fresh >/dev/null
    else
      echo "unknown Linux trust store; add $CRT to it by hand" >&2
    fi
    # Chrome and Firefox on Linux use their own NSS database for added roots.
    if command -v certutil >/dev/null; then
      for db in "$HOME/.pki/nssdb" "$HOME"/.mozilla/firefox/*.default*; do
        [[ -d $db ]] || continue
        certutil -d "sql:$db" -D -n "$NAME" 2>/dev/null || true
        (( remove )) || certutil -d "sql:$db" -A -t "C,," -n "$NAME" -i "$CRT"
      done
    else
      echo "note: install nss tools (certutil) so Chrome/Firefox pick it up, or import $CRT in their settings"
    fi ;;
  *) echo "unsupported OS; import $CRT as a trusted root by hand" >&2; exit 1 ;;
esac
(( remove )) && echo "Removed." || echo "Done. Restart the browser, then open https://<jump-ip>/."
