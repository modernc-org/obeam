%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% fib: the doubly recursive definition beside the tail-recursive one.
-module(fib).
-export([main/0, fib/1, fibt/1]).

fib(0) -> 0;
fib(1) -> 1;
fib(N) when N > 1 -> fib(N - 1) + fib(N - 2).

fibt(N) -> fibt(N, 0, 1).

fibt(0, A, _) -> A;
fibt(N, A, B) -> fibt(N - 1, B, A + B).

main() ->
    io:format("~w ~w ~w~n", [fib(20), fibt(20), fibt(40)]).
