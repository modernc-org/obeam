%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% erls: the functions of OTP's erlang module that the board has as a shim,
%% erl/shim/erlang.erl, held here to the real BIFs: conversions in a base,
%% tuples to lists, sizes, time units, spawn_monitor and the answers of a
%% board that is no node.
-module(erls).
-export([main/0, work/1]).

main() ->
    p(tuple_to_list, [tuple_to_list({}), tuple_to_list({a, {b}, "c"}), err(fun() -> tuple_to_list(id(x)) end)]),
    p(integer_to_list, [integer_to_list(255, 16), integer_to_list(-255, 2), integer_to_list(35, 36),
                        integer_to_list(0, 8), integer_to_binary(4095, 16), err(fun() -> integer_to_list(1, id(1)) end)]),
    p(list_to_integer, [list_to_integer("ff", 16), list_to_integer("-1010", 2), list_to_integer("+Z", 36),
                        binary_to_integer(<<"-42">>), binary_to_integer(<<"7f">>, 16),
                        err(fun() -> list_to_integer("12", id(2)) end), err(fun() -> binary_to_integer(id(<<"1.0">>)) end)]),
    p(binary_to_list, [binary_to_list(<<1, 2, 3, 4>>, 2, 3), err(fun() -> binary_to_list(<<1>>, 1, id(2)) end)]),
    p(iolist_size, [iolist_size([1, <<2, 3>>, [4, [5]] | <<6>>]), iolist_size(<<"abc">>), err(fun() -> iolist_size(id([256])) end)]),
    p(time_units, [erlang:convert_time_unit(1500, millisecond, second), erlang:convert_time_unit(-1, millisecond, second),
                   erlang:convert_time_unit(3, second, microsecond), erlang:convert_time_unit(1, native, nanosecond)]),
    p(node, [is_alive(), nodes(), erlang:send(self(), sent, []), receive M -> M end, erlang:yield(), garbage_collect()]),
    p(error3, err(fun() -> error(boom, [x], [{error_info, #{}}]) end)),
    {Pid1, Ref1} = spawn_monitor(fun() -> exit(at_once) end),
    p(spawn_monitor, receive {'DOWN', Ref1, process, Pid1, Why1} -> Why1 end),
    {Pid2, Ref2} = spawn_monitor(?MODULE, work, [21]),
    p(spawn_monitor3, receive {'DOWN', Ref2, process, Pid2, Why2} -> Why2 end),
    p(spawn_monitor_bad, err(fun() -> spawn_monitor(id(notafun)) end)).

work(N) -> exit({done, N * 2}).

id(X) -> X.

err(F) ->
    try F() catch C:R -> {C, R} end.

p(Tag, X) -> io:format("~w: ~w~n", [Tag, X]).
