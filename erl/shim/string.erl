%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% string: OTP's string module for a program packed for the board, which
%% takes what it calls of this by reach. A string is a list of characters,
%% or a binary in UTF-8, or chardata nesting them, which is taken as the flat
%% list of its characters: a function given a list answers flat lists where
%% OTP's may answer nested ones, as OTP's does given a flat list. A grapheme
%% cluster is a character, or "\r\n": the clusters OTP makes of combining
%% marks and the like are not made, and the case of a letter is changed in
%% Latin-1 only, and in the three letters outside it that Latin-1's change
%% to (U+0178, U+039C, U+03BC), others staying as they are. Normalization is
%% not done, and to_float/1, list_to_float/1 and jaro_similarity/2 are not
%% here. A list is
%% walked with an accumulator where OTP recurses on its body, since a
%% process's stack on the board is its heap block. Never on erl's path, where
%% it would hide OTP's own.
-module(string).
-compile({no_auto_import, [length/1, list_to_integer/1]}).
-export([casefold/1, centre/2, centre/3, chars/2, chars/3, chomp/1, chr/2,
         concat/2, copies/2, cspan/2, equal/2, equal/3, equal/4, find/2,
         find/3, is_empty/1, join/2, left/2, left/3, len/1, length/1,
         lexemes/2, list_to_integer/1, lowercase/1, next_codepoint/1,
         next_grapheme/1, nth_lexeme/3, pad/2, pad/3, pad/4, prefix/2,
         rchr/2, replace/3, replace/4, reverse/1, right/2, right/3, rstr/2,
         slice/2, slice/3, span/2, split/2, split/3, str/2, strip/1, strip/2,
         strip/3, sub_string/2, sub_string/3, sub_word/2, sub_word/3,
         substr/2, substr/3, take/2, take/3, take/4, titlecase/1,
         to_graphemes/1, to_integer/1, to_lower/1, to_upper/1, tokens/2,
         trim/1, trim/2, trim/3, uppercase/1, words/1, words/2]).

-define(WHITESPACE, [[13, 10], 9, 10, 11, 12, 13, 32, 133, 8206, 8207, 8232, 8233]).

%% Chardata.

%% cps answers chardata's characters, a binary's decoded from UTF-8.
cps(B) when is_binary(B) -> decode(binary_to_list(B), []);
cps(L) when is_list(L) -> flat(L, [], []);
cps(X) -> error(badarg, [X]).

flat([C | L], Stack, Acc) when is_integer(C) -> flat(L, Stack, [C | Acc]);
flat([B | L], Stack, Acc) when is_binary(B) -> flat(L, Stack, lists:reverse(cps(B), Acc));
flat([H | L], Stack, Acc) when is_list(H) -> flat(H, [L | Stack], Acc);
flat([], [L | Stack], Acc) -> flat(L, Stack, Acc);
flat([], [], Acc) -> lists:reverse(Acc);
flat(B, Stack, Acc) when is_binary(B) -> flat([], Stack, lists:reverse(cps(B), Acc));
flat(X, _, _) -> error(badarg, [X]).

%% back answers characters as the chardata Orig was: a binary for a binary,
%% a list otherwise.
back(Orig, Cs) when is_binary(Orig) -> list_to_binary(encode(Cs, []));
back(_, Cs) -> Cs.

decode([B | L], Acc) when B < 16#80 -> decode(L, [B | Acc]);
decode([B, C | L], Acc) when B >= 16#C2, B < 16#E0, C >= 16#80, C < 16#C0 ->
    decode(L, [((B band 16#1F) bsl 6) bor (C band 16#3F) | Acc]);
decode([B, C, D | L], Acc) when B >= 16#E0, B < 16#F0, C >= 16#80, C < 16#C0, D >= 16#80, D < 16#C0 ->
    decode(L, [((B band 16#0F) bsl 12) bor ((C band 16#3F) bsl 6) bor (D band 16#3F) | Acc]);
decode([B, C, D, E | L], Acc) when B >= 16#F0, B < 16#F5, C >= 16#80, C < 16#C0, D >= 16#80, D < 16#C0, E >= 16#80, E < 16#C0 ->
    decode(L, [((B band 16#07) bsl 18) bor ((C band 16#3F) bsl 12) bor ((D band 16#3F) bsl 6) bor (E band 16#3F) | Acc]);
decode([B | _], _) -> error({badarg, B});
decode([], Acc) -> lists:reverse(Acc).

encode([C | L], Acc) when C < 16#80 -> encode(L, [C | Acc]);
encode([C | L], Acc) when C < 16#800 -> encode(L, [16#80 bor (C band 16#3F), 16#C0 bor (C bsr 6) | Acc]);
encode([C | L], Acc) when C < 16#10000 ->
    encode(L, [16#80 bor (C band 16#3F), 16#80 bor ((C bsr 6) band 16#3F), 16#E0 bor (C bsr 12) | Acc]);
encode([C | L], Acc) ->
    encode(L, [16#80 bor (C band 16#3F), 16#80 bor ((C bsr 6) band 16#3F), 16#80 bor ((C bsr 12) band 16#3F), 16#F0 bor (C bsr 18) | Acc]);
encode([], Acc) -> lists:reverse(Acc).

%% Grapheme clusters: gc answers the first and the rest.
gc([13, 10 | L]) -> {[13, 10], L};
gc([C | L]) -> {C, L}.

gcs(L) -> gcs(L, []).

gcs([13, 10 | L], Acc) -> gcs(L, [[13, 10] | Acc]);
gcs([C | L], Acc) -> gcs(L, [C | Acc]);
gcs([], Acc) -> lists:reverse(Acc).

%% unit is what a search takes as one: the cluster at a character that may
%% begin a separator, the character otherwise, as OTP's searches do.
unit([C | L] = Cs, Firsts) ->
    case lists:member(C, Firsts) of
        true -> gc(Cs);
        false -> {C, L}
    end.

%% firsts answers the characters separators begin with.
firsts(Seps) -> [first(S) || S <- Seps].

first(C) when is_integer(C) -> C;
first(S) -> hd(cps(S)).

%% push prepends a unit's characters to a reversed list.
push(G, Acc) when is_list(G) -> lists:reverse(G, Acc);
push(C, Acc) -> [C | Acc].

%% Counting, comparing and reversing.

is_empty([]) -> true;
is_empty(<<>>) -> true;
is_empty([L | R]) -> is_empty(L) andalso is_empty(R);
is_empty(_) -> false.

length(CD) -> count(cps(CD), 0).

count([13, 10 | L], N) -> count(L, N + 1);
count([_ | L], N) -> count(L, N + 1);
count([], N) -> N.

to_graphemes(CD) -> gcs(cps(CD)).

reverse(CD) -> lists:reverse(gcs(cps(CD))).

equal(A, B) -> cps(A) =:= cps(B).

equal(A, B, false) -> equal(A, B);
equal(A, B, true) -> fold(cps(A), []) =:= fold(cps(B), []).

equal(A, B, IgnoreCase, _Norm) -> equal(A, B, IgnoreCase).

next_grapheme(CD) ->
    case cps(CD) of
        [] -> [];
        Cs ->
            {G, L} = gc(Cs),
            [G | back(CD, L)]
    end.

next_codepoint(CD) ->
    case cps(CD) of
        [] -> [];
        [C | L] -> [C | back(CD, L)]
    end.

%% Slicing and padding, by clusters.

%% A binary sliced just after a "\r" that is a cluster of its own answers, as
%% OTP's does, the character after it in a list: [C | Rest] for slice/2, and
%% a list of characters for slice/3.
slice(CD, N) when is_integer(N), N >= 0 ->
    case drop(N, cps(CD), false) of
        {true, [C | L]} when is_binary(CD) -> [C | back(CD, L)];
        {_, L} -> back(CD, L)
    end;
slice(CD, N) -> error(function_clause, [CD, N]).

slice(CD, N, Len) when is_integer(N), N >= 0, is_integer(Len), Len > 0 ->
    case drop(N, cps(CD), false) of
        {true, [_ | _] = L} when is_binary(CD) -> keep(Len, L, []);
        {_, L} -> back(CD, keep(Len, L, []))
    end;
slice(CD, N, infinity) when is_integer(N), N >= 0 -> slice(CD, N);
slice(CD, _, 0) -> back(CD, []);
slice(CD, N, Len) -> error(function_clause, [CD, N, Len]).

%% drop answers L without its first N clusters, and whether the last of them
%% was a "\r" of its own.
drop(0, L, CR) -> {CR, L};
drop(_, [], CR) -> {CR, []};
drop(N, L, _) ->
    {G, T} = gc(L),
    drop(N - 1, T, G =:= 13).

keep(0, _, Acc) -> lists:reverse(Acc);
keep(_, [], Acc) -> lists:reverse(Acc);
keep(N, L, Acc) ->
    {G, T} = gc(L),
    keep(N - 1, T, push(G, Acc)).

pad(CD, Length) -> pad(CD, Length, trailing, $\s).

pad(CD, Length, Dir) -> pad(CD, Length, Dir, $\s).

pad(CD, Length, leading, Char) when is_integer(Length) ->
    [lists:duplicate(max(0, Length - length(CD)), Char), CD];
pad(CD, Length, trailing, Char) when is_integer(Length) ->
    [CD | lists:duplicate(max(0, Length - length(CD)), Char)];
pad(CD, Length, both, Char) when is_integer(Length) ->
    Size = max(0, Length - length(CD)),
    Pre = lists:duplicate(Size div 2, Char),
    case Size rem 2 of
        1 -> [Pre, CD, Pre, Char];
        _ -> [Pre, CD, Pre]
    end.

%% Trimming and taking. Leading separators are clusters, and trailing ones
%% units of a search, as OTP's are.

trim(Str) -> trim(Str, both, ?WHITESPACE).

trim(Str, Dir) -> trim(Str, Dir, ?WHITESPACE).

trim(Str, _, []) -> Str;
trim(Str, leading, Seps) when is_list(Seps) -> back(Str, trim_l(cps(Str), Seps));
trim(Str, trailing, Seps) when is_list(Seps) -> back(Str, trim_t(cps(Str), Seps));
trim(Str, both, Seps) when is_list(Seps) -> back(Str, trim_t(trim_l(cps(Str), Seps), Seps)).

trim_l([], _) -> [];
trim_l(L, Seps) ->
    {G, T} = gc(L),
    case lists:member(G, Seps) of
        true -> trim_l(T, Seps);
        false -> L
    end.

trim_t(L, Seps) ->
    {Head, _} = tail_of(L, Seps, firsts(Seps), [], []),
    Head.

%% tail_of splits L at the run of separator units it ends with.
tail_of([], _, _, Head, Run) -> {lists:reverse(Head), lists:reverse(Run)};
tail_of(L, Seps, Firsts, Head, Run) ->
    {U, T} = unit(L, Firsts),
    case lists:member(U, Seps) of
        true -> tail_of(T, Seps, Firsts, Head, push(U, Run));
        false -> tail_of(T, Seps, Firsts, push(U, Run ++ Head), [])
    end.

chomp(Str) -> trim(Str, trailing, [[13, 10], 10]).

take(Str, Seps) -> take(Str, Seps, false, leading).

take(Str, Seps, Complement) -> take(Str, Seps, Complement, leading).

take(Str, [], Complement, Dir) ->
    Empty = back(Str, []),
    case {Complement, Dir} of
        {false, leading} -> {Empty, Str};
        {false, trailing} -> {Str, Empty};
        {true, leading} -> {Str, Empty};
        {true, trailing} -> {Empty, Str}
    end;
take(Str, Seps, false, leading) ->
    {H, T} = take_l(cps(Str), Seps, []),
    {back(Str, H), back(Str, T)};
take(Str, Seps, true, leading) ->
    {H, T} = take_lc(cps(Str), Seps, firsts(Seps), []),
    {back(Str, H), back(Str, T)};
take(Str, Seps, false, trailing) ->
    {H, T} = tail_of(cps(Str), Seps, firsts(Seps), [], []),
    {back(Str, H), back(Str, T)};
take(Str, Seps, true, trailing) ->
    {H, T} = take_tc(cps(Str), Seps, [], []),
    {back(Str, H), back(Str, T)}.

take_l([], _, Acc) -> {lists:reverse(Acc), []};
take_l(L, Seps, Acc) ->
    {G, T} = gc(L),
    case lists:member(G, Seps) of
        true -> take_l(T, Seps, push(G, Acc));
        false -> {lists:reverse(Acc), L}
    end.

take_lc([], _, _, Acc) -> {lists:reverse(Acc), []};
take_lc(L, Seps, Firsts, Acc) ->
    {U, T} = unit(L, Firsts),
    case lists:member(U, Seps) of
        true -> {lists:reverse(Acc), L};
        false -> take_lc(T, Seps, Firsts, push(U, Acc))
    end.

%% take_tc splits L at the run of clusters that are no separators it ends
%% with.
take_tc([], _, Head, Run) -> {lists:reverse(Head), lists:reverse(Run)};
take_tc(L, Seps, Head, Run) ->
    {G, T} = gc(L),
    case lists:member(G, Seps) of
        true -> take_tc(T, Seps, push(G, Run ++ Head), []);
        false -> take_tc(T, Seps, Head, push(G, Run))
    end.

%% Lexemes, by search units.

lexemes([], _) -> [];
lexemes(Str, []) -> [Str];
lexemes(Str, Seps) when is_list(Seps) -> lexemes(cps(Str), Str, Seps, firsts(Seps), []).

lexemes([], _, _, _, Acc) -> lists:reverse(Acc);
lexemes(L, Str, Seps, Firsts, Acc) ->
    {U, T} = unit(L, Firsts),
    case lists:member(U, Seps) of
        true -> lexemes(T, Str, Seps, Firsts, Acc);
        false ->
            {Lexeme, Rest} = lexeme(L, Seps, Firsts, []),
            lexemes(Rest, Str, Seps, Firsts, [back(Str, Lexeme) | Acc])
    end.

lexeme([], _, _, Acc) -> {lists:reverse(Acc), []};
lexeme(L, Seps, Firsts, Acc) ->
    {U, T} = unit(L, Firsts),
    case lists:member(U, Seps) of
        true -> {lists:reverse(Acc), T};
        false -> lexeme(T, Seps, Firsts, push(U, Acc))
    end.

nth_lexeme(Str, 1, []) -> Str;
nth_lexeme(Str, N, []) when is_binary(Str), is_integer(N), N > 1 -> error(badarg, [Str, N, []]);
nth_lexeme(Str, N, Seps) when is_list(Seps), is_integer(N), N > 0 ->
    nth_lexeme(cps(Str), Str, N, Seps, firsts(Seps)).

nth_lexeme([], Str, _, _, _) -> back(Str, []);
nth_lexeme(L, Str, N, Seps, Firsts) ->
    {U, T} = unit(L, Firsts),
    case lists:member(U, Seps) of
        true -> nth_lexeme(T, Str, N, Seps, Firsts);
        false ->
            {Lexeme, Rest} = lexeme(L, Seps, Firsts, []),
            if
                N =:= 1 -> back(Str, Lexeme);
                true -> nth_lexeme(Rest, Str, N - 1, Seps, Firsts)
            end
    end.

%% Searching. A pattern matches where its characters are, its last being a
%% cluster: "\r" does not match the "\r" of "\r\n", as in OTP.

%% match answers what follows Needle at the head of L, or nomatch.
match(L, [N]) ->
    case L of
        [] -> nomatch;
        _ ->
            case gc(L) of
                {N, T} -> T;
                _ -> nomatch
            end
    end;
match([C | L], [C | Needle]) -> match(L, Needle);
match(_, _) -> nomatch.

split(String, Pattern) -> split(String, Pattern, leading).

split(String, Pattern, Where) ->
    case is_empty(Pattern) of
        true -> [String];
        false ->
            case split_at(cps(String), cps(Pattern), Where, [], none, []) of
                none -> [String];
                Parts -> backs(String, Parts, [])
            end
    end.

%% split_at answers the parts, or none when Needle is nowhere: Curr is the
%% part so far, reversed, Last the parts of the last match for trailing, and
%% Acc the parts so far for all.
split_at([], _, all, Curr, _, [_ | _] = Acc) -> lists:reverse([lists:reverse(Curr) | Acc]);
split_at([], _, trailing, _, Last, _) -> Last;
split_at([], _, _, _, _, _) -> none;
split_at([C | L] = Cs, Needle, Where, Curr, Last, Acc) ->
    case match(Cs, Needle) of
        nomatch -> split_at(L, Needle, Where, [C | Curr], Last, Acc);
        Rest when Where =:= leading -> [lists:reverse(Curr), Rest];
        Rest when Where =:= trailing -> split_at(L, Needle, Where, [C | Curr], [lists:reverse(Curr), Rest], Acc);
        Rest when Where =:= all -> split_at(Rest, Needle, Where, [], Last, [lists:reverse(Curr) | Acc])
    end.

backs(String, [P | Ps], Acc) -> backs(String, Ps, [back(String, P) | Acc]);
backs(_, [], Acc) -> lists:reverse(Acc).

replace(String, Pattern, Replacement) -> lists:join(Replacement, split(String, Pattern)).

replace(String, Pattern, Replacement, Where) -> lists:join(Replacement, split(String, Pattern, Where)).

find(String, Pattern) -> find(String, Pattern, leading).

find(String, "", _) -> String;
find(String, <<>>, _) -> String;
find(String, Pattern, leading) -> found(String, find_l(cps(String), cps(Pattern)));
find(String, Pattern, trailing) -> found(String, find_t(cps(String), cps(Pattern), nomatch)).

found(_, nomatch) -> nomatch;
found(String, L) -> back(String, L).

find_l([], _) -> nomatch;
find_l([_ | L] = Cs, Needle) ->
    case match(Cs, Needle) of
        nomatch -> find_l(L, Needle);
        _ -> Cs
    end.

find_t([], _, Last) -> Last;
find_t([_ | L] = Cs, Needle, Last) ->
    case match(Cs, Needle) of
        nomatch -> find_t(L, Needle, Last);
        _ -> find_t(L, Needle, Cs)
    end.

prefix(Str, Prefix) ->
    case cps(Prefix) of
        [] -> Str;
        Needle ->
            case match(cps(Str), Needle) of
                nomatch -> nomatch;
                Rest -> back(Str, Rest)
            end
    end.

%% Case, in Latin-1.

uppercase(CD) -> back(CD, upper(cps(CD), [])).

lowercase(CD) -> back(CD, lower(cps(CD), [])).

casefold(CD) -> back(CD, fold(cps(CD), [])).

titlecase(CD) ->
    case cps(CD) of
        [] -> CD;
        [$ß | L] -> back(CD, [$S, $s | L]);
        [13, 10 | _] -> CD;
        [C | L] -> back(CD, upper([C], []) ++ L)
    end.

upper([C | L], Acc) when C >= $a, C =< $z; C >= 16#E0, C =< 16#FE, C =/= 16#F7 -> upper(L, [C - 32 | Acc]);
upper([$ß | L], Acc) -> upper(L, [$S, $S | Acc]);
upper([16#FF | L], Acc) -> upper(L, [16#178 | Acc]);
upper([16#B5 | L], Acc) -> upper(L, [16#39C | Acc]);
upper([16#3BC | L], Acc) -> upper(L, [16#39C | Acc]);
upper([C | L], Acc) -> upper(L, [C | Acc]);
upper([], Acc) -> lists:reverse(Acc).

lower([C | L], Acc) when C >= $A, C =< $Z; C >= 16#C0, C =< 16#DE, C =/= 16#D7 -> lower(L, [C + 32 | Acc]);
lower([16#178 | L], Acc) -> lower(L, [16#FF | Acc]);
lower([16#39C | L], Acc) -> lower(L, [16#3BC | Acc]);
lower([C | L], Acc) -> lower(L, [C | Acc]);
lower([], Acc) -> lists:reverse(Acc).

fold([C | L], Acc) when C >= $A, C =< $Z; C >= 16#C0, C =< 16#DE, C =/= 16#D7 -> fold(L, [C + 32 | Acc]);
fold([$ß | L], Acc) -> fold(L, [$s, $s | Acc]);
fold([16#B5 | L], Acc) -> fold(L, [16#3BC | Acc]);
fold([16#178 | L], Acc) -> fold(L, [16#FF | Acc]);
fold([16#39C | L], Acc) -> fold(L, [16#3BC | Acc]);
fold([C | L], Acc) -> fold(L, [C | Acc]);
fold([], Acc) -> lists:reverse(Acc).

to_upper(S) when is_list(S) -> to_upper(S, []);
to_upper(C) when is_integer(C) -> to_upper_char(C).

to_upper([C | S], Acc) -> to_upper(S, [to_upper_char(C) | Acc]);
to_upper([], Acc) -> lists:reverse(Acc).

to_lower(S) when is_list(S) -> to_lower(S, []);
to_lower(C) when is_integer(C) -> to_lower_char(C).

to_lower([C | S], Acc) -> to_lower(S, [to_lower_char(C) | Acc]);
to_lower([], Acc) -> lists:reverse(Acc).

to_upper_char(C) when is_integer(C), C >= $a, C =< $z; is_integer(C), C >= 16#E0, C =< 16#FE, C =/= 16#F7 -> C - 32;
to_upper_char(C) -> C.

to_lower_char(C) when is_integer(C), C >= $A, C =< $Z; is_integer(C), C >= 16#C0, C =< 16#DE, C =/= 16#D7 -> C + 32;
to_lower_char(C) -> C.

%% Numbers.

to_integer(String) ->
    try take(String, "+-0123456789") of
        {Head, _} ->
            case is_empty(Head) of
                true -> {error, no_integer};
                false ->
                    case list_to_integer(cps(Head)) of
                        {error, _} = Err -> Err;
                        {Int, _} ->
                            Cs = cps(String),
                            {Int, back(String, lists:nthtail(digits(Cs), Cs))}
                    end
            end
    catch
        _:_ -> {error, badarg}
    end.

%% digits answers how long the integer at the head of L is, its sign with it.
digits([S | L]) when S =:= $+; S =:= $- -> 1 + digits(L, 0);
digits(L) -> digits(L, 0).

digits([C | L], N) when C >= $0, C =< $9 -> digits(L, N + 1);
digits(_, N) -> N.

list_to_integer(L) when is_list(L) ->
    case L of
        [$- | T] -> sign(-1, T);
        [$+ | T] -> sign(1, T);
        _ -> sign(1, L)
    end;
list_to_integer(_) -> {error, not_a_list}.

sign(Sign, [C | _] = L) when C >= $0, C =< $9 -> number(L, 0, Sign);
sign(_, _) -> {error, no_integer}.

number([C | L], N, Sign) when C >= $0, C =< $9 -> number(L, N * 10 + C - $0, Sign);
number(L, N, Sign) -> {Sign * N, L}.

%% The old functions, of lists of characters.

len(S) -> erlang:length(S).

concat(S1, S2) -> S1 ++ S2.

chr(S, C) when is_integer(C) -> chr(S, C, 1).

chr([C | _], C, I) -> I;
chr([_ | S], C, I) -> chr(S, C, I + 1);
chr([], _, _) -> 0.

rchr(S, C) when is_integer(C) -> rchr(S, C, 1, 0).

rchr([C | S], C, I, _) -> rchr(S, C, I + 1, I);
rchr([_ | S], C, I, L) -> rchr(S, C, I + 1, L);
rchr([], _, _, L) -> L.

str(S, Sub) when is_list(Sub) -> str(S, Sub, 1).

str([C | S], [C | Sub], I) ->
    case l_prefix(Sub, S) of
        true -> I;
        false -> str(S, [C | Sub], I + 1)
    end;
str([_ | S], Sub, I) -> str(S, Sub, I + 1);
str([], _, _) -> 0.

rstr(S, Sub) when is_list(Sub) -> rstr(S, Sub, 1, 0).

rstr([C | S], [C | Sub], I, L) ->
    case l_prefix(Sub, S) of
        true -> rstr(S, [C | Sub], I + 1, I);
        false -> rstr(S, [C | Sub], I + 1, L)
    end;
rstr([_ | S], Sub, I, L) -> rstr(S, Sub, I + 1, L);
rstr([], _, _, L) -> L.

l_prefix([C | Pre], [C | S]) -> l_prefix(Pre, S);
l_prefix([], S) when is_list(S) -> true;
l_prefix(Pre, S) when is_list(Pre), is_list(S) -> false.

span(S, Cs) when is_list(Cs) -> span(S, Cs, 0).

span([C | S], Cs, I) ->
    case lists:member(C, Cs) of
        true -> span(S, Cs, I + 1);
        false -> I
    end;
span([], _, I) -> I.

cspan(S, Cs) when is_list(Cs) -> cspan(S, Cs, 0).

cspan([C | S], Cs, I) ->
    case lists:member(C, Cs) of
        true -> I;
        false -> cspan(S, Cs, I + 1)
    end;
cspan([], _, I) -> I.

substr(String, 1) when is_list(String) -> String;
substr(String, S) when is_integer(S), S > 1 -> substr2(String, S).

substr(String, S, L) when is_integer(S), S >= 1, is_integer(L), L >= 0 ->
    substr1(substr2(String, S), L, []).

substr1([C | String], L, Acc) when L > 0 -> substr1(String, L - 1, [C | Acc]);
substr1(String, _, Acc) when is_list(String) -> lists:reverse(Acc).

substr2(String, 1) when is_list(String) -> String;
substr2([_ | String], S) -> substr2(String, S - 1).

sub_string(String, Start) -> substr(String, Start).

sub_string(String, Start, Stop) when is_integer(Start), is_integer(Stop) ->
    substr(String, Start, Stop - Start + 1).

tokens(S, Seps) ->
    case Seps of
        [] ->
            case S of
                [] -> [];
                [_ | _] -> [S]
            end;
        _ -> tokens(lists:reverse(S), Seps, [], [])
    end.

%% tokens walks the string from its end, so that each token comes out in
%% order.
tokens([C | S], Seps, Tok, Toks) ->
    case lists:member(C, Seps) of
        true when Tok =:= [] -> tokens(S, Seps, [], Toks);
        true -> tokens(S, Seps, [], [Tok | Toks]);
        false -> tokens(S, Seps, [C | Tok], Toks)
    end;
tokens([], _, [], Toks) -> Toks;
tokens([], _, Tok, Toks) -> [Tok | Toks].

chars(C, N) -> chars(C, N, []).

chars(C, N, Tail) when is_integer(N), N > 0 -> chars(C, N - 1, [C | Tail]);
chars(C, 0, Tail) when is_integer(C) -> Tail.

copies(S, N) when is_list(S), is_integer(N), N >= 0 -> copies(S, N, []).

copies(_, 0, R) -> R;
copies(S, N, R) -> copies(S, N - 1, S ++ R).

words(String) -> words(String, $\s).

words(String, Char) when is_integer(Char) -> w_count(strip(String, both, Char), Char, 0).

w_count([], _, N) -> N + 1;
w_count([H | T], H, N) -> w_count(strip(T, left, H), H, N + 1);
w_count([_ | T], Char, N) -> w_count(T, Char, N).

sub_word(String, Index) -> sub_word(String, Index, $\s).

sub_word(String, Index, Char) when is_integer(Index), is_integer(Char) ->
    case words(String, Char) of
        N when N < Index -> [];
        _ -> s_word(strip(String, left, Char), Index, Char, 1, [])
    end.

s_word([], _, _, _, Res) -> lists:reverse(Res);
s_word([Char | _], Index, Char, Index, Res) -> lists:reverse(Res);
s_word([H | T], Index, Char, Index, Res) -> s_word(T, Index, Char, Index, [H | Res]);
s_word([Char | T], Stop, Char, Index, Res) when Index < Stop -> s_word(strip(T, left, Char), Stop, Char, Index + 1, Res);
s_word([_ | T], Stop, Char, Index, Res) when Index < Stop -> s_word(T, Stop, Char, Index, Res).

strip(String) -> strip(String, both).

strip(String, left) -> strip_left(String, $\s);
strip(String, right) -> strip_right(String, $\s);
strip(String, both) -> strip_right(strip_left(String, $\s), $\s).

strip(String, right, Char) -> strip_right(String, Char);
strip(String, left, Char) -> strip_left(String, Char);
strip(String, both, Char) -> strip_right(strip_left(String, Char), Char).

strip_left([Sc | S], Sc) -> strip_left(S, Sc);
strip_left([_ | _] = S, Sc) when is_integer(Sc) -> S;
strip_left([], Sc) when is_integer(Sc) -> [].

strip_right(S, Sc) when is_integer(Sc) -> lists:reverse(strip_left(lists:reverse(S), Sc)).

left(String, Len) when is_integer(Len) -> left(String, Len, $\s).

left(String, Len, Char) when is_integer(Len), is_integer(Char) ->
    Slen = erlang:length(String),
    if
        Slen > Len -> substr(String, 1, Len);
        Slen < Len -> String ++ chars(Char, Len - Slen);
        true -> String
    end.

right(String, Len) when is_integer(Len) -> right(String, Len, $\s).

right(String, Len, Char) when is_integer(Len), is_integer(Char) ->
    Slen = erlang:length(String),
    if
        Slen > Len -> substr(String, Slen - Len + 1);
        Slen < Len -> chars(Char, Len - Slen, String);
        true -> String
    end.

centre(String, Len) when is_integer(Len) -> centre(String, Len, $\s).

centre(String, 0, Char) when is_list(String), is_integer(Char) -> [];
centre(String, Len, Char) when is_integer(Len), is_integer(Char) ->
    Slen = erlang:length(String),
    if
        Slen > Len -> substr(String, (Slen - Len) div 2 + 1, Len);
        Slen < Len ->
            N = (Len - Slen) div 2,
            chars(Char, N, String ++ chars(Char, Len - (Slen + N)));
        true -> String
    end.

join([], Sep) when is_list(Sep) -> [];
join([H | T], Sep) -> H ++ join_rest(lists:reverse(T), Sep, []).

join_rest([X | T], Sep, Acc) -> join_rest(T, Sep, Sep ++ X ++ Acc);
join_rest([], _, Acc) -> Acc.
