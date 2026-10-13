#!/bin/bash
# Runs as student on jump via `lab drill cleanup`; this attempt's values are loaded.
source "$LAB_HOME/lib/common.sh"
set -uo pipefail
rm -f ~/answers/drill-"$FILE".txt
