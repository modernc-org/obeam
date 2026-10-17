#!/bin/sh
# Copyright 2026 The obeam Authors. All rights reserved.
# Use of this source code is governed by a BSD-style
# license that can be found in the LICENSE file.

# release.sh builds the obeam command for every target OctoGo's releases have
# and stages the zips for a GitHub Release, as ogo's scripts/release.sh does.
# The module is CGO-free, so every target cross-compiles from one host, and the
# VMs are not built here: they are the committed ones of internal/vmbin, which
# every obeam carries, and which go test holds to the sources first.
#
# Usage: scripts/release.sh [VERSION]
#   VERSION defaults to the exact tag at HEAD, so the flow is: make vms with the
#   released ogo, commit, git tag vX.Y.Z, make release. DEMO_MODULES, from the
#   Makefile, names the demo's modules.
#
# Output: build/release/<VERSION>/ with obeam-<VERSION>-<goos>-<goarch>.zip for
# every target and a SHA256SUMS over them. Each zip holds the obeam binary,
# LICENSE, LICENSE-flexprop (the VM is flexspin's output, and the loader is
# loadp2), README.txt and examples/: .beam files to run, with their sources.
#
# As ogo's say: only the host's binary can be run here. The others compile,
# and that is all this script knows of them.

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

VERSION="${1:-}"
if [ -z "$VERSION" ]; then
	VERSION=$(git describe --tags --exact-match 2>/dev/null || git describe --tags 2>/dev/null || echo dev)
fi
: "${DEMO_MODULES:?DEMO_MODULES unset: run make release}"

TARGETS='linux/amd64 linux/arm64 windows/amd64 darwin/arm64 darwin/amd64'

# The VMs must be the tree's.
go test -count=1 -run 'TestFresh|TestRegions' ./internal/vmbin
case "$(sed -n 's/^ogo //p' internal/vmbin/BUILD)" in
*dirty* | *-0.20*)
	echo "warning: the VMs were built by an ogo of no release: $(sed -n 's/^ogo //p' internal/vmbin/BUILD)" >&2
	;;
esac

FLEXPROP=$(go list -m -f '{{.Dir}}' modernc.org/ogo)/internal/flexcc/LICENSE-flexprop
OUT="$ROOT/build/release/$VERSION"
rm -rf "$OUT"
mkdir -p "$OUT"

echo "building obeam $VERSION for: $TARGETS"
for t in $TARGETS; do
	goos=${t%/*}
	goarch=${t#*/}
	bin=obeam
	[ "$goos" = windows ] && bin=obeam.exe

	stage="$OUT/stage-$goos-$goarch"
	mkdir -p "$stage/examples/demo"

	CGO_ENABLED=0 GOOS="$goos" GOARCH="$goarch" \
		go build -trimpath -ldflags "-s -w -X main.version=$VERSION" \
		-o "$stage/$bin" .

	cp LICENSE "$stage/LICENSE"
	cp "$FLEXPROP" "$stage/LICENSE-flexprop"
	for m in hello listlib ring sieve sup blink; do
		cp "erl/$m.erl" "erl/$m.beam" "$stage/examples/"
	done
	cp ex/hello.ex ex/Elixir.Hello.beam "$stage/examples/"
	for b in $DEMO_MODULES; do
		cp "$b" "$stage/examples/demo/"
		src=${b%.beam}.erl
		[ -e "$src" ] && cp "$src" "$stage/examples/demo/"
	done
	cp ex/*.ex "$stage/examples/demo/"

	cat > "$stage/README.txt" <<TXT
obeam $VERSION -- $goos/$goarch (preview)

OctoBeam is a BEAM, the Erlang virtual machine, for the Parallax Propeller 2:
the modules Erlang's and Elixir's compilers write, run with a scheduler on each
of seven of the P2's eight cogs. This one file is all of it: it carries the VM,
built for the P2, and a P2 loader, so there is nothing to install -- run it from
anywhere. To compile programs of your own you need Erlang/OTP 27's erlc (or
Elixir's elixirc); obeam reads the .beam files they write.

Quick start, with a P2 board on a USB port:
  ./$bin run examples/hello.beam          # put it into the VM, load it, show what it prints
                                          # (Ctrl-] leaves the terminal)
  ./$bin run examples/blink.beam          # a P2-EDGE's LEDs on pins 56 and 57, a process each
  ./$bin run -entry demo:main/0 examples/demo/*.beam
                                          # the demo: 26 modules of Erlang and Elixir
  ./$bin examples/hello.beam              # only write hello.binary, for any P2 loader
  ./$bin -sd examples/hello.beam          # write _BOOT_P2.BIX: copied onto a FAT32 SD card in
                                          # the board's slot, the board runs it when reset
  ./$bin flash examples/hello.beam        # into the board's flash, which it can boot from
  erlc hello.erl && ./$bin run hello.beam # a program of your own: hello:main/0
  ./$bin help                             # the flags
  ./$bin version                          # should print: obeam version $VERSION $goos/$goarch

It runs a subset of Erlang: no bignums, 32-bit floats, OTP's and Elixir's
libraries only as far as the shims obeam carries go (lists, maps, Enum, Map),
and 512 KB for everything. obeam says by name what a program uses that the VM
does not have. On Windows, run it from cmd.exe or PowerShell, not git-bash.

This is a preview. Report issues and follow progress at
https://gitlab.com/cznic/obeam (issues/PRs are also accepted at the GitHub
mirror https://github.com/modernc-org/obeam).

Licensing: obeam is BSD-licensed (see LICENSE). The VM it carries is built by
flexspin and includes its runtime, and its loader is loadp2, both FlexProp's;
see LICENSE-flexprop.
TXT

	name="obeam-$VERSION-$goos-$goarch.zip"
	(cd "$stage" && zip -q -X -r "$OUT/$name" "$bin" LICENSE LICENSE-flexprop README.txt examples)
	rm -rf "$stage"
	echo "  $name    ($(du -h "$OUT/$name" | cut -f1))"
done

(cd "$OUT" && sha256sum *.zip > SHA256SUMS)
echo
echo "artifacts in $OUT:"
ls -1 "$OUT"
