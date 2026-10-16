%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% tuples: tuples and a record, matched, built and updated.
-module(tuples).
-export([main/0]).

-record(point, {x = 0, y = 0}).

move(#point{x = X, y = Y} = P, {DX, DY}) -> P#point{x = X + DX, y = Y + DY}.

dist2(#point{x = X, y = Y}) -> X * X + Y * Y.

swap({A, B}) -> {B, A}.

main() ->
    P = move(#point{x = 1, y = 2}, {3, 4}),
    io:format("~w ~w~n", [P, dist2(P)]),
    T = {a, b, c},
    io:format("~w ~w ~w~n", [element(2, T), setelement(3, T, z), tuple_size(T)]),
    io:format("~w ~w~n", [swap({1, 2}), is_tuple(T)]),
    io:format("~w~n", [{P#point.x, P#point.y, is_record(P, point)}]).
