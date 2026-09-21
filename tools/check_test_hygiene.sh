#!/usr/bin/env bash
# Greps gdUnit suites and helpers for the hygiene violations the 2026-09 test audit found.
# Usage: tools/check_test_hygiene.sh [file ...]   (default: test/suite_*_test.gd test/helpers/*.gd)
# Exit 0 = clean, 1 = violations printed. Waive one line with a trailing comment:
#   # hygiene-ok: <reason>
set -u
cd "$(dirname "$0")/.." || exit 2
files=("$@")
if [ ${#files[@]} -eq 0 ]; then
	files=(test/suite_*_test.gd test/helpers/*.gd)
fi
status=0

check() { # $1 = label, $2 = extended regex
	local out
	out=$(grep -nHE "$2" "${files[@]}" 2>/dev/null | grep -v 'hygiene-ok:')
	if [ -n "$out" ]; then
		echo "== $1"
		echo "$out" | cut -c1-170
		status=1
	fi
}

check "H1 writes into res:// (Hard rule 4)" '(ResourceSaver\.save\([^)]*res://|FileAccess\.open\("res://[^"]*",[[:space:]]*FileAccess\.WRITE|DirAccess\.(remove|rename|copy|make_dir)[a-z_]*\("res://|DirAccess\.open\("res://[^"]*"\)\.(remove|rename|copy|make_dir))'
check "H2 reads shipped content (.tres/.sqlite/.vox/.tscn under res://data)" 'res://data/[A-Za-z0-9_/.-]+\.(tres|sqlite|vox|tscn)'
check "H3 tautological assert (assert_bool(true).is_true())" 'assert_bool\((true|false)\)\.is_(true|false)\(\)'
check "H4 wall-clock waits (await a frame or a signal instead)" 'create_timer\(|OS\.delay_m'
check "H5 loads a shipped map" 'load_map\("(dev|base)"\)'
check "H6 hardcoded res://data/maps path" 'res://data/maps/'
check "H7 legacy / back-compat test (Hard rule 10)" '^func test_[A-Za-z0-9_]*(legacy|backward_compat|backwards_compat)'

if [ "$status" -eq 0 ]; then
	echo "test hygiene: clean (${#files[@]} files)"
fi
exit "$status"
