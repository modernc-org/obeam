%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% gen_server: OTP's generic server, in Erlang over the VM's processes, for a
%% program packed for the board, which takes what it calls of this by reach.
%% Never on erl's path, where it would hide OTP's own.
%%
%% What a callback module meets is OTP's: start and start_link, named
%% {local, Name} or not, return when init/1 has; call, with OTP's exit
%% reasons for a timeout, a server that is not there and one that dies;
%% cast, reply and stop; a timeout or {continue, C} after a callback's
%% result; handle_info/2 and terminate/2 called only when the module exports
%% them; a throw from a callback taken as its result, and a crash in one
%% calling terminate/2 before the server ends with it. Not here: the sys and
%% proc_lib protocols, hibernation (which is waiting), the start options,
%% {global, _} and {via, _, _} names, and the logging of a crash, which the
%% VM's own report of a crashed process stands for.
-module(gen_server).
-export([start/3, start/4, start_link/3, start_link/4, call/2, call/3, cast/2,
         reply/2, stop/1, stop/3]).

start(Mod, Args, Opts) -> start_it(nolink, nameless, Mod, Args, Opts).
start(Name, Mod, Args, Opts) -> start_it(nolink, Name, Mod, Args, Opts).
start_link(Mod, Args, Opts) -> start_it(link, nameless, Mod, Args, Opts).
start_link(Name, Mod, Args, Opts) -> start_it(link, Name, Mod, Args, Opts).

%% The new process begins in a fun rather than at a function named by atoms,
%% which the packer, taking of a library what is reached, would not see.
start_it(Link, Name, Mod, Args, _Opts) ->
    Starter = self(),
    Init = fun() -> init_it(Starter, Name, Mod, Args, Link) end,
    Pid = case Link of
              link -> spawn_link(Init);
              nolink -> spawn(Init)
          end,
    Mref = erlang:monitor(process, Pid),
    receive
        {'$gen_ack', Pid, Return} ->
            erlang:demonitor(Mref),
            flush_down(Mref),
            Return;
        {'DOWN', Mref, process, Pid, Reason} ->
            {error, Reason}
    end.

%% init_it is the server's beginning: it takes its name, calls init/1 and
%% tells the starter what came of it.
init_it(Starter, Name, Mod, Args, Link) ->
    Parent = case Link of
                 link -> Starter;
                 nolink -> self()
             end,
    case register_name(Name) of
        {false, Pid} ->
            ack(Starter, {error, {already_started, Pid}});
        true ->
            try Mod:init(Args) of
                Result -> init_result(Result, Starter, Parent, Mod)
            catch
                throw:Result -> init_result(Result, Starter, Parent, Mod);
                Class:Reason:Stack ->
                    ack(Starter, {error, terminate_reason(Class, Reason, Stack)}),
                    erlang:raise(Class, Reason, Stack)
            end
    end.

init_result({ok, State}, Starter, Parent, Mod) ->
    ack(Starter, {ok, self()}),
    loop(Parent, Mod, State, infinity);
init_result({ok, State, Timeout}, Starter, Parent, Mod) ->
    ack(Starter, {ok, self()}),
    loop(Parent, Mod, State, Timeout);
init_result({stop, Reason}, Starter, _, _) ->
    ack(Starter, {error, Reason}),
    exit(Reason);
init_result(ignore, Starter, _, _) ->
    ack(Starter, ignore),
    exit(normal);
init_result(Other, Starter, _, _) ->
    ack(Starter, {error, {bad_return_value, Other}}),
    exit({bad_return_value, Other}).

ack(Starter, Return) -> Starter ! {'$gen_ack', self(), Return}.

register_name(nameless) -> true;
register_name({local, Name}) ->
    try register(Name, self()) of
        true -> true
    catch
        error:badarg -> {false, whereis(Name)}
    end.

%% loop waits for what comes, or for the timeout the last callback asked for.
loop(Parent, Mod, State, {continue, Continue}) ->
    dispatch(Parent, Mod, State, handle_continue, [Continue, State], noreply);
loop(Parent, Mod, State, hibernate) ->
    loop(Parent, Mod, State, infinity);
loop(Parent, Mod, State, Timeout) ->
    receive
        Msg -> message(Msg, Parent, Mod, State)
    after Timeout ->
        message(timeout, Parent, Mod, State)
    end.

message({'$gen_call', From, Request}, Parent, Mod, State) ->
    dispatch(Parent, Mod, State, handle_call, [Request, From, State], {call, From});
message({'$gen_cast', Msg}, Parent, Mod, State) ->
    dispatch(Parent, Mod, State, handle_cast, [Msg, State], noreply);
message({'$gen_stop', Reason}, _, Mod, State) ->
    terminate(Reason, Mod, State);
message({'EXIT', Parent, Reason}, Parent, Mod, State) when Parent =/= self() ->
    terminate(Reason, Mod, State);
message(Info, Parent, Mod, State) ->
    case erlang:function_exported(Mod, handle_info, 2) of
        true -> dispatch(Parent, Mod, State, handle_info, [Info, State], noreply);
        false -> loop(Parent, Mod, State, infinity)
    end.

%% dispatch calls a callback and does what its result says; a crash in it
%% calls terminate/2 and ends the server with the crash.
dispatch(Parent, Mod, State, Fun, Args, Kind) ->
    try apply(Mod, Fun, Args) of
        Result -> result(Result, Kind, Parent, Mod, State)
    catch
        throw:Result -> result(Result, Kind, Parent, Mod, State);
        Class:Reason:Stack ->
            call_terminate(terminate_reason(Class, Reason, Stack), Mod, State),
            erlang:raise(Class, Reason, Stack)
    end.

result({reply, Reply, NewState}, {call, From}, Parent, Mod, _) ->
    reply(From, Reply),
    loop(Parent, Mod, NewState, infinity);
result({reply, Reply, NewState, Timeout}, {call, From}, Parent, Mod, _) ->
    reply(From, Reply),
    loop(Parent, Mod, NewState, Timeout);
result({noreply, NewState}, _, Parent, Mod, _) ->
    loop(Parent, Mod, NewState, infinity);
result({noreply, NewState, Timeout}, _, Parent, Mod, _) ->
    loop(Parent, Mod, NewState, Timeout);
result({stop, Reason, Reply, NewState}, {call, From}, _, Mod, _) ->
    call_terminate(Reason, Mod, NewState),
    reply(From, Reply),
    exit(Reason);
result({stop, Reason, NewState}, _, _, Mod, _) ->
    terminate(Reason, Mod, NewState);
result(Other, _, _, Mod, State) ->
    terminate({bad_return_value, Other}, Mod, State).

terminate(Reason, Mod, State) ->
    call_terminate(Reason, Mod, State),
    exit(Reason).

call_terminate(Reason, Mod, State) ->
    case erlang:function_exported(Mod, terminate, 2) of
        true -> Mod:terminate(Reason, State);
        false -> ok
    end.

terminate_reason(error, Reason, Stack) -> {Reason, Stack};
terminate_reason(exit, Reason, _) -> Reason;
terminate_reason(throw, Reason, Stack) -> {{nocatch, Reason}, Stack}.

call(Server, Request) -> do_call(Server, Request, 5000, [Server, Request]).

call(Server, Request, Timeout) -> do_call(Server, Request, Timeout, [Server, Request, Timeout]).

do_call(Server, Request, Timeout, Args) ->
    Pid = case where(Server) of
              undefined -> exit({noproc, {gen_server, call, Args}});
              P when P =:= self() -> exit({calling_self, {gen_server, call, Args}});
              P -> P
          end,
    Mref = erlang:monitor(process, Pid),
    Pid ! {'$gen_call', {self(), Mref}, Request},
    receive
        {Mref, Reply} ->
            erlang:demonitor(Mref),
            flush_down(Mref),
            Reply;
        {'DOWN', Mref, _, _, Reason} ->
            exit({Reason, {gen_server, call, Args}})
    after Timeout ->
        erlang:demonitor(Mref),
        flush_down(Mref),
        exit({timeout, {gen_server, call, Args}})
    end.

cast(Server, Msg) ->
    case where(Server) of
        undefined -> ok;
        Pid -> Pid ! {'$gen_cast', Msg}, ok
    end.

reply({Pid, Tag}, Reply) ->
    Pid ! {Tag, Reply},
    ok.

stop(Server) -> stop(Server, normal, infinity).

stop(Server, Reason, Timeout) ->
    Pid = case where(Server) of
              undefined -> exit(noproc);
              P -> P
          end,
    Mref = erlang:monitor(process, Pid),
    Pid ! {'$gen_stop', Reason},
    receive
        {'DOWN', Mref, _, _, Reason} -> ok;
        {'DOWN', Mref, _, _, Other} -> exit(Other)
    after Timeout ->
        erlang:demonitor(Mref),
        flush_down(Mref),
        exit(timeout)
    end.

where(Pid) when is_pid(Pid) -> Pid;
where(Name) when is_atom(Name) -> whereis(Name);
where({local, Name}) -> whereis(Name);
where(_) -> undefined.

%% flush_down takes a monitor's 'DOWN' out of the mailbox if it came before
%% the monitor ended: the VM's demonitor/2 has no flush.
flush_down(Mref) ->
    receive {'DOWN', Mref, _, _, _} -> ok after 0 -> ok end.
