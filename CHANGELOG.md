# Changelog

Notable changes per release of `obeam`, the command, and of the VM it
carries. OctoBeam is an early preview and its version numbers say so: a
release may refuse a program the last one took, and such changes are called
out under **Behaviour changes**.

A released section is frozen: it says what that release did, and a later fix
to the same area is a new entry under **Unreleased**, not an edit to the old
one. `git show vX.Y.Z:CHANGELOG.md` is the check.

## v0.1.2

The first release. v0.1.0 and v0.1.1 were tagged but withdrawn before they
were published: on a Mac, v0.1.0's loads failed eight times in ten, and in
v0.1.1 a Ctrl-Z pressed during a load suspended `obeam`, which kept the
board's port.

### Added

- **`obeam`, one program for users**: `obeam hello.beam` writes `hello.binary`,
  the VM with the program in its arena, and `obeam run hello.beam` loads it onto
  a P2 board and shows what it prints. It carries the VM built twice, checked
  and, for `-unchecked`, without the runtime checks and with 55 KB more for the
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
- **More of OTP's library, as shims**: `string`, `timer`, `queue`,
  `proplists`, `rand` (over the P2's hardware generator), and the functions
  of `erlang` that Erlang can write, `tuple_to_list/1`, `spawn_monitor/1,3`
  and conversions in a base among them; each held to OTP's own.
- **`~s` and `io:put_chars` take nested chardata**, as OTP's do: what
  `string:pad/2` and `string:replace/3` answer prints.
- **The process dictionary**, `put/2`, `get/0,1`, `get_keys/0,1` and
  `erase/0,1`; **`io_lib:format/2`**; `list_to_tuple/1`,
  `list_to_existing_atom/1` and `binary_to_existing_atom/1,2`; `node/0,1`;
  `ceil/1` and `floor/1`; and `halt/0,1,2`, after which nothing more is
  written.
- **`erlang:send_after/3,4`, `start_timer/3,4`, `cancel_timer/1,2` and
  `read_timer/1,2`**, as a shim: one process keeps the timers.
- **The clock**, as shims: `erlang:system_time/0,1`, `time_offset/0,1` and
  `timestamp/0`, `os:system_time/0,1` and `os:timestamp/0`, counting from the
  board's start, which has no calendar's clock; `statistics/1`'s `wall_clock`
  and `runtime`, the time since the last call of any process as OTP's; and
  `pid_to_list/1`.
- **The floats read and written as OTP does**: `float_to_list/1,2` and
  `float_to_binary/1,2` with `decimals`, `scientific`, `compact` and `short`,
  `list_to_float/1` and `binary_to_float/1`, the nearest 32-bit float to any
  number of digits; and `~e`, `~f` and `~g` from the exact 21 digits OTP
  writes them from, at any precision, where the VM's own worked in 32-bit
  floats. A directive without a field width writes all it has, where it was
  cut at 256 bytes. Reading a float is slow, 5 to 34 ms on the board, a trade
  of speed for the heaps' room.
- **Stacktraces as OTP's**: a failing BIF's or operator's own frame with its
  arguments and `error_info`, a `function_clause`'s and an `undef`'s with the
  function's arguments, and `erlang:raise/3` keeping the stacktrace it is
  given; a crash report writes the call as the shell does.
- **`examples/leds.beam`**: "let it crash" on a P2-EDGE's two LEDs, a blinker
  for each under an OTP supervisor that starts a new one when its bug crashes
  it.

