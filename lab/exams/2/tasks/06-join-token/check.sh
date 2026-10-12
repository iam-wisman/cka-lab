#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
tok=$(grep -o -- '--token [a-z0-9.]*' "$HOME/exam2/join.txt" 2>/dev/null | awk '{print $2}')
tokid=${tok%%.*}
check "join.txt targets k8s-api.cka.lab:6443 with token and CA hash" grep -Eq '^kubeadm join k8s-api\.cka\.lab:6443 .*--token [a-z0-9]{6}\.[a-z0-9]{16} .*--discovery-token-ca-cert-hash sha256:[0-9a-f]{64}' "$HOME/exam2/join.txt"
check "token exists with description 'exam2 worker'" bash -c "[[ \$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get secret bootstrap-token-$tokid -o jsonpath='{.data.description}' | base64 -d) == 'exam2 worker' ]]"
check "token TTL about 2h" bash -c "exp=\$($GRADER_KUBECTL --kubeconfig $GRADER_KUBECONFIG -n kube-system get secret bootstrap-token-$tokid -o jsonpath='{.data.expiration}' | base64 -d); left=\$(( \$(date -d \"\$exp\" +%s) - \$(date +%s) )); (( left > 0 && left <= 7300 ))"
check "CA hash is correct" bash -c "h=\$(ssh cp1 sudo openssl x509 -pubkey -in /etc/kubernetes/pki/ca.crt | openssl rsa -pubin -outform der 2>/dev/null | sha256sum | cut -d' ' -f1); grep -q \"sha256:\$h\" $HOME/exam2/join.txt"
check "not a control-plane join" bash -c "! grep -q -- '--control-plane' $HOME/exam2/join.txt"
finish
