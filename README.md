*Eight cogs. Seven schedulers. One tiny BEAM.*

# obeam

A BEAM, the Erlang virtual machine, for the
[Parallax Propeller 2](https://www.parallax.com/propeller-2/), to be written in
[OctoGo](https://pkg.go.dev/modernc.org/ogo): the modules Erlang's own compiler
writes, run on the eight cores of a microcontroller, a scheduler on each of
seven of them. It is the second program of size in OctoGo, after
[p2-11](https://gitlab.com/cznic/p2-11), a PDP-11/40 that runs Unix V6.

## Status

Begun on 2026-10-16, and at milestone M1 of the plan in `ASSESSMENT.md`: one
Erlang process, on one cog, running modules compiled by `erlc`.

- `cmd/obeam`: the host tool, Go. `obeam pack` turns `.beam` files into the
  image the board runs, every operand resolved and every literal laid out as
  the board's own terms, and refuses, by module, function and line, what the
  VM cannot run yet. `obeam dis` and `obeam stats` list and count a module.
- `vm/`: the VM, in OctoGo: about 2,300 lines for the terms, a buddy arena,
  the interpreter, a copying collector per process, 79 BIFs, `io:format` and
  the exception reports. It is Go once given a package clause, and the tests
  run it so, against `erl`: `fac`, `fib`, `lst` and `tuples` of the corpus
  print the same bytes under both.
- `main.ogo`, `image/`: the board program and its image, `demo`, which runs
  the four. Build it with `ogo build`, run it with `make run`. On a P2-EC it
  prints what `erl` prints, line for line, and then:

  ```
  176700 instructions in 1238 ms, 142730 a second
  ```

  which is the checked build at 160 MHz; `--unchecked` makes it 194,175 a
  second and `--unchecked --clock 200MHz` 242,386. DESIGN.md section 8 says
  what that is made of.
- `erl/`: the corpus, twelve small Erlang modules from `fac` to a process
  ring and a concurrent prime sieve, compiled with OTP 27 and committed;
  `erl/stats.txt` is the opcode and call histogram over them.
- `DESIGN.md`: how it is made, and what each milestone measured.

Not yet: processes beyond the first, messages, exceptions caught, floats,
bit syntax, maps, bignums. Those are M2 and M4.

```sh
ogo build                                    # the board binary; ogo run loads it (make run takes the shared board lock)
make test                                    # the gate: formats, vet, the reader's tests, then the VM under Go against erl
make image                                   # regenerate image/image.ogo from the corpus
go run ./cmd/obeam dis erl/pingpong.beam     # the module's code, as erlc -S would list it
go run ./cmd/obeam stats erl/*.beam          # the histogram
make beam                                    # recompile the corpus after editing a .erl file (erlc of OTP 27)
```

The reader is held to OTP's own disassembler, `beam_disasm`, through
`erl/oracle.escript`; the VM to `erl` itself, module by module.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
