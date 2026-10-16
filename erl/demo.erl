%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% demo: what the board runs: the modules of the corpus the VM can run, one
%% after the other. counter waits a second for a reply that never comes.
-module(demo).
-export([main/0]).

main() ->
    fac:main(),
    fib:main(),
    lst:main(),
    tuples:main(),
    funs:main(),
    pingpong:main(),
    ring:main(),
    sieve:main(),
    counter:main(),
    cogs:main().
