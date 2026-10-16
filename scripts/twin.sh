#!/bin/bash
# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# twin.sh runs the tests of the packages that do not import p2 under Go, on this
# machine, from the sources the board runs; after p2-11's scripts/twin.sh.
#
# A package that does not touch the Propeller 2 is Go once it is given a package
# clause. This script makes that twin in a directory of its own -- every .ogo
# file as a .go file, under a go.mod that names the module ogo.mod does, with
# the Go packages of the repository (the packer, the reader) copied in beside
# them -- and runs "go vet" and "go test" there, with GOARCH=386 so that int is
# 32 bits wide as it is on the target, and with the build tag twin, which is
# what a .go test file beside the .ogo files is compiled under.
#
# Usage: scripts/twin.sh [-k DIR] [go test arguments]
#   -k DIR   make the twin in DIR and keep it; by default it goes to a temporary
#            directory that is removed afterwards
#
#   scripts/twin.sh                     every package
#   scripts/twin.sh -run TestErl ./vm
set -eu
unset CDPATH
root=$(cd "$(dirname "$0")/.." && pwd)

keep=
if [ "${1:-}" = -k ]; then
	keep=${2:?usage: twin.sh [-k DIR] [go test arguments]}
	shift 2
fi
if [ -n "$keep" ]; then
	rm -rf "$keep"
	mkdir -p "$keep"
	twin=$(cd "$keep" && pwd)
else
	twin=$(mktemp -d)
	trap 'rm -rf "$twin"' EXIT
fi

module=$(awk '$1 == "module" { print $2 }' "$root/ogo.mod")
printf 'module %s\n\ngo 1.26\n' "$module" > "$twin/go.mod"

cd "$root"
find . -name '*.ogo' -not -path './build/*' -printf '%h\n' | sort -u |
	while read -r dir; do
		# A package that imports p2, or carries a Spin2 object, is for the
		# board only.
		if grep -q -s -E '^(import)?[[:space:]]*"p2"' "$dir"/*.ogo; then
			continue
		fi
		if compgen -G "$dir/*.spin2" > /dev/null; then
			continue
		fi
		if [ "$dir" = . ]; then
			continue
		fi
		package=$(basename "$dir")
		mkdir -p "$twin/$dir"
		for f in "$dir"/*.ogo; do
			out="$twin/${f%.ogo}.go"
			{
				printf 'package %s\n\n' "$package"
				cat "$f"
			} > "$out"
		done
		for f in "$dir"/*.go; do
			if [ -e "$f" ]; then
				cp "$f" "$twin/$f"
			fi
		done
	done
cp -r internal "$twin/"

# Where a test finds the corpus and its modules.
export OBEAM_ROOT=${OBEAM_ROOT:-$root}

cd "$twin"
if [ $# -eq 0 ]; then
	set -- ./...
fi
GOARCH=386 go vet -tags twin ./...
GOARCH=386 go test -tags twin "$@"
