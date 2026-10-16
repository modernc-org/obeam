%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% fmt: io:format's directives with their widths, precisions and padding.
-module(fmt).
-export([main/0]).

main() ->
    io:format("~10w|~-10s|~.16B|~5c|~p|~10.3f|~-6w|~n", [42, "ab", 255, $x, "str", 2.5, abc]),
    io:format("~.3s|~*w|~-*w|~.2f|~e|~g|~8.3e|~n", ["abcdef", 6, 7, 6, 8, 3.14159, 10.0, 0.5, 2.0]),
    io:format("~w ~p ~w ~p~n", [<<"abc">>, <<"abc">>, "hi", "hi"]),
    io:format("~s ~s ~i~w~n", [abc, <<"bin">>, skipped, kept]),
    io:format("~.16b ~.2B ~10.4.0f|~-8.3.*s|~n", [255, 5, 3.14159, $_, "abcdef"]),
    io:format("~~ ~c ~3n", [$z]),
    io:format("~p ~p ~w~n", [[1, 2, 3], {a, "b", [c]}, {a, "b", [c]}]),
    io:format("~w ~w ~w~n", [-7, 1 bsl 40, -(1 bsl 40)]),
    io:format("~.1f ~.2e ~g ~g~n", [0.25, 1234.5, 12345.0, 0.05]).
