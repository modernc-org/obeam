%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% queues: what a program asks of OTP's queue, which the board has as a shim,
%% erl/shim/queue.erl, held here to the real one. The queues are printed as
%% they are, {Rear, Front}, which the shim keeps as OTP keeps it.
-module(queues).
-export([main/0]).

main() ->
    Q0 = queue:new(),
    Q1 = lists:foldl(fun queue:in/2, Q0, [1, 2, 3, 4, 5]),
    p(in, [Q1, queue:len(Q1), queue:to_list(Q1), queue:is_empty(Q0), queue:is_queue(Q1), queue:is_queue(x)]),
    {{value, V1}, Q2} = queue:out(Q1),
    {{value, V2}, Q3} = queue:out_r(Q2),
    p(out, [V1, Q2, V2, Q3, queue:out(Q0)]),
    p(ends, [queue:get(Q1), queue:get_r(Q1), queue:peek(Q1), queue:peek_r(Q1), queue:peek(Q0),
             queue:head(Q1), queue:last(Q1), queue:tail(Q1), queue:liat(Q1)]),
    Q4 = queue:in_r(0, queue:cons(-1, Q1)),
    p(front, [Q4, queue:snoc(Q4, 6), queue:drop(Q4), queue:drop_r(Q4)]),
    p(lists, [queue:from_list([a, b, c, d]), queue:reverse(Q1), queue:member(3, Q1), queue:member(9, Q1)]),
    p(join_split, [queue:join(Q1, queue:from_list([6, 7])), queue:split(2, Q1), queue:split(5, Q1), queue:split(0, Q1)]),
    p(filter, [queue:filter(fun(X) -> X rem 2 =:= 1 end, Q1), queue:filter(fun(X) -> [X, X] end, queue:from_list([1, 2])),
               queue:filtermap(fun(X) when X > 3 -> {true, X * 10}; (X) -> X < 2 end, Q1)]),
    p(fold, [queue:fold(fun(X, A) -> [X | A] end, [], Q1), queue:any(fun(X) -> X > 4 end, Q1),
             queue:all(fun(X) -> X > 0 end, Q1)]),
    p(delete, [queue:delete(3, Q1), queue:delete_r(5, Q1), queue:delete(9, Q1),
               queue:delete_with(fun(X) -> X > 1 end, Q1), queue:delete_with_r(fun(X) -> X < 5 end, Q1)]),
    p(empty, [catch_error(fun() -> queue:get(Q0) end), catch_error(fun() -> queue:drop(Q0) end),
              catch_error(fun() -> queue:len(nope) end)]),
    %% A queue of work, taken in turn.
    Jobs = lists:foldl(fun queue:in/2, queue:new(), [{job, N} || N <- lists:seq(1, 6)]),
    p(drain, drain(Jobs, [])).

drain(Q, Done) ->
    case queue:out(Q) of
        {empty, _} -> lists:reverse(Done);
        {{value, {job, N}}, Q1} when N rem 3 =:= 0 -> drain(queue:in({job, N + 10}, Q1), [N | Done]);
        {{value, {job, N}}, Q1} -> drain(Q1, [N | Done])
    end.

catch_error(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
