%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% mp: maps: literals and building, matching in heads and cases, the guard
%% BIFs, the maps functions, the BIFs' and the shim's, comparison and
%% equality, and the errors. A map with atom keys is printed with ~kp, in
%% term order: erl's ~p prints its keys in the order of erl's atom table,
%% which no other VM has, and a fold over one goes in that order too.
-module(mp).
-export([main/0]).

main() ->
    M = #{a => 1, b => 2},
    M2 = M#{c => 3},
    M3 = M2#{a := 10},
    #{a := A, c := C} = M3,
    io:format("~kp ~p ~p~n", [M3, A + C, map_size(M3)]),
    io:format("~p~n", [#{1 => one, 2.0 => two, "s" => [s], {t, 1} => t, <<"b">> => b, [] => nil}]),
    io:format("~w ~w~n", [#{}, #{x => #{y => [#{}]}}]),
    io:format("~p ~p ~p ~p~n", [maps:get(b, M3), maps:get(z, M3, none), maps:find(c, M3), maps:find(z, M3)]),
    io:format("~p ~p ~p~n", [is_map_key(a, M3), maps:is_key(z, M3), map_get(c, M3)]),
    N = maps:from_list([{I, I * I} || I <- seq(1, 10)]),
    io:format("~w~n", [maps:to_list(N)]),
    io:format("~w ~w~n", [maps:keys(N), maps:values(N)]),
    io:format("~w~n", [maps:remove(5, maps:put(11, 121, N))]),
    io:format("~w ~w~n", [maps:merge(#{1 => a, 2 => b}, #{2 => c, 3 => d}), maps:update(1, z, #{1 => a})]),
    io:format("~p~n", [maps:fold(fun(K, V, Acc) -> K + V + Acc end, 0, N)]),
    io:format("~w~n", [maps:map(fun(_K, V) -> V div 2 end, #{1 => 10, 2 => 20})]),
    io:format("~w~n", [maps:filter(fun(K, _V) -> K rem 2 =:= 0 end, N)]),
    io:format("~kp~n", [counts([a, b, a, c, b, a])]),
    io:format("~p ~p ~p ~p~n", [id(#{1 => a}) == id(#{1.0 => a}), id(#{1 => a}) < id(#{1.0 => a}),
                                id(#{a => 1}) < id(#{a => 1, b => 2}), id(#{{1} => x}) =:= id(#{{1.0} => x})]),
    io:format("~p ~p ~p ~p~n", [id({1}) =:= id({1.0}), id({1}) == id({1.0}), id(#{a => 1}) =:= id(#{a => 1}),
                                id(#{1 => {2}}) == id(#{1 => {2.0}})]),
    io:format("~p ~p~n", [lookup(#{name => "joe", age => 7}), lookup(#{name => "ann"})]),
    io:format("~p~n", [[shape(S) || S <- [#{kind => circle, r => 2}, #{kind => square, side => 3}, #{}]]]),
    io:format("~p~n", [errors()]),
    Big = maps:from_list([{I, I} || I <- seq(1, 30)]),
    io:format("~p ~w~n", [map_size(Big), maps:fold(fun(K, _, Acc) -> [K | Acc] end, [], Big)]),
    io:format("~w~n", [maps:with([1, 3, 99], N)]).

seq(A, B) when A > B -> [];
seq(A, B) -> [A | seq(A + 1, B)].

counts(Words) -> counts(Words, #{}).

counts([], Acc) -> Acc;
counts([W | Ws], Acc) -> counts(Ws, maps:update_with(W, fun(V) -> V + 1 end, 1, Acc)).

lookup(#{name := N, age := Age}) -> {N, Age};
lookup(#{name := N}) -> {N, unknown}.

shape(#{kind := circle, r := R}) -> {circle, R * R * 3};
shape(#{kind := square, side := S}) -> {square, S * S};
shape(M) when map_size(M) =:= 0 -> empty.

errors() ->
    [error_of(fun() -> maps:get(x, id(#{})) end),
     error_of(fun() -> map_get(x, id(nomap)) end),
     error_of(fun() -> (id(#{}))#{a := 1} end),
     error_of(fun() -> (id(nomap))#{a => 1} end),
     error_of(fun() -> map_size(id(x)) end),
     error_of(fun() -> maps:put(k, v, id([])) end)].

error_of(F) ->
    try F() catch error:R -> R end.

id(X) -> X.
