%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% exits: what a process linked to a worker that ends receives as the
%% worker's exit reason, the stacktrace shown by its first frame. Erlang logs
%% the crashes (error and throw) and the VM reports them in its own words, so
%% vm/host_test.go holds this module to the lines erl prints of it. An error
%% of a BIF and a function_clause have a first frame of the BIF or the
%% function and its arguments.
-module(exits).
-export([main/0, worker/1]).

main() ->
    process_flag(trap_exit, true),
    lists:foreach(fun(How) ->
                          Pid = spawn_link(?MODULE, worker, [How]),
                          receive {'EXIT', Pid, Reason} -> io:format("~w: ~w~n", [How, shape(Reason)]) end
                  end, [normal, exit, error, throw, badarith, badmatch, function_clause]).

worker(normal) -> ok;
worker(exit) -> exit(gone);
worker(error) -> erlang:error(oops);
worker(throw) -> throw(ball);
worker(badarith) -> 1 div id(0);
worker(badmatch) -> {a} = id({b});
worker(function_clause) -> clause(id(x)).

clause(y) -> y.

id(X) -> X.

shape({R, [{M, F, A, _} | _]}) -> {R, M, F, A};
shape(R) -> R.
