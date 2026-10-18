%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% halts: erlang:halt/0 called by a process that is not the first, which
%% waits for ever: what was written before it is all there is.
-module(halts).
-export([main/0]).

main() ->
    p(errors, [err(fun() -> halt(id(-1)) end), err(fun() -> halt(id(1.5)) end), err(fun() -> halt(0, id(x)) end)]),
    spawn(fun() ->
                  io:format("halting~n"),
                  halt()
          end),
    receive
    after infinity -> ok
    end.

id(X) -> X.

err(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
