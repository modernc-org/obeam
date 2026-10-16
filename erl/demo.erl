%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% demo: what the board runs at milestone M1: the four modules a single
%% process can run, one after the other.
-module(demo).
-export([main/0]).

main() ->
    fac:main(),
    fib:main(),
    lst:main(),
    tuples:main().
