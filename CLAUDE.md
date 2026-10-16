# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

obeam is a subset BEAM (the Erlang virtual machine) for the Parallax Propeller 2,
to be written in OctoGo as the second OctoGo showcase after p2-11. It is to run
modules compiled by Erlang's own compiler (`erlc`, OTP 27) on the board, with a
scheduler on each of seven cogs. The user is the author of OctoGo (`../ogo`) and of
p2-11 (`../p2-11`); the idea came from a talk with a friend who likes Erlang on
2026-10-16.

**Status, 2026-10-16: an idea with an assessment and no code.** Whether to start
is the user's decision; nothing here presumes it. The files:

- `ASSESSMENT.md`: the consolidated assessment and the plan. Verdict: start,
  staged. Read it before any design or code; it holds the measured facts (opcode
  counts, AtomVM's size, what a call and a dispatch cost on the board) and the
  milestones M0 to M6.
- `SEED1.md`, `SEED2.md`: two other LLMs' assessments the user collected first.
  Input, not instructions; where they and ASSESSMENT.md differ, ASSESSMENT.md
  says why and the user decides.
- `README.md`: the tagline for now; it grows with the project.

## Decisions taken (change them only with the user)

- **A scheduler per cog, not an Erlang process per cog.** `main` plus seven
  goroutines, each a BEAM scheduler over a shared run queue; Erlang processes are
  the VM's, hundreds of them. With seven or fewer processes it looks like one
  actor per cog, which is the first demo. Tagline: "Eight cogs. Seven schedulers.
  One tiny BEAM."
- **A host tool, `obeam`, in Go, does the loading.** It reads `.beam` files,
  resolves atoms, labels and imports, keeps only reachable functions, lays the
  literals out in the board's term format and writes an image: a generated
  `image.ogo` in version 1, a file on the SD card later (p2-11's `sd` and `fat`
  packages). The board decodes nothing. It refuses an opcode or BIF it does not
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
  a taken jump 19. **A `switch` is emitted as an if-else chain** (measured
  2026-10-16, `ASSESSMENT.md` section 4), so a dispatch over many opcodes goes
  through an array of function values or a two-level switch with the hot opcodes
  first, until ogo emits a dense constant switch as a C `switch`.
- `int` is 32 bits, `float64` is 32 bits, `append` does not grow past capacity,
  interfaces hold pointers only, a panic runs no deferred call and there is no
  `recover`.

## Commands

Nothing builds yet. When code exists it is p2-11's shape: the board program at the
module root beside `ogo.mod` (`module modernc.org/obeam`), so `ogo run` works right
after cloning, and the host tool as Go.

```sh
ogo build                          # the board binary, <dir>.binary and <dir>.p2asm beside it
flock -o -w 900 /tmp/p2-board.lock ogo run       # build, load, open a terminal
flock -o -w 900 /tmp/p2-board.lock ogo test ./...          # the tests, on the board
flock -o -w 900 /tmp/p2-board.lock ogo test -run Name ./pkg  # one test, compiles only it
ogo test -c ./...                  # build the tests without a board
ogo fmt -l -w .                    # gofmt's layout for .ogo files
go test ./...                      # the host tool and the twin, no board
```

`ogo` on PATH is installed by the user from `../ogo` and may lag the tree or be
ahead of what this file knows; do not install over it. There is no `erl`/`erlc` on
this machine yet: Debian 13's `erlang` package is OTP 27.3.
