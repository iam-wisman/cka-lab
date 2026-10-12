#!/bin/bash
source "$LAB_HOME/lib/common.sh"
source "$LAB_HOME/lib/grade.sh"
need_cluster
check_eq "t4-pod.txt" "$(cat $LAB_STATE/exam1-t4-victim 2>/dev/null)" cat "$HOME/exam1/t4-pod.txt"
check_eq "t4-line.txt" "panic: runtime error: index out of range [7] with length 7" cat "$HOME/exam1/t4-line.txt"
finish
