%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% leds: "let it crash", to be seen. The P2-EDGE's two LEDs, on pins 56 and
%% 57, are each blinked by a process of its own under an OTP supervisor. A
%% blinker has a bug: now and then it divides by zero and crashes, and its
%% LED goes out; the supervisor starts a new one, which keeps the LED dark
%% for a second, says so, and blinks again, while the other one blinks on.
%% It runs on the board only, until the board is reset; on a P2-EDGE the DIP
%% switch LED is to be on.
-module(leds).
-behaviour(supervisor).
-export([main/0, init/1, start_blinker/2]).

main() ->
    io:format("leds: a blinker for each LED, under a supervisor; each crashes now and then~n"),
    {ok, _} = supervisor:start_link({local, leds}, ?MODULE, []),
    receive after infinity -> ok end.

%% init is the supervisor's: a blinker for each LED, one restarted when it
%% crashes, ten crashes in ten seconds allowed.
init([]) ->
    {ok, {#{strategy => one_for_one, intensity => 10, period => 10},
          [blinker(56, 250), blinker(57, 400)]}}.

blinker(Pin, Ms) ->
    #{id => Pin, start => {?MODULE, start_blinker, [Pin, Ms]}}.

start_blinker(Pin, Ms) ->
    {ok, spawn_link(fun() -> begin_blinking(Pin, Ms) end)}.

begin_blinking(Pin, Ms) ->
    p2:pin_float(Pin),
    io:format("the blinker of pin ~w starts~n", [Pin]),
    receive after 1000 -> ok end,
    blink(Pin, Ms).

%% blink toggles its pin and waits a little more than Ms milliseconds, by a
%% jitter it computes with a bug: the divisor is zero once in 32 times.
blink(Pin, Ms) ->
    p2:pin_toggle(Pin),
    Jitter = 64 div (p2:rnd() rem 32),
    receive after Ms + Jitter -> blink(Pin, Ms) end.
