# The design of obeam

obeam is a BEAM for the Propeller 2, written in OctoGo, that runs modules
Erlang's own compiler writes. This is how it is to be made: what runs where,
how a term, a process and the image are laid out, and why. ASSESSMENT.md says
why the project exists and in what order it is built; README.md what there is
and how to run it.

**Status: proposed at the end of milestone M0 and decided with the user on
2026-10-16; section 7 records the decisions. M1, one process on one cog, M2,
processes and messages on that cog, M3, seven scheduler cogs, and M4,
exceptions caught, links and monitors, floats and the rest of io:format, were
built the same evening and night, then M5, speed, and M6a, Elixir: sections
3 and 4 say where what is built differs from what was proposed.** What M0
measured is in section 6 and in `erl/stats.txt`; what M1 to M6a measured is
in section 8.

## 1. The pieces

Three things, two of them programs:

- **The host tool, `obeam`, in Go** (the repository's root, `internal/beam`,
  `internal/pack`, `internal/vmbin`). It reads
  `.beam` files and, as the packer, turns a set of them into an image for the
  board. Everything that can be decided before the board runs is decided
  here: atoms are numbered, labels and imports resolved, literals laid out in
  the board's own term format, unreachable functions dropped, and anything the
  board cannot run refused by name, with the module, function and line.
- **The board program, in OctoGo**, in `board/`, under the `ogo.mod` at the
  repository's root (at the root itself, as p2-11's is, until the Go command
  took the root on 2026-10-17). `main` starts a scheduler on each of seven
  cogs and then serves the pins. Users never build it: `obeam` carries it
  built, checked and unchecked.
  The packages that do not import `p2` (the interpreter, the terms, the GC,
  the image reader) are Go once given a package clause, and are tested on the
  host under `go test` as p2-11's are, with OTP's own `erl` as the oracle.
- **The image**, what the packer writes and the board runs. It is the bottom
  of the VM's arena: the VM is built once, its arena marked, and `obeam pack
  -vm` writes the image over the mark in a copy of the VM's binary, so that a
  program is packed in milliseconds and no OctoGo build is needed for it.
  Until 2026-10-17 it was a generated OctoGo source file, `image.ogo`,
  compiled into the board program, as p2-11's `mac/*.ogo` are generated from
  MACRO-11. Later it is also a file on the SD card, read with p2-11's `sd`
  and `fat` packages into the same place.

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
| `111` | a header, or a continuation on the stack | bits 3-5 the kind: tuple, float, integer of 64 bits, fun, binary, map, a non-value, a binary's match context; bits 6-31 the size in longs or the arity. On the stack, bits 3-31 a code offset |

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

A map (M6b) is a header of kind 5 and its keys in map-key order, the order of
terms with every integer before every float, then their values in the same
order, the size twice the pairs: the collector and the copier pass over it as
over a tuple, and Erlang's order of maps, by size, then keys, then values, is
the comparison of tuples as it is. A key is found by a binary search, and a
change makes a new map, of any size; OTP keeps a map of more than 32 keys in a
hash trie, and orders its atom keys by its atom table, neither of which this
does. A binary's match context is kind 7, the binary and an offset in bits.
The non-values, a failing BIF's answer, `apply`'s two and the collector's mark
on a moved list cell, are kind 6, told apart by their size.

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

**As built in M1** (`vm/`, one scheduler, which is `main`'s cog): a frame is
the continuation, a word ending in `111` with the code offset above, and the
y registers above it, `allocate` zeroing them so that the collector never
reads a word that is not a term; `trim` moves the continuation up. The arena
is 49,152 longs, its free blocks holding their list links and their order in
their first three longs beside a bitmap of where free blocks begin, so that a
freed block finds its buddy in a few reads. A BIF takes its arguments from a
small array of the scheduler's, `bargs`, which is a root of the collection
with the live X registers; one that allocates asks `ensure` for the room and
reads its arguments again after, a collection having perhaps moved them; and
one that fails says so by its result, the handler going to the fail label or
raising. The comparison of terms and the writing of terms keep the parts
still to do on stacks of their own, sixty-four deep.

**As built in M2**, still on one scheduler: a process's turn ends at the
call that spends its last reduction, 2,000 a turn, where its arguments are
the live X registers and are saved in its table entry, sixteen at most,
which is why the packer refuses a function of more arguments; and at a
`receive` that finds no message, where nothing is live. The run queue is a
list through the table. `send` copies the message into a fragment of the
pool, sharing the literals and nothing else, and appends it to the receiver's
mailbox; the receive instructions walk the mailbox from where the last
receive stopped, `remove_message` moves the message's fragment to the
process's pending list, and the next collection, which the fourth pending
fragment forces, treats the pending fragments as from-space, copies what is
live out of them and frees them, so that a term read out of a message is
never copied twice and never dangles. `wait_timeout` records a deadline in
milliseconds from the `Millis` hook; the scheduler wakes the processes whose
time has passed before each turn and, with nothing to run, spins until the
earliest. A fun is local, an external function's or a BIF's, which its second
long says; `apply` by name finds the function in the image's table, puts the
arguments in the X registers and has the handler jump, or calls the BIF.

**As built in M3**, seven schedulers, each a goroutine, so a cog, started by
`Start` and stopped when the entry process ends. Everything a scheduler
keeps of its own, the process it runs, the X registers, a BIF's arguments
and verdict, the collector's and the copier's pointers, the stacks of
comparing and writing, the format buffer and its counts, is a `sched`
struct, one per scheduler in a package array, and every function that
touches one is given it as its first argument: OctoGo has no storage that is
one cog's, and threading the pointer costs a register a call and makes the
same code Go. The locks come through hooks, the board's `p2.NewLock`,
`TryLock` and `Unlock`, the host's mutexes, so that the twin runs the same
synchronization. There are eight: the pool, the run queue, the table's free
slots, the output, and four stripes of mailboxes, a process's by its index.
A process's state is written under its stripe only, by whoever writes it, so
that a sender that finds it waiting may make it runnable and queue it, and
the owner, about to wait, looks once more under the lock for a message that
came since the receive looked, which is what keeps a wakeup from being lost.
A timed wait puts the process on a list under the run queue's lock, which
every scheduler walks before a turn; an entry that no longer stands for a
timed wait is dropped there. A turn ends by `yield`, `sleep` or `raise`,
each saying so in the scheduler, so that `run` reads no state a sender may be
writing. The order the locks are taken in, where two are held: a stripe,
then the run queue or the pool; nothing holds the run queue while taking a
stripe. A process that ends frees its slot. `p2:cog/0` answers the
scheduler's number, 0 to 6, the cog's own being nothing OctoGo tells. And
since what several cogs drive on a pin is the OR of it, the scheduler cogs
drive no pin: `main.ogo` posts their pin BIFs to a ring under a lock of its
own and does them on main's cog, which has nothing else to do, a read
waiting for its answer. Go's race detector, run on the twin, found the
three unsynchronized reads the first version had and finds none now.

**As built in M4.** An exception unwinds the stack to the innermost catch
tag, a word ending in `1111` with the handler's offset above it, in a y
register of the frame that holds it, beside the continuations, which end in
`0111`; the handler gets the class, the reason and the raw stacktrace in x1
to x3, the non-value in x0, as BEAM's does. The raw stacktrace is {Class,
[Offset, ...]}, the code offsets of the frames, eight at most, built into
Erlang's list of {M, F, A, [{file, F}, {line, L}]} only by `build_stacktrace`
and `catch`, and a return clears the continuation register, which a crash
otherwise took for a frame. A process ends with an exit reason, {Reason,
Stacktrace} of an error, which goes as the signal {'EXIT', Pid, Reason} to
each of its links, eight at most, and as {'DOWN', Ref, process, Pid, Reason}
to each monitor on it; a signal is a message fragment of a kind of its own,
read by the receiver when its turn begins and when it receives: a message to
a process that traps exits, dropped when the reason is normal, fatal
otherwise, `kill` to `killed`. Erlang logs a crash of a spawned process and
not an exit; the report here is printed for errors and throws, and for the
entry process, which has the shell's part, for exits too. Registered names
are a table of sixteen under the table's lock, and a send to an atom looks
there. Floats are the board's 32-bit floats. `~w` writes
the fewest digits that read back as the same float, in the shorter of the
plain and the exponent form, the plain one on a tie, which is Erlang's rule
(1000.0 is `1.0e3`, 65536.0 is `65536.0`). The digits are found by the
free-format algorithm of Steele and White as Burger and Dybvig give it, in
exact integers of 224 bits, a tie in the last digit going to the even one;
`TestShortest` holds it to Go's `strconv` on a hundred thousand floats. A
first version scaled the float by tens in OctoGo's `float64`, which is 32
bits on the board: the twin agreed with `erl` and the board printed
`0.0010000002` for `0.001`. A directive of `io:format` with a width is written into the
scheduler's capture buffer first and padded from there; `~p` does not break a
long term over lines as Erlang's does. A timed wait is one entry of the
timer list, and the verdict on an entry and its removal are one step under
the process's stripe: two walkers at once could otherwise remove a valid
entry on a stale verdict, which the race detector did not see and a hang of
one run in ten did. Of the same kind, found the same way: a process that
ends is dead to a linker or a monitor from the locked step that takes the
links and monitors it has, not from when its slot is freed, or a monitor set
in between is never answered. What M4 left for later: loading an image from the SD
card, which wants the VM's atom names as bytes rather than OctoGo strings,
since a string cannot be made from bytes at run time; `~p`'s line breaking;
`demonitor` with `flush`; `spawn_opt`; bignums.

**The arena is 128 KB at the end of M4**, not the 192 KB section 7 decided
on, and a process has four links and four monitors at most, not eight. M4's
code did not fit beside 192 KB: the checked build was 551,088 bytes with a
160 KB arena, over the hub by 26,800. Once the float digits were found in
integers the checked build fell by 53 KB, and 128 KB fits: 464,452 bytes
checked and 419,800 unchecked, with main's stack of 12 KB beside them.
What gives more room back is a leaner VM, which is M5's question: the
runtime checks of a checked build, a nil test at every field and a bounds
test at every index, are a large part of the code, and the hot instructions
in PASM would take their handlers out of it. With 128 KB, four blocks of
8,192 longs are the largest allocations, and the ring of a hundred has its
room. A forced collection after four pending messages, not sixteen, is what
lets it: a hundred processes each holding fifteen fragments ran a 96 KB
arena dry, which the twin's dump showed.

**An image carries the fingerprint of the tables it was packed for**,
`TableID`, a hash of the well-known atoms and of the BIFs in their order,
which `obeam gen` writes into the VM and `obeam pack` into the image, and
`main.ogo` refuses an image whose fingerprint is not the VM's. Without it a
change to the BIF table and a forgotten `make image` made the board call
BIFs by numbers that were no longer theirs: `io:format` answered `badarg`
on the board while the twin, which packs in memory, passed.

**What the interpreter cannot do** in OctoGo: recurse in a goroutine without a
`--gostack` bound, so term comparison and message copying are written with an
explicit stack in the process's heap block, and the collector is Cheney's,
which never recurses; and spend more than 480 cog registers in one function,
so the interpreter is a loop of few locals and the handlers are functions.
Dispatch is through an array of function values until OctoGo emits a dense
constant `switch` as a C `switch`, when the backend's `jmprel` table takes
over (ASSESSMENT.md, section 4).

**As built in M5, the OctoGo part.** A handler that calls anything is no leaf,
and the backend saves all its registers on the way in and restores them on
the way out, some 150 clocks, more than most instructions' work. So the hot
instructions have handlers in `vm/fast.ogo` that call nothing, the operand
decoding written out in each: `move`, `swap`, the list and tuple accessors,
the type tests, the comparisons and `select_val` on what is no structure,
the calls while reductions last, `allocate` and `test_heap` while there is
room, and `gc_bif2` for `+`, `-`, `*`, `div` and `rem` of small integers in
32 bits, where the BIF had computed in software 64-bit arithmetic at 5,600
clocks. Where a fast handler meets what is not its case it answers
`slowPath` before it changes anything, and the loop calls the general
handler, kept in `slow`. The VM takes the P2's locks and clocks through
OctoGo's `p2` package, whose `TryLock` is one instruction: through hooks a
lock and its unlock cost 616 clocks, now 107. A collection sizes its new
block by the heap and by what pending messages hold, the size kept in each
fragment's header, not by their blocks, and shrinks the block to twice what
lives afterwards, halving it and moving the stack down while that fits: a
block only grew before, and a hundred processes of a ring held 256 longs
each for a few that lived. A collection is forced after sixteen pending
messages again, or at once when a message to the process found the pool
below a quarter free. A cache of free fragment blocks per scheduler was tried
and taken out: the blocks it held, scattered through the arena, kept their
buddies from joining, and a pool three quarters free had no block above 256
longs; `vm.Dump()`, now with the pool's free lists and the last request it
failed, showed it.

**Changed before M6b, for room** (section 8): a process's saved X registers
are on its own stack between turns, and its links and monitors are records
of a pool shared by all, a list a process; the VM calls no function value
but the handlers and the BIFs, so that ogo's bound on a goroutine's stack is
not a sum over every BIF; and the arena is 192 KB, 160 since M6b.

## 4. The image

Little-endian longs, in sections, every section long-aligned, at the bottom
of the arena, where the VM reads it in place (`internal/pack/region.go` is
the layout, `Load` in `vm/vm.ogo` the reader):

1. **Header**: 24 longs, a magic, the `TableID` the image was packed for
   (which fingerprints the layout too), the image's length, the entry point
   (its code offset, module, function and arity), and where each section
   begins and how long it is.
2. **Atoms**: the names, for printing and `atom_to_list`, numbered as the
   board's atom terms number them. The packer merges every module's atom
   table into one. An atom is a long, the byte offset of its name in the
   arena above 10 bits and its length below, and the names' bytes follow
   the tables, as the files' names do: OctoGo has no string made of bytes
   at run time, so the VM reads a name byte by byte.
3. **Code**: one stream for all modules, fixed-width: one long for the
   opcode, in its low byte, then one long per operand, a list operand as a
   count and its elements. (The proposal had an opcode byte; a long is what
   an interpreter in OctoGo indexes, and a PASM core reads a long as cheaply.)
   The operands are resolved: a count or an arity is the number itself; a
   label is the absolute offset of its code, 0 for none; an atom, a small
   integer or a character is the term itself; an integer past 30 bits and
   every other literal is the term that points into the literal heap; and a
   register is a marker word ending in `0111` for x and `1111` for y with
   its number above, which no term ends in, so that a handler reading a
   source operand tests three bits to know, and one writing a destination
   tests one; the packer may later specialise the common shapes instead, as
   the BEAM's loader does. What the packer rewrites: `call_ext` and its kin
   to `call`, `call_last` and `call_only` when the import is a function of
   the image, and to `call_bif`, the VM's own instruction, followed by the
   `deallocate` and `return` the kin stood for, when it is a BIF; the import
   operand of `bif0`, `bif1`, `bif2` and the `gc_bif`s to the BIF's number;
   `make_fun3`'s index to the image's fun table; `func_info` kept, with its
   atoms, as where a call lands when no clause matched; `label` and `line`
   to nothing. `Code[0]` is `halt`, so that no code is at offset 0 and a
   continuation of 0 ends a process.
4. **Literals**: a read-only heap in the board's term format, right after
   the header, so that every pointer in it is an absolute index of the arena
   and nothing moves or is copied.
5. **Exports**: module, function, arity and code offset, for `spawn/3` and
   `apply/3`, sorted for a binary search.
6. **Funs**: what `make_fun3` indexes: code offset, arity, number of free
   variables.

The packer keeps the entry, every export but `module_info`, and what they
reach through local calls, funs and calls into the modules of the image (the
proposal had it keep only what the entry and the `spawn` targets reach, which
would need the packer to read the module and function out of the registers a
`spawn/3` is given; every export is simpler and is the module's public face
anyway). It drops the `line` instructions from the stream and keeps their
locations in a seventh section, a table of code offset to file and line that
is searched only when a crash is printed, so that the board says what Erlang
says, `** exception error: an error occurred when evaluating an arithmetic
expression` and `in function fib:fib/1 (fib.erl, line 9)`, at no cost to a
program that does not crash; `-lines=false` leaves the table out of a tight
image. It refuses, by name and place: an opcode the VM does
not implement, an external call to a function neither a BIF nor in the image,
a literal the board cannot hold, and the bit syntax, maps and bignums until
they are done.

A VM binary's arena begins with a mark: four longs found nowhere else in the
binary, then the arena's length and the VM's `TableID`, the initializer of
`arena` in `vm/arena.ogo`, which flexspin places in the binary as data with
the arena's zeros after it. `obeam pack -vm` finds the mark, refuses a VM of
other tables or too small an arena, and writes the image over it; `Load`
finds the image's magic where the mark was, or reports that there is no
image. The heaps take the arena from the image's end, rounded up to the
smallest block, and the more a program leaves of the arena the more its
processes have.

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
  known. (The VM's size, once known, took the arena down to 128 KB in M4;
  section 3 says why.)
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

## 8. What M1 built and measured

Built on 2026-10-16, the evening of the decision: `cmd/obeam pack` and
`internal/pack`, which write `image/image.ogo` (and the same image in memory
for the tests); `vm/`, about 2,300 lines of OctoGo, Go once given a package
clause: terms, the arena, processes, the interpreter with 58 instructions,
the collector, 79 BIFs, comparison, `io:format` and the exception reports;
`main.ogo`, the board program; `scripts/twin.sh`, after p2-11's, which runs
`vm/` under Go with `GOARCH=386`; and `vm/host_test.go`, under the build tag
`twin`, which packs `fac`, `fib`, `lst` and `tuples`, runs them, and holds
their output to what `erl` prints for the same module, byte for byte. All
four agree. `ogo build ./vm` checked the package on its first build; the
Go twin found nothing the checker had not.

On the board, a P2-EC, the image of `demo` (1,177 longs of code, 136 of
literals, 63 atoms, 25 functions) printing what `erl` prints for the four
modules, line for line; the binary 322,048 bytes checked and 295,948
unchecked, 196,608 of them the arena:

| Build | 176,700 instructions in | Instructions a second |
| --- | --- | --- |
| checked, 160 MHz | 1,238 ms | 142,730 |
| `--unchecked`, 160 MHz | 910 ms | 194,175 |
| `--unchecked --clock 200MHz` | 729 ms | 242,386 |

That is about 1,100 clocks an instruction checked and 820 unchecked, two to
three times the 300 to 600 ASSESSMENT.md expected of an interpreter in
OctoGo, and with nothing yet measured as to where they go: every handler is
a call through a function value (40 to 155 clocks, section 3), the X
registers and the frame are in hub RAM (25 to 37 clocks a read), and a
checked build tests every index. Where the time goes is M5's question, with
p2-11's `prof/` as the method; the figures here are the baseline it starts
from. For the demos they are enough: the four modules together run in just
over a second.

**M2**, the same night: `vm/proc.ogo` and `vm/message.ogo` and the handlers
of `send` and the six receive instructions, and `spawn/1`, `spawn/3`,
`send/2`, `apply/2`, `apply/3` and `is_process_alive/1` among the BIFs, now
85. The twin holds nine modules to `erl`: the four of M1 and `funs`,
`pingpong`, `ring` (100 processes, a token 10,000 hops around them), `sieve`
(27 processes in a chain) and `counter` (a server, references, two
timeouts). All nine agree, and so does the board, line for line, with the
image of `demo` now 2,912 longs of code and 60 functions:

| Build | 351,393 instructions in | Instructions a second |
| --- | --- | --- |
| checked, 160 MHz | 4,552 ms | 77,195 |
| `--unchecked`, 160 MHz | 3,751 ms | 93,679 |

Of the time, 1,010 ms are `counter`'s two waits, in which nothing runs; the
rest is about 99,000 instructions a second checked and 128,000 unchecked,
below M1's figure because a `send` copies and allocates and a `receive`
walks the mailbox, which an instruction count does not show. The OctoGo
checker took M2 as it took M1; Go found one thing OctoGo allows, the BIF
table's initializer reaching `apply`, which reaches the table, so the table
is filled in `init`.

**M3**, the same night: the `sched` struct and its threading through every
handler and BIF, the locks, the timer list, the pin ring in `main.ogo`, and
`erl/cogs.erl`, seven workers that each count to 20,000 in tail calls and
report which scheduler ran them last. The twin runs the nine modules on
seven goroutines under mutexes and holds them to `erl` as before, five runs
in a row and twice under the race detector. On the board, the image of
`demo` with `cogs` added, 3,240 longs of code, on seven scheduler cogs:

| Build, 160 MHz | 912,500 instructions in | a second |
| --- | --- | --- |
| checked, 7 schedulers | 4,949 ms | 184,387 |
| `--unchecked`, 7 schedulers | 4,031 ms | 226,391 |
| `--unchecked`, 1 scheduler, the same image | 7,744 ms | 117,774 |

Seven cogs run the demo in half the time of one, 2.2 times faster once
`counter`'s 1,010 ms of waiting are taken out of both; most of the demo is
one process at a time, and only `cogs`' seven workers and the ring's and the
sieve's processes have anything to run beside each other. The single
scheduler's 117,774 a second is below M2's 128,000 by the locks, which it
takes as the seven do.

`cogs` printed `[{1,20000,3},{2,20000,4},{3,20000,3},{4,20000,6},{5,20000,1},{6,20000,1},{7,20000,6}]`
on one run and a different spread on the next: the seven workers on four or
five of the seven schedulers at a time, which is the picture the project was
started for. The count of instructions varies by a few dozen from run to run,
a receive that looks and finds nothing costing an instruction or two more or
less. 604 collections.

**M4**, the same night: `vm/except.ogo` rewritten for catching,
`vm/link.ogo`, `vm/float.ogo`, `vm/format.ogo` rewritten for widths, and
`vm/debug.ogo`, a dump of the process table that found the timer list's
race. The corpus grew by `exc`, `links`, `flt` and `fmt`, thirteen modules
the twin holds to `erl`, on seven goroutines, clean under the race detector
in four rounds of all of them and twenty-five of the process-heavy ones. The
BIFs are 105. On the board the demo runs all thirteen and then `cogs`, and the
59 lines before `cogs` are byte for byte what `erl` prints for the same
modules, in both builds:

| Build, 160 MHz, 7 schedulers | 913,200 instructions in | a second |
| --- | --- | --- |
| checked | 5,662 ms | 161,299 |
| `--unchecked` | 4,357 ms | 209,592 |

With 2,515 collections, against 604 in M3: four pending messages force one
where sixteen did. The demo's waits are about 1,050 ms of it.

**M5, the OctoGo part**, the same night: `make prof` builds `prof/`, a board
program that runs `erl/bench.erl`, a workload of the corpus's modules with
one line of output, on one scheduler, first plainly and then with every
instruction timed by the cycle counter, by opcode and by BIF. It found, in
this order: that a call into any handler costs more than the work of most;
that a lock taken through a hook cost 616 clocks; that 519 of 527
collections were forced by pending messages; and a fault, a process whose
block was the largest failing with `system_limit` because the collector
asked for a block larger than the largest. The workload, unchecked at 160 MHz
on one scheduler, in clocks an instruction:

| | Clocks an instruction |
| --- | --- |
| at the end of M4 | 1,267 |
| leaf fast handlers | 908 |
| the locks through `p2` | 808 |
| the collections sized by what lives | 809 |

And the demo on seven schedulers, both builds still printing what `erl`
prints line for line:

| Build, 160 MHz, 7 schedulers | 913,200 instructions in | a second |
| --- | --- | --- |
| checked | 4,139 ms | 220,632 |
| `--unchecked` | 3,148 ms | 290,095 |

Net of the demo's waits the unchecked build computes 1.57 times as fast as
at the end of M4. What is left is the dispatch: the profile's handlers take
617 clocks an instruction and the loop around them 192, and the backend's
code for the fast `move` is some forty instructions with six hub accesses and
three taken jumps, executed from hub RAM. A probe measured the same `move`,
a thousand in a row: 70 clocks in PASM that flexspin copies into the cog
(`org`), 100 in PASM run from hub (`orgh`), 110 in an OctoGo loop the backend
copies into the cog itself, against some 530 in the VM, handler and loop.
Flexspin copies an inline `org` block of up to about 250 longs and refuses
300 ("Inline assembly too large to fit in fcache"). Where a core is to run was
put to the user, who chose each scheduler's own cog.

**M5, the core**, the same night: `core/`, the hot instructions in PASM run
from hub on the scheduler's cog, a Spin2 method whose locals are its
registers. An `org` block copied into the cog was measured first and given
up: flexspin copies it at every entry, some 260 clocks, and 250 longs hold
too few instructions, so every other instruction would be a hand-back with a
reload. From hub there is no limit and no reload; what costs there is a taken
jump, which refills the instruction FIFO. What flexspin's inline assembly
allows decided the rest, found in its `inlineasm.c` and docs: no `call`, a
`ret` made a jump to the block's end (and the block then held to the cache's
size, whence the first "too large" for a block that was never to be copied),
`ptra` untouched, and `tjz` and its kin reaching 256 instructions. So the
source is a template, `core/core.pasm`, whose macros `obeam gen` expands into
`core/core.spin2`: an operand is read and written by runs of instructions with
no branch, conditions doing what a branch would; `ptrb` is the code pointer;
every handler ends with its own dispatch, which reads the table's entry, a
`jmp #\label`, and jumps to its address field. The packer writes each
instruction's index among the core's in bits 8-15 of its opcode long, which
OctoGo's loop masks off; the loop hands the core a block of the process's
state at the first such instruction, and the core runs until one it does not
do, or cannot do now, which the loop then does. The core does 35 instructions,
and `+`, `-`, `*`, `div` and `rem` of small integers with MULS and the CORDIC
divider; it takes no lock and raises nothing. It is in the board program and
the profiler, and not in the twin, which cannot run PASM; `TestCoreGenerated`
holds `core.spin2` to its template, the image's fingerprint covers the core's
list, and the board, against `erl`, is the core's test.

On the workload, unchecked at 160 MHz on one scheduler:

| | Clocks an instruction |
| --- | --- |
| without the core | 819 to 832 (the build's layout) |
| with the core, its first form | 689 |
| threaded dispatch, `*` `div` `rem` | 645 to 653 |

The core does 206,132 of the 233,676 instructions, 88%, at 231 clocks each
with its entries and exits (21,855 of them); the other 12%, the sends,
receives, BIF calls, collections and the scheduling between turns, take 69%
of the time, 3,800 clocks each. That is where M5 goes on: the core has done
what it can until the runtime around it is cheaper. On the demo, seven
schedulers, both builds printing what `erl` prints line for line:

| Build, 160 MHz, 7 schedulers | 913,200 instructions in | a second |
| --- | --- | --- |
| checked | 3,101 ms | 294,449 |
| `--unchecked` | 2,660 ms | 343,321 |

Net of the demo's waits, the unchecked build computes about twice as fast as
at the end of M4.

**M6a, Elixir runs**, 2026-10-16, the same night. Three small Elixir modules
compiled with Elixir 1.18.3 on OTP 27 named, through the packer's refusals,
all that stood between them and the VM: `__info__/1`, which every Elixir
module exports and which the packer now drops as it drops `module_info`;
Elixir's library, `IO`, `Enum` and `String.Chars`; and `bs_create_bin`, the
one instruction string interpolation and `<>` compile to. None needed maps or
the bit syntax's matching. What was built:

- `bs_create_bin`, which the packer rewrites into the VM's form, a kind, unit,
  flags, source and size a segment, a `string` segment, an offset into the
  module's string table, becoming a literal binary; binary, integer and UTF-8
  segments, bit by bit where they are not whole bytes, a binary of no whole
  number of bytes failing; float and UTF-16 and -32 segments refused by name.
- Binaries made at run time: `emit` has a third target, the bytes of a binary
  on the heap, so every writer makes a binary in two passes, one to count,
  one to write, the argument read again after the room is made.
  `integer_to_binary`, `atom_to_binary`, `binary_to_list`, `list_to_binary`,
  `iolist_to_binary`, `byte_size`.
- `IO.puts`, `IO.inspect`, `Kernel.inspect` and `String.Chars.to_string` as
  BIFs, the last for what is no struct; `vm/inspect.ogo` writes terms as
  Elixir's `inspect` does: atoms, aliases, strings with Elixir's escapes,
  printable charlists as `~c"..."`, keyword lists as `[a: 1]`, 50 items of a
  collection at most. It does not break a long result over lines at 80
  columns, which Elixir's pretty printer does, nor take bytes past 127 for
  text.
- `ex/shim/Elixir.Enum.erl`, the `Enum` functions the corpus calls, on lists,
  in Erlang, packed with an Elixir program and kept off the oracle's path.
- `ex/`, six Elixir modules: `Hello`, `Fac`, `Ping`, `Ring`, `Enums` and
  `Strings`, which `TestElixir` holds to what `elixir` prints, as `TestErl`
  holds the Erlang ones to `erl`. All six agreed on their first run.

On the board the demo runs the thirteen Erlang modules, the six Elixir ones
and `cogs`, and the 85 lines before `cogs` are byte for byte what `erl` and
`elixir` print, in both builds: 1,078,054 instructions in 4,787 ms checked,
3,908 unchecked. The checked binary is 503,788 bytes, which with `main`'s
stack of 12 KB leaves some 8 KB of the hub: the next addition to the VM or
the demo is a question of room. Maps, the bit syntax's matching and Elixir's
ranges and structs, which are maps, are M6b.


**Room, before M6b**, 2026-10-17. M6a left some 8 KB of the hub, and the
user put the programs the VM can run before its speed: a fast VM that cannot
run a realistic program is of less use than a slower one that can. Where
the checked demo build's 503,788 bytes went, by building it without each
part, by the backend's listing and by the tables' sizes under the twin:

| Part | Bytes |
| --- | --- |
| the arena, the processes' heaps | 131,072 |
| code: the VM 126 KB, the C library 17 KB, ogo's runtime 8 KB, the core 5 KB | 158,020 |
| the process table, 256 slots of 252 bytes | 64,512 |
| the goroutines' stacks, 7 slots of 1,776 longs | 49,728 |
| the demo's image | 40,508 |
| the schedulers' own state, 7 of 2,900 bytes | 20,300 |
| the rest: tables, strings, the runtime's data | about 39,600 |

Four changes gave 88 KB back, the profile on the board unchanged, 655
clocks an instruction with the core against 657:

- **The process table**, 33.8 KB. A process's saved X registers had 64
  bytes in its slot; they are pushed on its own stack when its turn ends at
  a call, `yield`, and popped when the next begins, and a block with no room
  for them even after a collection goes on running instead. Its links and
  monitors had room for four of each in its slot; they are records of one
  pool of 512, a list a process under its stripe, a link a record at each
  end and a monitor the watcher's and the watched one's, and a process that
  ends takes its records out of the other ends' lists, so that a monitor that
  fired or a watcher that died leaves nothing behind. A slot is 96 bytes, and
  a process has as many links as the pool has records, which a supervisor
  of more than four children needed: `erl/sup.erl` links fifty workers to
  one process and makes and ends six hundred monitors and links of each kind,
  three times what the pool holds.
- **The goroutines' stacks**, 30.5 KB. ogo sizes them from the backend's
  listing, which counts a call through a function value as going to every
  function whose address is taken. The output, the pins, the clock's
  frequency and `rnd` were hooks, function values `main.ogo` set, and `apply`
  called the BIF it applied through the table, so every BIF that wrote,
  drove a pin or applied, and every handler that called a BIF, made one cycle
  of 91 functions, whose frames the bound adds up. Now the VM writes to the
  serial line through `p2`, a newline as `CRLF` says, the pins' ring is the
  VM's (`vm/pins.ogo`), served by main's cog through `NextPin` and `PinRead`,
  and `apply` answers `bifValue`, the BIF and its arguments left for the
  handler to call (`callBif`), which also keeps a chain of applies from
  deepening the stack. The cycle is eleven handlers, a slot 688 longs.
- **The fast handlers on the board**, 16.8 KB. The core does their
  instructions, and they saw only what it handed back, which they handed on.
  A function whose address is taken is linked even when nothing calls the
  function that takes it, so the registration is the twin's, `useFast` in
  `vm/host_test.go`, and the twin runs every module of the corpus twice, with
  the general handlers alone, as the board does, and with the fast ones,
  which the core is written after. The profiler's second pass, without the
  core, now times the general handlers: 1,150 clocks an instruction, 830
  with the fast ones.
- **`printf` in `main.ogo`**, 7.9 KB, its formatter and its floats: the
  figures are written by two small functions.

Two things did not pay. The profiler behind a function the board's program
does not call kept `runProfiled` linked and made the build a kilobyte larger.
`--no-inline` changes nothing: the VM is built without inlining already,
its functions outgrowing a cog's registers with it. `--unchecked` saves 55 KB
of checks, not of speed, and stays a choice of the build.

With the demo's image as it was, the checked build is 413,800 bytes and the
unchecked 370,300. The arena is 192 KB again, as section 7 decided, and with
`sup` in the demo the checked build is 485,092 bytes and the unchecked
440,504; `main`'s stack needs 1,108 bytes, by ogo's own report, so 37 KB of
the hub are left (`make budget`). On the board both builds print the 91
lines before `cogs` that `erl` and `elixir` print: 1,136,479 instructions in
5,397 ms checked, 4,342 unchecked, 1,316 collections. The next room is the
image's: read from the SD card at boot into the bottom of the region the
heaps are in, so that a program and its heaps share it, and the VM's binary
carries no program. The card is no store to run from: p2-11 measured 1,610
microseconds to read a block of 512 bytes, about 8,000 hub reads for one
long.

**M6b, maps and binary matching**, 2026-10-17. Probes compiled with OTP 27
and Elixir 1.18 named what it took: maps are `put_map_assoc`,
`put_map_exact`, `get_map_elements` and `has_map_fields`, and the guard BIFs
and the `maps` functions; binary matching is `bs_start_match4` and its
older form `bs_start_match3`, `bs_match` with its list of commands,
`bs_get_tail`, `bs_get_position` and `bs_set_position`, `bs_get_binary2` for
a size taken from an earlier segment, `bs_get_utf8`, and `bs_init_writable`
before a loop that appends; Elixir's `map.field` calls
`elixir_erl_pass:no_parens_remote/2` where the field is missing, and `Mod:Fun()`
is the `apply_last` instruction. What was built:

- Maps as section 2 lays them out. The packer lays a literal map out with its
  keys in map-key order, `internal/pack/order.go`, which is the VM's
  comparison of terms in its exact mode. A comparison keeps, for each pair
  still to compare, whether it is exact, since a map's keys compare exactly
  even under `==`: `#{1 => a} == #{1.0 => a}` is false. And `=:=` is exact
  at every depth now, `{1} =:= {1.0}` having been true.
- `put_map_assoc` and `put_map_exact` copy the map and put each pair into the
  copy at the heap's top by a binary search, the room made for every pair
  first; `get_map_elements` and `has_map_fields`; `map_size`, `is_map_key`,
  `map_get` and `is_map`; and `maps:get/2,3`, `find`, `is_key`, `put`,
  `update`, `remove`, `keys`, `values`, `to_list`, `from_list`, `merge`,
  `size` and `new` as BIFs. A BIF that fails with `{badmap, M}` or `{badkey,
  K}` sets `bifTag` with the reason, and the handler builds the tuple when it
  raises, so that a guard BIF, which may not allocate, fails so too.
- `maps:fold`, `map`, `filter`, `filtermap`, `foreach`, `with`, `without`,
  `update_with`, `from_keys`, `take` and `merge_with` in a shim,
  `erl/shim/maps.erl`, as `ex/shim/` has Elixir's library. OTP's own
  `maps.beam` packs to more than the hub has: the reach of its `fold` goes
  through `iterator/2` and its `ordered` option to `lists:sort/2`, and from
  there through most of `lists`. A shim is a library module, `obeam pack
  -lib`, packed by what the program reaches and not by its exports, and its
  literals only when a function of it is.
- Binary matching: a match context is made by `bs_start_match4` of a binary,
  and `bs_match`, which the packer rewrites into the VM's form as it does
  `bs_create_bin`, ensures, reads integers of up to 64 bits big- or
  little-endian, signed or not, at any bit offset, takes binaries and the
  rest, skips, and compares, moving the context's offset on in place. A
  binary taken out is a copy, whole bytes at a byte's offset; one that would
  be a bitstring makes the match fail. UTF-8 is decoded strictly: no
  overlong forms, no surrogates, nothing past U+10FFFF.
- Elixir: `inspect` writes maps, `%{"a" => 1}` or `%{a: 1}`, a struct as
  `%Point{x: 3, y: -4, label: nil}` in the order of its fields, which only the
  module's `__info__(:struct)` knows and which the packer therefore reads and
  carries in the image, `Structs`, and a range as `1..5` or `1..10//3`.
  `__struct__/0,1` are no roots of the packer: the compiler expands a struct
  literal. The `Enum` shim takes maps and ranges, and sorts; a `Map` shim and
  an `elixir_erl_pass` one.
- `apply` and `apply_last`, a function called by a module and a name in
  registers, through the lookup `apply/3` has.

`erl/mp.erl`, `erl/bin.erl` and `ex/maps.ex` hold it to `erl` and `elixir`, all
three agreeing on their first run but for the `==` of maps, which `mp` found
once it compared maps at run time: `erlc` had folded the comparisons of its
literals away. A map with atom keys is printed with `~kp` in the corpus, or
sorted, since `erl` and `elixir` print them in the order of their atom
tables; `~p` breaks a line past 80 columns, which the VM's does not, so a
long one is `~w`.

The hub had 37 KB. The VM grew by about 21 KB, maps 15 KB of it, and the
demo's image by 24 KB, to 11,789 longs of code and 2,213 of literals. So the
arena is 160 KB, the lever section 8 named: the checked build is 512,444
bytes, the unchecked 459,752, and 10.7 KB of the hub are left beside
`main`'s stack. A program smaller than the demo's twenty-six modules and four
shims leaves more, and the image read from the SD card would let a program
and its heaps share the region as each needs. On the board both builds
print the 143 lines before `cogs` that `erl` and `elixir` print: 1,142,805
instructions in 5,483 ms checked and 4,451 unchecked; the profile is
unchanged, 657 clocks an instruction with the core.

**The image in the arena**, 2026-10-17, the first step of the way the user
and the assessment agreed for OctoBeam's users: one `obeam` executable that
carries the VM built once, checked and unchecked, and puts a program's image
into it, so that a user needs neither Go nor OctoGo nor a loader of their
own. The image left the binary for the bottom of the arena (section 4), and
the arena grew by what it had taken: 232 KB, the checked VM binary 513,068
bytes, 11,220 left beside it for `main`'s stack of 1,108 and what comes
next; the unchecked binary is 460,668. The demo's image is 17,743 longs,
69 KB, and leaves its heaps 41,649 longs, 162 KB, where they had 160; the
hello of the README's workflow is 490 longs and leaves 230 KB. Atom and file
names became bytes in the arena, and `nil` a well-known atom, which Elixir's
`to_string` tested by its name. On the board both builds print the 143 lines
before `cogs` that `erl` and `elixir` print, in 5,506 ms checked and 4,454
unchecked; the bare VM says it has no image; the profiler, which loads the
image afresh for each of its runs, finds 662 clocks an instruction with the
core.

**One program for users**, 2026-10-17, step 2: `obeam` is the Go command at
the root, so that `go install modernc.org/obeam@latest` installs it, and the
board program moved to `board/`. It carries the VM built twice by `make
vms` (`internal/vmbin`, committed with the hash of the sources, which a test
holds the tree to), the shims (`go:embed` of `erl/shim` and `ex/shim`; a
user's module of the same name wins), and the P2 loader, ogo's, now
`modernc.org/ogo/loadp2`: `obeam hello.beam` writes `hello.binary`, `obeam
run hello.beam` loads it and shows what the board prints, `obeam loadp2` is
the loader as it is. The unchecked VM has the 52 KB its checks leave for its
arena, 284 KB: ogo has no build-time constants, so `make vms` builds it from
a copy of the tree whose `arenaLongs` is `arenaUnchecked`. Its binary is
514,124 bytes, and the demo's heaps get 214 KB in it. OTP's `lists`, 62
functions of it, became a shim, held to OTP by `erl/listlib.erl`, which
printed what `erl` prints on its first run, in the twin and on the board.
`make release` builds the zips of ogo's five targets, 1.8 MB each, with
examples. The VMs carried are built by ogo v0.57.0; on the board, through
`obeam run`, both print the demo's 143 lines, in 5,506 ms checked and 4,452
unchecked.

**Without a computer**, 2026-10-17: the P2's ROM boots a file of an SD
card by itself, `_BOOT_P2.BIX` in the root directory of a FAT32 volume, so
`-sd` became that, as the user chose over a VM that reads an image from the
card: `obeam -sd` writes the binary under that name, and `obeam flash`
writes it into the board's flash with loadp2's `-FLASH`. On the P2-EDGE,
DIP switch SD on, a tiny program booted from the card at power-on and at a
DTR reset; the VM, 513,068 bytes, did not, and the board answered no loader
while the card was in. The ROM loads at most 512 KB less the 16 KB it keeps
its code in while loading, 507,904 bytes; a VM with an arena 8 KB smaller,
504,844 bytes, booted, its first line 7.7 s after the reset, the ROM reading
the card at about 65 KB/s. So both arenas are 8 KB smaller, 224 KB and 276
KB, and a test holds both binaries to the limit: the demo's heaps have 154
KB, 206 unchecked. The demo, booted from the card by the VM that is
committed, printed the 143 lines in 5,505 ms; over serial both VMs printed
them, in 5,507 and 4,453 ms. `obeam flash` wrote hello into the flash and
ran it, and serial loading worked after it; a boot from the flash at
power-on is not tried, the P2-EDGE's DIP switch FLASH being off.

**The LEDs**, 2026-10-17: `erl/leds.erl`, "let it crash" to be seen on the
P2-EDGE's two LEDs, a blinker for each under a supervisor that traps exits
and restarts a blinker its bug crashed, found three faults the corpus had
not, its workers all ending with `exit/1`. The exit reason of a process that
failed with an error was its raw stack, `{{error,[322]}, ...}` where Erlang
has `{badarith, Stacktrace}`: `stackList` kept its argument in `bargs[0]`
while it made room, over the reason `exitReason` had put there; it keeps it
after the caller's now, and `exitReason` roots the list it gets back. A
throw's was `{nocatch, V}`, without the stacktrace Erlang gives it. And a
receive of no clauses, `receive after 1000 -> ok end`, which erlc compiles
to a `wait_timeout` whose label is itself, went round in one turn for ever
when a message came while it waited, `sleep` answering the label because a
message was unseen: the supervisor hung when both blinkers died within a
second, its scheduler busy and its state running, which the twin's process
table and goroutines showed. Such a wait now counts every message seen; and
a receive's timeout is armed once, at its first wait, where every wait set
it again, so that messages it had no clause for put it off for ever.
`erl/exits.erl` and `erl/waits.erl` hold all of it to `erl`; a first frame
made of a BIF and its arguments, or of a `function_clause`'s function and
its arguments, which Erlang gives and the VM does not, is left for later.
On the board the demo restarts its blinkers, five each in a minute, and
goes on.

**gen_server**, 2026-10-17, a shim in Erlang over the VM's processes,
`erl/shim/gen_server.erl`: a synchronous start through a monitor, a name
taken in the new process, calls through a monitor with OTP's exit reasons,
the timeouts and `{continue, _}` of a callback's result, a throw taken as
the result, a crash calling `terminate/2` and raised again, and the optional
`handle_info/2` and `terminate/2` called only when exported, for which the
VM has `erlang:function_exported/3` now, a BIF over the image's function
table. The new process begins in a fun: a library is packed by reach, and
`spawn(gen_server, init_it, A)` reaches nothing. `erl/gs.erl`, a key-value
server, prints what OTP's gen_server prints, 22 lines, in the twin and on
the board in both builds, `erl` run with its logger off and the VM's crash
reports left out. The VMs are 505,900 and 506,728 bytes, 2,004 and 1,176
under the SD card's limit. After an exception raised again, the VM's report
names the place of the raise, where the stacktrace it carries names the
crash's.
