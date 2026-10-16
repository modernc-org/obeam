----

Prompt:

> How much code is the Erlang's Beam virtual machine?

----

The core Erlang virtual machine (**BEAM**, located in `erts/emulator/` inside the Erlang/OTP source tree) consists of roughly **280,000 to 330,000 lines of source code (SLOC)**—predominantly C99 with a C++17 subsystem for the JIT compiler—or about **420,000+ physical lines** including comments and blanks.

Because "BEAM" is often used interchangeably with the broader runtime or the entire OTP release, the exact footprint depends on where you draw the boundary:

* **Core BEAM Emulator (`erts/emulator/`):** **~300,000 SLOC** (C, C++, and `.tab` instruction definitions), plus ~70,000 SLOC of vendored/patched libraries (`asmjit`, `pcre`, `zlib`, `ryu`).
* **Full Erlang Run-Time System (`erts/`):** **~420,000 SLOC** once you include the multi-threading support library (`erts/lib_src/`), OS process managers (`erlexec`, `epmd`, `heart`, `run_erl`), and preloaded bootstrap Erlang modules.
* **Complete Erlang/OTP Repository:** **~1.8 million+ SLOC** (the majority of which is written in Erlang across the compiler, standard library, OTP applications, and test suites).

---

## Subsystem Breakdown (`erts/emulator/`)

| Subsystem | Directory | Primary Language | Approx. SLOC | What It Contains |
| --- | --- | --- | --- | --- |
| **Core Runtime, GC & SMP** | `beam/` (root) | C | ~165,000 | Process control (`erl_process.c` alone is ~14k lines), SMP work-stealing schedulers, per-process garbage collector (`erl_gc.c`), memory allocators (`erl_alloc*`), ETS tables (`erl_db*`), NIF/driver APIs, and BIFs. |
| **Bytecode Interpreter** | `beam/emu/` | C + `.tab` DSL | ~15,000 (handwritten)<br>

<br>*~60,000+ (generated)* | The classic threaded-code interpreter (`beam_emu.c` is only ~650 SLOC) plus instruction transformation and dispatch tables (`ops.tab`, `instrs.tab`). |
| **BeamAsm JIT Compiler** | `beam/jit/` | C++17 | ~42,000 | Native `x86_64` and `aarch64` JIT backends (`beam_asm*`, `instr_*.cpp`) that translate BEAM instructions directly into machine code at module load time. |
| **OS Abstraction & Threads** | `sys/` + `erts/lib_src/` | C | ~45,000 | Platform layers (`unix/`, `win32/`, `common/`), non-blocking kernel poll loops (`erl_poll.c` for `epoll`/`kqueue`/`select`), custom atomics, mutexes, and thread-progress barriers (`ethread`). |
| **Built-in Drivers & NIFs** | `drivers/` + `nifs/` | C | ~35,000 | Core TCP/UDP/SCTP socket drivers (`inet_drv.c` is ~13k lines), file I/O, TTY/console handling, and built-in cryptographic/string NIFs. |
| **Vendored & Patched Deps** | `asmjit/`, `pcre/`, `ryu/` | C++ / C | ~70,000 | `asmjit` (~40k SLOC C++) used by BeamAsm; heavily modified PCRE (~15k SLOC C), `ryu` float formatting, and `zlib`. |

---

## Three Quirks of the Codebase

1. **Heavy Build-Time Code Generation (`beam_makeops`):**
If you open `erts/emulator/beam/emu/beam_emu.c`, the main interpreter file is surprisingly small (~656 SLOC). That is because BEAM's instruction set, superinstructions, and operand-packing rules are written in a custom domain-specific language across `.tab` files (`ops.tab`, `instrs.tab`, `bif.tab`). During the build, a ~3,500-line Perl script (`beam_makeops`) processes these tables and emits tens of thousands of lines of C headers (`beam_hot.h`, `beam_warm.h`, `beam_cold.h`, `beam_opcodes.c`) that get `#include`d directly into `process_main()`.
2. **C++ is Strictly Confined to the JIT:**
The core runtime is 100% portable C. C++ was only introduced in OTP 24 for **BeamAsm** (`beam/jit/` and `asmjit/`). When configured with `--disable-jit` (or compiled for targets without an `x86_64` or `aarch64` JIT backend), the C++ files are skipped entirely and the build produces a pure C emulator using GCC/Clang computed gotos (`&&label` address-of-label extensions)—or a standard ANSI C `switch` loop if computed gotos are unavailable.
3. **Reduction-Yielding Regular Expressions (`erts/emulator/pcre/`):**
Rather than linking against a system `libpcre` dynamically, BEAM vendors a customized copy of PCRE. The internal matching loop is instrumented with Erlang reduction counters and explicit state checkpointing so that a catastrophic backtracking regex pauses mid-execution when its process exhausts its ~4,000-reduction slice, yields the OS thread back to the scheduler, and resumes later without blocking other Erlang processes.

---

## How Small *Can* a BEAM VM Be?

Much of upstream ERTS's ~300k SLOC comes from decades of production hardening: lock-free/fine-grained SMP work stealing, non-blocking code upgrades across three generations of code tables, DTrace/SystemTap probes, crash dump analyzers, and multi-carrier memory allocators designed to fight fragmentation on terabyte-scale servers.

If you only need a clean-room C implementation capable of loading `.beam` files and running concurrent actor processes, **AtomVM** (an open-source BEAM implementation in C99 targeting microcontrollers like ESP32/RP2040 as well as POSIX systems) implements a working BEAM runtime in roughly **25,000 to 30,000 SLOC of C**.

----

Prompt:

> WRT "beam_emu.c": What can run on this tiny (650 SLOC) VM? Any Erlang/Elixir code compiled to byte code? Or just some subset?
>
> Context: I am developing OctoGo (https://github.com/modernc-org/ogo). One of it's showcase programs is a PDP-11/40 emulator (https://github.com/modernc-org/p2-11). I just realized that the Beam VM is possibly another showcase OctoGo project.
>
> Tell me please what would be feasible in your opinion. Thank you.

----

`beam_emu.c` is a bit of an illusion: while the file itself is only ~650 lines of C, **it cannot run anything on its own**—and conversely, once it is compiled with its generated headers and linked into the runtime, it runs **100% of all Erlang and Elixir bytecode ever written**.

Here is the exact reality of what `beam_emu.c` actually is, followed by why a BEAM VM is actually a brilliant fit for **OctoGo** on the Propeller 2—provided you target the *raw instruction set* rather than upstream's superinstruction machinery.

---

## 1. The Reality of `beam_emu.c`

`beam_emu.c` is not a standalone miniature VM; it is the skeleton of the `process_main()` C function. Inside `beam_emu.c`, you will find lines like:

```c
#include "beam_hot.h"
#include "beam_warm.h"
#include "beam_cold.h"

```

When you build Erlang/OTP, the `beam_makeops` Perl script reads `instrs.tab` and `ops.tab` (~10,000 lines of macro-like DSL) and generates those three `.h` files—which expand to **~60,000 lines of C code** containing the actual `case` / `&&label` handlers for over **400+ specialized internal opcodes**.

Furthermore, those generated instruction handlers constantly call into the rest of `erts/emulator/beam/` for:

* **Term allocation & copying GC** (`HAlloc`, `erts_garbage_collect`)
* **Arbitrary-precision bignum arithmetic** (`big.c`)
* **Pattern-matching binaries / bitstrings** (`erl_bits.c`)
* **Built-In Functions (BIFs)** (`erlang:spawn/3`, `erlang:send/2`, maps, tuples, lists)

So `beam_emu.c` alone isn't a self-contained 650-line interpreter. **However**, the reason upstream `erts` is 300,000 lines is because of the *loader transformations*, SMP work-stealing, ETS tables, and OTP enterprise plumbing—**not** because the BEAM virtual machine architecture itself is complex.

---

## 2. How Big is the *Actual* BEAM Architecture?

If you strip away upstream ERTS's loader optimizations (which fuse sequences of simple opcodes into hundreds of specialized "superinstructions"), the actual `.beam` file format produced by the standard Erlang (`erlc`) and Elixir (`elixirc`) compilers is surprisingly small and clean:

* **The `.beam` File Container:** A trivial IFF-like chunked format (`Atom`/`AtU8`, `Code`, `StrT`, `ImpT`, `ExpT`, `LitT`, `FunT`). You can write a complete `.beam` chunk parser and loader in **~400–600 lines of Go/OctoGo**.
* **Register Machine:**
* `X[0..N]` registers: Temporary working registers and function arguments (usually an array of 16 to 64 machine words per scheduler).
* `Y[0..N]` registers: Local stack frame slots living on the current Erlang process stack.
* `FR[0..N]` registers: Floating-point registers (optional if you only target integer/control-flow workloads first).


* **The Canonical Opcode Set (`genop.tab`):**
There are ~180 historical opcodes in Erlang's `genop.tab`, many of which are obsolete or deprecated. A current OTP 26/27 compiler only emits roughly **85 to 100 active opcodes**—and a core subset of **~45–55 opcodes** is enough to run arbitrary functional Erlang/Elixir code with tail recursion, closures, pattern matching, tuples, lists, `spawn`, `send` (`!`), and `receive`.
* **Tagged Word Representation (32-bit or 64-bit):**
Every Erlang term fits in a single machine word (`uint32` fits the P2's 32-bit architecture naturally!) using 2 to 4 low tag bits:
* **Immediates (live entirely in the 32-bit word):** Small integers (28-bit signed fixnums), Atoms (index into global atom table), PIDs (process ID), Ports, and `NIL` (`[]`).
* **Boxed Pointers (point to process heap words):** Cons cells (`[H|T]`, just 2 words), Tuples (header word + $N$ element words), Closures, and Binaries.



---

## 3. Feasibility as an OctoGo / Propeller 2 (`P2`) Showcase

Comparing this to your **PDP-11/40 emulator (`p2-11`)**, a BEAM VM in OctoGo (`p2-beam` or `ogo-beam`) is **100% feasible** and arguably an even more eye-catching showcase for the Propeller 2. Here is why:

### Why P2 + OctoGo + BEAM is a Killer Combination

1. **8 Hardware Cogs = 8 True SMP BEAM Schedulers:**
BEAM's claim to fame is running thousands of isolated, ultra-lightweight actor processes across multi-core schedulers with preemptive reduction counting. Mapping 1 BEAM scheduler per P2 Cog (say, 6 or 7 Cogs running BEAM schedulers pulling from a run queue in Hub RAM, and 1 Cog handling serial console / I/O ports) demonstrates genuine multi-core actor concurrency on a microcontroller!
2. **Erlang Processes Have Tiny Memory Footprints:**
Unlike POSIX threads or even Go goroutines (which start at 2 KB+ stack), an Erlang process control block (PCB) plus initial stack/heap is only **~300 bytes** (a few dozen 32-bit words). Even in the P2's **512 KB of Hub RAM** (or more if using PSRAM), you can allocate a shared pool of 32-bit heap blocks and run **500 to 1,500 concurrent Erlang/Elixir processes** simultaneously passing messages to each other.
3. **Zero-Allocation OctoGo Synergy:**
Because OctoGo targets bare-metal/zero-allocation semantics, the BEAM VM itself doesn't need a host garbage collector! You statically allocate a big `[65536]uint32` arena in Hub RAM for the Erlang process heaps/mailboxes and a fixed `[1024]Process` table. Each Erlang process stacks downward and heaps upward inside its own tiny slice of that `uint32` array, and when a process dies (common in Erlang), its slice is returned to the block allocator in $O(1)$ time with zero GC work.
4. **Hardware I/O via Erlang Ports / BIFs:**
Controlling P2 Smart Pins, toggling LEDs, generating PWM, or reading UART directly from Erlang/Elixir pattern-matching actor loops (`Pid ! {pin_toggle, 56}`) makes for an unforgettable hardware demo.

---

## 4. What Subset vs. Full Language Can You Run?

If you write a **~2,500 to 4,000 SLOC OctoGo BEAM VM**, you can run **standard, unmodified `.beam` files** compiled on a desktop PC with standard `erlc` or `elixirc`! You do **not** need to write an Erlang compiler.

Here is the practical boundary of what works out-of-the-box vs. what you leave out:

| Feature / Workload | Feasible in ~3k SLOC OctoGo? | Notes |
| --- | --- | --- |
| **Unmodified `.beam` files from `erlc` / `elixirc**` | **Yes** | Load standard `.beam` chunks (`AtU8`, `Code`, `Impt`, `Expt`, `LitT`) directly from flash/SD/serial. |
| **Pattern Matching, Guards, Tail Recursion, Higher-Order Funs** | **Yes** | Uses standard `allocate`, `call`, `call_only`, `call_ext`, `select_val`, `is_eq_exact`, `test_heap`, `put_list`, `put_tuple2`, `get_tuple_element`. |
| **`spawn/1,3`, `!` (Send), `receive ... after` (Timers)** | **Yes** | About 8 opcodes (`send`, `loop_rec`, `loop_rec_end`, `wait`, `wait_timeout`, `timeout`, `remove_message`) plus a mailbox queue per process. |
| **Classic Concurrency Benchmarks (`ring`, `pingpong`, Prime Sieve, Dining Philosophers)** | **Yes** | Standard Joe Armstrong "spawn 1,000 processes in a ring and pass a token 10,000 times" runs unmodified! |
| **Elixir Modules & Pipelines (`|>`)** | **Yes** | Elixir compiles down to the exact same BEAM opcodes as Erlang. Any Elixir module that doesn't call massive `Enum`/`String` stdlib dependencies runs directly. |
| **Full OTP Standard Library (`gen_server`, `application`, `ets`, `mnesia`)** | **No (Too heavy for 512 KB RAM)** | Upstream OTP's `stdlib`/`kernel` pulls in megabytes of `.beam` files and requires hundreds of C BIFs (`ets`, regexes, socket drivers). Instead, like **AtomVM**, you provide a tiny ~200-line `erlang` BIF shim (`self/0`, `spawn/3`, `send/2`, `monotonic_time/0`, `display/1`, plus P2 hardware BIFs). |

---

## 5. Existing Prior Art to Reference

If you want to inspect clean, readable references rather than digging through `erts`'s 300k lines of macro soup:

1. **AtomVM (`[github.com/atomvm/AtomVM](https://github.com/atomvm/AtomVM)`):** A production-grade embedded BEAM VM in C99 for ESP32, STM32, and RP2040. Its core interpreter loop (`src/libAtomVM/context.c` and `opcodesswitch.h`) handles standard `.beam` opcodes directly without `beam_makeops` transformation tables.
2. **ward (`[github.com/kvakvs/ward](https://github.com/kvakvs/ward)`) / GluonVM (`[github.com/kvakvs/gluonvm](https://github.com/kvakvs/gluonvm)`):** Earlier minimalist BEAM VMs designed specifically to understand the smallest viable subset of opcodes needed to boot Erlang code.
3. **Erlang's `lib/compiler/src/genop.tab`:** This single text file in the Erlang/OTP repo is the ground-truth specification of every raw opcode number (1 to ~184), its name, and its arity as emitted into `.beam` files before loader fusion.

If you'd like, we can sketch out the exact 32-bit term tagging scheme, the `.beam` chunk loader structure, or the ~45 opcodes needed to get an Erlang process-ring benchmark and P2 Smart Pin blinker running in OctoGo.
