#!/usr/bin/env escript
%%! -pa .
%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erl/shim/queue.erl, as oqueue, against OTP's; see scripts/shimcheck.sh.
%% Random runs of operations on one queue, each operation's result, the queue
%% it leaves and the order a fun is called in compared.

main(_) ->
    rand:seed(exsss, {4, 5, 6}),
    Ops = ops(),
    Runs = [[pick(Ops) || _ <- lists:seq(1, 25)] || _ <- lists:seq(1, 3000)],
    Diff = [R || R <- Runs, run(queue, R) =/= run(oqueue, R)],
    io:format("~w runs of 25 operations, ~w differ~n", [length(Runs), length(Diff)]),
    case Diff of
        [D | _] ->
            {E, _} = run(queue, D),
            {O, _} = run(oqueue, D),
            [io:format("~w~n  ~w~n  ~w~n", [Op, X, Y]) || {{Op, X}, {_, Y}} <- lists:zip(E, O), X =/= Y],
            halt(1);
        [] -> halt(0)
    end.

%% An operation is {Name, ArgsBefore, ArgsAfter}, the queue going between them;
%% a fun logs what it is called with in the process dictionary.
ops() ->
    Log = fun(X) -> put(log, [X | get(log)]) end,
    [{in, [x], []}, {in, [y], []}, {in_r, [z], []}, {out, [], []}, {out_r, [], []}, {drop, [], []}, {drop_r, [], []},
     {get, [], []}, {get_r, [], []}, {peek, [], []}, {peek_r, [], []}, {head, [], []}, {tail, [], []}, {last, [], []},
     {liat, [], []}, {init, [], []}, {daeh, [], []}, {cons, [w], []}, {snoc, [], [v]}, {reverse, [], []},
     {len, [], []}, {to_list, [], []}, {is_empty, [], []}, {is_queue, [], []}, {member, [x], []},
     {join, [], [{[b, a], [c]}]}, {join, [{[q], [p]}], []}, {join, [], [{[], []}]},
     {split, [0], []}, {split, [1], []}, {split, [2], []}, {split, [3], []}, {split, [5], []},
     {filter, [fun(E) -> Log(E), E =/= x end], []},
     {filter, [fun(E) -> Log(E), [E, E] end], []},
     {filter, [fun(E) -> Log(E), if E =:= y -> []; E =:= z -> [zz]; true -> true end end], []},
     {filtermap, [fun(E) -> Log(E), if E =:= x -> {true, xx}; E =:= y -> false; true -> true end end], []},
     {fold, [fun(E, A) -> [E | A] end, []], []},
     {any, [fun(E) -> Log(E), E =:= z end], []},
     {all, [fun(E) -> Log(E), E =/= v end], []},
     {delete, [x], []}, {delete, [y], []}, {delete_r, [x], []},
     {delete_with, [fun(E) -> Log(E), E =:= z end], []},
     {delete_with_r, [fun(E) -> Log(E), E =:= x end], []},
     {from_list, [], []}].

%% run answers the results of a run of operations, and the fun calls' log.
run(Mod, Run) ->
    put(log, []),
    {_, Out} = lists:foldl(fun({Op, A, B}, {Q, Acc}) ->
                                   Args = case Op of
                                              from_list -> [[a, b, c, d, e]];
                                              _ -> A ++ [Q] ++ B
                                          end,
                                   Res = try apply(Mod, Op, Args) catch C:R -> {C, R} end,
                                   {next(Mod, Op, Res, Q), [{Op, Res} | Acc]}
                           end, {Mod:new(), []}, Run),
    {lists:reverse(Out), get(log)}.

%% next answers the queue an operation leaves.
next(_, _, {{value, _}, Q}, _) -> Q;
next(_, _, {empty, Q}, _) -> Q;
next(_, split, {Q, _}, _) -> Q;
next(Mod, _, {_, _} = Q, Q0) ->
    case Mod:is_queue(Q) of
        true -> Q;
        false -> Q0
    end;
next(_, _, _, Q0) -> Q0.

pick(L) -> lists:nth(rand:uniform(length(L)), L).
