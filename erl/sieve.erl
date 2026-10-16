%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% sieve: the primes to Max through a chain of filter processes, one for each
%% prime found, the numbers streamed through them.
-module(sieve).
-export([main/0, primes/1]).

primes(Max) ->
    Main = self(),
    First = spawn(fun() -> sieve(Main) end),
    generate(2, Max, First),
    collect([]).

generate(N, Max, To) when N > Max -> To ! done;
generate(N, Max, To) ->
    To ! N,
    generate(N + 1, Max, To).

%% sieve is the end of the chain. The first number to reach it is a prime, and
%% it becomes that prime's filter, with a new end of the chain behind it.
sieve(Main) ->
    receive
        done ->
            Main ! done;
        P ->
            Main ! {prime, P},
            Next = spawn(fun() -> sieve(Main) end),
            filter(P, Next)
    end.

filter(P, Next) ->
    receive
        done ->
            Next ! done;
        N when N rem P =:= 0 ->
            filter(P, Next);
        N ->
            Next ! N,
            filter(P, Next)
    end.

collect(Acc) ->
    receive
        {prime, P} -> collect(insert(P, Acc));
        done -> Acc
    end.

insert(X, [H | T]) when H < X -> [H | insert(X, T)];
insert(X, L) -> [X | L].

main() ->
    io:format("~w~n", [primes(100)]).
