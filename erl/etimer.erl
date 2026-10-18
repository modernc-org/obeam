%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% etimer: erlang:send_after/3,4, start_timer/3,4, cancel_timer/1,2 and
%% read_timer/1,2, which the board has as a shim, erl/shim/erlang.erl. The
%% times left are compared, not printed, being the clock's.
-module(etimer).
-export([main/0]).

main() ->
    R1 = erlang:send_after(30, self(), one),
    R2 = erlang:start_timer(10, self(), two),
    R3 = erlang:send_after(1000, self(), never),
    p(refs, [is_reference(R1), is_reference(R2), R1 =/= R2]),
    p(read, [erlang:read_timer(R3) > 900, erlang:read_timer(make_ref())]),
    C1 = erlang:cancel_timer(R3),
    C2 = erlang:cancel_timer(R3),
    p(cancel, [C1 > 900, C2, erlang:read_timer(R3)]),
    p(first, receive M1 -> M1 =:= {timeout, R2, two} end),
    p(second, receive M2 -> M2 end),
    p(fired, [erlang:cancel_timer(R1), erlang:read_timer(R2)]),
    p(nothing, receive X -> X after 50 -> none end),
    erlang:send_after(20, self(), a),
    erlang:send_after(20, self(), b),
    erlang:send_after(10, self(), c),
    p(order, [receive Y -> Y end || _ <- [1, 2, 3]]),
    R4 = erlang:send_after(500, self(), x4),
    p(async, [erlang:cancel_timer(R4, [{async, true}]), receive {cancel_timer, R4, L4} -> L4 > 400 end]),
    R5 = erlang:send_after(500, self(), x5),
    N5 = erlang:cancel_timer(R5, [{info, false}]),
    A5 = erlang:read_timer(R5, [{async, true}]),
    p(no_info, [N5, A5, receive {read_timer, R5, L5} -> L5 end]),
    p(async_no_info, [erlang:cancel_timer(make_ref(), [{async, true}, {info, false}]), receive Z -> Z after 20 -> none end]),
    erlang:send_after(erlang:monotonic_time(millisecond) + 20, self(), abs, [{abs, true}]),
    p(abs, receive abs -> ok end),
    register(etimer_box, self()),
    erlang:send_after(10, etimer_box, by_name),
    erlang:send_after(5, nobody_here, lost),
    erlang:send_after(5, spawn(fun() -> ok end), lost),
    p(name, receive by_name -> ok end),
    p(errors, [err(fun() -> erlang:send_after(id(-1), self(), x) end),
               err(fun() -> erlang:send_after(id(1.0), self(), x) end),
               err(fun() -> erlang:send_after(1, id(3), x) end),
               err(fun() -> erlang:send_after(1, self(), x, id([bad])) end),
               err(fun() -> erlang:cancel_timer(id(x)) end),
               err(fun() -> erlang:read_timer(id(x)) end),
               err(fun() -> erlang:cancel_timer(make_ref(), id([{async, perhaps}])) end)]),
    R6 = erlang:start_timer(0, self(), z, [{abs, false}]),
    p(start_timer4, receive {timeout, R6, z} -> ok end),
    p(empty, receive W -> W after 30 -> none end).

id(X) -> X.

err(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
