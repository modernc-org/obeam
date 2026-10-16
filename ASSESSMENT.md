# obeam: a BEAM for the Propeller 2, in OctoGo

Assessment of 2026-10-16. It consolidates SEED1.md (one LLM's answers on the
size of the BEAM and on feasibility), SEED2.md (another's on the fit with the
P2 and on the architecture) and this session's own checks, made against the
Erlang/OTP sources, the AtomVM sources, the OctoGo tree (../ogo, v0.56.0) and
p2-11 (../p2-11), with a few measurements on the OctoGo backend.

## 1. Verdict

Start it, with the scope below. The idea is sound, the hardware fits unusually
well, and nobody has done it: there is no Erlang, BEAM or AtomVM port for the
Propeller 2 anywhere. It is a second showcase of a different kind from p2-11:
that one is a large sequential machine, this one is a concurrent runtime
expressed in concurrent hardware.

Three corrections to the idea as it was put:

1. The BEAM is not 650 lines. The 650 is `beam_emu.c`, a skeleton that includes
   some 60,000 generated lines and leans on 300,000 more. A usable subset VM
   for the P2 is about 5,000 to 8,000 lines of OctoGo plus a host tool of
   about 2,000 lines of Go. That is the size of p2-11, which took about two
   weeks to Unix V6 with its PASM core.
2. Eight cogs are eight BEAM schedulers, not a cap of seven Erlang processes.
   The one-actor-per-cog picture is the first demo's observable state, not the
   architecture (section 3).
3. A per-process garbage collector is not optional and not late: without it a
   server loop dies after a few thousand messages. It is small (a Cheney
   copying collector, a few hundred lines) and belongs to the second milestone.

## 2. Where the two seeds and this assessment agree

- The compiler is not written: `erlc` (and `elixirc`) produce the `.beam`
  files, and a host-side tool turns them into an image for the board, as
  AtomVM's `packbeam` does. Say "runs modules compiled by Erlang's own
  compiler", not "runs unmodified .beam files" (SEED2's qualification).
- Erlang first. Elixir compiles to the same opcodes but drags in `Enum`,
  `String` and friends, and its strings are binaries.
- No OTP standard library on the board. A small `erlang` BIF layer in OctoGo,
  a native `io:format` subset, and P2 BIFs for pins, timing and the serial
  line.
- AtomVM is the reference to read, not to port: it proves a subset BEAM runs
  on 264 KB (Raspberry Pi Pico) to 520 KB (ESP32) of RAM, and it has the
  design answers (terms, contexts, mailboxes, GC, the AVM image). Licence is
  Apache-2.0 OR LGPL-2.1-or-later; its `estdlib` (21,700 lines of Erlang,
  `lists.erl` 1,000, `gen_server.erl` 618, `io_lib.erl` 608) could be compiled
  and packed for the board later under Apache-2.0 terms, with its notices.
- The P2 fits: eight symmetric cores, one uniformly shared 512 KB hub RAM, no
  caches and so no coherency problem, 16 hardware locks, and XBYTE, a hardware
  bytecode dispatcher with 6 clocks of overhead (Chip Gracey's figure; the
  whole Spin2 interpreter is 3,564 bytes and runs from cog and LUT RAM).
- The demos write themselves: `pingpong.erl` with the two processes on two
  cogs; the process ring; a pin per cog toggled by the scheduler so a scope
  shows which core runs which actor.

## 3. Where they differ, and the call

**Architecture.** SEED2 wants A: one Erlang process per cog, at most seven,
no scheduler. SEED1 wants B: a scheduler per cog over a shared run queue,
hundreds of processes. The call is B, built so that A is what it looks like
at the first demo:

- B is Erlang; A is not. Every Erlang program of interest spawns freely (a
  ring, a supervisor, `lists:foreach(fun(_) -> spawn(...) end, ...)`), and a
  seventh `spawn` that panics makes an Erlang person wince where a seven-cog
  SMP VM on a $100 board makes them smile.
- B costs little over A. The synchronisation work is identical: a mailbox is
  many-producers-one-consumer in both, and `spawn` needs a lock in both. B
  adds a run queue, a reduction counter (BEAM counts calls, which the
  interpreter does anyway) and a context save of some forty words per switch,
  which happens every few thousand reductions or at an empty `receive`. A few
  hundred lines.
- With seven or fewer processes B behaves exactly as A: each scheduler holds
  its one process and never switches. The scope demo is the same.
- It keeps the two levels clean, which is the OctoGo story: OctoGo's
  concurrency is the hardware (`go scheduler()` seven times), Erlang's is the
  VM's. The tagline becomes "Eight cogs. Seven schedulers. One tiny BEAM.", and
  "eight actors" is the first picture of it.

**The GC.** SEED1 says the VM needs none, a dead process returning its block
in O(1). That is true of short-lived processes and false of every server
loop, which allocates a tuple per message. SEED2 says "later". It is milestone
2, with processes.

**How many processes.** SEED1's 500 to 1,500 is optimistic. The 512 KB holds
the VM's code as well (the P2 executes from hub RAM, where AtomVM's code sits
in flash), so some 300 to 350 KB remain for code image, atoms, process
control blocks and heaps. BEAM's default minimum heap is 233 words, 932 bytes
on a 32-bit VM; with a configurable minimum of 128 to 256 bytes a ring of
several hundred processes fits, a thousand only with the smallest heaps.

**Size of the VM.** SEED1's 2,500 to 4,000 lines of OctoGo buys the first
demos, not a VM people try their own modules on. AtomVM's core library is
65,000 lines (46,500 of code) for a broad subset. Plan for 5,000 to 8,000.

**XBYTE and PASM.** Both seeds say OctoGo first, XBYTE later. Agreed, and
p2-11 is the template: its OctoGo machine runs 130,000 to 180,000 PDP-11
instructions a second and its PASM core five times that. The host tool should
emit a fixed-width instruction format from the start (a byte of opcode, long
operands) so that a PASM core can read the same image later.

## 4. Facts established in this session

**The 650 lines.** `erts/emulator/beam/emu/beam_emu.c` on OTP master today is
778 lines, 494 of them code. It `#include`s `beam_hot.h`, `beam_warm.h` and
`beam_cold.h`, which `beam_makeops` generates from the `.tab` files, and calls
into the rest of `erts/emulator/beam/` for terms, GC, bignums, binaries and
BIFs. SEED1's account of this is right.

**The opcodes.** `lib/compiler/src/genop.tab` numbers 193 opcodes, 59 marked
obsolete, 134 live. Numbers 186 to 193 are the native records of the OTP 29
development branch; 184 and 185 are OTP 28's. Debian 13's `erlang-base` is
OTP 27.3.4.1, whose set ends at 183 (`executable_line`). Pin OTP 27, and have
the host tool refuse an opcode or a BIF it does not implement, by name. How
many a program needs is measured in milestone 0; the expectation is 30 to 40
for pingpong-class programs, about 50 with lists, funs and exceptions, and
well under 100 for anything the compiler emits today. **Measured, M0, the same
day:** over the eleven modules of `erl/` (1,486 instructions) the compiler
uses 63 distinct opcodes; `pingpong` alone 30, `fac` 20, `ring` 32, the
concurrent sieve 35, the server with references and timeouts 41. So version
1's subset is about sixty-five opcodes, not fifty; `erl/stats.txt` has the
counts and DESIGN.md section 6 what they add to the list below.

**AtomVM.** `src/libAtomVM`: 65,104 lines of C and headers, 46,515 of code;
`opcodesswitch.h` handles 142 opcode cases; SMP is on by default
(`AVM_DISABLE_SMP` off); platforms are generic Unix, ESP32, STM32, rp2 (Pico
and Pico 2) and Emscripten. A new context starts with a heap of 8 terms and
grows at GC. `exavmlib` carries the Elixir shims (`Enum`, `Access`, the
exceptions).

**Prior art on the P2.** None for Erlang. Dynamic languages have run there:
MicroPython under riscvp2, Eric Smith's RISC-V to P2 JIT, in 2020; Forth
(TAQOZ, in this board's flash); the Spin2 interpreter itself.

**OctoGo today** (v0.56.0, 1,810 commits, releases weekly): no heap; seven
goroutines plus `main`, each a cog; channels as rendezvous cells with
constant-size buffers; 16 locks through `p2.NewLock`, which cannot report
exhaustion; `unsafe.Pointer`, `Add`, `Slice`, `Sizeof`; Spin2 objects for
PASM on a cog; interfaces holding pointers only; `float64` is 32 bits; no
`recover` yet; a function's locals in a pool of 480 cog registers; a
goroutine's stack sized from the backend's listing, so a goroutine that
recurses needs `--gostack`. All of this is workable for a VM, and some of it
is a gift: the VM is its own allocator over package-level arrays, which is
what a no-heap language asks for anyway.

**What a call and a jump cost** (p2-11's measurements, 160 MHz, code in hub
RAM): a leaf call about 40 clocks, a call of a function that calls others
150 to 160 (it saves and restores every shared local), a hub read 25 to 37, a
write about 10, a taken jump 19 from hub and 4 from cog or LUT RAM.

**How OctoGo compiles a dispatch `switch`, measured here.** A 64-case
`switch` over a byte was built with `ogo build` and the listing read: the
emitter writes it as an `if / else if` chain in C, and the backend compiles
that chain as it stands, `cmp` and a taken jump for every case passed. Case
63 pays about 63 x 19 clocks before its body runs. The same switch written as
a C `switch` and given to the same backend (`scripts/flexcc`, at -O1 already)
compiles to `fle` + `jmprel` + a table of 64 jumps: two taken jumps whatever
the case. So the backend has O(1) dispatch and OctoGo's emitter withholds it.
Until that is changed, an OctoGo interpreter dispatches through an array of
function values (one indirect call, 40 to 155 clocks) or a two-level switch
with the hot opcodes first, p2-11's way. Emitting a dense constant `switch`
as a C `switch` is the first thing this project would give back to OctoGo.

**Expected speed.** An OctoGo interpreter at 300 to 600 clocks per BEAM
instruction is 250,000 to 500,000 instructions a second per cog at 160 MHz,
and the egg-beater hub gives each cog its own slot, so seven schedulers scale
nearly linearly until they meet a lock. A PASM core would multiply the per-cog
figure by three to ten, as p2-11's did by five. For the demos the OctoGo
figure is enough: a ring of 300 processes passing a token 10,000 times is a
few million instructions.

**Memory.** p2-11's binary is 385 KB, of which 248 KB is the PDP-11's memory
array; everything else, code, tables, stacks and screens, is about 130 KB. A
VM of 6,000 lines should come to 70 to 120 KB of code. Budget: VM 120 KB,
seven goroutine stacks about 20 KB, image of Erlang code and literals 20 to
60 KB, the rest heaps.

**Tools on this machine.** `ogo` is on PATH (v0.55.1 from the tree, go1.27).
There is no `erl`/`erlc`; `apt install erlang-base erlang-dev` (or the whole
`erlang`) gives OTP 27.

## 5. The shape of version 1

**Host tool, `obeam`, in Go.** Reads `.beam` files: the IFF chunks `AtU8`,
`Code`, `ImpT`, `ExpT`, `LitT` (zlib, then the external term format), `FunT`,
`StrT`; drops `Line`, `Dbgi`, `Docs`. Resolves atoms into one global table,
labels into offsets, imports into BIF numbers or code addresses; decodes the
compact term encoding of operands; keeps only the functions reachable from
the entry points (exports named on the command line and every `spawn`
target it can see); refuses an unsupported opcode or BIF with the module,
function and line; lays the literals out as a read-only heap in the board's
own term format, so the board decodes nothing; and writes the image, in
version 1 as a generated `image.ogo` (as p2-11's `mac/*.ogo` are generated
from MACRO-11), later as a file read from the SD card with p2-11's `sd` and
`fat` packages. Subcommands `dis` (a disassembler, also the milestone 0
histogram) and `run` (the host twin, below).

**Terms.** A term is a `uint32` with two tag bits: small integer (30 bits),
immediate (atom index, pid, nil, a port or ref later), list cell, boxed
(tuple, float, bigger integer, fun, binary), the pointer an index into the
arena. The arena is one or more package-level `[N]uint32` arrays; the VM
allocates blocks from it under a lock. Floats are the board's 32-bit floats;
integers beyond 30 bits are 64-bit boxed in version 1, no bignums.

**Processes.** A process control block table, a heap block per process with
the stack growing down and the heap up as in BEAM, Cheney GC per process into
a spare block, a mailbox of heap fragments appended under one of a few
striped locks (BEAM's own design for SMP: the sender never touches the
receiver's heap), a run queue under a lock, reductions, `receive` with
`after` by `p2.GetMs`. Each scheduler is a goroutine; a scheduler with
nothing to run polls the queue with a short wait.

**Opcodes for milestones 1 to 3**, about 50: `label`, `func_info`,
`int_code_end`, `call`, `call_last`, `call_only`, `call_ext`,
`call_ext_last`, `call_ext_only`, `bif0`, `bif1`, `bif2`, `gc_bif1`,
`gc_bif2`, `allocate`, `allocate_heap`, `deallocate`, `init_yregs`,
`test_heap`, `return`, `move`, `swap`, `jump`, `select_val`,
`select_tuple_arity`, `is_lt`, `is_ge`, `is_eq_exact`, `is_ne_exact`,
`is_eq`, `is_ne`, the `is_*` type tests, `is_tagged_tuple`, `test_arity`,
`get_list`, `get_hd`, `get_tl`, `put_list`, `put_tuple2`,
`get_tuple_element`, `set_tuple_element`, `send`, `loop_rec`,
`loop_rec_end`, `wait`, `wait_timeout`, `timeout`, `remove_message`,
`recv_marker_*` (as no-ops to begin with), `badmatch`, `case_end`,
`if_end`, `line` (dropped by the host tool). Milestone 4 adds funs
(`make_fun3`, `call_fun2`, `call_fun`), exceptions (`try`, `try_end`,
`try_case`, `catch`, `catch_end`, `raise`, `build_stacktrace`), floats
(`fmove`, `fconv`, `fadd` and so on) and `update_record`. Out of version 1:
bitstrings (`bs_*`), maps, bignums, on_load, tracing, hot code loading.

**BIFs**, about 30: `self`, `spawn/1,3`, `send`, `+ - * div rem band bor
bxor bsl bsr`, `abs`, the comparisons, `length`, `hd`, `tl`, `element`,
`setelement`, `tuple_size`, `is_*`, `integer_to_list`, `list_to_integer`,
`atom_to_list`, `make_ref`, `monotonic_time`, `error`, `exit`, `throw`,
`display`; `lists:reverse/2`, `lists:member/2`, `lists:keyfind/3`, which are
BIFs in BEAM too; `io:format` for `~w ~p ~s ~B ~n`; `p2:pin_high/1` and its
kin. Links and exit signals in milestone 4, with `process_flag(trap_exit)`.

**Tests.** The packages that do not import `p2` are Go once given a package
clause, as p2-11's are: the interpreter, the GC, the terms and the image
reader run under `go test` on the host. The oracle is OTP itself: a corpus
of modules is run under `erl` and under the twin, and the output must match,
as p2-11's processor is held to SimH. On the board, `ogo test` with the same
corpus, under the board lock `/tmp/p2-board.lock` that the ogo and p2-11
sessions share.

## 6. Milestones

| | What it shows | Mostly |
| --- | --- | --- |
| M0 | `obeam dis pingpong.beam`; an opcode and BIF histogram over a corpus of ten small modules; the term and image formats written down | host Go |
| M1 | one process on one cog: `fac`, `fib`, list recursion, printed on the serial line; the twin and the board agree with `erl` | the interpreter, terms, GC |
| M2 | processes on one scheduler cog: `spawn`, `!`, `receive ... after`; `pingpong`, the ring; failures reported as Erlang reports them | processes, mailboxes, scheduler |
| M3 | seven scheduler cogs; a pin per cog on a scope; the ring across cogs; measurements; the forum post | locks, the run queue, SMP |
| M4 | funs, exceptions, floats, links, timers, `io:format`, loading from the SD card, a gen_server-shaped demo without OTP | breadth |
| M5 | a PASM core for the hot opcodes, on p2-11's pattern, XBYTE if it pays | speed, optional |
| M6 | Elixir: hello and pingpong with shims after `exavmlib`; bitstrings | optional |

M0 to M3 is the showcase. At p2-11's cadence that is three to five weeks of
sessions, M4 two to three more; the estimate rests on the OctoGo compiler not
blocking, which p2-11's experience says it does not for long, the ogo session
being a directory away.

## 7. Risks

- **OctoGo's edges.** No recursion in a goroutine without `--gostack`, so
  term comparison, message copy and the GC are written with explicit stacks
  or in Cheney's iterative style (`errors.Is` is the precedent in the
  standard library); the 480-register pool, so the interpreter is a loop of
  modest locals and handlers are functions; dispatch is an indirect call or
  a two-level switch until the emitter learns the dense switch; 16 locks
  and no compare-and-swap, so the run queue, the allocator and a few mailbox
  stripes share them with the channel sites; `p2.NewLock` cannot report
  exhaustion, so count them.
- **Scope creep from Erlang's side.** Binaries and bitstrings are 25
  opcodes and a world; maps another; bignums another. Version 1 refuses them
  on the host with a clear message. Exceptions and funs are needed sooner
  than one thinks, since `try` appears in ordinary code.
- **The opcode set moves** with each OTP release. Pin OTP 27 and generate
  the opcode table from `genop.tab`.
- **Memory is one pool of 512 KB** for the VM's code too; the host tool
  prints the image's size and the board prints what it has left at start.
- **Honesty of the claims.** It runs modules compiled by `erlc`, a subset of
  the instruction set and of the `erlang` module, with 32-bit floats and no
  bignums; the README says so in its first screen, as DIFFERENCES.md does
  for OctoGo.
- **Time.** ogo is pre-1.0 with weekly releases and p2-11's phase 2 (screen
  and keyboard) is open. This is a third project for the same person and the
  same board. The milestones are cut so that each leaves something whole.

## 8. What OctoGo gets out of it

- A dense constant `switch` emitted as a C `switch`, so the backend's
  `jmprel` table applies (measured above; the largest single win for any
  interpreter in OctoGo).
- A `p2.CogID()` intrinsic (`_cogid`) for per-cog state, and possibly the
  cog-attention instructions for waking an idle scheduler.
- A second large program with a different shape: a heap-free language
  hosting a garbage-collected runtime, which exercises `unsafe`, slices of
  package arrays, locks and shared-memory rules in ways p2-11 does not.
- The `go` that reports a cog it could not start, already on ogo's list.

## 9. Housekeeping

- OTP 27 is installed on the host (`erlang`, 2026-10-16).
- Decide the licence (BSD-3-Clause as ogo and p2-11) and what, if anything,
  is taken from AtomVM (nothing for the VM itself; perhaps `estdlib` modules
  later, under Apache-2.0 with notices).

## Sources

- `beam_emu.c`, OTP master: https://raw.githubusercontent.com/erlang/otp/master/erts/emulator/beam/emu/beam_emu.c
- `genop.tab`, OTP master: https://raw.githubusercontent.com/erlang/otp/master/lib/compiler/src/genop.tab
- AtomVM: https://github.com/atomvm/AtomVM
- XBYTE, Chip Gracey's 6-clock figure and the Spin2 interpreter's size: https://forums.parallax.com/discussion/comment/1564876 and https://p2docs.github.io/xbyte.html
- riscvp2 and MicroPython on the P2: https://github.com/totalspectrum/riscvp2 and https://forums.parallax.com/discussion/170295/riscvp2-a-c-and-c-compiler-for-p2
- OctoGo: ../ogo (README.md, DIFFERENCES.md, CLAUDE.md); p2-11: ../p2-11 (DESIGN.md, OCTOGO.md)
