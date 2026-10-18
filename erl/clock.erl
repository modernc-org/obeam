%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% clock: erlang:system_time/0,1, time_offset/0,1 and timestamp/0,
%% os:system_time/0,1 and os:timestamp/0, statistics/1's wall_clock and
%% runtime, and pid_to_list/1, which the board has as shims,
%% erl/shim/erlang.erl and erl/shim/os.erl. The times are compared, not
%% printed, being the clock's, and the board's counting from its start.
-module(clock).
-export([main/0]).

main() ->
    S = erlang:system_time(second),
    M = erlang:system_time(millisecond),
    N = erlang:system_time(),
    p(system_time, [is_integer(S), abs(M div 1000 - S) =< 1, near(N div 1000000, M),
                    near(erlang:system_time(perf_counter) div 1000000, M)]),
    M1 = erlang:system_time(millisecond),
    p(os_system_time, [near(os:system_time() div 1000000, M1), near(os:system_time(millisecond), M1)]),
    Off = erlang:system_time() - erlang:monotonic_time() - erlang:time_offset(),
    p(time_offset, [abs(Off) =< erlang:convert_time_unit(50, millisecond, native),
                    erlang:time_offset(second) =:= erlang:convert_time_unit(erlang:time_offset(), native, second)]),
    S1 = erlang:system_time(second),
    p(timestamp, [stamp(erlang:timestamp(), S1), stamp(os:timestamp(), S1)]),
    T0 = os:timestamp(),
    timer:sleep(20),
    p(now_diff, timer:now_diff(os:timestamp(), T0) >= 20000),
    {W0, _} = statistics(wall_clock),
    timer:sleep(50),
    {W1, D1} = statistics(wall_clock),
    p(wall_clock, [W1 - W0 >= 50, D1 >= 50, abs(D1 - (W1 - W0)) =< 1]),
    Self = self(),
    timer:sleep(100),
    spawn(fun() -> Self ! statistics(wall_clock) end),
    p(since_any_process, receive {_, D2} -> D2 >= 100 end),
    {_, D3} = statistics(wall_clock),
    p(since_last, D3 < 100),
    {R0, _} = statistics(runtime),
    {R1, D4} = statistics(runtime),
    p(runtime, [is_integer(R0), R1 >= R0, D4 >= 0]),
    L = pid_to_list(self()),
    p(pid_to_list, [L =:= lists:flatten(io_lib:format("~w", [self()])), hd(L) =:= $<, lists:last(L) =:= $>]),
    p(errors, [err(fun() -> erlang:system_time(id(bad)) end),
               err(fun() -> erlang:system_time(id(0)) end),
               err(fun() -> erlang:time_offset(id(bad)) end),
               err(fun() -> os:system_time(id(bad)) end),
               err(fun() -> statistics(id(bad)) end),
               err(fun() -> pid_to_list(id(x)) end)]).

%% near tells two readings of the clock in milliseconds taken one after the
%% other, the test's load allowed for.
near(A, B) -> abs(A - B) =< 50.

%% stamp checks a timestamp's shape and that it says the second S, or the
%% next.
stamp({Mega, Sec, Micro}, S) ->
    is_integer(Mega) andalso Sec >= 0 andalso Sec < 1000000 andalso Micro >= 0 andalso Micro < 1000000
        andalso (Mega * 1000000 + Sec - S) div 2 =:= 0.

id(X) -> X.

err(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
