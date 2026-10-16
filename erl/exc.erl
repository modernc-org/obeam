%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% exc: exceptions thrown, raised and exited, and caught in every way.
-module(exc).
-export([main/0]).

safe_div(A, B) ->
    try A div B of
        Q -> {ok, Q}
    catch
        error:badarith -> {error, badarith}
    end.

classify(X) ->
    try
        check(X)
    catch
        throw:T -> {thrown, T};
        error:E -> {errored, E};
        exit:R -> {exited, R}
    end.

check(0) -> throw(zero);
check(1) -> erlang:error(one);
check(2) -> exit(two);
check(3) -> case_of(three);
check(4) -> match_of({error, 4});
check(X) -> X.

%% case_of and match_of fail for what check hands them; a function apart, so
%% that the compiler cannot see it and leave the case and the match out.
case_of(V) ->
    case V of
        four -> ok
    end.

match_of(V) -> {ok, 4} = V.

main() ->
    io:format("~w ~w~n", [safe_div(7, 2), safe_div(1, 0)]),
    io:format("~w~n", [[classify(X) || X <- [0, 1, 2, 3, 4, 5]]]),
    io:format("~w~n", [catch check(0)]),
    R = try
            check(1)
        catch
            _:_:Stk -> {caught, is_list(Stk)}
        end,
    io:format("~w~n", [R]).
