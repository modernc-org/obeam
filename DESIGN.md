# The design of obeam

obeam is a BEAM for the Propeller 2, written in OctoGo, that runs modules
Erlang's own compiler writes. This is how it is to be made: what runs where,
how a term, a process and the image are laid out, and why. ASSESSMENT.md says
why the project exists and in what order it is built; README.md what there is
and how to run it.

**Status: proposed at the end of milestone M0 and decided with the user on
2026-10-16; section 7 records the decisions.** Nothing below runs yet. What
M0 measured is in section 6 and in `erl/stats.txt`.

## 1. The pieces

Three things, two of them programs:

- **The host tool, `obeam`, in Go** (`cmd/obeam`, `internal/beam`). It reads
  `.beam` files and, as the packer, turns a set of them into an image for the
  board. Everything that can be decided before the board runs is decided
  here: atoms are numbered, labels and imports resolved, literals laid out in
  the board's own term format, unreachable functions dropped, and anything the
  board cannot run refused by name, with the module, function and line.
- **The board program, in OctoGo**, at the repository's root beside an
  `ogo.mod`, so that `ogo run` works after cloning, as p2-11 does. `main`
  starts a scheduler on each of seven cogs and then serves the serial line.
  The packages that do not import `p2` (the interpreter, the terms, the GC,
  the image reader) are Go once given a package clause, and are tested on the
  host under `go test` as p2-11's are, with OTP's own `erl` as the oracle.
- **The image**, what the packer writes and the board runs. In version 1 it is
  a generated OctoGo source file, `image.ogo`, compiled into the board program,
  as p2-11's `mac/*.ogo` are generated from MACRO-11; later a file on the SD
  card, read with p2-11's `sd` and `fat` packages, in the same layout.

The board decodes nothing: no IFF chunks, no compact term encoding, no external
term format, no zlib. That is what keeps the VM small, and what AtomVM's
`packbeam` does for the same reason.

## 2. Terms on the board

A term is a `uint32`. The low bits say what it is; a pointer is an index into
the arena, a package-level array of longs, not an address, so that the image's
literals can be laid out at pack time and nothing is relocated.

| Low bits | What | The rest of the word |
| --- | --- | --- |
| `00` | small integer | 30 bits, two's complement: -536870912 to 536870911 |
| `01` | a list cell | the index of its two longs, head then tail |
| `10` | a boxed term | the index of its header long |
| `011` | an immediate | bits 3-4 say which: `00` atom, index in bits 5-31; `01` pid, the process's index and generation; `10` nil, so that `[]` is the one value `0x13`; `11` reference, its number |
| `111` | a header, or a continuation on the stack | bits 3-5 the kind: tuple, float, integer of 64 bits, fun, binary; bits 6-31 the size in longs or the arity. On the stack, bits 3-31 a code offset |

Why so:

- A small integer with tag `00` adds, subtracts and compares as it is: the sum
  of two tagged integers is the tagged sum, and only multiplication shifts.
  That is the Lisp fixnum, not the BEAM's `1111`, and it is chosen because the
  interpreter in OctoGo pays for every instruction.
- A header can never be mistaken for a term, and no term for a header, which
  is what lets the collector walk a heap word by word: a word ending in `111`
  begins a boxed object whose header says how long it is and whether its
  payload is terms (a tuple, a fun's environment) or bytes (a float, a binary);
  any other word is a term, a list cell being two of them with no header.
- A continuation pointer on the stack ends in `111` too, so the collector
  skips it, the stack holding nothing else that is not a term.
- `[]` is one bit pattern, tested with one compare, and `is_list` is two.
- A pid is the process's index in the table, 8 bits, beside a generation of
  19 bits that a slot counts up each time it is reused: a message to a dead
  process is dropped, as in Erlang, and one to a reused slot is dropped too,
  not misdelivered.

Floats are the board's 32-bit floats, boxed, with one long of payload (a
documented difference from Erlang, as OctoGo's `float64` is from Go's).
Integers outside 30 bits are boxed 64-bit integers, and there are no bignums:
the packer refuses a literal beyond 64 bits and the BIFs raise `system_limit`
on overflow. Binaries are heap binaries, copied with the message they are in,
with no reference counting; a literal binary lives in the image.

## 3. Processes

**A process** is an entry of a fixed table, its control block: its state, its
heap block, its heap top, its stack top, its continuation, its saved X
registers while it is not running, its mailbox, its reductions left, its links
later. The table has 256 entries, a build-time constant, and `spawn` fails
with `system_limit` past them.

**The heap** is a block of the arena, a package-level array of 49,152 longs
(192 KB) to begin with, a build-time constant to raise once the VM's own size
is known. The arena is managed as buddy blocks of 8 to 8,192 longs by powers
of two: eleven free lists, a block split on allocation and joined with its
buddy when freed. A process begins with 64 longs, its heap growing up from
the block's start and its stack down from the end, as in the BEAM, so that
`test_heap` and `allocate` are one compare between the two tops. When they
meet, the process is collected: a Cheney copy of what its registers, stack
and mailbox reach into a fresh block, the next size up where the live data
needs it, and the old block goes back to the pool. The largest block, 8,192
longs, is the most a process can have; one that needs more exits with
`system_limit`. There is no generational collector and no shared heap; a
process that dies returns its block, which is most of what Erlang programs
do with memory.

**A message** is copied by the sender into a fragment, the smallest block
of the pool that holds the term and a link, and the fragment is appended to the
receiver's mailbox under one of a few locks, striped by the receiver's index.
The receiver's `loop_rec` reads fragments in place; `remove_message` unlinks
one; and the next collection copies what live fragments hold into the heap and
frees them. That is the BEAM's own SMP design, and it means a sender never
touches a receiver's heap.

**A scheduler** is a goroutine, so a cog. It takes a process off the run
queue, loads the process's X registers into cog RAM, and interprets until the
process has used its reductions (2,000, a reduction being a call, as the BEAM
counts them), waits in `receive` with nothing to take, or ends; then it saves
the registers and takes the next. A scheduler with nothing to run polls the
queue with a short wait. Seven schedulers and `main`, which loads the image,
starts them and serves the serial line, are the eight cogs. With seven or
fewer processes alive each scheduler holds its one process and never switches,
which is the one-actor-per-cog demo.

**Locks.** The P2 has sixteen and no compare-and-swap, and OctoGo's channel
sites take up to eight of them. The VM takes six: the run queue, the block
pool, and four stripes of mailboxes. Every other shared variable is written by
one cog only, as p2-11's are.

**What the interpreter cannot do** in OctoGo: recurse in a goroutine without a
`--gostack` bound, so term comparison and message copying are written with an
explicit stack in the process's heap block, and the collector is Cheney's,
which never recurses; and spend more than 480 cog registers in one function,
so the interpreter is a loop of few locals and the handlers are functions.
Dispatch is through an array of function values until OctoGo emits a dense
constant `switch` as a C `switch`, when the backend's `jmprel` table takes
over (ASSESSMENT.md, section 4).

## 4. The image

Little-endian longs, in sections, every section long-aligned:

1. **Header**: a magic, a version, the size of each section, the entry point
   (module, function, arity) and the counts.
2. **Atoms**: the names, for printing and `atom_to_list`, numbered as the
   board's atom terms number them. The packer merges every module's atom
   table into one.
3. **Code**: one stream for all modules, fixed-width: an opcode byte, then
   one long per operand, a list operand as a count and its elements. The
   layout is XBYTE's, so that a PASM core can read the same stream later. The
   operands are resolved: a register is its number, an atom or a small
   integer the term itself, a label the absolute offset of its code, a
   literal the term that points into the literal heap, an import either a BIF
   number or the code offset of a function in the image, which the packer
   tells apart by emitting a different opcode. A source operand that may be a
   register or a term carries the register as a marker word ending in `111`,
   which no term ends in, so that a handler tests three bits to know; the
   packer may later specialise the common shapes instead, as the BEAM's
   loader does.
4. **Literals**: a read-only heap in the board's term format, placed at the
   start of the arena, so that every pointer in it is an absolute index and
   nothing moves. In the generated `image.ogo` it is the arena's initializer.
5. **Exports**: module, function, arity and code offset, for `spawn/3` and
   `apply/3`, sorted for a binary search.
6. **Funs**: what `make_fun3` indexes: code offset, arity, number of free
   variables.

The packer keeps only what the entry point, the exports named on the command
line and every `spawn/3` and `apply/3` target it can see reach. It drops the
`line` instructions from the stream and keeps their locations in a seventh
section, a table of code offset to file and line that is searched only when
a crash is printed, so that the board says what Erlang says, `exception
error: badarith in function fib:fib/1 (fib.erl, line 9)`, at no cost to a
program that does not crash; `-lines=none` leaves the table out of a tight
image. It refuses, by name and place: an opcode the VM does
not implement, an external call to a function neither a BIF nor in the image,
a literal the board cannot hold, and the bit syntax, maps and bignums until
they are done.

## 5. What runs where

| | Host, Go | Board, OctoGo |
| --- | --- | --- |
| read `.beam` | `internal/beam` | |
| resolve, drop, lay out, refuse | the packer | |
| interpret, schedule, collect | the twin, for the tests | the VM |
| BIFs, `io:format`, pins, timing | the twin's stubs | `p2` |
| the oracle | OTP's `erl` and `beam_disasm` | |

## 6. What M0 measured

Eleven modules in `erl/`, 1,486 instructions, compiled by OTP 27.3.4.1:
63 distinct opcodes of the 139 live ones, and the external calls they make
(`erl/stats.txt` has the counts). By module, the distinct opcodes run from 11
(`tuples`) to 41 (`counter`, a server with calls, casts, references and
timeouts); `fac` uses 20, `pingpong` 30, `ring` 32, the concurrent sieve 35,
`exc` 33. What a demo-sized program is made of, then: `move`, `label`, `line`
and `func_info` are half of all instructions; the calls and returns,
`test_heap`, `put_list`, `allocate` and `deallocate` another quarter. What
the measurement adds to ASSESSMENT.md's list for version 1, whose fifty
opcodes come to about sixty-five:

- `trim`, `swap` and `init_yregs` are everywhere the compiler saves a frame
  word, and `is_tagged_tuple` wherever a tuple is matched by its first element.
- `recv_marker_bind`, `_clear`, `_reserve` and `_use` come with a `receive`
  that waits for a fresh reference; the VM may treat them as no-ops, which
  only costs the mailbox scan they shortcut.
- `make_fun3`, `call_fun2` and `call_fun` appear as soon as a `spawn` takes a
  fun, which is most spawns; funs are milestone 2, not 4.
- `select_val`, `select_tuple_arity` and `test_arity` carry every `case`
  with more than two clauses.
- Of the BIFs: `io:format/2` is in ten modules of eleven, the arithmetic
  operators (`+`, `-`, `*`, `div`, `rem`) through `gc_bif2`, `self/0`,
  `spawn/1` and `spawn/3`, `make_ref/0`, `++`, `=:=`, `length/1`,
  `integer_to_list/1`, `is_list/1`, `error/1`, `exit/1`, `throw/1`,
  `lists:member/2` and `lists:reverse/1`; and the `get_module_info` pair that
  every module's `module_info` stubs call, which the packer drops.
- `exc` alone reaches `try`, `try_case`, `try_end`, `catch`, `catch_end`,
  `raise`, `build_stacktrace`, `badmatch` and `case_end`: exceptions are a
  milestone of their own, M4, as planned.

## 7. Decided, 2026-10-16

Proposed at the end of M0 and decided with the user the same day, each with
what the alternative was:

- **Small integers are tagged `00`**, the Lisp fixnum, not the BEAM's `1111`:
  the interpreter pays for every instruction, and 30 bits hold what the demos
  compute. The layout is section 2's and is not meant to look like the BEAM's.
- **256 processes, pids with a generation, buddy blocks of 8 to 8,192
  longs**, a process beginning with 64 of them, in an arena of 192 KB to begin
  with (section 3). Not a fixed 2 KB a process, which the ring of 100 would
  outgrow, and not 512 processes over 256 KB before the VM's own size is
  known.
- **Line numbers ride on the board**, in a side table the packer writes and
  `-lines=none` leaves out (section 4), rather than on the host only: a crash
  prints the file and the line as Erlang does.
- **The board's hardware API is the module `p2`**, mirroring OctoGo's `p2`
  package name for name in snake_case, with the same arities and argument
  order, so that the two documentations mirror each other. AtomVM's `gpio`
  spelling may come later as a module written in Erlang over it, if anyone
  wants `blink.erl` to run on an ESP32 unchanged. The names:

| Erlang | OctoGo | |
| --- | --- | --- |
| `p2:pin_high(Pin)`, `pin_low/1`, `pin_toggle/1`, `pin_float/1` | `PinHigh`, `PinLow`, `PinToggle`, `PinFloat` | drive a pin |
| `p2:pin_in(Pin)` | `PinIn` | read a pin, 0 or 1 |
| `p2:pin_write(Pin, V)` | `PinWrite` | |
| `p2:pin_start(Pin, Mode, X, Y)`, `write_pin_mode/2`, `write_pin_x/2`, `write_pin_y/2`, `read_pin/1`, `ack_pin/1` | `PinStart`, `WritePinMode`, `WritePinX`, `WritePinY`, `ReadPin`, `AckPin` | smart pins |
| `p2:get_ct()`, `clock_freq/0` | `GetCt`, `ClockFreq` | the cycle counter and the clock |
| `p2:rnd()`, `rev/1`, `reboot/0` | `Rnd`, `Rev`, `Reboot` | |
| `p2:cog()` | | the cog the calling process runs on, which its next switch may change |

A mode is an integer, or a list of atoms named after OctoGo's constants in
snake_case (`dac_990r_3v`, `output_enable`), which the BIF ORs together.
There is no `wait_ms`: an Erlang process waits with `receive after`, which
lets its scheduler run others; and no `get_ms`: the time is
`erlang:monotonic_time(millisecond)`. The serial line is `io`'s. The LUT,
the locks and the baud rate are the VM's own and out of reach.
