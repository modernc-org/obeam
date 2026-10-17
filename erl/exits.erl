%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% exits: what a process linked to a worker that ends receives as the
%% worker's exit reason, the stacktrace shown by its first frame. Erlang logs
%% the crashes (error and throw) and the VM reports them in its own words, so
%% vm/host_test.go holds this module to the lines erl prints of it. Not here
%% yet: an error of a BIF and a function_clause, whose first frame Erlang
%% makes of the BIF or the function and its arguments, where the VM's is the
%% caller's.
-module(exits).
-export([main/0, worker/1]).

main() ->
    process_flag(trap_exit, true),
    lists:foreach(fun(How) ->
                          Pid = spawn_link(?MODULE, worker, [How]),
                          receive {'EXIT', Pid, Reason} -> io:format("~w: ~w~n", [How, shape(Reason)]) end
                  end, [normal, exit, error, throw, badmatch]).

worker(normal) -> ok;
worker(exit) -> exit(gone);
worker(error) -> erlang:error(oops);
worker(throw) -> throw(ball);
worker(badmatch) -> {a} = id({b}).

id(X) -> X.

shape({R, [{M, F, A, _} | _]}) -> {R, M, F, A};
shape(R) -> R.
