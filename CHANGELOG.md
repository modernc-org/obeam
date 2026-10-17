# Changelog

Notable changes per release of `obeam`, the command, and of the VM it
carries. OctoBeam is an early preview and its version numbers say so: a
release may refuse a program the last one took, and such changes are called
out under **Behaviour changes**.

A released section is frozen: it says what that release did, and a later fix
to the same area is a new entry under **Unreleased**, not an edit to the old
one. `git show vX.Y.Z:CHANGELOG.md` is the check.

## Unreleased

The first release.

### Added

- **`obeam`, one program for users**: `obeam hello.beam` writes `hello.binary`,
  the VM with the program in its arena, and `obeam run hello.beam` loads it onto
  a P2 board and shows what it prints. It carries the VM built twice, checked
  and, for `-unchecked`, without the runtime checks and with 52 KB more for the
  heaps, the shims and a P2 loader (`obeam loadp2`), so nothing else is
  installed. `go install modernc.org/obeam@latest`, or a release zip.
- **Without a computer**: `obeam -sd` writes `_BOOT_P2.BIX`, which the P2's ROM
  boots from an SD card, and `obeam flash` writes the program into the board's
  flash. Every binary obeam writes fits the 496 KB the ROM loads from a card.
- **The VM**: Erlang and Elixir processes on seven scheduler cogs, messages and
  `receive` with timeouts, links, monitors, exit signals and registered names,
  exceptions caught by `try` and `catch`, 32-bit floats, binaries made and
  matched, maps, Elixir's structs and ranges, `io:format` with its widths and
  precisions, Elixir's `inspect`, and the pins through the module `p2`. The hot
  instructions run in PASM on each scheduler's own cog.
- **The shims**: OTP's `lists`, sixty-two functions of it, and the functions of
  `maps` that take a fun; Elixir's `Enum` and `Map`, as far as the corpus goes.
- **`gen_server`**, as a shim: start and start_link, named or not, call, cast,
  reply and stop, timeouts and `{continue, _}`, the optional callbacks, a throw
  as a callback's result, and a crash calling `terminate/2`; and
  `erlang:function_exported/3`, which it asks.
- **`supervisor`**, as a shim: one_for_one, one_for_all, rest_for_one and
  simple_one_for_one; permanent, transient and temporary children and their
  shutdown; the restart intensity; start_child, terminate_child,
  restart_child, delete_child, which_children and count_children.
- **Stacktraces as OTP's**: a failing BIF's or operator's own frame with its
  arguments and `error_info`, a `function_clause`'s and an `undef`'s with the
  function's arguments, and `erlang:raise/3` keeping the stacktrace it is
  given; a crash report writes the call as the shell does.
- **`examples/leds.beam`**: "let it crash" on a P2-EDGE's two LEDs, a blinker
  for each under an OTP supervisor that starts a new one when its bug crashes
  it.

