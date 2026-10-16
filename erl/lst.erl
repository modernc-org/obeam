%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% lst: lists built, walked and folded by the module's own functions, beside
%% the few list functions that are BIFs.
-module(lst).
-export([main/0, reverse/1, map/2, foldl/3, seq/2, sum/1, len/1, member/2]).

reverse(L) -> reverse(L, []).

reverse([H | T], Acc) -> reverse(T, [H | Acc]);
reverse([], Acc) -> Acc.

map(F, [H | T]) -> [F(H) | map(F, T)];
map(_, []) -> [].

foldl(F, Acc, [H | T]) -> foldl(F, F(H, Acc), T);
foldl(_, Acc, []) -> Acc.

seq(Lo, Hi) when Lo > Hi -> [];
seq(Lo, Hi) -> [Lo | seq(Lo + 1, Hi)].

sum(L) -> foldl(fun(X, S) -> X + S end, 0, L).

len([_ | T]) -> 1 + len(T);
len([]) -> 0.

member(X, [X | _]) -> true;
member(X, [_ | T]) -> member(X, T);
member(_, []) -> false.

main() ->
    L = seq(1, 10),
    Sq = map(fun(X) -> X * X end, L),
    io:format("~w~n", [Sq]),
    io:format("~w ~w ~w~n", [sum(Sq), len(Sq), length(Sq)]),
    io:format("~w~n", [reverse(Sq) =:= lists:reverse(Sq)]),
    io:format("~w ~w~n", [member(49, Sq), lists:member(50, Sq)]),
    io:format("~w~n", [L ++ [11, 12]]),
    io:format("~s~n", ["sum=" ++ integer_to_list(sum(L))]).
