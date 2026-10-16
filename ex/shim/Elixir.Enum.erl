%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% 'Elixir.Enum' is the VM's Enum: the functions of Elixir's that a program
%% of the corpus calls, on lists, maps, whose items are {Key, Value} in
%% map-key order, and ranges, Elixir's Enumerable protocol being Elixir's
%% own. It is packed with an Elixir program, by what the program reaches
%% (obeam pack -lib), and kept off the oracle's code path, where it would
%% hide the real one.
-module('Elixir.Enum').
-export([map/2, each/2, filter/2, reject/2, reduce/3, sum/1, count/1, reverse/1,
         'member?'/2, to_list/1, 'all?'/2, 'any?'/2, find/2, sort/1, sort/2,
         into/2, with_index/1, take/2, max/1, min/1]).

%% A value is true unless it is false or nil, as in Elixir.
truthy(false) -> false;
truthy(nil) -> false;
truthy(_) -> true.

%% to_list makes a list of what Enum enumerates: a list as it is, a range's
%% integers, and a map's pairs.
to_list(L) when is_list(L) -> L;
to_list(#{'__struct__' := 'Elixir.Range', first := F, last := L, step := S}) -> range(F, L, S);
to_list(M) when is_map(M) -> maps:to_list(M).

range(F, L, S) when S > 0, F > L; S < 0, F < L -> [];
range(F, L, S) -> [F | range(F + S, L, S)].

map(T, F) -> map_1(to_list(T), F).

map_1([H | T], F) -> [F(H) | map_1(T, F)];
map_1([], _) -> [].

each(T, F) -> each_1(to_list(T), F).

each_1([H | T], F) -> F(H), each_1(T, F);
each_1([], _) -> ok.

filter(T, F) -> filter_1(to_list(T), F).

filter_1([H | T], F) ->
    case truthy(F(H)) of
        true -> [H | filter_1(T, F)];
        false -> filter_1(T, F)
    end;
filter_1([], _) -> [].

reject(T, F) -> filter(T, fun(X) -> not truthy(F(X)) end).

reduce(T, Acc, F) -> reduce_1(to_list(T), Acc, F).

reduce_1([H | T], Acc, F) -> reduce_1(T, F(H, Acc), F);
reduce_1([], Acc, _) -> Acc.

sum(T) -> reduce(T, 0, fun(X, A) -> X + A end).

count(T) -> length(to_list(T)).

reverse(T) -> lists:reverse(to_list(T)).

'member?'(T, X) -> lists:member(X, to_list(T)).

'all?'(T, F) -> 'all?_1'(to_list(T), F).

'all?_1'([H | T], F) ->
    case truthy(F(H)) of
        true -> 'all?_1'(T, F);
        false -> false
    end;
'all?_1'([], _) -> true.

'any?'(T, F) -> 'any?_1'(to_list(T), F).

'any?_1'([H | T], F) ->
    case truthy(F(H)) of
        true -> true;
        false -> 'any?_1'(T, F)
    end;
'any?_1'([], _) -> false.

find(T, F) -> find_1(to_list(T), F).

find_1([H | T], F) ->
    case truthy(F(H)) of
        true -> H;
        false -> find_1(T, F)
    end;
find_1([], _) -> nil.

%% sort is a merge sort, stable, by =< or by a function that says whether
%% its first argument goes first, or by asc or desc.
sort(T) -> sort(T, fun(A, B) -> A =< B end).

sort(T, asc) -> sort(T);
sort(T, desc) -> sort(T, fun(A, B) -> A >= B end);
sort(T, F) -> msort(to_list(T), F).

msort([], _) -> [];
msort([X], _) -> [X];
msort(L, F) ->
    {A, B} = halve(L, [], []),
    merge(msort(A, F), msort(B, F), F).

halve([X, Y | T], A, B) -> halve(T, [X | A], [Y | B]);
halve([X], A, B) -> {lists:reverse([X | A]), lists:reverse(B)};
halve([], A, B) -> {lists:reverse(A), lists:reverse(B)}.

merge([X | Xs] = L, [Y | Ys] = R, F) ->
    case truthy(F(X, Y)) of
        true -> [X | merge(Xs, R, F)];
        false -> [Y | merge(L, Ys, F)]
    end;
merge([], R, _) -> R;
merge(L, [], _) -> L.

into(T, M) when is_map(M) -> maps:merge(M, maps:from_list(to_list(T)));
into(T, L) when is_list(L) -> L ++ to_list(T).

with_index(T) -> with_index_1(to_list(T), 0).

with_index_1([H | T], I) -> [{H, I} | with_index_1(T, I + 1)];
with_index_1([], _) -> [].

take(T, N) -> take_1(to_list(T), N).

take_1([H | T], N) when N > 0 -> [H | take_1(T, N - 1)];
take_1(_, _) -> [].

max(T) -> [H | Rest] = to_list(T), reduce_1(Rest, H, fun(X, A) when X > A -> X; (_, A) -> A end).

min(T) -> [H | Rest] = to_list(T), reduce_1(Rest, H, fun(X, A) when X < A -> X; (_, A) -> A end).
