%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% sup: links and monitors past what a process held before the pool of them,
%% four each, and past the pool's 512 records unless each comes back: fifty
%% linked workers whose exits are seen, six hundred monitors that fire, six
%% hundred watchers that end while they watch a server, six hundred links
%% made and taken back, and a demonitor that stops its DOWN.
-module(sup).
-export([main/0, worker/1]).

worker(N) ->
    receive
        go -> exit({done, N})
    end.

main() ->
    process_flag(trap_exit, true),
    Ws = workers(50, []),
    go(Ws),
    io:format("~w~n", [collect(Ws, 0)]),
    io:format("~w~n", [monitors(600, 0)]),
    S = spawn(fun() -> receive stop -> ok end end),
    io:format("~w~n", [watchers(S, 600, 0)]),
    io:format("~w~n", [links(S, 600, 0)]),
    S ! stop,
    W = spawn(fun() -> receive go -> ok end end),
    Ref = monitor(process, W),
    io:format("~w~n", [demonitor(Ref)]),
    W ! go,
    receive
        {'DOWN', Ref, process, W, _} -> io:format("down~n")
    after 20 -> io:format("no down~n")
    end.

workers(0, Acc) -> Acc;
workers(N, Acc) -> workers(N - 1, [spawn_link(?MODULE, worker, [N]) | Acc]).

go([]) -> ok;
go([W | Ws]) ->
    W ! go,
    go(Ws).

collect([], Sum) -> Sum;
collect([W | Ws], Sum) ->
    receive
        {'EXIT', W, {done, N}} -> collect(Ws, Sum + N)
    end.

%% A monitor of a process that ends: the DOWN gives both records back.
monitors(0, Seen) -> Seen;
monitors(N, Seen) ->
    W = spawn(fun() -> receive go -> ok end end),
    Ref = monitor(process, W),
    W ! go,
    receive
        {'DOWN', Ref, process, W, normal} -> monitors(N - 1, Seen + 1)
    end.

%% A process that monitors the server and ends: its end gives the server's
%% record back.
watchers(_, 0, Done) -> Done;
watchers(S, N, Done) ->
    Self = self(),
    spawn(fun() -> monitor(process, S), Self ! watching end),
    receive
        watching -> watchers(S, N - 1, Done + 1)
    end.

%% A link to the server, taken back.
links(_, 0, Made) -> Made;
links(S, N, Made) ->
    true = link(S),
    true = unlink(S),
    links(S, N - 1, Made + 1).
