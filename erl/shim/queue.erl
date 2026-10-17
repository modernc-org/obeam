%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% queue: OTP's queue module for a program packed for the board, which takes
%% what it calls of this by reach. A queue is OTP's {Rear, Front}, the rear
%% reversed, balanced as OTP balances it, so that a queue printed prints as
%% OTP's; a fun is called on the items in the order OTP calls it. A list is
%% walked with an accumulator where OTP recurses on its body, since a
%% process's stack on the board is its heap block. Never on erl's path, where
%% it would hide OTP's own.
-module(queue).
-export([all/2, any/2, cons/2, daeh/1, delete/2, delete_r/2, delete_with/2,
         delete_with_r/2, drop/1, drop_r/1, filter/2, filtermap/2, fold/3,
         from_list/1, get/1, get_r/1, head/1, in/2, in_r/2, init/1,
         is_empty/1, is_queue/1, join/2, lait/1, last/1, len/1, liat/1,
         member/2, new/0, out/1, out_r/1, peek/1, peek_r/1, reverse/1,
         snoc/2, split/2, tail/1, to_list/1]).

new() -> {[], []}.

is_queue({R, F}) when is_list(R), is_list(F) -> true;
is_queue(_) -> false.

is_empty({[], []}) -> true;
is_empty({R, F}) when is_list(R), is_list(F) -> false;
is_empty(Q) -> error(badarg, [Q]).

len({R, F}) when is_list(R), is_list(F) -> length(R) + length(F);
len(Q) -> error(badarg, [Q]).

to_list({R, F}) when is_list(R), is_list(F) -> F ++ lists:reverse(R);
to_list(Q) -> error(badarg, [Q]).

from_list(L) when is_list(L) -> f2r(L);
from_list(L) -> error(badarg, [L]).

member(X, {R, F}) when is_list(R), is_list(F) -> lists:member(X, R) orelse lists:member(X, F);
member(X, Q) -> error(badarg, [X, Q]).

in(X, {[_] = R, []}) -> {[X], R};
in(X, {R, F}) when is_list(R), is_list(F) -> {[X | R], F};
in(X, Q) -> error(badarg, [X, Q]).

in_r(X, {[], [_] = F}) -> {F, [X]};
in_r(X, {R, F}) when is_list(R), is_list(F) -> {R, [X | F]};
in_r(X, Q) -> error(badarg, [X, Q]).

out({[], []} = Q) -> {empty, Q};
out({[V], []}) -> {{value, V}, {[], []}};
out({[Y | R], []}) ->
    [V | F] = lists:reverse(R),
    {{value, V}, {[Y], F}};
out({R, [V]}) when is_list(R) -> {{value, V}, r2f(R)};
out({R, [V | F]}) when is_list(R) -> {{value, V}, {R, F}};
out(Q) -> error(badarg, [Q]).

out_r({[], []} = Q) -> {empty, Q};
out_r({[], [V]}) -> {{value, V}, {[], []}};
out_r({[], [Y | F]}) ->
    [V | R] = lists:reverse(F),
    {{value, V}, {R, [Y]}};
out_r({[V], F}) when is_list(F) -> {{value, V}, f2r(F)};
out_r({[V | R], F}) when is_list(F) -> {{value, V}, {R, F}};
out_r(Q) -> error(badarg, [Q]).

get({[], []} = Q) -> error(empty, [Q]);
get({R, F}) when is_list(R), is_list(F) -> front(R, F);
get(Q) -> error(badarg, [Q]).

head({[], []} = Q) -> error(empty, [Q]);
head({R, F}) when is_list(R), is_list(F) -> front(R, F);
head(Q) -> error(badarg, [Q]).

front(_, [H | _]) -> H;
front([H], []) -> H;
front([_ | R], []) -> lists:last(R).

get_r({[], []} = Q) -> error(empty, [Q]);
get_r({[H | _], F}) when is_list(F) -> H;
get_r({[], [H]}) -> H;
get_r({[], [_ | F]}) -> lists:last(F);
get_r(Q) -> error(badarg, [Q]).

peek({[], []}) -> empty;
peek({R, [H | _]}) when is_list(R) -> {value, H};
peek({[H], []}) -> {value, H};
peek({[_ | R], []}) -> {value, lists:last(R)};
peek(Q) -> error(badarg, [Q]).

peek_r({[], []}) -> empty;
peek_r({[H | _], F}) when is_list(F) -> {value, H};
peek_r({[], [H]}) -> {value, H};
peek_r({[], [_ | F]}) -> {value, lists:last(F)};
peek_r(Q) -> error(badarg, [Q]).

drop({[], []} = Q) -> error(empty, [Q]);
drop({[_], []}) -> {[], []};
drop({[Y | R], []}) ->
    [_ | F] = lists:reverse(R),
    {[Y], F};
drop({R, [_]}) when is_list(R) -> r2f(R);
drop({R, [_ | F]}) when is_list(R) -> {R, F};
drop(Q) -> error(badarg, [Q]).

drop_r({[], []} = Q) -> error(empty, [Q]);
drop_r({[], [_]}) -> {[], []};
drop_r({[], [Y | F]}) ->
    [_ | R] = lists:reverse(F),
    {R, [Y]};
drop_r({[_], F}) when is_list(F) -> f2r(F);
drop_r({[_ | R], F}) when is_list(F) -> {R, F};
drop_r(Q) -> error(badarg, [Q]).

reverse({R, F}) when is_list(R), is_list(F) -> {F, R};
reverse(Q) -> error(badarg, [Q]).

join({R, F} = Q, {[], []}) when is_list(R), is_list(F) -> Q;
join({[], []}, {R, F} = Q) when is_list(R), is_list(F) -> Q;
join({R1, F1}, {R2, F2}) when is_list(R1), is_list(F1), is_list(R2), is_list(F2) ->
    {R2, F1 ++ lists:reverse(R1, F2)};
join(Q1, Q2) -> error(badarg, [Q1, Q2]).

split(0, {R, F} = Q) when is_list(R), is_list(F) -> {{[], []}, Q};
split(N, {R, F} = Q) when is_integer(N), N >= 1, is_list(R), is_list(F) ->
    Lf = length(F),
    if
        N < Lf ->
            [X | F1] = F,
            front_to_rear(N - 1, R, F1, [], [X]);
        N > Lf ->
            M = length(R) - (N - Lf),
            if
                M < 0 -> error(badarg, [N, Q]);
                M > 0 ->
                    [X | R1] = R,
                    rear_to_front(M - 1, R1, F, [X], []);
                true -> {Q, {[], []}}
            end;
        true -> {f2r(F), r2f(R)}
    end;
split(N, Q) -> error(badarg, [N, Q]).

front_to_rear(0, R1, F1, R2, F2) -> {{R2, F2}, {R1, F1}};
front_to_rear(N, R1, [X | F1], R2, F2) -> front_to_rear(N - 1, R1, F1, [X | R2], F2).

rear_to_front(0, R1, F1, R2, F2) -> {{R1, F1}, {R2, F2}};
rear_to_front(N, [X | R1], F1, R2, F2) -> rear_to_front(N - 1, R1, F1, R2, [X | F2]).

%% filter and filtermap call the fun on the items in the queue's order, the
%% front's and then the rear's, and keep a list a fun answers in place of its
%% item.
filter(Fun, {R0, F0}) when is_function(Fun, 1), is_list(R0), is_list(F0) ->
    F = lists:reverse(filter(Fun, F0, [])),
    rebuild(filter(Fun, lists:reverse(R0), []), F);
filter(Fun, Q) -> error(badarg, [Fun, Q]).

filter(Fun, [X | L], Acc) ->
    case Fun(X) of
        true -> filter(Fun, L, [X | Acc]);
        [Y] -> filter(Fun, L, [Y | Acc]);
        false -> filter(Fun, L, Acc);
        [] -> filter(Fun, L, Acc);
        Ys when is_list(Ys) -> filter(Fun, L, lists:reverse(Ys, Acc))
    end;
filter(_, [], Acc) -> Acc.

filtermap(Fun, {R0, F0}) when is_function(Fun, 1), is_list(R0), is_list(F0) ->
    F = lists:filtermap(Fun, F0),
    rebuild(filtermap_r(Fun, lists:reverse(R0), []), F);
filtermap(Fun, Q) -> error(badarg, [Fun, Q]).

filtermap_r(Fun, [X | L], Acc) ->
    case Fun(X) of
        true -> filtermap_r(Fun, L, [X | Acc]);
        {true, Y} -> filtermap_r(Fun, L, [Y | Acc]);
        false -> filtermap_r(Fun, L, Acc)
    end;
filtermap_r(_, [], Acc) -> Acc.

rebuild([], F) -> f2r(F);
rebuild(R, []) -> r2f(R);
rebuild(R, F) -> {R, F}.

fold(Fun, Acc0, {R, F}) when is_function(Fun, 2), is_list(R), is_list(F) ->
    lists:foldr(Fun, lists:foldl(Fun, Acc0, F), R);
fold(Fun, Acc0, Q) -> error(badarg, [Fun, Acc0, Q]).

any(Pred, {R, F}) when is_function(Pred, 1), is_list(R), is_list(F) ->
    lists:any(Pred, F) orelse lists:any(Pred, R);
any(Pred, Q) -> error(badarg, [Pred, Q]).

all(Pred, {R, F}) when is_function(Pred, 1), is_list(R), is_list(F) ->
    lists:all(Pred, F) andalso lists:all(Pred, R);
all(Pred, Q) -> error(badarg, [Pred, Q]).

%% delete and delete_with take out the first item in the queue's order that
%% is Item or that Pred holds for, calling Pred until one does.
delete(Item, {R0, F0} = Q) when is_list(R0), is_list(F0) ->
    remove(fun(X) -> X =:= Item end, R0, F0, Q);
delete(Item, Q) -> error(badarg, [Item, Q]).

delete_r(Item, {R0, F0}) when is_list(R0), is_list(F0) ->
    {F1, R1} = delete(Item, {F0, R0}),
    {R1, F1};
delete_r(Item, Q) -> error(badarg, [Item, Q]).

delete_with(Pred, {R0, F0} = Q) when is_function(Pred, 1), is_list(R0), is_list(F0) ->
    remove(Pred, R0, F0, Q);
delete_with(Pred, Q) -> error(badarg, [Pred, Q]).

delete_with_r(Pred, {R0, F0}) when is_function(Pred, 1), is_list(R0), is_list(F0) ->
    {F1, R1} = delete_with(Pred, {F0, R0}),
    {R1, F1};
delete_with_r(Pred, Q) -> error(badarg, [Pred, Q]).

remove(Pred, R0, F0, Q) ->
    case take(Pred, F0, []) of
        false ->
            case take(Pred, lists:reverse(R0), []) of
                false -> Q;
                [] -> f2r(F0);
                R1 -> {lists:reverse(R1), F0}
            end;
        [] -> r2f(R0);
        F1 -> {R0, F1}
    end.

%% take answers the list without the first item Pred holds for, or false.
take(Pred, [X | L], Acc) ->
    case Pred(X) of
        true -> lists:reverse(Acc, L);
        false -> take(Pred, L, [X | Acc])
    end;
take(_, [], _) -> false.

cons(X, Q) -> in_r(X, Q).

tail(Q) -> drop(Q).

snoc(Q, X) -> in(X, Q).

daeh(Q) -> get_r(Q).

last(Q) -> get_r(Q).

liat(Q) -> drop_r(Q).

lait(Q) -> drop_r(Q).

init(Q) -> drop_r(Q).

r2f([]) -> {[], []};
r2f([_] = R) -> {[], R};
r2f([Y, X]) -> {[Y], [X]};
r2f(L) ->
    {R, F} = lists:split(length(L) div 2, L),
    {R, lists:reverse(F)}.

f2r([]) -> {[], []};
f2r([_] = F) -> {F, []};
f2r([X, Y]) -> {[Y], [X]};
f2r(L) ->
    {F, R} = lists:split(length(L) div 2, L),
    {lists:reverse(R), F}.
