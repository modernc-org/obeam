%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% leds: "let it crash", to be seen. The P2-EDGE's two LEDs, on pins 56 and
%% 57, are each blinked by a process of its own, which has a bug: now and then
%% it divides by zero and crashes, and its LED goes out. A supervisor, linked
%% to both and trapping their exits, sees it go, says so, and a second later
%% starts a new blinker on that pin, while the other one blinks on. It runs
%% on the board only, until the board is reset; on a P2-EDGE the DIP switch
%% LED is to be on.
-module(leds).
-export([main/0, blinker/2]).

main() ->
    process_flag(trap_exit, true),
    io:format("leds: a blinker for each LED, under a supervisor; each crashes now and then~n"),
    supervise([start(56, 250), start(57, 400)], 0).

start(Pin, Ms) ->
    {spawn_link(?MODULE, blinker, [Pin, Ms]), Pin, Ms}.

supervise(Kids, Restarts) ->
    receive
        {'EXIT', Pid, Reason} ->
            {Pid, Pin, Ms} = lists:keyfind(Pid, 1, Kids),
            p2:pin_float(Pin),
            io:format("supervisor: the blinker of pin ~w died of ~w; restart ~w in a second~n",
                      [Pin, why(Reason), Restarts + 1]),
            receive after 1000 -> ok end,
            supervise(lists:keyreplace(Pid, 1, Kids, start(Pin, Ms)), Restarts + 1)
    end.

why({Reason, _Stack}) -> Reason;
why(Reason) -> Reason.

%% blinker toggles its pin and waits a little more than Ms milliseconds, by
%% a jitter it computes with a bug: the divisor is zero once in 32 times.
blinker(Pin, Ms) ->
    p2:pin_toggle(Pin),
    Jitter = 64 div (p2:rnd() rem 32),
    receive after Ms + Jitter -> blinker(Pin, Ms) end.
