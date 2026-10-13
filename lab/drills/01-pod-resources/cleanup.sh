#!/bin/bash
# Runs as student on jump via `lab drill cleanup`; this attempt's values are loaded.
source "$LAB_HOME/lib/common.sh"
set -uo pipefail
kubectl delete ns -l "cka-lab/drill=$GRADE_ID" --ignore-not-found
