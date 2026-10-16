*Eight cogs. Seven schedulers. One tiny BEAM.*

# obeam

A BEAM, the Erlang virtual machine, for the
[Parallax Propeller 2](https://www.parallax.com/propeller-2/), to be written in
[OctoGo](https://pkg.go.dev/modernc.org/ogo): the modules Erlang's own compiler
writes, run on the eight cores of a microcontroller, a scheduler on each of
seven of them. It is the second program of size in OctoGo, after
[p2-11](https://gitlab.com/cznic/p2-11), a PDP-11/40 that runs Unix V6.

## Status

Begun on 2026-10-16. What there is:

- `ASSESSMENT.md`: why, what, and in what order. The plan is staged: M0, the
  host tool and a corpus; M1, one process on one cog; M2, processes and
  messages; M3, seven scheduler cogs. Read it first.
- `cmd/obeam`, `internal/beam`: the host tool, in Go, which reads `.beam`
  files and lists and counts what is in them. It will be the packer that
  makes the board's image.
- `erl/`: eleven small Erlang modules, from `fac` to a process ring and a
  concurrent prime sieve, compiled with OTP 27 and committed; `erl/stats.txt`
  is the opcode and call histogram over them, which is what M0 was for.

Nothing runs on the board yet.

```sh
go run ./cmd/obeam dis erl/pingpong.beam     # the module's code, as erlc -S would list it
go run ./cmd/obeam stats erl/*.beam          # the histogram
make test                                    # gofmt, go vet, go test; the oracle tests want OTP's escript
make beam                                    # recompile the corpus after editing a .erl file (erlc of OTP 27)
make stats                                   # regenerate erl/stats.txt
```

The reader is held to OTP's own disassembler: `erl/oracle.escript` prints what
`beam_disasm` finds in a module, and the tests compare.

## License

BSD-3-Clause, see [LICENSE](LICENSE).
