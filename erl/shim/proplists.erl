%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% proplists: OTP's proplists module for a program packed for the board,
%% which takes what it calls of this by reach. A list is walked with an
%% accumulator where OTP recurses on its body, since a process's stack on the
%% board is its heap block. Never on erl's path, where it would hide OTP's
%% own.
-module(proplists).
-export([append_values/2, compact/1, delete/2, expand/2, from_map/1,
         get_all_values/2, get_bool/2, get_keys/1, get_value/2, get_value/3,
         is_defined/2, lookup/2, lookup_all/2, normalize/2, property/1,
         property/2, split/2, substitute_aliases/2, substitute_negations/2,
         to_map/1, to_map/2, unfold/1]).

%% entry says whether P is an entry of Key: the atom itself, a tuple whose
%% first element it is, or neither.
entry(Key, Key) when is_atom(Key) -> atom;
entry(Key, P) when tuple_size(P) >= 1, element(1, P) =:= Key -> tuple;
entry(_, _) -> false.

property({Key, true}) when is_atom(Key) -> Key;
property(P) -> P.

property(Key, true) when is_atom(Key) -> Key;
property(Key, Value) -> {Key, Value}.

unfold(Ps) -> unfold(Ps, []).

unfold([P | Ps], Acc) when is_atom(P) -> unfold(Ps, [{P, true} | Acc]);
unfold([P | Ps], Acc) -> unfold(Ps, [P | Acc]);
unfold([], Acc) -> lists:reverse(Acc).

compact(Ps) -> compact(Ps, []).

compact([P | Ps], Acc) -> compact(Ps, [property(P) | Acc]);
compact([], Acc) -> lists:reverse(Acc).

lookup(Key, [P | Ps]) ->
    case entry(Key, P) of
        atom -> {Key, true};
        tuple -> P;
        false -> lookup(Key, Ps)
    end;
lookup(_, []) -> none.

lookup_all(Key, Ps) -> lookup_all(Key, Ps, []).

lookup_all(Key, [P | Ps], Acc) ->
    case entry(Key, P) of
        atom -> lookup_all(Key, Ps, [{Key, true} | Acc]);
        tuple -> lookup_all(Key, Ps, [P | Acc]);
        false -> lookup_all(Key, Ps, Acc)
    end;
lookup_all(_, [], Acc) -> lists:reverse(Acc).

is_defined(Key, [P | Ps]) ->
    case entry(Key, P) of
        false -> is_defined(Key, Ps);
        _ -> true
    end;
is_defined(_, []) -> false.

get_value(Key, List) -> get_value(Key, List, undefined).

%% get_value/3 stops at the first entry of Key, a tuple that is no pair
%% answering the default.
get_value(Key, [P | Ps], Default) ->
    case entry(Key, P) of
        atom -> true;
        tuple ->
            case P of
                {_, Value} -> Value;
                _ -> Default
            end;
        false -> get_value(Key, Ps, Default)
    end;
get_value(_, [], Default) -> Default.

get_all_values(Key, Ps) -> get_all_values(Key, Ps, []).

get_all_values(Key, [P | Ps], Acc) ->
    case entry(Key, P) of
        atom -> get_all_values(Key, Ps, [true | Acc]);
        tuple ->
            case P of
                {_, Value} -> get_all_values(Key, Ps, [Value | Acc]);
                _ -> get_all_values(Key, Ps, Acc)
            end;
        false -> get_all_values(Key, Ps, Acc)
    end;
get_all_values(_, [], Acc) -> lists:reverse(Acc).

append_values(Key, Ps) -> append_values(Key, Ps, []).

append_values(Key, [P | Ps], Acc) ->
    case entry(Key, P) of
        atom -> append_values(Key, Ps, [true | Acc]);
        tuple ->
            case P of
                {_, Value} when is_list(Value) -> append_values(Key, Ps, lists:reverse(Value, Acc));
                {_, Value} -> append_values(Key, Ps, [Value | Acc]);
                _ -> append_values(Key, Ps, Acc)
            end;
        false -> append_values(Key, Ps, Acc)
    end;
append_values(_, [], Acc) -> lists:reverse(Acc).

get_bool(Key, [P | Ps]) ->
    case entry(Key, P) of
        atom -> true;
        tuple ->
            case P of
                {_, true} -> true;
                _ -> false
            end;
        false -> get_bool(Key, Ps)
    end;
get_bool(_, []) -> false.

%% get_keys answers the keys in a map's order, as OTP's, which keeps them in a
%% set that is a map.
get_keys(Ps) -> maps:keys(get_keys(Ps, #{})).

get_keys([P | Ps], Keys) when is_atom(P) -> get_keys(Ps, Keys#{P => []});
get_keys([P | Ps], Keys) when tuple_size(P) >= 1 -> get_keys(Ps, Keys#{element(1, P) => []});
get_keys([_ | Ps], Keys) -> get_keys(Ps, Keys);
get_keys([], Keys) -> Keys.

delete(Key, Ps) -> delete(Key, Ps, []).

delete(Key, [P | Ps], Acc) ->
    case entry(Key, P) of
        false -> delete(Key, Ps, [P | Acc]);
        _ -> delete(Key, Ps, Acc)
    end;
delete(_, [], Acc) -> lists:reverse(Acc).

substitute_aliases(As, Ps) -> substitute(fun alias/2, As, Ps, []).

substitute_negations(Ns, Ps) -> substitute(fun negation/2, Ns, Ps, []).

substitute(F, Subs, [P | Ps], Acc) -> substitute(F, Subs, Ps, [F(Subs, P) | Acc]);
substitute(_, _, [], Acc) -> lists:reverse(Acc).

alias([{Key, Key1} | As], P) ->
    case entry(Key, P) of
        atom -> property(Key1, true);
        tuple -> property(setelement(1, P, Key1));
        false -> alias(As, P)
    end;
alias([], P) -> P.

%% negation takes a tuple that is not {_, false} as false, as get_bool/2
%% does.
negation([{Key, Key1} | Ns], P) ->
    case entry(Key, P) of
        atom -> property(Key1, false);
        tuple ->
            case P of
                {_, false} -> property(Key1, true);
                {_, true} -> property(Key1, false);
                _ -> property(Key1, true)
            end;
        false -> negation(Ns, P)
    end;
negation([], P) -> P.

expand(Es, Ps) when is_list(Ps) ->
    splice(expand_all(uniq([{property(P), V} || {P, V} <- Es]), Ps), []).

%% uniq drops an expansion whose property is the one before it.
uniq([{K, V} | Es]) -> lists:reverse(uniq(K, Es, [{K, V}]));
uniq([]) -> [].

uniq(K, [{K1, _} | Es], Acc) when K1 =:= K -> uniq(K, Es, Acc);
uniq(_, [{K1, V} | Es], Acc) -> uniq(K1, Es, [{K1, V} | Acc]);
uniq(_, [], Acc) -> Acc.

expand_all([{P, L} | Es], Ps) when is_atom(P) -> expand_all(Es, expand_one(P, P, L, Ps, []));
expand_all([{P, L} | Es], Ps) when tuple_size(P) >= 1 -> expand_all(Es, expand_one(element(1, P), P, L, Ps, []));
expand_all([_ | Es], Ps) -> expand_all(Es, Ps);
expand_all([], Ps) -> Ps.

%% expand_one puts the expansion L in place of the first entry of Key when
%% that entry is P1 and drops Key's other entries; an entry that is not P1
%% stays, in its normal form, and so do the rest.
expand_one(Key, P1, L, [P | Ps], Acc) ->
    Found = case entry(Key, P) of
                atom -> P;
                tuple -> property(P);
                false -> none
            end,
    if
        Found =:= none -> expand_one(Key, P1, L, Ps, [P | Acc]);
        Found =:= P1 -> lists:reverse(Acc, [L | delete(Key, Ps)]);
        true -> lists:reverse(Acc, [Found | Ps])
    end;
expand_one(_, _, _, [], Acc) -> lists:reverse(Acc).

splice([E | Es], Acc) when is_list(E) -> splice(Es, lists:reverse(E, Acc));
splice([E | Es], Acc) -> splice(Es, [E | Acc]);
splice([], Acc) -> lists:reverse(Acc).

normalize(L, Stages) -> compact(stages(L, Stages)).

stages(L, [{aliases, As} | Xs]) -> stages(substitute_aliases(As, L), Xs);
stages(L, [{expand, Es} | Xs]) -> stages(expand(Es, L), Xs);
stages(L, [{negations, Ns} | Xs]) -> stages(substitute_negations(Ns, L), Xs);
stages(L, []) -> L.

split(List, Keys) ->
    {Store, Rest} = split(List, maps:from_list([{K, []} || K <- Keys]), []),
    {[lists:reverse(map_get(K, Store)) || K <- Keys], lists:reverse(Rest)}.

split([P | Ps], Store, Rest) when is_atom(P) -> split(P, P, Ps, Store, Rest);
split([P | Ps], Store, Rest) when tuple_size(P) >= 1 -> split(element(1, P), P, Ps, Store, Rest);
split([P | Ps], Store, Rest) -> split(Ps, Store, [P | Rest]);
split([], Store, Rest) -> {Store, Rest}.

split(Key, P, Ps, Store, Rest) ->
    case is_map_key(Key, Store) of
        true -> split(Ps, Store#{Key := [P | map_get(Key, Store)]}, Rest);
        false -> split(Ps, Store, [P | Rest])
    end.

%% to_map takes the entries from the last, so that the first of a key wins;
%% a tuple that is no pair takes its key out.
to_map(List) -> fold_map(lists:reverse(List), #{}).

fold_map([{K, V} | Ps], M) -> fold_map(Ps, M#{K => V});
fold_map([T | Ps], M) when tuple_size(T) >= 1 -> fold_map(Ps, maps:remove(element(1, T), M));
fold_map([K | Ps], M) when is_atom(K) -> fold_map(Ps, M#{K => true});
fold_map([_ | Ps], M) -> fold_map(Ps, M);
fold_map([], M) -> M.

to_map(List, Stages) -> to_map(stages(List, Stages)).

from_map(Map) -> maps:to_list(Map).
