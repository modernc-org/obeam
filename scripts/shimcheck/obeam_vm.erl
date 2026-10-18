%% Copyright 2026 The obeam Authors. All rights reserved.
%% Use of this source code is governed by a BSD-style
%% license that can be found in the LICENSE file.

%% obeam_vm: what the VM's erlang:'$float'/2 does, in OTP's terms, for the
%% erlang shim under erl, where shimcheck.sh points the shim's calls of it
%% here: the float of 0.D times 10^K.
-module(obeam_vm).
-export([float/2]).

float([], _) -> 0.0;
float(Ds, K) -> list_to_float("0." ++ Ds ++ "e" ++ integer_to_list(K)).
