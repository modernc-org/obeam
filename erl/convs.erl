%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% convs: list_to_tuple/1, the existing atoms of a list or a binary, node/0,1,
%% ceil/1 and floor/1, io_lib:format/2, the floats read and written: ~e, ~f
%% and ~g, float_to_list/1,2 and float_to_binary/1,2, list_to_float/1 and
%% binary_to_float/1. The floats are exact in 32 bits, which the board's
%% floats have, so that the board and erl write the same 21 digits of them,
%% and less than 10^21 where whole digits are written, and past the 21st
%% digit only where the digits end before it; what is read has few digits, so
%% that ~w writes it as erl does. ~p would break lines where erl's does.
-module(convs).
-export([main/0]).

main() ->
    p(list_to_tuple, [list_to_tuple([]), list_to_tuple([a, "b", 1]), err(fun() -> list_to_tuple(id([a | b])) end)]),
    p(existing, [list_to_existing_atom("ok"), list_to_existing_atom("convs"),
                 err(fun() -> list_to_existing_atom(id("zzqq_none")) end), err(fun() -> list_to_existing_atom(id([a])) end),
                 binary_to_existing_atom(<<"main">>), binary_to_existing_atom(<<"ok">>, latin1),
                 err(fun() -> binary_to_existing_atom(id(<<"zzqq_none">>)) end)]),
    p(node, [node(), node(self()), node(make_ref()), g(2.5), g(x)]),
    p(ceil_floor, [ceil(1.5), ceil(-1.5), floor(-1.5), floor(1.5), ceil(id(3)), floor(id(-3)), floor(-0.0), ceil(-0.5),
                   err(fun() -> ceil(id(a)) end)]),
    p(io_lib, [lists:flatten(io_lib:format("a~wb~5.2fc|~-6s|~p", [12, 1.5, "ab", {x, "y"}])), io_lib:format("", []),
               lists:flatten(io_lib:format("~s~n", [[<<"bin">>, "ary"]])), length(lists:flatten(io_lib:format("~w", [lists:seq(1, 100)]))),
               err(fun() -> io_lib:format("~w", id([])) end), err(fun() -> io_lib:format("~f", id([1])) end),
               err(fun() -> io_lib:format("~.1e", id([1.0])) end), err(fun() -> io_lib:format("~.0f", id([1.0])) end)]),
    io:format("~w~n", [lists:seq(1, 120)]),
    io:format("~s|~n", [lists:duplicate(300, $x)]),
    Tenth = 13421773 / 134217728,
    Tiny = 1 / 1048576,
    io:format("~.21e ~.20f ~.3g ~.15e ~.1f ~.2e ~.25f~n", [Tenth, Tiny, 0.375, 1.0e10, 0.25, 9.9609375, Tenth]),
    io:format("~e ~f ~g ~g ~g ~.1g ~.1g ~.8g ~.3g ~10.3f| ~-10.3e|~n", [-0.0, -0.0, 0.0, 12345.0, 0.05, 0.5, 5.0, 99999.0, 0.0625, 3.0, 3.0]),
    Fs = [1.5, -2.25, 0.125, 0.375, 2.5, 99.5, 1.0e10, Tenth, Tiny, 16777215.0, 0.0, -0.0, 3.4028234663852886e38, 1.401298464324817e-45],
    [p(I, [float_to_list(F), float_to_list(F, [{scientific, 3}]), float_to_binary(F, [{scientific, 0}])]) || {I, F} <- lists:enumerate(Fs)],
    [p(I, [float_to_list(F, [{decimals, 3}]), float_to_list(F, [{decimals, 0}]), float_to_list(F, [{decimals, 4}, compact]),
           float_to_binary(F, [{decimals, 1}]), float_to_list(F, [compact, {decimals, 2}])]) || {I, F} <- lists:enumerate(Fs), abs(F) < 1.0e20],
    p(short, [float_to_list(F, [short]) || F <- [1.5, -2.25, 0.125, 1.0e10, 16777215.0, 0.0, -0.0]]),
    p(float_opts, [float_to_list(1.5, [{decimals, 2}, {scientific, 1}]), float_to_list(1.5, [short, {decimals, 2}]),
                   float_to_list(1.5, [{scientific, 25}]), float_to_list(-0.125, [{decimals, 30}]),
                   err(fun() -> float_to_list(1.5, id([bad])) end), err(fun() -> float_to_list(id(1), []) end),
                   err(fun() -> float_to_list(1.5, [{decimals, id(254)}]) end), length(float_to_list(1.5, [{decimals, 253}])),
                   err(fun() -> float_to_list(10.0, [{decimals, id(253)}]) end)]),
    p(list_to_float, [list_to_float(S) || S <- ["1.5", "-0.125", "+2.5e3", "1.0E-2", "0.1", "3.14159", "01.5", "1.0e-400", "-0.0", "1.5e-0", "0.0e0"]]),
    p(bad_floats, [err(fun() -> list_to_float(id(S)) end) || S <- ["1e5", "1.", ".5", "1.5e", "1.5e+", "1.5 ", "abc", "1.0e400", "1.2.3", [$1, $., 1633],
                                                                         "1.0e--5", "1.0e+-5", "+-1.0", "1.0e", "", "-", "e5", "1.5E+", a, "1.0" ++ [x]]]),
    p(more_floats, [list_to_float(S) || S <- ["1.0e0000001", "-1.0e-99999999", "1.0e-00", "250000000000000000000000000000.0e-30"]]),
    p(binary_to_float, [binary_to_float(<<"2.5">>), err(fun() -> binary_to_float(id(<<"2">>)) end)]).

g(X) when is_float(X), ceil(X) =:= 3, floor(X) =:= 2, node() =:= nonode@nohost -> yes;
g(_) -> no.

id(X) -> X.

err(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
