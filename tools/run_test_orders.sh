#!/usr/bin/env bash
# Runs gdUnit suites in alphabetical order and/or reversed order to expose order leaks.
# Usage: tools/run_test_orders.sh [forward|reversed|both] [test/suite_x_test.gd ...]
# With no suite paths, every test/suite_*_test.gd is used. DRY_RUN=1 prints the commands only.
# A parse error in ANY selected suite aborts discovery for the whole run (exit 105).
set -u
cd "$(dirname "$0")/.." || exit 2
: "${GODOT_BIN:=/usr/bin/godot}"
export GODOT_BIN
mode="${1:-both}"
[ $# -gt 0 ] && shift
if [ $# -gt 0 ]; then
	suites=("$@")
else
	mapfile -t suites < <(ls test/suite_*_test.gd | sort)
fi
mkdir -p tmp/test-audit

run_order() { # $1 = label, remaining = suite paths in run order
	local label="$1"
	shift
	local args=()
	local s
	for s in "$@"; do
		args+=(-a "res://${s}")
	done
	echo "== ${label}: $(( ${#args[@]} / 2 )) suites" >&2
	if [ "${DRY_RUN:-0}" = "1" ]; then
		echo "addons/gdUnit4/runtest.sh ${args[*]}"
		return 0
	fi
	addons/gdUnit4/runtest.sh "${args[@]}" 2>&1 | tee "tmp/test-audit/run_orders_${label}.txt" | grep -E 'Run tests ends|Failed|FAILED|Overall Summary' || true
}

if [ "$mode" = "forward" ] || [ "$mode" = "both" ]; then
	run_order forward "${suites[@]}"
fi
if [ "$mode" = "reversed" ] || [ "$mode" = "both" ]; then
	rev=()
	for ((i = ${#suites[@]} - 1; i >= 0; i--)); do
		rev+=("${suites[$i]}")
	done
	run_order reversed "${rev[@]}"
fi
