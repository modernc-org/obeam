%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% props: what a program asks of OTP's proplists, which the board has as a
%% shim, erl/shim/proplists.erl, held here to the real one: options looked
%% up, defaulted, expanded and normalized. A map is printed as its sorted
%% list, and get_keys/1's keys sorted, their order being OTP's set's.
-module(props).
-export([main/0]).

main() ->
    Opts = [verbose, {port, 8080}, {host, "board"}, {debug, false}, {port, 9090}, {path, ["a"]}, {path, "b"}, {x, 1, 2}],
    p(get, [proplists:get_value(port, Opts), proplists:get_value(missing, Opts),
            proplists:get_value(missing, Opts, none), proplists:get_value(verbose, Opts),
            proplists:get_value(x, Opts, dflt)]),
    p(bool, [proplists:get_bool(verbose, Opts), proplists:get_bool(debug, Opts), proplists:get_bool(nothing, Opts)]),
    p(all, [proplists:get_all_values(port, Opts), proplists:append_values(path, Opts)]),
    p(lookup, [proplists:lookup(port, Opts), proplists:lookup(verbose, Opts), proplists:lookup(nope, Opts),
               proplists:lookup_all(port, Opts), proplists:is_defined(x, Opts), proplists:is_defined(y, Opts)]),
    p(delete, proplists:delete(port, Opts)),
    p(keys, lists:sort(proplists:get_keys(Opts))),
    p(forms, [proplists:compact([{a, true}, {b, 1}, c]), proplists:unfold([a, {b, 1}]),
              proplists:property({a, true}), proplists:property(b, 2)]),
    p(aliases, proplists:substitute_aliases([{colour, color}], [colour, {colour, red}, {size, 3}])),
    p(negations, proplists:substitute_negations([{no_debug, debug}], [no_debug, {no_debug, false}, {no_debug, 7}])),
    p(expand, proplists:expand([{foo, [bar, baz]}, {{quiet, true}, [{verbose, false}]}], [fie, foo, quiet, fum, foo])),
    p(normalize, proplists:normalize([colour, no_debug, quiet], [{aliases, [{colour, color}]},
                                                              {negations, [{no_debug, debug}]},
                                                              {expand, [{quiet, [{volume, 0}]}]}])),
    p(split, proplists:split([{c, 2}, {e, 1}, a, {c, 3, 4}, d, {b, 5}, b], [a, b, c])),
    p(map, lists:sort(maps:to_list(proplists:to_map(Opts)))),
    p(from_map, lists:sort(proplists:from_map(#{a => 1, b => 2}))).

p(Tag, X) -> io:format("~w: ~p~n", [Tag, X]).
