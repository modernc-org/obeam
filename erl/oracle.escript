#!/usr/bin/env escript
%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% oracle.escript prints what OTP's own disassembler, beam_disasm, finds in a
%% .beam file, one line a function: "Name/Arity: op op op ...", each op the
%% name of the opcode in genop.tab. The tests of internal/beam hold obeam's
%% reader to it.
%%
%% beam_disasm does not hand back the opcodes as they are: it folds every test
%% into {test,Name,...}, and bif0/1/2 and gc_bif1/2/3 into {bif,...} and
%% {gc_bif,...} with their arguments in a list, as the compiler's own assembly
%% spells them, raise into a {bif,raise,...} of two arguments, and the float
%% arithmetic, fadd to fnegate, into {bif,...} under its own name. op/1 undoes
%% that; everything else keeps its name as the first element of its tuple, or
%% is a bare atom.

main([File]) ->
    {beam_file, _Mod, _Exp, _Attr, _CInf, Code} = beam_disasm:file(File),
    lists:foreach(
      fun({function, Name, Arity, _Entry, Is}) ->
              Ops = [atom_to_list(op(I)) || I <- Is],
              io:format("~w/~w: ~s~n", [Name, Arity, lists:join(" ", Ops)])
      end, Code);
main(_) ->
    io:format("usage: oracle.escript FILE.beam~n"),
    halt(2).

op(I) when is_tuple(I), element(1, I) =:= test -> element(2, I);
op({bif, raise, _Fail, [_, _], _Dst}) -> raise;
op({bif, Name, _Fail, _Args, _Dst}) when Name =:= fadd; Name =:= fsub; Name =:= fmul; Name =:= fdiv; Name =:= fnegate -> Name;
op({bif, _Name, _Fail, Args, _Dst}) -> list_to_atom("bif" ++ integer_to_list(length(Args)));
op({gc_bif, _Name, _Fail, _Live, Args, _Dst}) -> list_to_atom("gc_bif" ++ integer_to_list(length(Args)));
op(I) when is_tuple(I) -> element(1, I);
op(I) when is_atom(I) -> I.
