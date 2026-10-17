%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% lists: the functions of OTP's lists a program reaches for first, in Erlang,
%% for a program packed for the board, which takes what it calls of this by
%% reach. member/2, reverse/1,2 and keyfind/3 are the VM's BIFs, as they are
%% OTP's. Never on erl's path, where it would hide OTP's own. What OTP writes
%% as body recursion is written here with an accumulator where the order of
%% the calls of a fun is the same, since a process's stack on the board is
%% its heap block.
-module(lists).
-export([all/2, any/2, append/1, append/2, delete/2, droplast/1, dropwhile/2,
         duplicate/2, enumerate/1, enumerate/2, filter/2, filtermap/2,
         flatlength/1, flatmap/2, flatten/1, flatten/2, foldl/3, foldr/3,
         foreach/2, join/2, keydelete/3, keymap/3, keymember/3, keyreplace/4,
         keysearch/3, keysort/2, keystore/4, keytake/3, last/1, map/2,
         mapfoldl/3, mapfoldr/3, max/1, merge/2, min/1, nth/2, nthtail/2,
         partition/2, prefix/2, search/2, seq/2, seq/3, sort/1, sort/2,
         split/2, splitwith/2, sublist/2, sublist/3, subtract/2, suffix/2,
         sum/1, takewhile/2, uniq/1, uniq/2, unzip/1, unzip3/1, usort/1,
         usort/2, zip/2, zip3/3, zipwith/3, zipwith3/4]).

all(Pred, [H | T]) ->
    case Pred(H) of
        true -> all(Pred, T);
        false -> false
    end;
all(_, []) -> true.

any(Pred, [H | T]) ->
    case Pred(H) of
        true -> true;
        false -> any(Pred, T)
    end;
any(_, []) -> false.

append([E]) -> E;
append([H | T]) -> H ++ append(T);
append([]) -> [].

append(L1, L2) -> L1 ++ L2.

delete(Item, [Item | Rest]) -> Rest;
delete(Item, [H | Rest]) -> [H | delete(Item, Rest)];
delete(_, []) -> [].

droplast([_]) -> [];
droplast([H | T]) -> [H | droplast(T)].

dropwhile(Pred, [H | T] = L) ->
    case Pred(H) of
        true -> dropwhile(Pred, T);
        false -> L
    end;
dropwhile(_, []) -> [].

duplicate(N, X) when is_integer(N), N >= 0 -> duplicate(N, X, []).

duplicate(0, _, L) -> L;
duplicate(N, X, L) -> duplicate(N - 1, X, [X | L]).

enumerate(List) -> enumerate(1, List).

enumerate(Index, List) when is_integer(Index), is_list(List) -> enumerate_1(Index, List, []).

enumerate_1(_, [], Acc) -> lists:reverse(Acc);
enumerate_1(I, [H | T], Acc) -> enumerate_1(I + 1, T, [{I, H} | Acc]).

filter(Pred, List) -> filter_1(Pred, List, []).

filter_1(_, [], Acc) -> lists:reverse(Acc);
filter_1(Pred, [H | T], Acc) ->
    case Pred(H) of
        true -> filter_1(Pred, T, [H | Acc]);
        false -> filter_1(Pred, T, Acc)
    end.

filtermap(Fun, List) -> filtermap_1(Fun, List, []).

filtermap_1(_, [], Acc) -> lists:reverse(Acc);
filtermap_1(Fun, [H | T], Acc) ->
    case Fun(H) of
        false -> filtermap_1(Fun, T, Acc);
        true -> filtermap_1(Fun, T, [H | Acc]);
        {true, V} -> filtermap_1(Fun, T, [V | Acc])
    end.

flatlength(List) -> flatlength(List, 0).

flatlength([H | T], N) when is_list(H) -> flatlength(T, flatlength(H, N));
flatlength([_ | T], N) -> flatlength(T, N + 1);
flatlength([], N) -> N.

flatmap(Fun, List) -> append(map(Fun, List)).

flatten(List) when is_list(List) -> flatten_1(List, []).

flatten(List, Tail) when is_list(List), is_list(Tail) -> flatten_1(List, Tail).

flatten_1([H | T], Tail) when is_list(H) -> flatten_1(H, flatten_1(T, Tail));
flatten_1([H | T], Tail) -> [H | flatten_1(T, Tail)];
flatten_1([], Tail) -> Tail.

foldl(Fun, Acc, [H | T]) -> foldl(Fun, Fun(H, Acc), T);
foldl(_, Acc, []) -> Acc.

foldr(Fun, Acc, List) -> foldl(Fun, Acc, lists:reverse(List)).

foreach(Fun, [H | T]) ->
    Fun(H),
    foreach(Fun, T);
foreach(_, []) -> ok.

join(_, []) -> [];
join(Sep, [H | T]) -> [H | join_prepend(Sep, T)].

join_prepend(_, []) -> [];
join_prepend(Sep, [H | T]) -> [Sep, H | join_prepend(Sep, T)].

keydelete(Key, N, [H | T]) when element(N, H) == Key -> T;
keydelete(Key, N, [H | T]) -> [H | keydelete(Key, N, T)];
keydelete(_, _, []) -> [].

keymap(Fun, N, [H | T]) -> [setelement(N, H, Fun(element(N, H))) | keymap(Fun, N, T)];
keymap(_, _, []) -> [].

keymember(Key, N, List) -> lists:keyfind(Key, N, List) =/= false.

keyreplace(Key, N, [H | T], New) when element(N, H) == Key -> [New | T];
keyreplace(Key, N, [H | T], New) -> [H | keyreplace(Key, N, T, New)];
keyreplace(_, _, [], _) -> [].

keysearch(Key, N, List) ->
    case lists:keyfind(Key, N, List) of
        false -> false;
        T -> {value, T}
    end.

keysort(N, List) -> sort(fun(A, B) -> element(N, A) =< element(N, B) end, List).

keystore(Key, N, [H | T], New) when element(N, H) == Key -> [New | T];
keystore(Key, N, [H | T], New) -> [H | keystore(Key, N, T, New)];
keystore(_, _, [], New) -> [New].

keytake(Key, N, List) -> keytake(Key, N, List, []).

keytake(Key, N, [H | T], Rev) when element(N, H) == Key -> {value, H, lists:reverse(Rev, T)};
keytake(Key, N, [H | T], Rev) -> keytake(Key, N, T, [H | Rev]);
keytake(_, _, [], _) -> false.

last([E]) -> E;
last([_ | T]) -> last(T).

map(Fun, List) -> map_1(Fun, List, []).

map_1(_, [], Acc) -> lists:reverse(Acc);
map_1(Fun, [H | T], Acc) -> map_1(Fun, T, [Fun(H) | Acc]).

mapfoldl(Fun, Acc, List) -> mapfoldl_1(Fun, Acc, List, []).

mapfoldl_1(_, Acc, [], Rev) -> {lists:reverse(Rev), Acc};
mapfoldl_1(Fun, Acc0, [H | T], Rev) ->
    {R, Acc} = Fun(H, Acc0),
    mapfoldl_1(Fun, Acc, T, [R | Rev]).

mapfoldr(Fun, Acc0, List) ->
    {Rev, Acc} = mapfoldl(Fun, Acc0, lists:reverse(List)),
    {lists:reverse(Rev), Acc}.

max([H | T]) -> max_1(T, H).

max_1([H | T], Max) when H > Max -> max_1(T, H);
max_1([_ | T], Max) -> max_1(T, Max);
max_1([], Max) -> Max.

merge(L1, L2) -> merge_by(fun(A, B) -> A =< B end, L1, L2, []).

min([H | T]) -> min_1(T, H).

min_1([H | T], Min) when H < Min -> min_1(T, H);
min_1([_ | T], Min) -> min_1(T, Min);
min_1([], Min) -> Min.

nth(1, [H | _]) -> H;
nth(N, [_ | T]) when N > 1 -> nth(N - 1, T).

nthtail(0, L) -> L;
nthtail(N, [_ | T]) when N > 0 -> nthtail(N - 1, T).

partition(Pred, List) -> partition_1(Pred, List, [], []).

partition_1(_, [], Yes, No) -> {lists:reverse(Yes), lists:reverse(No)};
partition_1(Pred, [H | T], Yes, No) ->
    case Pred(H) of
        true -> partition_1(Pred, T, [H | Yes], No);
        false -> partition_1(Pred, T, Yes, [H | No])
    end.

prefix([X | T1], [X | T2]) -> prefix(T1, T2);
prefix([], _) -> true;
prefix(_, _) -> false.

search(Pred, [H | T]) ->
    case Pred(H) of
        true -> {value, H};
        false -> search(Pred, T)
    end;
search(_, []) -> false.

seq(First, Last) when is_integer(First), is_integer(Last), First - 1 =< Last ->
    seq_loop(Last - First + 1, Last, 1, []).

seq(First, Last, Inc) when is_integer(First), is_integer(Last), is_integer(Inc) ->
    if
        Inc > 0, First - Inc =< Last; Inc < 0, First - Inc >= Last ->
            N = (Last - First + Inc) div Inc,
            seq_loop(N, Inc * (N - 1) + First, Inc, []);
        Inc =:= 0, First =:= Last ->
            [First];
        true ->
            erlang:error(badarg)
    end.

seq_loop(0, _, _, L) -> L;
seq_loop(N, X, D, L) -> seq_loop(N - 1, X - D, D, [X | L]).

%% sort/1 and sort/2 are a merge sort of runs of two, stable: of elements
%% that compare equal the first stays first.
sort(List) -> sort(fun(A, B) -> A =< B end, List).

sort(Fun, List) -> merge_all(Fun, pairs(Fun, List, [])).

pairs(Fun, [A, B | T], Acc) ->
    case Fun(A, B) of
        true -> pairs(Fun, T, [[A, B] | Acc]);
        false -> pairs(Fun, T, [[B, A] | Acc])
    end;
pairs(_, [A], Acc) -> lists:reverse([[A] | Acc]);
pairs(_, [], Acc) -> lists:reverse(Acc).

merge_all(_, []) -> [];
merge_all(_, [L]) -> L;
merge_all(Fun, Runs) -> merge_all(Fun, merge_pairs(Fun, Runs, [])).

merge_pairs(Fun, [A, B | T], Acc) -> merge_pairs(Fun, T, [merge_by(Fun, A, B, []) | Acc]);
merge_pairs(_, [A], Acc) -> lists:reverse([A | Acc]);
merge_pairs(_, [], Acc) -> lists:reverse(Acc).

merge_by(Fun, [A | Ta] = La, [B | Tb] = Lb, Acc) ->
    case Fun(A, B) of
        true -> merge_by(Fun, Ta, Lb, [A | Acc]);
        false -> merge_by(Fun, La, Tb, [B | Acc])
    end;
merge_by(_, [], Lb, Acc) -> lists:reverse(Acc, Lb);
merge_by(_, La, [], Acc) -> lists:reverse(Acc, La).

split(N, List) when is_integer(N), N >= 0, is_list(List) ->
    case split_1(N, List, []) of
        {_, _} = R -> R;
        short -> erlang:error(badarg)
    end.

split_1(0, L, Rev) -> {lists:reverse(Rev), L};
split_1(N, [H | T], Rev) -> split_1(N - 1, T, [H | Rev]);
split_1(_, [], _) -> short.

splitwith(Pred, List) -> splitwith_1(Pred, List, []).

splitwith_1(Pred, [H | T] = L, Rev) ->
    case Pred(H) of
        true -> splitwith_1(Pred, T, [H | Rev]);
        false -> {lists:reverse(Rev), L}
    end;
splitwith_1(_, [], Rev) -> {lists:reverse(Rev), []}.

sublist(List, Len) when is_integer(Len), Len >= 0 -> sublist_1(List, Len, []).

sublist_1([H | T], N, Acc) when N > 0 -> sublist_1(T, N - 1, [H | Acc]);
sublist_1(_, _, Acc) -> lists:reverse(Acc).

sublist(List, Start, Len) when is_integer(Start), Start >= 1 -> sublist(nthtail(Start - 1, List), Len).

subtract(L1, L2) -> L1 -- L2.

suffix(Suffix, List) ->
    Delta = length(List) - length(Suffix),
    Delta >= 0 andalso nthtail(Delta, List) =:= Suffix.

sum(List) -> sum(List, 0).

sum([H | T], Sum) -> sum(T, Sum + H);
sum([], Sum) -> Sum.

takewhile(Pred, List) -> takewhile_1(Pred, List, []).

takewhile_1(Pred, [H | T], Acc) ->
    case Pred(H) of
        true -> takewhile_1(Pred, T, [H | Acc]);
        false -> lists:reverse(Acc)
    end;
takewhile_1(_, [], Acc) -> lists:reverse(Acc).

uniq(List) -> uniq_1(List, []).

uniq_1([H | T], Seen) ->
    case lists:member(H, Seen) of
        true -> uniq_1(T, Seen);
        false -> [H | uniq_1(T, [H | Seen])]
    end;
uniq_1([], _) -> [].

uniq(Fun, List) -> uniq_2(Fun, List, []).

uniq_2(Fun, [H | T], Seen) ->
    K = Fun(H),
    case lists:member(K, Seen) of
        true -> uniq_2(Fun, T, Seen);
        false -> [H | uniq_2(Fun, T, [K | Seen])]
    end;
uniq_2(_, [], _) -> [].

unzip(List) -> unzip_1(List, [], []).

unzip_1([{X, Y} | T], Xs, Ys) -> unzip_1(T, [X | Xs], [Y | Ys]);
unzip_1([], Xs, Ys) -> {lists:reverse(Xs), lists:reverse(Ys)}.

unzip3(List) -> unzip3_1(List, [], [], []).

unzip3_1([{X, Y, Z} | T], Xs, Ys, Zs) -> unzip3_1(T, [X | Xs], [Y | Ys], [Z | Zs]);
unzip3_1([], Xs, Ys, Zs) -> {lists:reverse(Xs), lists:reverse(Ys), lists:reverse(Zs)}.

usort(List) -> dedup(fun(A, B) -> A == B end, sort(List)).

usort(Fun, List) -> dedup(fun(A, B) -> Fun(A, B) andalso Fun(B, A) end, sort(Fun, List)).

dedup(Same, [A, B | T]) ->
    case Same(A, B) of
        true -> dedup(Same, [A | T]);
        false -> [A | dedup(Same, [B | T])]
    end;
dedup(_, L) -> L.

zip([X | Xs], [Y | Ys]) -> [{X, Y} | zip(Xs, Ys)];
zip([], []) -> [].

zip3([X | Xs], [Y | Ys], [Z | Zs]) -> [{X, Y, Z} | zip3(Xs, Ys, Zs)];
zip3([], [], []) -> [].

zipwith(F, [X | Xs], [Y | Ys]) -> [F(X, Y) | zipwith(F, Xs, Ys)];
zipwith(_, [], []) -> [].

zipwith3(F, [X | Xs], [Y | Ys], [Z | Zs]) -> [F(X, Y, Z) | zipwith3(F, Xs, Ys, Zs)];
zipwith3(_, [], [], []) -> [].
