%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% pingpong: two processes passing a message back and forth, the first demo.
%% ping and pong are started by name, so they are exported.
-module(pingpong).
-export([main/0, start/1, ping/3, pong/0]).

start(N) ->
    Pong = spawn(?MODULE, pong, []),
    spawn(?MODULE, ping, [self(), Pong, N]),
    receive
        {done, Rounds} -> Rounds
    end.

ping(Parent, Pong, N) -> ping(Parent, Pong, N, 0).

ping(Parent, Pong, 0, Rounds) ->
    Pong ! stop,
    Parent ! {done, Rounds};
ping(Parent, Pong, N, Rounds) ->
    Pong ! {ping, self()},
    receive
        pong -> ping(Parent, Pong, N - 1, Rounds + 1)
    end.

pong() ->
    receive
        {ping, From} ->
            From ! pong,
            pong();
        stop ->
            ok
    end.

main() ->
    io:format("done ~w~n", [start(10)]).
