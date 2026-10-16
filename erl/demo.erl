%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% demo: what the board runs: the modules of the corpus the VM can run, one
%% after the other, Erlang's and then Elixir's, ex/, and cogs last. counter
%% waits a second for a reply that never comes.
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
    exc:main(),
    links:main(),
    sup:main(),
    flt:main(),
    fmt:main(),
    mp:main(),
    bin:main(),
    'Elixir.Hello':main(),
    'Elixir.Fac':main(),
    'Elixir.Ping':main(),
    'Elixir.Ring':main(),
    'Elixir.Enums':main(),
    'Elixir.Strings':main(),
    'Elixir.Maps':main(),
    cogs:main().
