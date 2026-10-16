%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% cogs: seven workers that each do some work and report which scheduler ran
%% them last, which shows the processes spread over the cogs. What it prints
%% depends on the scheduling, so it is a demo for the board, not a test.
-module(cogs).
-export([main/0, worker/2]).

main() ->
    spawn_workers(self(), 7),
    io:format("~w~n", [collect(7, [])]).

spawn_workers(_, 0) -> ok;
spawn_workers(Parent, N) ->
    spawn(?MODULE, worker, [Parent, N]),
    spawn_workers(Parent, N - 1).

worker(Parent, N) ->
    Parent ! {done, N, spin(20000, 0), p2:cog()}.

%% spin counts, a tail call a step, so that the workers are long enough on
%% the schedulers to be seen there together. It is a tail call because a
%% process's stack here is bounded by its largest heap block, 8,192 longs,
%% where Erlang's grows without limit.
spin(0, Acc) -> Acc;
spin(N, Acc) -> spin(N - 1, Acc + 1).

collect(0, Acc) -> insert_all(Acc, []);
collect(N, Acc) ->
    receive
        {done, I, Steps, Cog} -> collect(N - 1, [{I, Steps, Cog} | Acc])
    end.

insert_all([], Sorted) -> Sorted;
insert_all([H | T], Sorted) -> insert_all(T, insert(H, Sorted)).

insert(X, [H | T]) when H < X -> [H | insert(X, T)];
insert(X, L) -> [X | L].
