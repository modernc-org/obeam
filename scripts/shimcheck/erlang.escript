#!/usr/bin/env escript
%%! -pa .
%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erl/shim/erlang.erl, as oerlang, against OTP's BIFs; see scripts/shimcheck.sh.

main(_) ->
    Args = #{tuple_to_list => [[{}], [{a}], [{a, b, {c}}], [x], [[1]]],
             integer_to_list => [[I, B] || I <- [0, 1, -1, 255, -255, 35, 36, 123456789, -987654321],
                                           B <- [2, 8, 10, 16, 36, 1, 37, x]] ++ [[x, 10]],
             list_to_integer => [[L, B] || L <- ["0", "ff", "FF", "-ff", "+10", "+-1", "-", "+", "", "1z", "zz", "12 ",
                                                 " 12", "--1", "007", x, [$1 | x]],
                                           B <- [2, 10, 16, 36, 1, 37]],
             integer_to_binary => [[I, B] || I <- [0, -255, 4095], B <- [2, 16, 36, 0]],
             binary_to_integer => [[B] || B <- [<<"12">>, <<"-12">>, <<"+0">>, <<"x">>, <<>>, <<"1.0">>, "12"]],
             binary_to_list => [[<<1, 2, 3, 4>>, S, E] || S <- [0, 1, 2, 4, 5], E <- [0, 1, 2, 3, 4, 5]] ++ [[x, 1, 1]],
             iolist_size => [[L] || L <- [[], <<1, 2>>, [1, <<2, 3>>, [4, [5]] | <<6>>], [256], [-1], [a], [1 | 2], "abc"]],
             convert_time_unit => [[T, F, U] || T <- [0, 1, 999, 1000, 1001, -1, -999, -1000, -1001, 123456789],
                                                F <- [second, millisecond, microsecond, nanosecond, native, 3],
                                                U <- [second, millisecond, microsecond, nanosecond, native, 7]]
                                  ++ [[1, x, second], [x, second, second]]},
    Calls = [{F, A} || {F, As} <- lists:sort(maps:to_list(Args)), A <- As],
    report(Calls, erlang, oerlang).

report(Calls, Real, Shim) ->
    Diff = [{F, A, E, O} || {F, A} <- Calls,
                            E <- [run(fun() -> apply(Real, F, A) end)],
                            O <- [run(fun() -> apply(Shim, F, A) end)],
                            E =/= O],
    io:format("~w calls, ~w differ~n", [length(Calls), length(Diff)]),
    [io:format("~w~n", [D]) || D <- lists:sublist(Diff, 20)],
    halt(min(1, length(Diff))).

run(F) ->
    try F() catch C:R -> {C, R} end.
