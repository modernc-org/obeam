%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% funs: closures, higher-order functions, a fun of an external function and
%% apply.
-module(funs).
-export([main/0, twice/2]).

adder(N) -> fun(X) -> X + N end.

compose(F, G) -> fun(X) -> F(G(X)) end.

twice(F, X) -> F(F(X)).

main() ->
    Add3 = adder(3),
    Dbl = fun(X) -> X * 2 end,
    io:format("~w ~w~n", [Add3(4), twice(Dbl, 5)]),
    Both = compose(Add3, Dbl),
    io:format("~w~n", [Both(10)]),
    Len = fun erlang:length/1,
    io:format("~w ~w~n", [Len([a, b, c]), apply(erlang, tuple_size, [{1, 2}])]),
    io:format("~w~n", [apply(?MODULE, twice, [Add3, 0])]),
    io:format("~w ~w~n", [is_function(Add3), is_function(Dbl, 1)]).
