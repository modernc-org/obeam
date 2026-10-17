%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% waits: a receive's timeout with messages coming meanwhile. A receive of no
%% clauses, an after alone, ends at its time though a message comes while it
%% waits, and the message stays for a later receive; one that waits for ever
%% goes on waiting when a message comes; and messages a receive has no clause
%% for do not put its timeout off.
-module(waits).
-export([main/0]).

main() ->
    Self = self(),
    spawn(fun() -> receive after 50 -> Self ! early end end),
    receive after 200 -> ok end,
    io:format("after an after alone: ~w~n", [mailbox()]),
    Sleeper = spawn(fun() -> receive after infinity -> ok end end),
    Sleeper ! wake_up,
    receive after 50 -> ok end,
    io:format("an after infinity alone waits on: ~w~n", [is_process_alive(Sleeper)]),
    exit(Sleeper, kill),
    T0 = erlang:monotonic_time(millisecond),
    spawn(fun() -> noise(Self, 12) end),
    R = receive never -> never after 300 -> timeout end,
    T = erlang:monotonic_time(millisecond) - T0,
    io:format("~w, in time: ~w~n", [R, T < 450]),
    receive after 400 -> ok end,
    io:format("the noise: ~w~n", [length(mailbox())]).

noise(_, 0) -> ok;
noise(To, N) ->
    receive after 50 -> To ! {noise, N} end,
    noise(To, N - 1).

mailbox() ->
    receive M -> [M | mailbox()] after 0 -> [] end.
