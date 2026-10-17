%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% strs: what a program asks of OTP's string, which the board has as a shim,
%% erl/shim/string.erl, held here to the real one: lines read from a serial
%% line with their "\r\n", fields split and trimmed, numbers taken out,
%% padding, case, binaries as UTF-8, and the old functions of lists. Results
%% are written with ~w, which shows the shape of what is nested.
-module(strs).
-export([main/0]).

main() ->
    Line = "  temp = 21.5 C, hum=40 %\r\n",
    p(chomp, [string:chomp(Line), string:chomp("ok\n\n"), string:chomp("cr\r")]),
    p(trim, [string:trim(Line), string:trim(Line, leading), string:trim("..x..", both, "."),
             string:trim("a\r\n", trailing, "\n"), string:trim(<<"  bin  ">>)]),
    Fields = string:split(string:trim(Line), ",", all),
    p(split, [Fields, string:split("k=v=w", "="), string:split("k=v=w", "=", trailing),
              string:split("abc", "x"), string:split(<<"a;b;;c">>, ";", all), string:split("a\r\nb", "\n")]),
    p(pairs, [[string:trim(X) || X <- string:split(F, "=")] || F <- Fields]),
    p(lexemes, [string:lexemes("  a  b,c ", " ,"), string:lexemes(<<"x y">>, " "),
                string:lexemes("l1\r\nl2\nl3", [$\n, [$\r, $\n]]), string:nth_lexeme("a b c", 2, " ")]),
    p(take, [string:take("123abc", "0123456789"), string:take("abc def", " ", true),
             string:take("x...", ".", false, trailing), string:take(<<"ab cd">>, " ", true, trailing)]),
    p(find, [string:find("a.b.c", "."), string:find("a.b.c", ".", trailing), string:find("abc", "z"),
             string:prefix("http://x", "http://"), string:prefix("x", "y")]),
    p(replace, [string:replace("a-b-c", "-", "+"), string:replace("a-b-c", "-", "+", all),
                string:replace(<<"a-b">>, "-", "")]),
    p(pad, [string:pad("ab", 5), string:pad("ab", 5, leading), string:pad("ab", 6, both, $*),
            string:pad("abcdef", 3), string:pad(<<"x">>, 3)]),
    io:format("[~ts] [~ts] [~ts]~n", [string:pad("left", 8), string:pad("right", 8, leading), string:pad("mid", 9, both)]),
    p(slice, [string:slice("hello", 1, 3), string:slice("hello", 3), string:slice(<<"hello">>, 1, 2),
              string:slice("a\r\nb", 1), string:slice("ab", 5)]),
    p(length, [string:length("abc"), string:length("a\r\nb"), string:length(<<"é"/utf8>>), string:is_empty(""),
               string:is_empty(["", <<>>]), string:is_empty(" ")]),
    p(graphemes, [string:to_graphemes("a\r\nb"), string:reverse("abc"), string:reverse("x\r\ny"),
                  string:next_grapheme("\r\nz"), string:next_codepoint("ab")]),
    p(case_, [string:uppercase("Hello, World"), string:lowercase(<<"MiXeD">>), string:titlecase("erlang"),
              string:casefold("ÀÉÎ"), string:uppercase("straße"), string:to_upper("abc"), string:to_lower($Q),
              string:equal("ABC", "abc", true), string:equal("ab", <<"ab">>)]),
    p(numbers, [string:to_integer("42 rest"), string:to_integer("-7"), string:to_integer("x1"),
                string:to_integer(<<"12ab">>), string:to_integer("+-3"), string:list_to_integer("99 bottles")]),
    p(old, [string:tokens("a,b;;c", ",;"), string:join(["one", "two", "three"], ", "), string:strip("  x  "),
            string:strip("..x..", right, $.), string:substr("hello", 2, 3), string:sub_string("hello", 2, 3),
            string:str("hello", "ll"), string:rstr("abab", "ab"), string:chr("hello", $l), string:rchr("hello", $l),
            string:left("ab", 4), string:right("ab", 4, $.), string:centre("ab", 6), string:copies("ab", 3),
            string:words(" a  b c "), string:sub_word("a b c", 2), string:span("aabc", "ab"), string:cspan("abc", "c"),
            string:len("abc"), string:concat("ab", "cd"), string:chars($-, 5)]),
    Csv = <<"name,qty\r\nbolt,12\r\nnut,40\r\n">>,
    Rows = [string:split(R, ",") || R <- string:lexemes(Csv, [[$\r, $\n]])],
    p(csv, Rows),
    p(total, lists:sum([element(1, string:to_integer(Q)) || [_, Q] <- tl(Rows)])).

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
