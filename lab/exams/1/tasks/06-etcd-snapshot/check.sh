#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check "snapshot valid" on cp1 bash -c 'etcdutl snapshot status /var/backups/etcd/exam1.db >/dev/null 2>&1'
check "snapshot taken during the exam" on cp1 bash -c "(( \$(stat -c %Y /var/backups/etcd/exam1.db) >= $(cat $LAB_STATE/exam1-t6-start 2>/dev/null || echo 0) ))"
check "status table saved" on cp1 grep -Eq '^\| *HASH *\| *REVISION' /var/backups/etcd/exam1.status
finish
