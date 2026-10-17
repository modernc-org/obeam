#!/usr/bin/env escript
%%! -pa .
%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erl/shim/string.erl, as ostring, against OTP's; see scripts/shimcheck.sh.
%% Strings of an alphabet with "\r\n", Latin-1's letters whose case changes
%% out of it (ß, ÿ, µ), a character of three bytes in UTF-8 and one of four,
%% as lists and as binaries, against patterns and separators of a smaller
%% one. Combining marks and letters beyond Latin-1, which the shim does not
%% take as OTP does, are left out.

main(_) ->
    D1 = check({7, 8, 9}, 9, 1500, 6),
    D2 = check({11, 12, 13}, 24, 1200, 8),
    halt(min(1, D1 + D2)).

check(Seed, MaxLen, NStrs, NPats) ->
    rand:seed(exsss, Seed),
    Alpha = ["a", "b", " ", ",", "\r", "\n", "\r\n", "\t", [233], [223], [255], "A", [201], [181], "-", "+", "1", "2",
             [16#263A], [16#1F600], "ab", "  "],
    PatA = ["a", "b", ",", "\r", "\n", "\r\n", " ", "ab", "1"],
    SepA = [$\s, $,, $\r, $\n, [13, 10], $a, $1, $-],
    Lists = [str(Alpha, MaxLen) || _ <- lists:seq(1, NStrs)]
            ++ ["", " ", "\r\n", "a\r\n", "\r\na", "12ab", "-7", "+", "-", "+-5", "5-3", " 12", "007x"],
    Strs = Lists ++ [unicode:characters_to_binary(S) || S <- Lists],
    Pats = [str(PatA, 3) || _ <- lists:seq(1, NPats)] ++ ["", <<",">>],
    Seps = [lists:usort([pick(SepA) || _ <- lists:seq(1, rand:uniform(3))]) || _ <- lists:seq(1, 5)] ++ [[]],
    Calls = lists:append([
        [{F, [S]} || S <- Strs, F <- [is_empty, length, to_graphemes, reverse, next_grapheme, next_codepoint, trim,
                                      chomp, uppercase, lowercase, casefold, titlecase, to_integer]],
        [{equal, [S, T]} || S <- lists:sublist(Strs, 200),
                            T <- [hd(Strs), unicode:characters_to_binary(string:uppercase(S)), S]],
        [{equal, [S, string:uppercase(S), true]} || S <- lists:sublist(Strs, 300)],
        [{slice, [S, N]} || S <- Strs, N <- [0, 1, 3, 20]],
        [{slice, [S, N, L]} || S <- Strs, N <- [0, 2], L <- [0, 1, 3, infinity]],
        [{pad, [S, N]} || S <- Strs, N <- [0, 4, 9]],
        [{pad, [S, 7, D, $*]} || S <- Strs, D <- [leading, trailing, both]],
        [{trim, [S, D]} || S <- Strs, D <- [leading, trailing, both]],
        [{trim, [S, D, Sp]} || S <- Strs, D <- [leading, trailing, both], Sp <- Seps],
        [{take, [S, Sp, C, D]} || S <- Strs, Sp <- Seps, C <- [false, true], D <- [leading, trailing]],
        [{lexemes, [S, Sp]} || S <- Strs, Sp <- Seps],
        [{nth_lexeme, [S, N, Sp]} || S <- Strs, Sp <- Seps, N <- [1, 2, 5]],
        [{split, [S, P, W]} || S <- Strs, P <- Pats, W <- [leading, trailing, all]],
        [{replace, [S, P, "X", W]} || S <- Strs, P <- Pats, W <- [leading, trailing, all]],
        [{find, [S, P, D]} || S <- Strs, P <- Pats, D <- [leading, trailing]],
        [{prefix, [S, P]} || S <- Strs, P <- Pats],
        [{F, [S]} || S <- Lists, F <- [to_upper, to_lower, len, words, strip, list_to_integer]],
        [{to_upper, [C]} || C <- [$a, 224, 247, 255, 223, $1]],
        [{to_lower, [C]} || C <- [$A, 192, 215, 222, $1]],
        [{F, [S, C]} || S <- Lists, C <- [$a, $\s, $,], F <- [chr, rchr, words]],
        [{F, [S, P]} || S <- Lists, P <- ["a", "ab", ",", "", " a"], F <- [str, rstr, span, cspan, tokens, concat]],
        [{tokens, [S, ", "]} || S <- Lists],
        [{substr, [S, N]} || S <- Lists, N <- [1, 2, 4]],
        [{substr, [S, N, L]} || S <- Lists, N <- [1, 3], L <- [0, 2, 9]],
        [{sub_string, [S, A, B]} || S <- Lists, A <- [1, 2], B <- [2, 5]],
        [{F, [S, N]} || S <- Lists, N <- [0, 3, 8], F <- [left, right, centre]],
        [{F, [S, 6, $.]} || S <- Lists, F <- [left, right, centre]],
        [{sub_word, [S, N]} || S <- Lists, N <- [1, 2, 3]],
        [{sub_word, [S, 2, $,]} || S <- Lists],
        [{strip, [S, D]} || S <- Lists, D <- [left, right, both]],
        [{strip, [S, D, $a]} || S <- Lists, D <- [left, right, both]],
        [{copies, [S, N]} || S <- lists:sublist(Lists, 100), N <- [0, 1, 3]],
        [{chars, [$x, 3]}, {chars, [$x, 0, "yz"]}, {chars, [$x, 2, "yz"]}],
        [{join, [L, ", "]} || L <- [[], ["a"], ["a", "", "bc"], lists:sublist(Lists, 5)]]]),
    Diff = [{F, A, E, O} || {F, A} <- Calls,
                            E <- [run(fun() -> apply(string, F, A) end)],
                            O <- [run(fun() -> apply(ostring, F, A) end)],
                            E =/= O],
    io:format("~w calls, ~w differ~n", [length(Calls), length(Diff)]),
    [io:format("~w~n", [X]) || X <- lists:sublist(Diff, 20)],
    length(Diff).

str(Alpha, Max) -> lists:append([pick(Alpha) || _ <- lists:seq(1, rand:uniform(Max + 1) - 1)]).

pick(L) -> lists:nth(rand:uniform(length(L)), L).

run(F) ->
    try F() catch C:R -> {C, R} end.
