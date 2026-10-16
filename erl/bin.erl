%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% bin: binary matching: segments of integers of any size and endianness,
%% signed and not, binaries of a size, given or taken from an earlier
%% segment, the rest, UTF-8, literal prefixes, skipping, a parser of numbers
%% that loops over a match context, and a match that fails over to the next
%% clause.
-module(bin).
-export([main/0]).

main() ->
    <<A:8, B:16/little, Rest/binary>> = id(<<1, 2, 3, 4, 5>>),
    io:format("~p ~p ~p~n", [A, B, Rest]),
    <<S:16/signed, U:12, V:4, W:32/little-signed>> = id(<<255, 254, 171, 205, 255, 255, 255, 255>>),
    io:format("~p ~p ~p ~p~n", [S, U, V, W]),
    io:format("~p~n", [parse(id(<<"12,34,5">>), 0, [])]),
    io:format("~w~n", [utf(id(<<"a", 233/utf8, 9731/utf8, "z">>), [])]),
    io:format("~p~n", [[method(R) || R <- [<<"GET /index">>, <<"POST /form">>, <<"PUT x">>]]]),
    io:format("~p~n", [tlv(id(<<1, 3, "abc", 2, 0, 9, 2, "hi">>))]),
    <<_:2/binary, Mid:3/binary, _/binary>> = id(<<"0123456789">>),
    io:format("~p~n", [Mid]),
    <<X:32>> = id(<<16#DEADBEEF:32>>),
    io:format("~p~n", [X]),
    io:format("~p ~p~n", [words(id(<<"one two  three">>), <<>>, []), byte_size(id(<<"four">>))]),
    io:format("~p~n", [[first(Bin) || Bin <- [<<>>, <<7>>, <<1, 2>>]]]),
    io:format("~p~n", [sum16(id(<<0, 1, 0, 2, 1, 0>>), 0)]).

id(X) -> X.

parse(<<C, R/binary>>, N, Acc) when C >= $0, C =< $9 -> parse(R, N * 10 + C - $0, Acc);
parse(<<$,, R/binary>>, N, Acc) -> parse(R, 0, [N | Acc]);
parse(<<>>, N, Acc) -> lists:reverse([N | Acc]).

utf(<<C/utf8, R/binary>>, Acc) -> utf(R, [C | Acc]);
utf(<<>>, Acc) -> lists:reverse(Acc).

method(<<"GET ", Path/binary>>) -> {get, Path};
method(<<"POST ", Path/binary>>) -> {post, Path};
method(Other) -> {other, Other}.

tlv(<<T, L, V:L/binary, R/binary>>) -> [{T, V} | tlv(R)];
tlv(<<>>) -> [].

words(<<$\s, R/binary>>, <<>>, Acc) -> words(R, <<>>, Acc);
words(<<$\s, R/binary>>, W, Acc) -> words(R, <<>>, [W | Acc]);
words(<<C, R/binary>>, W, Acc) -> words(R, <<W/binary, C>>, Acc);
words(<<>>, <<>>, Acc) -> lists:reverse(Acc);
words(<<>>, W, Acc) -> lists:reverse([W | Acc]).

first(<<B, _/binary>>) -> {byte, B};
first(<<>>) -> empty.

sum16(<<N:16, R/binary>>, Acc) -> sum16(R, Acc + N);
sum16(<<>>, Acc) -> Acc.
