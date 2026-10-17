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
- **The VM**: Erlang and Elixir processes on seven scheduler cogs, messages and
  `receive` with timeouts, links, monitors, exit signals and registered names,
  exceptions caught by `try` and `catch`, 32-bit floats, binaries made and
  matched, maps, Elixir's structs and ranges, `io:format` with its widths and
  precisions, Elixir's `inspect`, and the pins through the module `p2`. The hot
  instructions run in PASM on each scheduler's own cog.
- **The shims**: OTP's `lists`, sixty-two functions of it, and the functions of
  `maps` that take a fun; Elixir's `Enum` and `Map`, as far as the corpus goes.
