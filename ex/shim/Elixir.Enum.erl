%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% 'Elixir.Enum' is the VM's Enum: the functions of Elixir's that a program of
%% the corpus calls, on lists only, Elixir's Enumerable protocol and its
%% ranges, which are maps, being past M6a. It is packed with an Elixir program
%% and kept off the oracle's code path, where it would hide the real one.
-module('Elixir.Enum').
-export([map/2, each/2, filter/2, reject/2, reduce/3, sum/1, count/1, reverse/1,
         'member?'/2, to_list/1, 'all?'/2, 'any?'/2, find/2]).

%% A value is true unless it is false or nil, as in Elixir.
truthy(false) -> false;
truthy(nil) -> false;
truthy(_) -> true.

map([H | T], F) -> [F(H) | map(T, F)];
map([], _) -> [].

each([H | T], F) -> F(H), each(T, F);
each([], _) -> ok.

filter([H | T], F) ->
    case truthy(F(H)) of
        true -> [H | filter(T, F)];
        false -> filter(T, F)
    end;
filter([], _) -> [].

reject(L, F) -> filter(L, fun(X) -> not truthy(F(X)) end).

reduce([H | T], Acc, F) -> reduce(T, F(H, Acc), F);
reduce([], Acc, _) -> Acc.

sum(L) -> reduce(L, 0, fun(X, A) -> X + A end).

count(L) -> length(L).

reverse(L) -> lists:reverse(L).

'member?'(L, X) -> lists:member(X, L).

to_list(L) when is_list(L) -> L.

'all?'([H | T], F) ->
    case truthy(F(H)) of
        true -> 'all?'(T, F);
        false -> false
    end;
'all?'([], _) -> true.

'any?'([H | T], F) ->
    case truthy(F(H)) of
        true -> true;
        false -> 'any?'(T, F)
    end;
'any?'([], _) -> false.

find([H | T], F) ->
    case truthy(F(H)) of
        true -> H;
        false -> find(T, F)
    end;
find([], _) -> nil.
