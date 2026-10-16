%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% ring: N processes in a ring, a token sent M times around it. Each process
%% but the first is started by a fun of the one before it.
-module(ring).
-export([main/0, start/2]).

start(N, M) ->
    Main = self(),
    spawn(fun() -> first(Main, N, M) end),
    receive
        {done, Hops} -> Hops
    end.

%% first builds the rest of the ring, which closes back on it, and counts the
%% rounds of the token.
first(Main, N, M) ->
    Next = build(N - 1, self()),
    Next ! {token, 1},
    rounds(Main, Next, M, 0).

build(0, First) -> First;
build(K, First) -> spawn(fun() -> hop(build(K - 1, First)) end).

hop(Next) ->
    receive
        {token, Hops} ->
            Next ! {token, Hops + 1},
            hop(Next);
        stop ->
            Next ! stop
    end.

rounds(Main, Next, M, Done) ->
    receive
        {token, Hops} when Done + 1 =:= M ->
            Next ! stop,
            receive
                stop -> ok
            end,
            Main ! {done, Hops};
        {token, Hops} ->
            Next ! {token, Hops + 1},
            rounds(Main, Next, M, Done + 1)
    end.

main() ->
    io:format("~w~n", [start(100, 100)]).
