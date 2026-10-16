----

Prompt:

> I am developing OctoGo ([https://github.com/modernc-org/ogo](https://github.com/modernc-org/ogo)). Its first showcase project is a PDP-11/40 emulator ([https://github.com/modernc-org/ogo](https://github.com/modernc-org/ogo)). I just talked to my friend who likes Erlang. Here comes the idea: The Beam VM is said to be in just 650 SLOC. Maybe a Propeller 2 Beam VM, running some Erlang/Elixir byte code, using the 8 cogs as the VM + max 7 Erlang processes could be a good fit for people, who like the P2 and Erlanf/Elixir and a another showcase for the OctoGo programming language. WDYT?

----

I like this idea quite a lot. In fact, I think a tiny Erlang runtime on the Propeller 2 could be an even more distinctive OctoGo showcase than the PDP-11/40 emulator.

There is a particularly appealing symmetry:

- Erlang: lightweight, isolated processes communicating by messages.
- Propeller 2: eight independent physical processors (cogs), sharing hub memory.
- OctoGo: Go-like concurrency mapped directly onto those physical processors.

The combination practically suggests itself: one Erlang process per cog, with real hardware parallelism and no software scheduler.

Having looked at [OctoGo's current architecture](https://github.com/modernc-org/ogo?utm_source=chatgpt.com), I also see why this fits your design philosophy. Your goroutines already map 1:1 onto hardware cogs, channels use hub RAM and hardware locks, and the language deliberately avoids a general-purpose scheduler and garbage collector.

My verdict is yes, definitely worth exploring—but I'd distinguish a small BEAM interpreter from an Erlang runtime, and deliberately target a subset.

## Why the P2 is unusually interesting

Actual P2 capabilities, rather than a proposed architecture

# 8

Independent cogs

# 512 KiB

Shared hub RAM

# 2+2 KiB

Cog + LUT RAM per cog

Conceptual eight-cog runtime

Cog 0

VM / control

Cog 1

Actor 1

Cog 2

Actor 2

Cog 3

Actor 3

Cog 4

Actor 4

Cog 5

Actor 5

Cog 6

Actor 6

Cog 7

Actor 7

Shared hub RAM

Loaded bytecode · mailboxes · message pools · process metadata

One possible mapping, not a hardware requirement. The control cog could also interpret an Erlang process.

And the P2 has an especially relevant feature: XBYTE, its hardware-assisted bytecode execution mechanism. It can fetch bytecodes from hub RAM and dispatch through a LUT-based table, with just six clocks of dispatch overhead according to the P2 documentation.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://p2docs.github.io\&sz=32)

Propeller 2 Online Documentation

+1



That makes a bytecode VM a much more natural P2 showcase than it would be on most microcontrollers.

However, XBYTE does not automatically understand BEAM operands or instructions. I'd initially implement an ordinary interpreter in OctoGo and investigate XBYTE as a later optimization.

## The biggest catch: BEAM is not the whole Erlang runtime

I couldn't substantiate the 650 SLOC claim for a usable BEAM implementation. Perhaps it refers to a minimal experimental interpreter.

The Erlang documentation makes an important distinction: BEAM executes bytecode, but the Erlang Runtime System (ERTS) implements processes, message passing and other runtime facilities.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://www.erlang.org\&sz=32)

Erlang/OTP

+1



For this project, I'd rank the challenges as follows:

| Component                                    | My assessment                  |
| -------------------------------------------- | ------------------------------ |
| BEAM instruction dispatch                    | Manageable                     |
| X/Y registers, calls, branches               | Manageable                     |
| BEAM module loader                           | Moderate                       |
| Tagged Erlang terms                          | Moderate                       |
| Mailboxes and selective receive              | Tricky                         |
| Dynamic tuples, lists and memory reclamation | Harder                         |
| Full Erlang/OTP or Elixir compatibility      | Far beyond an initial showcase |

One especially relevant detail: OctoGo channels are rendezvous channels, while Erlang messages are asynchronous and queued. You can't directly reuse channel semantics for `Pid ! Message`. You'd want bounded mailboxes, probably ring buffers in hub RAM, protected with P2 hardware locks.

Similarly, OctoGo itself doesn't need GC, but the guest Erlang program creates dynamic terms. That's a separate memory-management problem. A small runtime could use statically allocated per-process arenas and initially reject programs exceeding their limits. Later, a simple per-process copying GC could be added.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://doc.atomvm.org\&sz=32)

AtomVM 0.6.7+git.bcb9d81a documentation

+1



## How I'd implement the first version

I'd preserve your hardware-process idea and aggressively limit everything else.

1\. Compile Erlang on the host

Use `erlc` to generate real `.beam` files. Start with Erlang rather than Elixir, because Elixir-generated code can have additional library dependencies.

2\. Convert BEAM modules into a small P2 execution image

A host-side tool decodes the BEAM chunks, resolves atoms, imports, labels and supported instructions, then emits a compact image. This avoids spending scarce P2 memory on a complete loader.

3\. Run a minimal interpreter written in OctoGo

Each participating cog has its own instruction pointer, register state, stack and mailbox. Immutable bytecode is shared, while process state lives in bounded hub-memory regions.

4\. Implement real asynchronous message passing

Support `self()`, `spawn`, `send` and `receive`. Initially cap the system at seven guest actors, with fixed mailbox capacities and a clearly documented subset of message-pattern matching.

5\. Optimize using XBYTE only if justified

Benchmark the OctoGo interpreter first. Then consider an XBYTE-friendly instruction representation and small assembly dispatch layer.

One qualification: if you convert BEAM into a custom execution image, it's more accurate to advertise this as running code compiled from Erlang BEAM modules than as executing arbitrary unmodified `.beam` files directly.

## An excellent first demonstration

Imagine running this on the P2, with the two Erlang processes genuinely executing on different cogs:

```

-module(pingpong).
-export([start/0, ping/1, pong/0]).

start() ->
    P = spawn(?MODULE, pong, []),
    spawn(?MODULE, ping, [P]).

ping(P) ->
    P ! {ping, self()},
    receive
        pong -> ping(P)
    end.

pong() ->
    receive
        {ping, From} ->
            From ! pong,
            pong()
    end.

```

This is more compelling than a CPU-intensive benchmark: a genuine Erlang ping-pong program, compiled using Erlang's own compiler, running concurrently on two independent P2 processors.

For an even better showcase, expose the cog identities on GPIO pins. An oscilloscope or logic analyzer could then visibly demonstrate which hardware processor executes which actor.

## One project worth studying

AtomVM is directly relevant. It's a small-footprint implementation that already executes BEAM files on microcontrollers, including STM32 and RP2040/RP2350-based boards.

See [AtomVM on GitHub](https://github.com/atomvm/AtomVM?utm_source=chatgpt.com). Its existing implementation of BEAM instructions, term representation, mailbox handling and memory management could save you significant design work.&#x20;

[image](https://www.google.com/s2/favicons?domain=https://github.com\&sz=32)

atomvm/AtomVM: Tiny Erlang VM · GitHub

+1



I'd study its design, but not necessarily port the entire codebase. For OctoGo, the small, P2-specific implementation is precisely what makes the idea interesting.

## One design question I'd decide early

There are really two possible projects:

A. Hardware Erlang

One guest process per cog, maximum seven or eight processes, no software scheduler.

Most original and the best match for OctoGo's design philosophy.

B. Small conventional Erlang runtime

Many logical Erlang processes, scheduled across available cogs.

More useful to the Erlang community, but significantly more complex and less representative of OctoGo's hardware-native concurrency model.

I'd choose A, emphatically.

The seven-process limit is a severe restriction by ordinary Erlang standards. But as a hardware-native demonstration, it is a feature: each Erlang actor has its own real processor. No preemption, no timeslicing, and no software context switching between guest actors.

That makes the project interesting even to Erlang people who would never deploy an application on this restricted runtime.

My suggested ambition would be a first milestone that runs the compiled `pingpong.erl` example on two dedicated cogs, with bounded mailboxes and a minimal term representation. If that works, the project has already proved its central idea without requiring a full implementation of Erlang.

And that's the exciting part: the PDP-11/40 showcases OctoGo's ability to implement a substantial sequential machine. An Erlang runtime could showcase something fundamentally different: OctoGo expressing a concurrent virtual machine directly in concurrent hardware.
