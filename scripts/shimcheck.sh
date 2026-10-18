#!/bin/bash
# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# shimcheck.sh holds the shims whose answers are functions of their arguments,
# erl/shim's erlang, proplists, queue and string, to OTP's own modules under
# erl. Each shim is compiled renamed, oerlang and so on, into build/shimcheck,
# and scripts/shimcheck/NAME.escript calls it beside OTP's module with the same
# generated arguments, comparing results and errors as terms, so that the shape
# of a nested answer is held too, and the order a fun is called in where the
# shim takes funs. The erlang shim's calls of the VM's erlang:'$float'/2 go to
# scripts/shimcheck/obeam_vm.erl, which does it with OTP's list_to_float/1.
# timer and rand, whose answers depend on the clock and on chance, are held by
# erl/tmr.erl and erl/rnd.erl instead, and the process dictionary and
# erlang's timers by erl/pdict.erl and erl/etimer.erl.
#
# Usage: scripts/shimcheck.sh [NAME...]   (all four by default)

set -eu
unset CDPATH
root=$(cd "$(dirname "$0")/.." && pwd)
dir=$root/build/shimcheck
names=${*:-erlang proplists queue string}
rm -rf "$dir"
mkdir -p "$dir"
erlc +deterministic -o "$dir" "$root/scripts/shimcheck/obeam_vm.erl"
for m in $names; do
	sed -e "s/^-module($m)\./-module(o$m)./" -e "s/erlang:'\$float'(/obeam_vm:float(/g" \
		"$root/erl/shim/$m.erl" >"$dir/o$m.erl"
	grep -q "^-module(o$m)\.$" "$dir/o$m.erl"
	erlc +deterministic -o "$dir" "$dir/o$m.erl"
done
grep -q "obeam_vm:float(" "$dir/oerlang.erl" 2>/dev/null || [ ! -e "$dir/oerlang.erl" ]
status=0
for m in $names; do
	echo "== $m"
	(cd "$dir" && escript "$root/scripts/shimcheck/$m.escript") || status=1
done
exit $status
