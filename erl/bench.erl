%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% bench: the profiler's workload, what the corpus's modules compute, with
%% one line printed at the end, so that the serial line does not dominate
%% what is measured: recursion, lists, funs, tuples, messages and a ring.
-module(bench).
-export([main/0]).

main() ->
    Fib = fib:fib(18),
    Seq = lst:seq(1, 1000),
    Squares = lst:sum(lst:map(fun(X) -> X * X end, Seq)),
    Rev = hd(lst:reverse(Seq)),
    Points = points(2000, tuples:point(0, 0)),
    Pings = pingpong:start(300),
    Hops = ring:start(50, 40),
    Primes = length(sieve:primes(300)),
    io:format("~w~n", [[Fib, Squares, Rev, Points, Pings, Hops, Primes]]).

%% points moves a record a step at a time and sums where it has been.
points(0, P) -> element(2, P) + element(3, P);
points(N, P) -> points(N - 1, setelement(2, P, element(2, P) + 1)).
