![OctoBeam](logo.png)

*Eight cogs. Seven schedulers. One tiny BEAM.*

*For M. G., who likes Erlang — from a fan of Go. We both like the Propeller 2.*

# OctoBeam

OctoBeam is a BEAM, the Erlang virtual machine, for the
[Parallax Propeller 2](https://www.parallax.com/propeller-2/), written in
[OctoGo](https://pkg.go.dev/modernc.org/ogo): the modules Erlang's own compiler
writes, run on the eight cores of a microcontroller, a scheduler on each of
seven of them. Its short name, the repository's and the host tool's, is
`obeam`, as OctoGo's is `ogo`. It is the second program of size in OctoGo,
after [p2-11](https://gitlab.com/cznic/p2-11), a PDP-11/40 that runs Unix V6.

It runs a subset of Erlang and Elixir, in 512 KB: processes, messages,
links, monitors, exceptions, floats, binaries and maps, but no bignums,
floats of 32 bits, no distribution, and of OTP's and Elixir's libraries only
what the VM's BIFs and the shims `obeam` carries do (`io:format`,
`gen_server`, `supervisor`, `lists`, `maps`, `Enum`, `Map` and more, listed
below). `obeam` names what a program
uses that the VM does not have, before anything runs.

The repository you are currently viewing might be a mirror. Please review the
guidelines below based on where you are viewing this:

| Platform | Role | Contributing Guidelines |
| :--- | :--- | :--- |
| **GitLab** | **Primary Source** | This is the canonical repository ([`cznic/obeam`](https://gitlab.com/cznic/obeam)). Development happens here. |
| **GitHub** | **Mirror** | This is a mirror ([`modernc-org/obeam`](https://github.com/modernc-org/obeam)), where the release binaries are published. We **do accept** Issues and Pull Requests here for your convenience! <br> *Note: PRs submitted here will be manually merged into the GitLab source, so please allow extra time for processing.* |

## Installation

`obeam` is one program. It carries the VM, built for the P2 once and for
all, the shims, and a P2 loader, so there is no OctoGo, FlexProp or loader to
install beside it. Either:

- **A release zip**, no Go needed: from the
  [releases page](https://github.com/modernc-org/obeam/releases), take the zip
  for your system (`linux-amd64`, `linux-arm64`, `windows-amd64`,
  `darwin-arm64` for Apple silicon, `darwin-amd64`), unzip it, and put
  `obeam` (`obeam.exe` on Windows) in a directory on your `PATH`. The zip has
  `examples/` beside it.
- **With Go 1.26 or newer**: `go install modernc.org/obeam@latest`.

To compile programs of your own you also need Erlang/OTP's `erlc`, and for
Elixir `elixirc`. OctoBeam is built and tested with OTP 27.3 and Elixir 1.18.3,
which is what Debian 13 has: `sudo apt install erlang-base`, and `elixir`.
Elsewhere, see [erlang.org](https://www.erlang.org/downloads). A `.beam` file
of another OTP release may use an instruction OctoBeam does not know yet, and
`obeam` then says which.

## Getting started, step by step

1. **Connect the board.** A Propeller 2 board with a USB serial port, such as
   the P2-EDGE (P2-EC) on a breakout board, which is what OctoBeam is tested
   on, plugged into a USB port.
   - On Linux, the serial port belongs to a group, usually `dialout` (`ls -l
     /dev/ttyUSB0` shows it). Join it once, then log out and in again: `sudo
     usermod -aG dialout $USER`.
   - On Windows, run `obeam` from `cmd.exe` or PowerShell, not from git-bash,
     MSYS2 or Cygwin, whose consoles the loader cannot drive.
2. **Check obeam**: `obeam version` says which release it is.
3. **Run an example** from the zip's `examples/`:

   ```
   $ obeam run examples/hello.beam
   obeam: hello.binary: hello:main/0, the VM checked; the image 511 longs, 12 of them code; 220 KB of the arena left for the heaps
   obeam: loading hello.binary; Ctrl-] leaves the terminal
   ( Entering terminal mode.  Press Ctrl-] or Ctrl-Z to exit. )
   obeam: hello:main/0, 12 longs of code, 7 schedulers

   Hello, world!

   3 instructions in 1 ms, 3000 a second, 0 collections, the core run 2 times
   ```

   `obeam run` wrote `hello.binary`, the VM with the program in it, loaded it
   into the board's RAM, and shows what the board prints until you press
   Ctrl-]. The loader finds the board by itself; with several, name the port:
   `-p /dev/ttyUSB0` (`-p COM3` on Windows). The program is in the board's
   RAM, not its flash, so a reset ends it. Then try `examples/ring.beam`, a
   ring of processes; `examples/leds.beam`, Erlang's "let it crash" to be
   seen: the P2-EDGE's two LEDs, on pins 56 and 57 (its DIP switch LED on),
   each blinked by a process with a bug that crashes it now and then, its LED
   going out, under an OTP supervisor that starts a new one, which keeps the
   LED dark for a second and says so;
   and the whole demo, 26 modules of Erlang and Elixir: `obeam run -entry
   demo:main/0 examples/demo/*.beam`.
4. **Write a program.** `hello.erl`:

   ```erlang
   -module(hello).
   -export([main/0]).

   main() ->
       io:format("Hello, world!~n").
   ```

   then `erlc hello.erl` and `obeam run hello.beam`. The program starts at the
   first module's `main/0`; `-entry hello:world/0` starts it elsewhere, at an
   exported function of no arguments. A program of several modules is named
   whole: `obeam run main.beam util.beam`, or `obeam run -entry main:main/0
   *.beam`. What a program reaches of OTP that the VM does not have is refused
   by name:

   ```
   obeam: greet.beam: greet:main/0, call_ext at code offset 19: calls string:uppercase/1, which is no BIF and no function of the modules packed
   ```

5. **Elixir** works the same way: `elixirc hello.ex` writes
   `Elixir.Hello.beam`, and `obeam run Elixir.Hello.beam` runs its `main/0`,
   `def main`.
6. **The pins** are the module `p2`: `p2:pin_high(56)`, `pin_low/1`,
   `pin_toggle/1`, `pin_float/1`, `pin_write/2`, `pin_in/1`, `p2:cog()`, the
   scheduler a process runs on, and `get_ct/0`, `clock_freq/0` and `rnd/0`.
   `examples/blink.erl` uses them. Such a program compiles anywhere but runs
   on the board only.
7. **Without `run`**, `obeam hello.beam` only writes `hello.binary`, an
   ordinary P2 binary for any loader: `obeam loadp2 -t -b 230400
   hello.binary`, FlexProp's `loadp2`, or `ogo loadp2`. The board prints at
   230400 baud.
8. **From an SD card, with no computer**: `obeam -sd hello.beam` writes
   `_BOOT_P2.BIX`, the file the P2's ROM boots from the root directory of a
   FAT32 card in the board's slot. Copy it onto the card (onto a card that
   holds no other `_BOOT_P2.BIX`, so that the file is in one piece, which the
   ROM needs), put the card into the slot, and the board runs the program
   whenever it is powered or reset; on a P2-EDGE the DIP switch SD is on.
   The ROM reads the card at about 65 KB/s, so the program starts eight
   seconds after the reset. While such a card is in the slot the board does
   not answer a loader: take it out to load programs over USB again.
9. **From the board's flash**: `obeam flash hello.beam` writes the program
   into the board's flash and runs it; with the board set to boot from flash
   (a P2-EDGE's DIP switch FLASH on), it runs whenever the board is powered.

The flags, before or after the files (`obeam help`):

| Flag | |
| :--- | :--- |
| `-o FILE` | the binary to write; by default the entry's module's name, `.binary`, in the current directory |
| `-sd` | name it `_BOOT_P2.BIX`, the file the P2 boots from an SD card |
| `-entry m:f/a` | the function to start, exported, of no arguments; the first module's `main/0` by default |
| `-unchecked` | the VM without its runtime checks: 54 KB more for the heaps, and a fifth faster, but a fault of the VM's corrupts memory silently where the checked VM stops with a `panic:` message. Develop with the default. |
| `-lines=false` | leave out the line numbers a crash report names, for room |
| `-lib A.beam,...` | more library modules, of which the program takes what it reaches |
| `-p PORT` | with `run`: the board's serial port |
| `-vm FILE` | a VM binary of your own, built from this repository with `ogo build ./board` |

## What the VM has and has not

The VM's BIFs include `io:format` with its widths and precisions,
`erlang`'s arithmetic, comparisons, type tests, lists, tuples, binaries,
maps, processes, links, monitors, registered names and exceptions,
`lists:reverse`, `member` and `keyfind`, and Elixir's `IO`, `Kernel.inspect`
and `String.Chars`. The shims `obeam` carries are Erlang modules for the
rest of what programs reach for first: OTP's `gen_server` (start and
start_link, named or not, call, cast, reply and stop, timeouts and
`{continue, _}`, the optional callbacks, and a crash calling `terminate/2`),
`supervisor` (the four strategies, permanent, transient and temporary
children, the restart intensity, and the children's API), `lists` (`map`, `foldl`, `filter`, `seq`, `sort`, `zip`, `keysort` and
fifty-five more) and `maps`' functions that take a fun, and Elixir's `Enum`
and `Map`. A program takes what it calls of them and nothing else, so a
child spec's start function, which a supervisor calls by `apply`, is to be
the program's own, as in OTP's examples (`{my_server, start_link, []}`): a
shim's named there, `{gen_server, start_link, ...}`, is not packed.

Not yet: bignums, bitstrings that are not whole bytes, OTP's other
behaviours (`gen_statem`, `gen_event` and the like) and the `sys` and
`proc_lib` sides of `gen_server` and `supervisor`, `~p`'s line breaking, and OTP's and Elixir's
libraries beyond the shims. The functions of OTP's `lists` that the VM has
as BIFs, `reverse`, `member` and `keyfind`, fail as BIFs do, with `badarg`,
where OTP's `reverse` fails with a `function_clause` of its own. A map with atom
keys prints its keys in term order, where `erl` and `elixir` print them in
the order of their atom tables, and a map of more than 32 keys in term
order, where OTP prints its hash trie's. The arena is 222 KB (276 KB
unchecked), the image at its bottom and the process heaps above, so the
demo's image of 69 KB leaves its heaps 152 KB and a hello, world 220 KB; the
VM is no larger than the 496 KB the P2's ROM boots from an SD card. A
process's stack is bounded by its largest heap block, 8,192 longs, so a
recursion 20,000 deep that Erlang takes ends here in `system_limit`; write it
as a tail call. The links and monitors of all processes together are 256 at
most, a record at each end. Floats are 32 bits wide: what is not exact in 32
bits prints differently from Erlang's 64.

## Status, and the repository

This repository is for OctoBeam's development; to use it, `obeam` is
enough. Begun on 2026-10-16, and at milestone M6b of the plan in
`ASSESSMENT.md`: Erlang and Elixir processes, spawned, linked and monitored, sending and
receiving, catching exceptions, computing in floats, making and matching
binaries, and building and matching maps, Elixir's structs and ranges among
them, on seven scheduler cogs, running modules compiled by `erlc` and
`elixirc`.

- The root: `obeam`, the host tool, Go. It turns `.beam` files into the image
  the board runs, every operand resolved and every literal laid out as the
  board's own terms, refuses, by module, function and line, what the VM
  cannot run yet, and puts the image into the arena of the VM it carries, in
  milliseconds. `internal/vmbin` holds that VM, checked and unchecked, built
  from `board/` by `make vms`. `obeam dis` and `obeam stats` list and count a
  module.
- `vm/`: the VM, in OctoGo: about 8,500 lines for the terms, a buddy arena,
  processes with mailboxes, links, monitors and a run queue, seven schedulers
  each a cog, the interpreter, a copying collector per process, exceptions
  caught by `try` and `catch`, floats, binaries and their matching, maps,
  135 BIFs, `io:format` with its widths and precisions, Elixir's `inspect`,
  and the exception reports. It is Go once given a package clause, and the
  tests run it so, on seven goroutines, against `erl` and `elixir`: twenty-four
  Erlang modules of the corpus, from `hello` to a ring of a hundred processes,
  a server with timeouts, linked workers, a process linked to fifty, `try`
  and `catch`, floats, maps and binary parsers, and the seven Elixir ones,
  print the same bytes under both.
- `board/`: the board program, the VM, which runs the image at the bottom
  of its arena; and the demo, which runs the sixteen Erlang modules, the
  seven Elixir ones, and then `cogs`, seven workers that report which
  scheduler ran them. `make demo` builds the VM with `ogo build` and puts
  the demo into it, and `make run` runs it. On a P2-EC it prints what `erl`
  and `elixir` print, line for line, then the workers' schedulers, and
  then:

  ```
  1142805 instructions in 5483 ms, 208426 a second, 1332 collections, the core run 75001 times
  ```

  which is the checked build at 160 MHz, a second of it the demo's own
  waiting. DESIGN.md section 8 has the figures of each milestone.
- `core/`: the hot instructions in PASM, run on each scheduler's own cog from
  hub RAM. It does 88% of the instructions of the profiler's workload, at 231
  clocks each against 800 in OctoGo.
- `prof/`: the profiler, which times every instruction of a workload on the
  board, by opcode and by BIF: `make prof-run`.
- `ex/`: seven Elixir modules, from `IO.puts("hello, world")` to a ring of a
  hundred processes, string interpolation of every kind, and maps, structs
  and ranges, held to what `elixir` prints; `ex/shim/` the parts of Elixir's
  `Enum` and `Map` they use, in Erlang.
- `erl/`: the corpus, twenty-nine small Erlang modules from `hello` to a
  process ring, a concurrent prime sieve, linked workers, exit reasons,
  stacktraces, timeouts, floats, maps, binary parsers, OTP's `lists`, `gen_server` and
  `supervisor`, and `blink` and `leds` for the board's LEDs, compiled with
  OTP 27 and committed; `erl/shim/` OTP's `gen_server`, `supervisor`,
  `lists` and the functions of `maps` that take a fun;
  `erl/stats.txt` is the opcode and call histogram M0 measured over the
  first eleven.
- `DESIGN.md`: how it is made, and what each milestone measured.

Developing it takes Go 1.26, OctoGo (`ogo`) and OTP 27:

```sh
make test                                    # the gate: formats, vet, the tests, then the VM under Go against erl
make demo                                    # the VM, obeam.binary, and demo.binary, the VM with the demo in its arena
make run                                     # load demo.binary onto the board (under the shared board lock)
make budget                                  # build the VM and say how much of the hub it leaves
make vms                                     # rebuild the VMs obeam carries, after any change to board/, vm/ or core/
go run . -vm obeam.binary hello.beam         # a program into the VM built from the tree
go run . dis erl/pingpong.beam               # the module's code, as erlc -S would list it
go run . stats erl/*.beam                    # the histogram
make beam                                    # recompile the corpus after editing a .erl file (erlc of OTP 27)
```

A release: `make vms OGO=<a released ogo>` if the VM changed since the last
one, a section in `CHANGELOG.md`, commit, `git tag -a vX.Y.Z`, then `make
release`, which writes `build/release/vX.Y.Z/`: a zip for each of the five
targets OctoGo's releases have, and `SHA256SUMS`, for the GitHub release.

The reader is held to OTP's own disassembler, `beam_disasm`, through
`erl/oracle.escript`; the VM to `erl` itself, module by module.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
