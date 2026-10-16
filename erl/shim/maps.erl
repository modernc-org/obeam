%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% maps: the functions of OTP's maps that take a fun or are made of others, in
%% Erlang over the VM's map BIFs, for a program packed for the board, which
%% takes what it calls of this by reach (obeam pack -lib). Never on erl's path,
%% where it would hide OTP's own. A fold goes in map-key order, which is OTP's
%% for a map of fewer than 33 keys none of which are atoms.
-module(maps).
-export([fold/3, map/2, filter/2, filtermap/2, foreach/2, with/2, without/2,
         update_with/3, update_with/4, from_keys/2, take/2, merge_with/3]).

fold(Fun, Acc, Map) when is_map(Map) -> fold_1(Fun, Acc, maps:to_list(Map));
fold(_, _, Map) -> erlang:error({badmap, Map}).

fold_1(_, Acc, []) -> Acc;
fold_1(Fun, Acc, [{K, V} | T]) -> fold_1(Fun, Fun(K, V, Acc), T).

map(Fun, Map) when is_map(Map) -> maps:from_list(map_1(Fun, maps:to_list(Map)));
map(_, Map) -> erlang:error({badmap, Map}).

map_1(_, []) -> [];
map_1(Fun, [{K, V} | T]) -> [{K, Fun(K, V)} | map_1(Fun, T)].

filter(Pred, Map) when is_map(Map) -> maps:from_list(filter_1(Pred, maps:to_list(Map)));
filter(_, Map) -> erlang:error({badmap, Map}).

filter_1(_, []) -> [];
filter_1(Pred, [{K, V} = E | T]) ->
    case Pred(K, V) of
        true -> [E | filter_1(Pred, T)];
        false -> filter_1(Pred, T)
    end.

filtermap(Fun, Map) when is_map(Map) -> maps:from_list(filtermap_1(Fun, maps:to_list(Map)));
filtermap(_, Map) -> erlang:error({badmap, Map}).

filtermap_1(_, []) -> [];
filtermap_1(Fun, [{K, V} = E | T]) ->
    case Fun(K, V) of
        true -> [E | filtermap_1(Fun, T)];
        {true, W} -> [{K, W} | filtermap_1(Fun, T)];
        false -> filtermap_1(Fun, T)
    end.

foreach(Fun, Map) when is_map(Map) -> foreach_1(Fun, maps:to_list(Map));
foreach(_, Map) -> erlang:error({badmap, Map}).

foreach_1(_, []) -> ok;
foreach_1(Fun, [{K, V} | T]) ->
    Fun(K, V),
    foreach_1(Fun, T).

with(Keys, Map) when is_map(Map) -> maps:from_list(with_1(Keys, Map));
with(_, Map) -> erlang:error({badmap, Map}).

with_1([], _) -> [];
with_1([K | T], Map) ->
    case maps:find(K, Map) of
        {ok, V} -> [{K, V} | with_1(T, Map)];
        error -> with_1(T, Map)
    end.

without([], Map) when is_map(Map) -> Map;
without([K | T], Map) -> without(T, maps:remove(K, Map));
without(_, Map) -> erlang:error({badmap, Map}).

update_with(Key, Fun, Map) -> maps:put(Key, Fun(maps:get(Key, Map)), Map).

update_with(Key, Fun, Init, Map) ->
    case maps:find(Key, Map) of
        {ok, V} -> maps:put(Key, Fun(V), Map);
        error -> maps:put(Key, Init, Map)
    end.

from_keys(Keys, Value) -> maps:from_list([{K, Value} || K <- Keys]).

take(Key, Map) ->
    case maps:find(Key, Map) of
        {ok, V} -> {V, maps:remove(Key, Map)};
        error -> error
    end.

merge_with(Fun, Map1, Map2) when is_map(Map1), is_map(Map2) ->
    fold(fun(K, V2, Acc) ->
                 case maps:find(K, Acc) of
                     {ok, V1} -> maps:put(K, Fun(K, V1, V2), Acc);
                     error -> maps:put(K, V2, Acc)
                 end
         end, Map1, Map2);
merge_with(_, Map1, Map2) when is_map(Map1) -> erlang:error({badmap, Map2});
merge_with(_, Map1, _) -> erlang:error({badmap, Map1}).
