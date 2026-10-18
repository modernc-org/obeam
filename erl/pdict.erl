%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% pdict: the process dictionary, each process's own, which outlives the
%% collections of its heap. What get/0 and get_keys/0,1 answer is sorted
%% before it is printed, 1 before 1.0: OTP answers in its hash table's order,
%% the board in its map's.
-module(pdict).
-export([main/0]).

main() ->
    P1 = put(a, 1),
    P2 = put(a, 2),
    P3 = put({k, "x"}, [1, 2]),
    P4 = put(1, int),
    P5 = put(1.0, float),
    p(put, [P1, P2, P3, P4, P5]),
    p(get, [get(a), get(b), get({k, "x"}), get(1), get(1.0)]),
    p(all, [lists:sort(get()), sort_keys(get_keys()), lists:sort(get_keys(2)), get_keys(nothing)]),
    E1 = erase(a),
    E2 = erase(a),
    E3 = lists:sort(erase()),
    p(erase, [E1, E2, get(a), E3, get(), get_keys()]),
    Self = self(),
    Pid = spawn(fun() -> put(mine, child), Self ! {self(), get(mine), get(parent)} end),
    put(parent, here),
    p(own, receive {Pid, Mine, Parent} -> {Mine, Parent, get(mine), get(parent)} end),
    [put({n, N}, lists:seq(1, N)) || N <- lists:seq(1, 40)],
    churn(3000),
    p(kept, [length(get({n, 40})), lists:sum([length(get({n, N})) || N <- lists:seq(1, 40)])]),
    p(apply, [apply(erlang, get, [parent]), erlang:put(x, y), erlang:get(x), lists:member({x, y}, get())]).

%% sort_keys sorts keys that may compare equal, 1 and 1.0, the integer
%% first.
sort_keys(Ks) -> [K || {K, _} <- lists:sort([{K, is_float(K)} || K <- Ks])].

%% churn makes garbage, so that the heap is collected.
churn(0) -> ok;
churn(N) ->
    _ = lists:seq(1, 50),
    churn(N - 1).

p(Tag, X) -> io:format("~w: ~p~n", [Tag, X]).
