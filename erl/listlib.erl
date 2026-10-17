%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% listlib: what a program asks of OTP's lists, which the board has as a shim,
%% erl/shim/lists.erl, held here to the real one.
-module(listlib).
-export([main/0]).

main() ->
    L = lists:seq(1, 10),
    p(seq, [L, lists:seq(1, 0), lists:seq(10, 1, -3), lists:seq(1, 10, 4), lists:seq(5, 5, 0)]),
    p(map, [lists:map(fun(X) -> X * X end, L), lists:filter(fun(X) -> X rem 3 =:= 0 end, L)]),
    p(fold, [lists:foldl(fun(X, A) -> [X | A] end, [], [a, b, c]),
             lists:foldr(fun(X, A) -> [X | A] end, [], [a, b, c]),
             lists:sum(L), lists:sum([1, 2.5])]),
    lists:foreach(fun(X) -> io:format("~w ", [X]) end, [x, y, z]),
    io:format("~n"),
    p(sort, [lists:sort([3, 1, 2, 1]), lists:sort([b, 1, "s", {t}, 2.0, a]),
             lists:sort(fun(A, B) -> A >= B end, [3, 1, 2]),
             lists:usort([3, 1, 2, 1, 3]), lists:usort(fun(A, B) -> A =< B end, [2, 1, 2]),
             lists:keysort(2, [{a, 3}, {b, 1}, {c, 2}, {d, 1}]),
             lists:merge([1, 3, 5], [2, 3, 4])]),
    p(take, [lists:nth(3, L), lists:nthtail(8, L), lists:sublist(L, 3), lists:sublist(L, 4, 2),
             lists:sublist([1, 2], 5), lists:last(L), lists:droplast([1, 2, 3]),
             lists:split(2, [a, b, c]), lists:takewhile(fun(X) -> X < 4 end, L),
             lists:dropwhile(fun(X) -> X < 8 end, L), lists:splitwith(fun(X) -> X < 3 end, L)]),
    p(pick, [lists:partition(fun(X) -> X > 5 end, L), lists:all(fun is_integer/1, L),
             lists:any(fun(X) -> X > 9 end, L), lists:search(fun(X) -> X > 4 end, L),
             lists:search(fun(X) -> X > 40 end, L), lists:max([3, 9, 2]), lists:min([3, 9, 2]),
             lists:filtermap(fun(X) when X > 8 -> {true, X * 10}; (X) -> X =:= 2 end, L)]),
    p(build, [lists:append([[1], [2, 3], []]), lists:append("ab", "cd"),
              lists:flatten([1, [2, [3, []], 4], [[5]]]), lists:flatten([a, [b]], [c]),
              lists:flatlength([1, [2, [3]], 4]), lists:flatmap(fun(X) -> [X, X] end, [a, b]),
              lists:duplicate(3, z), lists:join(x, [a, b, c]), lists:join(x, []),
              lists:delete(b, [a, b, c, b]), lists:subtract([1, 2, 3, 2], [2]),
              lists:enumerate([a, b]), lists:enumerate(0, [a, b])]),
    p(zip, [lists:zip([1, 2], [a, b]), lists:unzip([{1, a}, {2, b}]),
            lists:zip3([1], [a], ["x"]), lists:unzip3([{1, a, x}]),
            lists:zipwith(fun(X, Y) -> X + Y end, [1, 2], [10, 20]),
            lists:zipwith3(fun(X, Y, Z) -> X + Y + Z end, [1], [2], [3])]),
    T = [{a, 1}, {b, 2}, {c, 3}],
    p(keys, [lists:keymember(b, 1, T), lists:keymember(z, 1, T), lists:keysearch(c, 1, T),
             lists:keydelete(b, 1, T), lists:keyreplace(a, 1, T, {a, 9}),
             lists:keystore(z, 1, T, {z, 0}), lists:keystore(c, 1, T, {c, 0}),
             lists:keytake(b, 1, T), lists:keytake(q, 1, T),
             lists:keymap(fun(V) -> V * 2 end, 2, T)]),
    p(more, [lists:mapfoldl(fun(X, A) -> {X * 2, A + X} end, 0, [1, 2, 3]),
             lists:mapfoldr(fun(X, A) -> {[X | A], [X | A]} end, [], [1, 2, 3]),
             lists:prefix([1, 2], [1, 2, 3]), lists:prefix([2], [1, 2]),
             lists:suffix([2, 3], [1, 2, 3]), lists:suffix([1], [1, 2]),
             lists:uniq([3, 1, 3, 2, 1]), lists:uniq(fun(X) -> X rem 2 end, [1, 2, 3, 4])]).

p(Tag, Results) ->
    io:format("~w:~n", [Tag]),
    lists:foreach(fun(R) -> io:format("  ~w~n", [R]) end, Results).
