%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% fac: recursion and integer arithmetic, the smallest program there is.
-module(fac).
-export([main/0, fac/1]).

fac(0) -> 1;
fac(N) when is_integer(N), N > 0 -> N * fac(N - 1).

main() ->
    io:format("~w~n", [[fac(N) || N <- [0, 1, 5, 10, 12]]]).
