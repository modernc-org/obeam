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
                                  ++ [[1, x, second], [x, second, second]],
             float_to_list => [[F] || F <- floats()] ++ [[F, O] || F <- floats(), O <- float_opts(F)] ++ [[1, []], [1.5, x], [1.5, [x]]],
             float_to_binary => [[F] || F <- lists:sublist(floats(), 50)] ++ [[F, O] || F <- lists:sublist(floats(), 50), O <- float_opts(F)]
                                ++ [[F, [{decimals, D}]] || F <- ties(), D <- lists:seq(0, 20)],
             list_to_float => [[S] || S <- float_strings()] ++ [[x], [[$1, $. | x]], [<<"1.0">>]],
             binary_to_float => [[list_to_binary(S)] || S <- lists:sublist(float_strings(), 200)] ++ [["1.0"], [x]],
             binary_to_existing_atom => [[B] || B <- [<<"ok">>, <<"erlang">>, <<"zzqq_none">>, <<>>, x]]
                                        ++ [[B, E] || B <- [<<"ok">>, <<"zzqq_none">>], E <- [utf8, latin1, unicode, x]]},
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

%% floats are exact binary fractions of few bits, decimals, which are not
%% exact, and the ends and the signs, all under 10^15: the shim writes 0s past
%% the 21st significant digit, where OTP writes the exact value's, and rounds
%% on what the 21 digits tell, so the options below ask for 19 digits at most.
%% A decimal is not asked for fewer decimals than it has, which OTP rounds in
%% floating point, and the shim from its 21 digits.
floats() ->
    rand:seed(exsss, {5, 6, 7}),
    Bin = [rand:uniform(1 bsl 20) / (1 bsl rand:uniform(30)) || _ <- lists:seq(1, 150)],
    Dec = [decimal(rand:uniform(1000000), rand:uniform(12)) || _ <- lists:seq(1, 150)],
    Big = [float(rand:uniform(1 bsl 40)) * pow10(rand:uniform(3)) || _ <- lists:seq(1, 30)],
    Fs = [0.0, 0.5, 1.0, 2.5, 9.5, 99.5, 0.125, 0.375, 1.0e-10, 1.0e14] ++ Bin ++ Dec ++ Big,
    Fs ++ [-F || F <- Fs] ++ [-0.0].

decimal(N, K) -> N / pow10(K).

%% ties are halfway between two decimals of up to 20 digits, which OTP
%% rounds up to 18 of them and to the even one past.
ties() -> [(2 * rand:uniform(1000) + 1) / (1 bsl K) || K <- lists:seq(1, 24)].

pow10(0) -> 1;
pow10(N) -> 10 * pow10(N - 1).

%% float_opts are the options for a float that keep within 21 digits, and,
%% for a decimal, within its own.
float_opts(F) ->
    Whole = length(integer_to_list(trunc(abs(F)))),
    Own = own_decimals(abs(F)),
    Ds = [D || D <- [0, 1, 2, 3, 5, 8, 12, 19], Whole + D =< 19, D >= Own],
    [[{decimals, D}] || D <- Ds] ++ [[{decimals, D}, compact] || D <- Ds]
        ++ [[{scientific, D}] || D <- [0, 1, 2, 5, 10, 20]]
        ++ [[], [short], [compact], [{decimals, 2}, {scientific, 3}], [{scientific, 3}, {decimals, 2}],
            [short, {decimals, 1}], [{decimals, 1}, short], [{decimals, 254}], [{scientific, 250}], [{decimals, -1}], [x], [compact | x]].

%% float_strings are good floats and bad ones, as Erlang writes them and not.
float_strings() ->
    rand:seed(exsss, {8, 9, 10}),
    Good = [sign() ++ digits(1 + rand:uniform(12)) ++ "." ++ digits(1 + rand:uniform(12)) ++ exp() || _ <- lists:seq(1, 400)],
    Good ++ ["1.0", "0.0", "-0.0", "+1.5", "00.000", "1.0e0000001", "1.0E-2", "1.0e+2", "3.4028235e38", "1.0e400", "1.0e-400",
             "1.0e-99999999", "1.0e99999999", "123456789012345678901234567890.0e-29",
             "1e5", "1.", ".5", "1.5e", "1.5e+", "1.5e-", "1.5 ", " 1.5", "abc", "", "-", "+", "1.2.3", "1.0e5.0", "1_0.0",
             "--1.0", "+-1.0", "1.0e--5", "1.0e+-5", "1.0ee5", "0x1.0", "1.0f", [$1, $., 1633], [$1, $., $5 | x]].

%% own_decimals answers how many decimals a float's shortest form has, 0 for
%% one of more than 12, a binary fraction's.
own_decimals(F) ->
    case string:split(float_to_list(F, [short]), ".") of
        [_, Fr] ->
            case string:split(Fr, "e") of
                [M, E] -> max(0, length(M) - list_to_integer(E));
                [M] when length(M) > 12 -> 0;
                [M] -> length(M)
            end;
        _ -> 0
    end.

sign() -> lists:nth(rand:uniform(3), ["", "-", "+"]).

digits(N) -> [$0 + rand:uniform(10) - 1 || _ <- lists:seq(1, N)].

exp() ->
    case rand:uniform(4) of
        1 -> "";
        _ -> lists:nth(rand:uniform(4), ["e", "E", "e+", "e-"]) ++ integer_to_list(rand:uniform(40) - 1)
    end.
