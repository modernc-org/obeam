%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% 'Elixir.Map' is the VM's Map: Elixir's functions over the VM's map BIFs
%% and the maps shim, erl/shim/maps.erl. What fails fails as maps does, with
%% badmap and badkey, where Elixir's raise BadMapError and KeyError. Packed
%% with an Elixir program by what it reaches, and kept off the oracle's path.
-module('Elixir.Map').
-export([get/2, get/3, put/3, fetch/2, 'fetch!'/2, 'has_key?'/2, keys/1, values/1,
         to_list/1, new/0, new/1, merge/2, delete/2, drop/2, take/2, update/4,
         'update!'/3, replace/3, 'replace!'/3, put_new/3, pop/2, pop/3,
         from_struct/1, filter/2, reject/2]).

get(Map, Key) -> maps:get(Key, Map, nil).
get(Map, Key, Default) -> maps:get(Key, Map, Default).
put(Map, Key, Value) -> maps:put(Key, Value, Map).
fetch(Map, Key) -> maps:find(Key, Map).
'fetch!'(Map, Key) -> maps:get(Key, Map).
'has_key?'(Map, Key) -> maps:is_key(Key, Map).
keys(Map) -> maps:keys(Map).
values(Map) -> maps:values(Map).
to_list(Map) -> maps:to_list(Map).
new() -> #{}.
new(Enumerable) -> maps:from_list('Elixir.Enum':to_list(Enumerable)).
merge(A, B) -> maps:merge(A, B).
delete(Map, Key) -> maps:remove(Key, Map).
drop(Map, Keys) -> maps:without(Keys, Map).
take(Map, Keys) -> maps:with(Keys, Map).

update(Map, Key, Default, Fun) ->
    case maps:find(Key, Map) of
        {ok, V} -> maps:put(Key, Fun(V), Map);
        error -> maps:put(Key, Default, Map)
    end.

'update!'(Map, Key, Fun) -> maps:update(Key, Fun(maps:get(Key, Map)), Map).

replace(Map, Key, Value) ->
    case maps:is_key(Key, Map) of
        true -> maps:put(Key, Value, Map);
        false -> Map
    end.

'replace!'(Map, Key, Value) -> maps:update(Key, Value, Map).

put_new(Map, Key, Value) ->
    case maps:is_key(Key, Map) of
        true -> Map;
        false -> maps:put(Key, Value, Map)
    end.

pop(Map, Key) -> pop(Map, Key, nil).

pop(Map, Key, Default) ->
    case maps:find(Key, Map) of
        {ok, V} -> {V, maps:remove(Key, Map)};
        error -> {Default, Map}
    end.

from_struct(Struct) -> maps:remove('__struct__', Struct).

filter(Map, Fun) -> maps:from_list([P || P <- maps:to_list(Map), truthy(Fun(P))]).

reject(Map, Fun) -> maps:from_list([P || P <- maps:to_list(Map), not truthy(Fun(P))]).

truthy(false) -> false;
truthy(nil) -> false;
truthy(_) -> true.
