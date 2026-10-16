%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% tuples: tuples and a record, matched, built and updated. The values come
%% through calls of the module by name, which the compiler cannot see through;
%% written as literals, the whole program folded to its output at compile time.
-module(tuples).
-export([main/0, point/2, pair/2]).

-record(point, {x = 0, y = 0}).

point(X, Y) -> #point{x = X, y = Y}.

pair(A, B) -> {A, B}.

move(#point{x = X, y = Y} = P, {DX, DY}) -> P#point{x = X + DX, y = Y + DY}.

dist2(#point{x = X, y = Y}) -> X * X + Y * Y.

swap({A, B}) -> {B, A}.

main() ->
    P = move(?MODULE:point(1, 2), ?MODULE:pair(3, 4)),
    io:format("~w ~w~n", [P, dist2(P)]),
    T = ?MODULE:pair(a, ?MODULE:pair(b, c)),
    {A, {B, C}} = T,
    U = {A, B, C},
    io:format("~w ~w ~w~n", [element(2, U), setelement(3, U, z), tuple_size(U)]),
    io:format("~w ~w ~w~n", [swap(?MODULE:pair(1, 2)), is_tuple(T), is_tuple(A)]),
    io:format("~w~n", [{P#point.x, P#point.y, is_record(P, point)}]).
