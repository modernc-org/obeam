%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% stacks: the stacktraces of exceptions, as try ... catch C:R:S binds them,
%% with the frames of this module and of the BIFs: the first frame a failing
%% BIF or operator makes of itself and its arguments, a function_clause's of
%% the function and its arguments, an undef's of the function that is not
%% there, none for error, exit and throw, and the stacktrace a raise is
%% given. The frames of other modules, erl's -eval's and lists' (OTP's in
%% erl, a shim on the board), are left out.
-module(stacks).
-export([main/0]).

main() ->
    lists:foreach(fun({Name, F}) -> show(Name, F) end,
                  [{divz, fun divz/0}, {plus, fun plus/0}, {elem, fun elem/0}, {clause, fun clause/0},
                   {deep_clause, fun deep_clause/0}, {atl, fun atl/0}, {hd, fun hd_/0},
                   {len, fun len/0}, {err, fun err/0}, {ex, fun ex/0}, {thr, fun thr/0},
                   {mtch, fun mtch/0}, {apply_undef, fun apply_undef/0}, {apply3_undef, fun apply3_undef/0},
                   {reraise, fun reraise/0}, {raise_named, fun raise_named/0}]).

show(Name, F) ->
    try F() of
        V -> io:format("~w: ~w~n", [Name, V])
    catch
        C:R:S -> io:format("~w: ~w ~w~n  ~w~n", [Name, C, R, [Fr || Fr = {M, _, _, _} <- S, lists:member(M, [?MODULE, erlang, nomod])]])
    end.

divz() -> 1 div id(0).
plus() -> id(a) + 1.
elem() -> element(5, id({})).
clause() -> c(id(x), 2).
deep_clause() -> [c(id(x), 3)].
atl() -> atom_to_list(id(1)).
hd_() -> hd(id([])).
len() -> length(id(x)).
err() -> erlang:error(oops).
ex() -> exit(gone).
thr() -> throw(ball).
mtch() -> {a} = id({b}).
apply_undef() -> (id(nomod)):f(1).
apply3_undef() -> [apply(id(nomod), f, [2])].
reraise() -> try 1 div id(0) catch C:R:S -> erlang:raise(C, R, S) end.
raise_named() -> try 1 div id(0) catch C:R:S -> (id(erlang)):raise(C, R, S) end.

c(y, _) -> y.

id(X) -> X.
