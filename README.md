*Eight cogs. Seven schedulers. One tiny BEAM.*

# obeam

A BEAM, the Erlang virtual machine, for the
[Parallax Propeller 2](https://www.parallax.com/propeller-2/), to be written in
[OctoGo](https://pkg.go.dev/modernc.org/ogo): the modules Erlang's own compiler
writes, run on the eight cores of a microcontroller, a scheduler on each of
seven of them. It is the second program of size in OctoGo, after
[p2-11](https://gitlab.com/cznic/p2-11), a PDP-11/40 that runs Unix V6.

## Status

Begun on 2026-10-16, and at milestone M6b of the plan in `ASSESSMENT.md`:
Erlang and Elixir processes, spawned, linked and monitored, sending and
receiving, catching exceptions, computing in floats, making and matching
binaries, and building and matching maps, Elixir's structs and ranges among
them, on seven scheduler cogs, running modules compiled by `erlc` and
`elixirc`.

- `cmd/obeam`: the host tool, Go. `obeam pack` turns `.beam` files into the
  image the board runs, every operand resolved and every literal laid out as
  the board's own terms, and refuses, by module, function and line, what the
  VM cannot run yet. `obeam dis` and `obeam stats` list and count a module.
- `vm/`: the VM, in OctoGo: about 8,500 lines for the terms, a buddy arena,
  processes with mailboxes, links, monitors and a run queue, seven schedulers
  each a cog, the interpreter, a copying collector per process, exceptions
  caught by `try` and `catch`, floats, binaries and their matching, maps,
  134 BIFs, `io:format` with its widths and precisions, Elixir's `inspect`,
  and the exception reports. It is Go once given a package clause, and the
  tests run it so, on seven goroutines, against `erl` and `elixir`: seventeen
  Erlang modules of the corpus, from `fac` to a ring of a hundred processes,
  a server with timeouts, linked workers, a process linked to fifty, `try`
  and `catch`, floats, maps and binary parsers, and the seven Elixir ones,
  print the same bytes under both.
- `main.ogo`, `image/`: the board program and its image, `demo`, which runs
  the sixteen Erlang modules, the seven Elixir ones, and then `cogs`, seven
  workers that report which scheduler ran them. Build it with `ogo build`,
  run it with `make run`. On a P2-EC it prints what `erl` and `elixir`
  print, line for line, then the workers' schedulers, and then:

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
- `erl/`: the corpus, twenty small Erlang modules from `fac` to a process
  ring, a concurrent prime sieve, linked workers, floats, maps and binary
  parsers, compiled with OTP 27 and committed; `erl/shim/` the functions of
  OTP's `maps` that take a fun; `erl/stats.txt` is the opcode and call
  histogram M0 measured over the first eleven.
- `DESIGN.md`: how it is made, and what each milestone measured.

Not yet: bignums, bitstrings that are not whole bytes, an image loaded from
the SD card, `~p`'s line breaking, and OTP's and Elixir's libraries beyond
the shims. A map with atom keys prints its keys in term order, where `erl`
and `elixir` print them in the order of their atom tables, and a map of more
than 32 keys in term order, where OTP prints its hash trie's. The arena for
process heaps is 160 KB, and the checked build with the demo leaves 10.7 KB
of the 512 KB (`make budget`). A process's stack is bounded by its largest
heap block, 8,192 longs, so a recursion 20,000 deep that Erlang takes ends
here in `system_limit`; write it as a tail call. The links and monitors of
all processes together are 256 at most, a record at each end. Floats are 32
bits wide: what is not exact in 32 bits prints differently from Erlang's 64.

```sh
ogo build                                    # the board binary; ogo run loads it (make run takes the shared board lock)
make test                                    # the gate: formats, vet, the reader's tests, then the VM under Go against erl
make image                                   # regenerate image/image.ogo from the corpus
make budget                                  # build the board binary and say how much of the hub it leaves
go run ./cmd/obeam dis erl/pingpong.beam     # the module's code, as erlc -S would list it
go run ./cmd/obeam stats erl/*.beam          # the histogram
make beam                                    # recompile the corpus after editing a .erl file (erlc of OTP 27)
```

The reader is held to OTP's own disassembler, `beam_disasm`, through
`erl/oracle.escript`; the VM to `erl` itself, module by module.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
