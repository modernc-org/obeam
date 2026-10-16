%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% flt: floats. The values are exact in 32 bits, which the board's floats
%% have, so that the board and erl print the same; what is not exact, a third
%% or pi, differs in its last digits and is not here.
-module(flt).
-export([main/0, half/1, area/1]).

half(X) -> X / 2.

area(R) -> R * R * 3.0.

main() ->
    io:format("~w ~w ~w ~w~n", [1.5, 1.5 * 2.0, 7 / 2, half(5)]),
    io:format("~w ~w ~w ~w~n", [0.25 + 0.5, 100.0 - 0.5, -2.5, 1.0e10]),
    io:format("~w ~w ~w ~w ~w~n", [trunc(2.75), round(2.5), round(-2.5), float(3), trunc(-2.75)]),
    io:format("~w ~w ~w ~w~n", [math:sqrt(16.0), math:pow(2.0, 10.0), math:sqrt(2.25), area(2.0)]),
    io:format("~w ~w ~w ~w ~w~n", [1.0 == 1, 1.0 =:= 1, 2.5 > 2, [1.5, 2.5] < [1.5, 3], abs(-1.5)]),
    io:format("~w ~w ~w ~w ~w ~w~n", [1000.0, 100.0, 65536.0, 0.001, 0.0001, 1.0e-5]),
    io:format("~w ~w ~w ~w~n", [1234567.0, 1.25e7, 0.0015, 12345678.0]),
    io:format("~.2f ~f ~.1f ~e ~.3e ~g ~g~n", [3.125, 2.5, 2.5, 10.0, 2.0, 0.5, 123456.0]),
    io:format("~w ~w~n", [is_float(1.0), is_float(1)]),
    io:format("~w~n", [case catch 1.0 / list_to_integer("0") of {'EXIT', {Reason, _}} -> Reason end]).
