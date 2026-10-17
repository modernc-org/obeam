%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% rnd: what a program asks of OTP's rand, which the board has as a shim over
%% the P2's hardware generator, erl/shim/rand.erl, held here to the real one:
%% the numbers are printed as whether they are in their ranges and spread.
-module(rnd).
-export([main/0]).

main() ->
    _ = rand:seed(exsss),
    Dice = [rand:uniform(6) || _ <- lists:seq(1, 600)],
    p(dice, [lists:all(fun(X) -> is_integer(X) andalso X >= 1 andalso X =< 6 end, Dice), lists:usort(Dice)]),
    Fs = [rand:uniform() || _ <- lists:seq(1, 200)],
    p(floats, [lists:all(fun(X) -> is_float(X) andalso X >= 0.0 andalso X < 1.0 end, Fs),
               length(lists:usort(Fs)) > 150]),
    Rs = [rand:uniform_real() || _ <- lists:seq(1, 200)],
    p(reals, lists:all(fun(X) -> is_float(X) andalso X > 0.0 andalso X < 1.0 end, Rs)),
    p(one, [rand:uniform(1), rand:uniform(1)]),
    Big = [rand:uniform(1000000) || _ <- lists:seq(1, 100)],
    p(big, [lists:min(Big) >= 1, lists:max(Big) =< 1000000, length(lists:usort(Big)) > 90]),
    Huge = [rand:uniform(1 bsl 40) || _ <- lists:seq(1, 50)],
    p(huge, [lists:min(Huge) >= 1, lists:max(Huge) =< 1 bsl 40, lists:max(Huge) > 1 bsl 33]),
    B = rand:bytes(16),
    p(bytes, [is_binary(B), byte_size(B), rand:bytes(0)]),
    p(bad, [catch_error(fun() -> rand:uniform(0) end), catch_error(fun() -> rand:uniform(x) end),
            catch_error(fun() -> rand:bytes(-1) end)]).

catch_error(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
