# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

OctoBeam (short name `obeam`, as OctoGo's is `ogo`; the user named it so on
2026-10-17) is a subset BEAM (the Erlang virtual machine) for the Parallax
Propeller 2, written in OctoGo as the second OctoGo showcase after p2-11. It
is to run modules compiled by Erlang's own compiler (`erlc`, OTP 27) on the board, with a
scheduler on each of seven cogs. The user is the author of OctoGo (`../ogo`) and of
p2-11 (`../p2-11`); the idea came from a talk with a friend who likes Erlang on
2026-10-16.

**Status, 2026-10-18: v0.1.0 being prepared, the CHANGELOG's section headed; M6b, the distribution and OTP's library as shims committed.** The user said go that afternoon; M0
(the reader, the corpus, DESIGN.md) was done by evening, DESIGN.md's open
points decided with the user, M1 (one process on one cog, e1a384e), M2
(processes, messages, receive with timeouts, funs and apply, 18c3c27), M3
(seven scheduler cogs, locks, the pin ring, da899c2) and M4 (exceptions
caught, links, monitors, exit signals, registered names, floats, io:format's
widths and precisions) built the same night: thirteen modules of the corpus
run under the Go twin on seven goroutines with the bytes `erl` prints, clean
under the race detector, and the board prints the same lines on seven cogs.
Left for later: loading an image from the SD card (the VM's atom names would
have to become bytes), bit syntax, maps, bignums, `~p`'s line breaking. M5's
OctoGo part is done (a profiler, leaf fast handlers, the P2's locks directly,
collections sized by what lives) and the PASM core, on each scheduler's own
cog as the user chose, run from hub: it does 88% of the instructions, and
the demo runs twice as fast as at the end of M4 (bba5a36; the user put the
runtime around the core off for later). M6a, Elixir: six Elixir modules run
and print what `elixir` prints, through `bs_create_bin`, run-time binaries,
`IO`/`Kernel.inspect`/`String.Chars` BIFs and an `Enum` shim. Then room, at
the user's word that the programs the VM can run come before its speed: 88
KB of the checked build given back at no cost in speed (DESIGN.md section
8), the arena back to 192 KB, 37 KB of the hub left. M6b, maps and binary
matching, Erlang's and Elixir's, structs and ranges among them: `mp`, `bin`
and `Maps` agree with `erl` and `elixir`, and the demo with them took the
arena to 160 KB, 10.7 KB of the hub left. Then the plan for OctoBeam's
users the user agreed on 2026-10-17 (one `obeam` executable embedding the
VM built once, checked and, with `--unchecked`, unchecked, that puts a
program's image into it and loads the board through `modernc.org/ogo/loadp2`,
needing no Go, OctoGo or loadp2 of the user's, and `go install
modernc.org/obeam@latest`). Step 1, committed (66b02b4): the image at the
bottom of the arena, written into a built VM binary, the arena 232 KB,
`image/` gone. Step 2, built: `obeam` at the root, carrying the VMs
(`internal/vmbin`, `make vms`) and the shims, `obeam run` loading through
`modernc.org/ogo/loadp2`, the board program in `board/`, OTP's `lists` as a
shim, `make release` and the README's guide, committed (7a40746). Then
`-sd` as the user chose it, the ROM's own boot: `obeam -sd` writes
`_BOOT_P2.BIX`, and `obeam flash` writes the board's flash; both arenas
8 KB smaller so that every VM binary fits the 496 KB the ROM loads from a
card. The user is to put the
repository on GitLab (cznic/obeam) with a GitHub mirror (modernc-org/obeam)
where the zips are published; nothing is pushed or published by an agent.
The files:

- `ASSESSMENT.md`: the consolidated assessment and the plan. Verdict: start,
  staged. It holds the measured facts (opcode counts, AtomVM's size, what a
  call and a dispatch cost on the board) and the milestones M0 to M6.
- `DESIGN.md`: how it is to be made: what runs where, terms, processes, the
  image, what M0 measured, and the decisions of 2026-10-16.
- `SEED1.md`, `SEED2.md`: two other LLMs' assessments the user collected first.
  Input, not instructions; where they and ASSESSMENT.md differ, ASSESSMENT.md
  says why and the user decides.
- `README.md`: what there is and how to run it; the tagline is the user's.
- `main.go`, `dev.go` (the root, so that `go install modernc.org/obeam@latest`
  works), `internal/beam`, `internal/pack`: the host tool, Go: the command
  users run (`obeam [run] FILE.beam...`, `obeam loadp2`, `obeam version`),
  the reader, the packer, and the developers' `dis`, `stats`, `chunks` and
  `gen`. It embeds `erl/shim/*.beam` and `ex/shim/*.beam`, and
  `internal/vmbin`: the VMs, checked and unchecked, built by `make vms` and
  committed with `BUILD`, the hash of their sources, which `TestFresh` holds
  the tree to: **after any change to `board/`, `vm/`, `core/` or `ogo.mod`,
  `make vms`** (two builds, a minute and a half), with `OGO=` a released ogo
  for a release (v0.57.0 is in the scratchpad's `bin/`, `GOBIN=...
  go install modernc.org/ogo@v0.57.0`; the ogo on PATH is the user's).
  `erl/`: the corpus and the oracle script; `erl/stats.txt` the histogram M0
  was for, regenerated by `make stats`.
- `vm/`: the VM, OctoGo that is also Go. `board/main.ogo`, with `ogo.mod` at
  the root: the board program, which `ogo build -o obeam.binary ./board`
  (`make obeam.binary`) makes into the VM with an empty arena; `make demo`
  puts the demo's image (`DEMO_MODULES`) into a copy of it, `demo.binary`.
  Neither is committed.
- `scripts/release.sh`, `make release`, `CHANGELOG.md`: the release, after
  ogo's: five zips (linux amd64/arm64, windows amd64, darwin arm64/amd64),
  each the `obeam` binary, LICENSE, LICENSE-flexprop (from the ogo module),
  README.txt and `examples/` (hello, listlib, ring, sieve, sup, blink, the
  Elixir hello, and the demo's modules), and SHA256SUMS. Tagging and
  publishing are the user's.
- `scripts/twin.sh`: runs `vm/` under Go; `make test` runs it last.
- `prof/`: the profiler, a board program over `erl/bench.erl`; `make prof`
  writes `prof/names.ogo`, the names the VM does not carry, builds
  `prof/vm.binary` from a copy of the tree under `build/prof` in which
  `profOn` (`vm/profile.ogo`) is 1, and puts the bench's image into it,
  `prof/prof.binary`. In the tree `profOn` is 0, so that the board's VMs
  leave the profiler's tables and `runProfiled` out, 5.8 KB.
- `ex/`: the Elixir corpus, `*.ex` compiled by `make exbeam` into committed
  `Elixir.*.beam`; `ex/shim/` the Erlang shims of Elixir's library (`Enum`,
  `Map`, `elixir_erl_pass`), and `erl/shim/` of OTP's (`lists`,
  `gen_server`, `supervisor`, `string`, `timer`, `queue`, `proplists`,
  `rand`, `os`'s time, `maps`' functions that take a fun, and `erlang`'s
  that are no BIF of the VM's), packed as libraries (`obeam pack -lib`, by what the
  program reaches) and **never on the oracle's path**, where they would hide
  the real ones. `TestElixir` runs `elixir -pa ex -e "Mod.main()"`; `exUses`
  in `vm/host_test.go` names the modules an Elixir one is packed with
  (`Maps` with `Point`).
- `core/`: the PASM core. **Edit `core/core.pasm`, never `core/core.spin2`**,
  which `go run . gen -vm vm -names prof` writes from it and from
  `CoreOps` in `internal/pack/tables.go`; `TestCoreGenerated` fails on a stale
  one.

## Decisions taken (change them only with the user)

- **A scheduler per cog, not an Erlang process per cog.** `main` plus seven
  goroutines, each a BEAM scheduler over a shared run queue; Erlang processes are
  the VM's, hundreds of them. With seven or fewer processes it looks like one
  actor per cog, which is the first demo. Tagline: "Eight cogs. Seven schedulers.
  One tiny BEAM."
- **A host tool, `obeam`, in Go, does the loading.** It reads `.beam` files,
  resolves atoms, labels and imports, keeps only reachable functions, lays the
  literals out in the board's term format and writes an image, which `obeam
  pack -vm` puts into the arena of a VM binary built once (a generated
  `image.ogo` compiled in until 2026-10-17), and a file on the SD card later
  (p2-11's `sd` and `fat` packages). The board decodes nothing. It refuses an opcode or BIF it does not
  implement, by name, with module, function and line.
- **Erlang first, OTP 27 pinned**, the opcode table generated from
  `lib/compiler/src/genop.tab`. Elixir, bitstrings, maps, bignums, hot loading
  and tracing are out of version 1. Floats are the board's 32-bit floats.
- **Terms are tagged `uint32`s** with the boxed pointer an index into
  package-level arena arrays; each process has a heap block with a Cheney
  copying collector from milestone 2; mailboxes are heap fragments appended
  under a few striped locks; a fixed-width instruction format (a byte of opcode,
  long operands) so a PASM/XBYTE core can read the same image later, as p2-11's
  core does.
- **The oracle is OTP.** A corpus of modules runs under `erl` and under the
  host twin and must print the same; the same corpus runs on the board under
  `ogo test`. Packages that do not import `p2` stay valid Go once given a
  package clause (p2-11's twin), so the interpreter, GC and image reader are
  developed and tested on the host.
- **Claims stay honest**: the README's first screen says which subset it is, as
  ogo's DIFFERENCES.md does for OctoGo.
- **Decided 2026-10-16, DESIGN.md section 7**: small integers tagged `00`
  (30 bits); 256 processes, a pid an 8-bit index and a 19-bit generation,
  buddy blocks of 8 to 8,192 longs in an arena of 192 KB to begin with, a
  process starting with 64 longs; line numbers in a side table on the board,
  `-lines=false` to drop it; the hardware API is the module `p2`, OctoGo's
  `p2` package name for name in snake_case, plus `p2:cog/0`, with no blocking
  waits. The arena was 128 KB from M4 until the room before M6b gave the
  192 KB back, 160 KB since M6b, 232 KB since the image moved into it
  from the binary, 224 KB since the binary must fit the SD boot's 496 KB, 222 KB since the stacktraces took 7 KB and the profiler, leaving the board's build, gave 5 back, and 219 KB since the BIFs of OTP's library that could be no shims took 3 (`arenaLongs` in `vm/arena.ogo`), what the image does not
  take going to the heaps; it is the lever when the hub runs short. `ogo build` says by how much a build
  misses the 512 KB, but when it misses, the size it names is of an attempt
  with other stack slots: compare only builds that fit.
- **The programs the VM can run come before its speed** (the user,
  2026-10-16): trade clocks for hub RAM where it buys room, and take the room
  that costs nothing first. DESIGN.md section 8 has where the bytes go.

## The neighbours and the board

- `../ogo` is the compiler's tree and `../p2-11` the first showcase. Another
  session works in each: **read them, never edit them.** p2-11's `DESIGN.md` and
  `OCTOGO.md` are the model for how this project's documents are written, and
  its `main.ogo` and `pdp11/exec.ogo` for how OctoGo code of size is shaped.
- A compiler fault is checked against the tree's compiler before it is reported
  to the user, as p2-11 does: `(cd ../ogo && go build -o "$SCRATCH/ogo-head" .)`,
  and any compiler run on a suspect program goes under `ulimit -v 4000000` and
  `timeout -s KILL`.
- **One P2-EDGE board is shared with the ogo and p2-11 sessions.** Every use of
  its serial port (`ogo run`, `ogo test`, `ogo loadp2`) runs under
  `flock -w 900 /tmp/p2-board.lock` (`flock -o` when the command starts
  children). A second loader on the port talks over the first.
- The machine is shared with the user's builder VMs: one heavy batch at a time,
  `xargs -P 4` at most.
- Pushing and tagging only when the user asks. Nothing is posted to any tracker
  or forum without the user's approval of the exact text.

## OctoGo facts that shape the code

OctoGo is Go without a heap, on hardware: `../ogo/README.md` (Status) and
`DIFFERENCES.md` are the inventory, `specs.go`'s doc comment the specification.
What matters most for a VM:

- No `new`, no maps, no closures capturing scope, no runtime string
  concatenation, `make` only for a slice or a channel of constant size. Storage
  is package-level arrays; the VM is its own allocator over them.
- A goroutine is a cog (seven besides `main`); a goroutine's stack is sized from
  the backend's listing, so **nothing a scheduler calls may recurse** without
  `--gostack`. Term comparison, message copying and the GC are written with
  explicit stacks or in Cheney's iterative style.
- One function's locals come from a pool of 480 cog registers (`fit 480 failed`
  names the function): the interpreter is a loop of modest locals, handlers are
  functions.
- 16 hardware locks via `p2.NewLock`, which cannot report exhaustion, shared with
  the channel sites; no compare-and-swap. Memory shared between cogs is defined
  (a read in a loop is made on every pass, writes land in program order).
- Costs measured by p2-11 at 160 MHz, code in hub RAM: a leaf call about 40
  clocks, a call of a function that calls others 150 to 160, a hub read 25 to 37,
  a taken jump 19. **A `switch` was emitted as an if-else chain** (measured
  2026-10-16, `ASSESSMENT.md` section 4), so a dispatch over many opcodes goes
  through an array of function values or a two-level switch with the hot opcodes
  first. ogo v0.57.0 emits a switch of constant integer cases as a C `switch`,
  dense ones through a jump table, unless the program outgrows a cog's
  registers; not measured here yet.
- `int` is 32 bits, `float64` is 32 bits, `append` does not grow past capacity,
  interfaces hold pointers only, a panic runs no deferred call and there is no
  `recover`.

## Commands

```sh
make test                        # gofmt and ogo fmt -l, go vet, go test ./..., then the twin; the gate
make twin ARGS='-run TestErl -v ./vm'   # the twin alone, kept in build/twin, with go test arguments
make shimcheck                   # erl/shim's erlang, proplists, queue and string against OTP's under erl, generated arguments
scripts/twin.sh -run TestErl/lst ./vm   # the same without make
ogo build ./vm                   # the VM through OctoGo's checker, no main, no board
make obeam.binary                # the VM from board/: ogo build -o obeam.binary ./board, its arena empty, marked
make demo                        # obeam.binary, then demo.binary: the VM with the demo in its arena
                                 # after ANY change to internal/pack/tables.go: `go run . gen -vm vm`, then rebuild;
                                 # obeam refuses a VM whose TableID is not the packer's
make vms                         # the VMs obeam carries, internal/vmbin (OGO=... for a release); go test fails until it is run
make release                     # the zips, build/release/VERSION/ (VERSION= or the tag at HEAD)
make run                         # load demo.binary onto the board (ogo loadp2 -b 230400 -t), under the shared lock
make budget                      # build the VM and say how much of the hub it leaves
make prof                        # the profiler, prof/prof.binary, over erl/bench.erl (names, build, pack)
make prof-run                    # and run it on the board, under the shared lock
make beam                        # recompile the corpus (erlc +deterministic, OTP 27) after a .erl edit
make exbeam                      # recompile the Elixir corpus and its shims (elixirc 1.18.3, deterministic)
make stats                       # regenerate erl/stats.txt
make generate                    # regenerate internal/beam/opcodes.go and vm/{opcodes,tags,atoms,biftab}.ogo
go run . dis erl/pingpong.beam   # a listing, as erlc -S would write it
go run . -vm obeam.binary erl/fac.beam   # any program into the tree's VM: fac.binary (-entry m:f/a; main/0 by default)
go run . run erl/fac.beam        # into the carried VM and onto the board: under the board lock, flock -o
```

To capture a board run without a terminal, as ogo's `scripts/board.sh` does:

```sh
flock -o -w 900 /tmp/p2-board.lock bash -c \
  '(sleep 15; printf "\x1d") | timeout 90 ogo loadp2 -t -NOEOF -p /dev/ttyUSB0 -b 230400 demo.binary' \
  | tr -d "\r" | grep -a -v "Entering terminal mode" | grep -a -v "^( "
```

`obeam run` is the loader in-process (`modernc.org/ogo/loadp2`; the
`modernc.org/loadp2` in go.mod is its own dependency, the transpiled C, and
indirect): capture it the same way with `build/obeam run -p /dev/ttyUSB0 ...`
in place of `ogo loadp2 ...`. A program's output starts after obeam's two
lines and loadp2's `( Entering terminal mode ... )`.

A port that is busy under the lock is another session's loader, reported and
not killed. OTP 27.3 is installed (`erl`, `erlc`, `escript` on PATH since
2026-10-16). `ogo` on PATH is installed by the user from `../ogo` and may lag
the tree or be ahead of what this file knows; do not install over it.

## The VM

- `vm/` is OctoGo that is also Go: no `print` builtins, no `Builder`. It
  imports `p2` for the locks, the clocks, a pause, the serial line, the
  clock's frequency and `rnd` (`vm/hooks.ogo`, `vm/profile.ogo`, `vm/bif.ogo`,
  `vm/core.ogo`), and `scripts/twin.sh` rewrites that import to
  `internal/p2twin`, a Go shim of them whose serial line is the test's buffer,
  `Sink`. `main.ogo` sets `CRLF` and `PinsServed` and serves the pins' ring.
  The twin adds the package clauses, skips
  any directory with a `func main()`, and runs under `GOARCH=386` with the
  build tag `twin`, which `vm/host_test.go` is compiled under and nothing
  else; at the repository root that file is excluded, so plain `go vet ./...`
  and `go test ./...` do not see it. A lock through a hook cost 616 clocks a
  round and through `p2` costs 107: keep the locks direct.
- **The VM calls no function value but the handlers and the BIFs** (`run`,
  the BIF handlers, `callBif`; `Core` from `coreRun`). ogo sizes a
  goroutine's stack from the backend's listing, which counts a call through a
  function value as going to every function whose address is taken: a hook
  called from a BIF made every BIF and handler one cycle whose frames the
  bound added up, 1,776 longs a slot, 688 since. So nothing a BIF calls goes
  through a function value, and `apply` answers `bifValue` with the BIF in
  `bifJump` and its arguments in `bargs`, for `callBif` to call, rather than
  calling it. And a function whose address is taken is linked even when
  nothing calls the function that takes it.
- **Nothing in `vm/` recurses** (a scheduler is a goroutine from M3 on, and a
  goroutine's stack is sized by the build): the collector is Cheney's, and
  comparison and the term writer keep their pending parts on stacks of their
  own (`cmpStack*`, `wstack`), sixty-four deep. Keep it so.
- **A BIF that allocates calls `ensure` and then reads `bargs` again**: a
  collection moves terms, and `bargs` and the live X registers are its roots.
  A BIF fails by `failWith` or `badarg()`, never by raising; the handler
  raises or takes the fail label. `curLive` is -1 under `bif0/1/2`, which may
  not allocate, and `ensure` panics if one does.
- **The word layout is the packer's**: `internal/pack/term.go` is the one
  copy, `obeam gen` writes `vm/tags.ogo`, `vm/opcodes.ogo`, `vm/atoms.ogo` and
  `vm/biftab.ogo` from it and from `internal/pack/tables.go`; a new BIF is a
  line in `Bifs` there, a function `bifX(n uint32) uint32` in `vm/bif.ogo`,
  and `make generate`. A header and a continuation end in `111`, a register
  marker in code in `0111` or `1111`, and no term does.
- A handler answers the next pc, or 0 to stop; `run` sets `cur.pc` before
  each so that a report knows where it was. `raise*` ends the process: a
  handler that raised returns 0 and nothing after it runs.
- **The fast handlers are the twin's only** (`vm/fast.ogo`): on the board the
  core does their instructions, so the board's build leaves them out, 16.8
  KB, and `useFast` in `vm/host_test.go` registers them, where it must stay;
  `TestErl` and `TestElixir` run every module with and without them.
  A hot handler calls nothing: a call makes it a non-leaf,
  and the backend saves every register at its entry, ~150 clocks, even on a
  path that never calls. The operand decoding is written out in each, not
  `src`/`store`. A case it does not do it answers `slowPath` with nothing
  changed, and the loop calls the general handler, which `fast()` keeps in
  `slow`. A new fast handler is registered in `useFast`; every empty slot of
  `handlers` is `hBad`, so the loop has no nil test.
- **The core** (`core/core.pasm`): flexspin's inline assembly allows no
  `call` and no `ret` (a `ret` becomes a jump to the block's end and holds the
  block to the cog cache's size), must not touch `ptra`, and its `tjz`/`tjnz`/
  `tjs` reach 256 instructions only. So operands are read and written by the
  macros `@src X`, `@dst`, `@one`, `@two`, `@kinds`, runs of instructions
  with no branch; a handler ends with `@pass N` (N longs, then the dispatch)
  or jumps to `.jump`/`.fail`/`.back`; `ptrb` is the code pointer. A handler
  must do exactly what `vm/fast.ogo`'s does, and answer `.back`, with nothing
  changed, for a case it does not do. A new instruction is a line in
  `CoreOps`, a `.op_<name>` in the template, `obeam gen`, `make demo`. The
  core is not in the twin: run the demo on the board and diff it against
  `erl`, and `make prof`, after every change to it.
- **Hub RAM**: a VM binary must be at most **507,904 bytes**, the 496 KB
  the P2's ROM loads from an SD card (`_BOOT_P2.BIX`; it keeps its own code
  in the top 16 KB while loading), which `TestBootable` in
  `internal/vmbin` holds both VMs to; a larger one does not boot, and the
  board, finding the file, answers no serial loader either (found
  2026-10-17). The checked VM binary is 506,632 bytes, whatever the image,
  the unchecked 507,044, 1,272 and 860 under; `make budget` says how far.
  The arenas are 219 and 274 KB: the stacktraces' 6 KB of code took 7 and
  5 KB of them, the profiler, out of the board's build since (`profOn`),
  gave 5 and 5 KB back, and the BIFs of 2026-10-18 took 3 and 2. The
  goroutine slots are 800 longs checked, 798 of them the deepest's; a
  build with `--gostack N` shows by the size how much of a growth is
  theirs. In the checked build every field of a pointer and every `arena`
  index read is a test and a jump of 16 to 44 bytes: a new function reads a
  field once into a local, and `ogo build --report` (ogo master) names the
  largest functions and variables. The next VM growth takes the arenas: the
  arena is 219 KB (`arenaChecked`): the demo's image takes 69 KB of it and
  leaves 149 KB to the heaps, which `obeam` reports. The unchecked VM's
  arena is 274 KB (`arenaUnchecked`, which `make vms` swaps in, in a copy of
  the tree under `build/unchecked`).
- **The board's slot**: p2-11's 32 GB card belongs there; the user's 4 GB
  card (FAT32, partition type 0x0b) is for OctoBeam's SD tests. With the
  P2-EDGE's DIP switch SD on and a card holding `_BOOT_P2.BIX`, the board
  boots the card at power-on and at a DTR reset, 7.7 s for a VM, and no
  loader finds it: the card comes out before the board is loaded over USB,
  the other sessions' loads included. The board's flash holds hello since
  `obeam flash` was tried on 2026-10-17 (DIP switch FLASH off, so it does not
  boot it). `scripts/listen.py -r PORT SECS`,
  under the lock, resets the board by DTR and prints what it sends. `ogo build` says by how much a build misses; the arena
  (`arenaLongs`) is the lever. DESIGN.md section 8 has where the bytes go.
- **The image is the bottom of the arena** (`internal/pack/region.go`, DESIGN.md
  section 4): a header of 24 longs, the literals at `LitBase` where the
  packer's pointers say, the code and tables, then the atoms' and files'
  names as bytes. `arena`'s initializer is the mark `obeam pack -vm` finds
  in the binary; `Load()` reads the header in place, or answers false. A
  name is a long (byte offset above `nameLenBits`, length below), read with
  `nameLen`/`nameAt`/`nameIs`/`emitName`: OctoGo has no `string(b)`. The
  twin copies `img.Region()` into the arena; a change to the header is a
  change to `ImageLayout`, which `TableID` fingerprints.
- Elixir's `inspect` is `vm/inspect.ogo`; it does not break lines at 80
  columns as Elixir's pretty printer does, so a corpus module keeps what it
  inspects short. A struct prints in its fields' order, which the packer
  reads from the module's `__info__(:struct)` into the image's `Structs`.
- **Maps** (`vm/maps.ogo`) are a header, the keys in map-key order (every
  integer before every float), then the values: `internal/pack/order.go` and
  `cmpExact` must agree, and a map's keys compare exactly even under `==`
  (`cmpX`, a flag per pair waiting on the comparison stack). `erl` and
  `elixir` print a map's atom keys in their atom tables' order, and OTP a map
  of more than 32 keys in its hash trie's: a corpus module prints such maps
  with `~kp`, sorted, or not at all. erlc folds comparisons of literals at
  compile time, so a test of comparison passes its operands through `id/1`.
- **Binary matching** (`vm/match.ogo`): a match context is a header of kind
  7, the binary and the offset in bits, moved on in place; `bs_match`'s
  command list the packer rewrites (`emitBsMatch`). What a match takes out is
  a copy, whole bytes at a byte's offset, and a would-be bitstring fails the
  match. A BIF that fails with `{badmap, M}` or `{badkey, K}` uses
  `failTagged`, and the handler's `bifRaise` builds the tuple.
- **Measure before and after** with `make prof` and the board: the profile is
  by opcode and by BIF, on one scheduler. `vm.Dump()` prints the pool's free
  lists and the last request it failed: a `system_limit` with the pool mostly
  free is fragmentation.
- The frame: `arena[stop]` is the continuation, `y(i)` is `arena[stop+1+i]`.
  `allocate` zeroes the slots so the collector reads only terms.
- Check a change three ways: `ogo build ./vm` (the OctoGo checker, seconds),
  `make twin` (Go, and the oracle against `erl`), and the board; a change to
  the synchronization also under the race detector, and a change for speed
  with `make prof`.
- **Never run the twin, or `make test`, in a shell that has `ulimit -v
  4000000` set for the compiler cap**: `erl` reserves more virtual memory
  than that at boot and dies with `load_failed` of its own kernel modules,
  which the test reports as `erl: exit status 1` for every module. Cap the
  compiler in a subshell, `(ulimit -v 4000000; ogo build .)`, and nothing
  else. Found 2026-10-16, twice, before the crash dump said why.
- **A stacktrace's head**: a raw stacktrace is `{Class, Offsets}` or
  `{Class, Offsets, {M, F, Args, Where}}`; `s.head` is made just before a
  raise (`bifHead` in `bifRaise`, `xHead` at `func_info` and in `applyX`,
  `bifApply3`), `throw` roots it in `bargs[1]` for `buildRaw` and clears it;
  `s.headSkip` drops the frame of the pc, a function not entered. Every BIF
  handler sets `s.bifNum`. `erlang:raise/3` leaves its stacktrace in
  `s.raiseRaw`; `raw_raise`'s x2 is the raw stacktrace as it is. A crash
  report is written from the list `stackList` makes, once, in `throw`.
  `erl/stacks.erl` holds it all to `erl`.
- **A receive of no clauses** (`receive after T -> ok end`, and `receive
  after infinity -> ok end`, which is a `wait`) is a wait whose label is
  itself: `allSeen` marks every message seen for it, or `sleep`, finding one
  unseen, answers the label and the process goes round in one turn for
  ever. A receive's timeout is `armed`
  at its first wait and disarmed when it takes a message or times out.
  `stackList` keeps the caller's `bargs` (found 2026-10-17 by `erl/leds.erl`,
  held by `erl/exits.erl` and `erl/waits.erl`; `reports` in
  `vm/host_test.go` leaves the VM's crash reports out of the comparison and
  runs `erl` with `-kernel logger_level none` for those modules).
- **A shim is held to OTP's own under `erl` first**: `make shimcheck`
  (`scripts/shimcheck.sh`, `scripts/shimcheck/*.escript`) compiles a copy
  renamed (`-module(ostring)`) and calls it and OTP's module with the same
  generated arguments, results and errors compared as terms, so that a
  nested answer's shape is held too (`string` 1.2 million calls, `queue`
  3,000 runs of 25 operations, the funs' calls in order with them); then a
  corpus module in the twin and on the board. A new shim whose answers are
  its arguments' gets an escript there; a shim's call of a BIF of the VM's
  own that OTP has not, `erlang:'$float'/2`, `shimcheck.sh` points at
  `scripts/shimcheck/obeam_vm.erl`, which does it in OTP's terms.
  `erl/shim/erlang.erl` serves a call of `erlang:F/A` that is no BIF of
  the VM's: the packer takes a BIF first and a packed module's function
  after, so what `erlc` makes an instruction of (`get/1`, `node/0`,
  `ceil/1`, `floor/1`; `erlc -S` says) cannot be a shim, an instruction
  calling no function. Where a library function needs the VM, the VM gives
  a small BIF named `erlang:'$name'` and the shim does the rest:
  `erlang:'$dict'/1` swaps the process dictionary, a map in the heap's first
  long, which `gc` keeps first; `erlang:'$float'/2` is the float nearest
  0.D times 10^k, found by halving the floats' bits and comparing digits
  (`readFloat`), the syntax being the shim's: 5 to 34 ms a call on the
  board, a trade-off the README names and the user left for later on
  2026-10-18 (DESIGN.md has the faster ways and their bytes). `~e`, `~f` and `~g` and the
  shim's `float_to_list/2` round the exact 21 digits `fdigits` writes, as
  OTP's `io_lib_format` rounds `float_to_list/1`'s; `TestDigits21` and
  `TestReadFloat` hold them to Go's `strconv`. `io_lib:format/2` writes the
  format twice, through `put`'s sinks: counting, then into a string's cells
  at the heap's top. `halt/1` sets `halted` under `lockOut`, after which
  `put` writes nothing, and `stopping`, and the process jumps to 0.
- **A shim that spawns** begins the new process in a fun
  (`spawn_link(fun() -> init_it(...) end)`): a library is packed by what
  the program reaches, and `spawn(M, F, A)` with atoms reaches nothing, so
  the function would be left out and the spawn fail with `undef`
  (`gen_server`, 2026-10-17). A shim that is a behaviour's callback module
  has the same trouble, its callbacks being called by name: `supervisor`
  runs its own loop and answers `gen_server:call` itself; and a child
  spec's start function, called by `apply`, must be the program's own.
  `TestErl` reads the corpus through
  `OBEAM_ROOT`, which go test's cache does not see: `-count=1` after a
  `.beam` changes.
- A process's turn ends only at a call (`jump`) or a `receive` that waits;
  what is saved is the call's arguments, `maxArity` of them, pushed on the
  process's own stack by `yield` and popped by `turnStart`. Its links and
  monitors are records of the pool in `vm/link.ogo`, 512 for all, a list a
  process under its stripe, the free list under `lockPool`; an end that dies
  takes its records out of the other ends' lists. A message lives
  in a fragment of the pool until the receiver's next collection; `inFrom`
  counts the pending fragments as from-space. The timers are `Millis`'s
  milliseconds; without the hook `now()` ticks once a reading, so a timeout
  still ends.
- **Every function that touches a scheduler's own state takes `s *sched`
  first**: the X registers, `bargs`, the BIF verdict, the collector's and
  copier's pointers, the stacks and the format buffer are fields of it, and
  nothing of them is a package variable. A scheduler's identity is that
  pointer; OctoGo has no cog-local storage.
- **The lock order**: a stripe (`stripe(p)`, a process's mailbox and state),
  then the run queue or the pool; the table's lock (`lockProcs`) and the pool
  are never held while taking anything else; nothing holds the run queue
  while taking a stripe (`wakeExpired` releases it between entries). A
  process's `state` is written under its stripe by whoever writes it; a
  turn's end is `s.left`, not the state. Check a synchronization change with
  the race detector on the twin:
  `cd build/twin && OBEAM_ROOT=$PWD/../.. go test -race -tags twin -run TestErl ./vm`
  (native arch; `GOARCH=386` has no race detector). It was clean at the end
  of M3 and should stay so.
- The scheduler cogs drive no pin: a pin BIF posts to the VM's ring
  (`vm/pins.ogo`, under `lockPins`), which main's cog serves with `NextPin`
  and `PinRead`, since several cogs' drives on a pin OR together.
  `p2:cog/0` is the scheduler's number, not the cog's.
- **A verdict about a process and the change it leads to are one step under
  the process's stripe** (`wakeExpired`'s removal of a timer entry, `sleep`'s
  appending of one): a verdict taken under the stripe and acted on after it
  let two walkers remove a valid entry, a hang of one run in ten that only
  `vm.Dump()`, the process table printed by the test's watchdog, explained.
  A hang is diagnosed with `Dump()`, not with guesses; the host test prints
  it after a minute.
- **`raise*` answer the pc to go on at**: a handler writes `return raise(...)`,
  never `raise(...); return 0`. A catch is a `1111` word in a y register, a
  continuation a `0111` word; `hReturn` clears the continuation register.
- Every writer takes the scheduler and goes through `emit`, so that a
  directive with a width can be captured and padded; `out` is the raw serial
  line, under `lockOut`. Erlang's rule for writing a float is the shorter
  of the plain and the exponent form, plain on a tie.
- Erlang logs a crash of a spawned process (error, throw) and not an exit, so
  a corpus module's workers end with `exit/1` when the test must compare
  outputs; the VM reports exits only for the entry process.

## The host tool and the corpus

- `internal/beam` reads a `.beam` file whole: chunks, atoms, the code with its
  operands decoded from the compact term encoding (`decode.go`, documented at
  the decoder), imports, exports, literals through the external term format
  (`etf.go`), funs and the line table. `opcodes.go` is generated from
  genop.tab of the pinned OTP release and not edited by hand; the `Op*`
  constants and the arity table come from it.
- `Functions()` splits the code as OTP's beam_disasm does: a function is its
  `func_info` with the run of `label` and `line` instructions before it. One
  quirk to know: beam_disasm writes that prefix in reverse order for every
  function but the first, so the oracle test sorts the prefix on both sides.
- `Format` writes an instruction with the opcode's own operands, `{is_lt,...}`,
  not the compiler's regrouping into `{test,is_lt,...}`, `{bif,...}` and
  `{gc_bif,...}` that `erlc -S` and beam_disasm print; `erl/oracle.escript`
  undoes that regrouping so the two can be compared.
- `erl/` holds the corpus: forty modules, each with a `main/0` that prints
  its result, so that the board's twin can be held to `erl` later; `blink`
  calls the board's `p2` module and does not run under `erl`. The `.beam`
  files are committed, compiled by `make beam` with `+deterministic`; commit
  them with the `.erl` they come from. A module must compile without a
  warning: a case or a match the compiler can see failing goes into a helper
  function (`exc.erl`).
- The reader is held to OTP: `TestOracle` runs `erl/oracle.escript`, which
  prints what `beam_disasm` finds, function by function, and compares. A
  change to the reader or the corpus is run through it; `make test` is the
  gate.
