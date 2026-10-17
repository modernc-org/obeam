%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% tmr: what a program asks of OTP's timer, which the board has as a shim,
%% erl/shim/timer.erl, held here to the real one: sleeping, timing, one-shot
%% and interval timers, cancelled or not, to processes and to names. What
%% depends on the clock is printed as whether it is within bounds.
-module(tmr).
-export([main/0, ping/2, add/2]).

main() ->
    Self = self(),
    p(sleep, timer:sleep(20)),
    p(units, [timer:seconds(3), timer:minutes(2), timer:hours(1), timer:hms(1, 2, 3)]),
    p(now_diff, timer:now_diff({1, 2, 3}, {0, 999999, 999999})),
    {T1, V1} = timer:tc(fun() -> timer:sleep(30), done end),
    {T2, V2} = timer:tc(fun(X, Y) -> X + Y end, [1, 2]),
    {T3, V3} = timer:tc(?MODULE, add, [3, 4]),
    {T4, V4} = timer:tc(fun() -> timer:sleep(25) end, millisecond),
    p(tc, [V1, V2, V3, V4, T1 >= 30000, T1 < 2000000, T2 >= 0, T3 >= 0, T4 >= 25, T4 < 2000]),
    {ok, _} = timer:send_after(60, self(), late),
    {ok, _} = timer:send_after(20, self(), early),
    {ok, _} = timer:send_after(40, mid),
    p(order, [recv(), recv(), recv()]),
    {ok, {instant, _}} = timer:send_after(0, self(), now),
    p(instant, recv()),
    {ok, R} = timer:send_after(30, self(), cancelled),
    p(cancel, timer:cancel(R)),
    p(after_cancel, recv(80)),
    p(bad, [timer:cancel(nonsense), timer:send_after(-1, self(), x),
            timer:apply_after(10, notafun), timer:send_after(10, "str", x),
            timer:apply_interval(10, fun(_) -> x end)]),
    {ok, _} = timer:apply_after(10, fun() -> Self ! {applied, self() =/= Self} end),
    p(apply_after, recv()),
    {ok, _} = timer:apply_after(10, ?MODULE, ping, [Self, mfa]),
    p(apply_after_mfa, recv()),
    {ok, _} = timer:apply_after(10, fun(X) -> Self ! {arg, X} end, [42]),
    p(apply_after_args, recv()),
    {ok, _} = timer:apply_after(0, ?MODULE, ping, [Self, at_once]),
    p(apply_now, recv()),
    register(tmr_box, self()),
    {ok, _} = timer:send_after(10, tmr_box, by_name),
    p(by_name, recv()),
    {ok, _} = timer:send_after(10, nobody_here, lost),
    p(nobody, recv(50)),
    {ok, I} = timer:send_interval(20, tmr_box, tick),
    p(ticks, [recv(), recv(), recv()]),
    p(cancel_interval, timer:cancel(I)),
    p(no_more_ticks, recv(60)),
    unregister(tmr_box),
    {ok, A} = timer:apply_interval(15, ?MODULE, ping, [Self, beat]),
    p(beats, [recv(), recv()]),
    {ok, cancel} = timer:cancel(A),
    drain(),
    {ok, B} = timer:apply_repeatedly(10, fun() -> Self ! rep, timer:sleep(20) end),
    p(repeatedly, [recv(), recv()]),
    {ok, cancel} = timer:cancel(B),
    drain(),
    W1 = spawn(fun() -> receive _ -> ok end end),
    M1 = monitor(process, W1),
    {ok, _} = timer:kill_after(10, W1),
    p(killed, receive {'DOWN', M1, process, W1, Why1} -> Why1 end),
    W2 = spawn(fun() -> receive _ -> ok end end),
    M2 = monitor(process, W2),
    {ok, _} = timer:exit_after(10, W2, enough),
    p(exited, receive {'DOWN', M2, process, W2, Why2} -> Why2 end),
    W3 = spawn(fun() -> receive _ -> ok end end),
    M3 = monitor(process, W3),
    {ok, K} = timer:kill_after(30, W3),
    {ok, cancel} = timer:cancel(K),
    p(spared, receive {'DOWN', M3, process, W3, Why3} -> Why3 after 80 -> alive end),
    W3 ! bye,
    ok.

ping(Pid, Tag) -> Pid ! Tag.

add(X, Y) -> X + Y.

recv() -> recv(1000).

recv(T) ->
    receive
        X -> X
    after T -> none
    end.

%% drain takes what a timer cancelled had already started on its way.
drain() ->
    receive
        _ -> drain()
    after 50 -> ok
    end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
