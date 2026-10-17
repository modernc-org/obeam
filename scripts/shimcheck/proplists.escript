#!/usr/bin/env escript
%%! -pa .
%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erl/shim/proplists.erl, as oproplists, against OTP's; see
%% scripts/shimcheck.sh. get_keys/1's keys are compared sorted: OTP 27 keeps
%% them in a hashed set, whose order the shim does not make.

main(_) ->
    rand:seed(exsss, {1, 2, 3}),
    Elems = [a, b, c, none, {a, 1}, {b, 2}, {a, true}, {b, false}, {c, x, y}, {a}, {}, 7, "str", {1, one},
             {1.0, onef}, {a, [1, 2]}, {b, [3]}, {no_a, true}, no_b, {no_c, 5}, {d, true}, d],
    Lists = [[pick(Elems) || _ <- lists:seq(1, rand:uniform(8) - 1)] || _ <- lists:seq(1, 400)],
    Keys = [a, b, c, d, none, 1, 1.0, no_a, x],
    Calls = lists:append([
        [{F, [K, L]} || L <- Lists, K <- Keys,
                        F <- [lookup, lookup_all, is_defined, get_value, get_all_values, append_values, get_bool, delete]],
        [{get_value, [K, L, dflt]} || L <- Lists, K <- Keys],
        [{F, [L]} || L <- Lists, F <- [unfold, compact, get_keys, to_map]],
        [{property, [P]} || P <- Elems],
        [{property, [K, V]} || K <- [a, 1, "s"], V <- [true, false, 3]],
        [{substitute_aliases, [[{a, z}, {b, y}, {a, w}], L]} || L <- Lists],
        [{substitute_negations, [[{no_a, a}, {no_b, b}, {no_c, c}], L]} || L <- Lists],
        [{expand, [[{a, [x1, x2]}, {{b, true}, [y1]}, {{b, false}, [y2]}, {{a, 1}, [z]}, {a, [dup]}, {{c, x, y}, []}], L]}
         || L <- Lists],
        [{normalize, [L, [{aliases, [{a, b}]}, {negations, [{no_b, c}]}, {expand, [{{c, false}, [cf]}]}]]} || L <- Lists],
        [{split, [L, [a, b, none, 1, a]]} || L <- Lists],
        [{to_map, [L, [{aliases, [{a, b}]}]]} || L <- Lists],
        [{from_map, [M]} || M <- [#{}, #{a => 1, b => 2}, #{1 => x, 1.0 => y, a => z}]],
        [{F, [a, notalist]} || F <- [lookup, get_value, delete]]]),
    Diff = [{F, A, E, O} || {F, A} <- Calls,
                            E <- [norm(F, run(fun() -> apply(proplists, F, A) end))],
                            O <- [norm(F, run(fun() -> apply(oproplists, F, A) end))],
                            E =/= O],
    io:format("~w calls, ~w differ~n", [length(Calls), length(Diff)]),
    [io:format("~w~n", [D]) || D <- lists:sublist(Diff, 20)],
    halt(min(1, length(Diff))).

%% norm sorts get_keys/1's keys, by term order and then exactly, so that 1 and
%% 1.0, equal in term order, come in the same order on both sides.
norm(get_keys, Keys) when is_list(Keys) -> lists:sort(fun(A, B) -> {A, is_float(A)} =< {B, is_float(B)} end, Keys);
norm(_, X) -> X.

pick(L) -> lists:nth(rand:uniform(length(L)), L).

run(F) ->
    try F() catch C:R -> {C, R} end.
