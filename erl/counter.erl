%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% counter: a server process with calls that wait for a reply, casts that do
%% not, references to tell the replies apart, and timeouts.
-module(counter).
-export([main/0, start/0, call/2, cast/2]).

start() -> spawn(fun() -> loop(0) end).

call(Pid, Req) ->
    Ref = make_ref(),
    Pid ! {call, self(), Ref, Req},
    receive
        {Ref, Reply} -> Reply
    after 1000 ->
        timeout
    end.

cast(Pid, Req) ->
    Pid ! {cast, Req},
    ok.

loop(N) ->
    receive
        {call, From, Ref, get} ->
            From ! {Ref, N},
            loop(N);
        {call, From, Ref, stop} ->
            From ! {Ref, stopped};
        {cast, incr} ->
            loop(N + 1);
        {cast, {add, K}} when is_integer(K) ->
            loop(N + K)
    after 5000 ->
        idle
    end.

main() ->
    C = start(),
    ok = cast(C, incr),
    ok = cast(C, incr),
    ok = cast(C, {add, 40}),
    io:format("~w~n", [call(C, get)]),
    io:format("~w~n", [call(C, stop)]),
    io:format("~w~n", [call(C, get)]),
    receive
    after 10 -> ok
    end,
    io:format("~w~n", [is_reference(make_ref())]).
