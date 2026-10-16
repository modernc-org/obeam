// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"fmt"

	"modernc.org/obeam/internal/beam"
)

// The VM's own opcodes, above genop.tab's. The packer writes them where the
// module's instructions cannot be run as they are.
const (
	OpHalt    beam.Opcode = 200 // at code offset 0: a continuation of 0 ends the process
	OpCallBif beam.Opcode = 201 // call_bif Arity Bif: the BIF's arguments in x0.., its result to x0
)

// vmOpcodes names the VM's own opcodes for obeam gen.
var vmOpcodes = []struct {
	name string
	op   beam.Opcode
}{
	{"halt", OpHalt},
	{"call_bif", OpCallBif},
}

// CoreOps are the instructions the PASM core, core/core.spin2, does, in the
// order of its dispatch table: the packer writes an instruction's index here,
// counted from 1, in bits 8-15 of its opcode long, which the OctoGo loop
// masks off and the core dispatches on; 0 is an instruction the core leaves
// to OctoGo. obeam gen writes the core's table from this list.
var CoreOps = []beam.Opcode{
	beam.OpMove, beam.OpSwap, beam.OpCall, beam.OpCallLast, beam.OpCallOnly, beam.OpReturn,
	beam.OpJump, beam.OpAllocate, beam.OpAllocateHeap, beam.OpDeallocate, beam.OpInitYregs,
	beam.OpTrim, beam.OpTestHeap, beam.OpGcBif2, beam.OpIsLt, beam.OpIsGe, beam.OpIsEq,
	beam.OpIsNe, beam.OpIsEqExact, beam.OpIsNeExact, beam.OpSelectVal, beam.OpIsNonemptyList,
	beam.OpIsNil, beam.OpIsList, beam.OpIsAtom, beam.OpIsInteger, beam.OpIsTuple, beam.OpTestArity,
	beam.OpIsTaggedTuple, beam.OpGetList, beam.OpGetHd, beam.OpGetTl, beam.OpPutList,
	beam.OpPutTuple2, beam.OpGetTupleElement,
}

// coreIndex answers an instruction's index in CoreOps, from 1, or 0.
func coreIndex(op beam.Opcode) uint32 {
	for i, o := range CoreOps {
		if o == op {
			return uint32(i + 1)
		}
	}
	return 0
}

// opw is the opcode long of an instruction: the opcode, and its core index
// above it.
func opw(op beam.Opcode) uint32 { return uint32(op) | coreIndex(op)<<8 }

// WellKnownAtoms are the atoms the VM names in its own code. They come first
// in every image's atom table, in this order, so that the VM's constants hold.
var WellKnownAtoms = []string{
	"false", "true", "ok", "error", "undefined",
	"badarg", "badarith", "badmatch", "case_clause", "if_clause", "function_clause",
	"try_clause", "badrecord", "undef", "badfun", "badarity", "system_limit",
	"timeout", "normal", "kill", "killed", "noproc", "nocatch", "infinity",
	"exit", "throw", "EXIT",
	"erlang", "lists", "io", "p2",
	"millisecond", "microsecond", "nanosecond", "second", "native",
	"timeout_value", "file", "line", "trap_exit", "process", "DOWN", "flush",
	"spawn_link", "link", "unlink", "process_flag", "register", "unregister",
	"whereis", "monitor", "demonitor", "raise",
	"math", "float", "trunc", "round", "sqrt", "pow", "pi", "/",
	// The BIFs apply/3 can reach by name: the functions of the table whose
	// names are atoms a program would write.
	"abs", "length", "hd", "tl", "element", "setelement", "tuple_size", "self",
	"spawn", "send", "apply", "is_process_alive", "integer_to_list",
	"list_to_integer", "atom_to_list", "min", "max", "make_ref", "display",
	"monotonic_time", "reverse", "member", "keyfind", "format", "put_chars", "nl",
	"pin_high", "pin_low", "pin_toggle", "pin_float", "pin_in", "pin_write",
	"cog", "get_ct", "clock_freq", "rnd",
	"is_atom", "is_integer", "is_number", "is_float", "is_list", "is_tuple",
	"is_boolean", "is_function", "is_pid", "is_reference", "is_binary", "is_record",
	"not", "and", "or", "xor", "band", "bor", "bxor", "bsl", "bsr", "bnot", "div", "rem",
	"+", "-", "*", "==", "/=", "=:=", "=/=", "<", ">", "=<", ">=", "++", "--",
	"badmap", "badkey", "maps", "is_map", "map_size", "is_map_key", "map_get",
	"get", "find", "is_key", "put", "update", "remove", "keys", "values",
	"to_list", "from_list", "merge", "size", "new", "all",
	"__struct__", "Elixir.Range", "first", "last", "step",
}

// A Bif is a function the VM implements itself: what an import of it resolves
// to, and the OctoGo function in package vm that is it. Its index in Bifs is
// its number in the code.
type Bif struct {
	Module, Function string
	Arity            int
	Func             string
}

// Bifs are the VM's BIFs. A new one goes at the end; the numbers are not
// stable across versions of the image, which carries no number anywhere a
// program could see.
var Bifs = []Bif{
	{"erlang", "+", 2, "bifAdd"},
	{"erlang", "-", 2, "bifSub"},
	{"erlang", "*", 2, "bifMul"},
	{"erlang", "div", 2, "bifDiv"},
	{"erlang", "rem", 2, "bifRem"},
	{"erlang", "-", 1, "bifNeg"},
	{"erlang", "+", 1, "bifPlus"},
	{"erlang", "abs", 1, "bifAbs"},
	{"erlang", "band", 2, "bifBand"},
	{"erlang", "bor", 2, "bifBor"},
	{"erlang", "bxor", 2, "bifBxor"},
	{"erlang", "bsl", 2, "bifBsl"},
	{"erlang", "bsr", 2, "bifBsr"},
	{"erlang", "bnot", 1, "bifBnot"},
	{"erlang", "==", 2, "bifEq"},
	{"erlang", "/=", 2, "bifNe"},
	{"erlang", "=:=", 2, "bifEqExact"},
	{"erlang", "=/=", 2, "bifNeExact"},
	{"erlang", "<", 2, "bifLt"},
	{"erlang", ">", 2, "bifGt"},
	{"erlang", "=<", 2, "bifLe"},
	{"erlang", ">=", 2, "bifGe"},
	{"erlang", "not", 1, "bifNot"},
	{"erlang", "and", 2, "bifAnd"},
	{"erlang", "or", 2, "bifOr"},
	{"erlang", "xor", 2, "bifXor"},
	{"erlang", "length", 1, "bifLength"},
	{"erlang", "hd", 1, "bifHd"},
	{"erlang", "tl", 1, "bifTl"},
	{"erlang", "element", 2, "bifElement"},
	{"erlang", "setelement", 3, "bifSetelement"},
	{"erlang", "tuple_size", 1, "bifTupleSize"},
	{"erlang", "is_atom", 1, "bifIsAtom"},
	{"erlang", "is_integer", 1, "bifIsInteger"},
	{"erlang", "is_number", 1, "bifIsNumber"},
	{"erlang", "is_float", 1, "bifIsFloat"},
	{"erlang", "is_list", 1, "bifIsList"},
	{"erlang", "is_tuple", 1, "bifIsTuple"},
	{"erlang", "is_boolean", 1, "bifIsBoolean"},
	{"erlang", "is_function", 1, "bifIsFunction1"},
	{"erlang", "is_function", 2, "bifIsFunction2"},
	{"erlang", "is_pid", 1, "bifIsPid"},
	{"erlang", "is_reference", 1, "bifIsReference"},
	{"erlang", "is_binary", 1, "bifIsBinary"},
	{"erlang", "is_record", 3, "bifIsRecord3"},
	{"erlang", "integer_to_list", 1, "bifIntegerToList"},
	{"erlang", "list_to_integer", 1, "bifListToInteger"},
	{"erlang", "atom_to_list", 1, "bifAtomToList"},
	{"erlang", "++", 2, "bifAppend"},
	{"erlang", "--", 2, "bifSubtract"},
	{"erlang", "min", 2, "bifMin"},
	{"erlang", "max", 2, "bifMax"},
	{"erlang", "self", 0, "bifSelf"},
	{"erlang", "spawn", 1, "bifSpawn1"},
	{"erlang", "spawn", 3, "bifSpawn3"},
	{"erlang", "send", 2, "bifSend"},
	{"erlang", "apply", 2, "bifApply2"},
	{"erlang", "apply", 3, "bifApply3"},
	{"erlang", "is_process_alive", 1, "bifIsProcessAlive"},
	{"erlang", "raise", 3, "bifRaise3"},
	{"erlang", "spawn_link", 1, "bifSpawnLink1"},
	{"erlang", "spawn_link", 3, "bifSpawnLink3"},
	{"erlang", "link", 1, "bifLink"},
	{"erlang", "unlink", 1, "bifUnlink"},
	{"erlang", "exit", 2, "bifExit2"},
	{"erlang", "process_flag", 2, "bifProcessFlag"},
	{"erlang", "register", 2, "bifRegister"},
	{"erlang", "unregister", 1, "bifUnregister"},
	{"erlang", "whereis", 1, "bifWhereis"},
	{"erlang", "monitor", 2, "bifMonitor2"},
	{"erlang", "demonitor", 1, "bifDemonitor1"},
	{"erlang", "demonitor", 2, "bifDemonitor2"},
	{"erlang", "/", 2, "bifFdiv"},
	{"erlang", "byte_size", 1, "bifByteSize"},
	{"erlang", "integer_to_binary", 1, "bifIntegerToBinary"},
	{"erlang", "atom_to_binary", 1, "bifAtomToBinary"},
	{"erlang", "atom_to_binary", 2, "bifAtomToBinary"},
	{"erlang", "binary_to_list", 1, "bifBinaryToList"},
	{"erlang", "list_to_binary", 1, "bifIolistToBinary"},
	{"erlang", "iolist_to_binary", 1, "bifIolistToBinary"},
	{"Elixir.IO", "puts", 1, "bifExPuts"},
	{"Elixir.IO", "inspect", 1, "bifExInspect"},
	{"Elixir.Kernel", "inspect", 1, "bifExKernelInspect"},
	{"Elixir.String.Chars", "to_string", 1, "bifExToString"},
	{"erlang", "float", 1, "bifFloat"},
	{"erlang", "trunc", 1, "bifTrunc"},
	{"erlang", "round", 1, "bifRound"},
	{"math", "sqrt", 1, "bifMathSqrt"},
	{"math", "pow", 2, "bifMathPow"},
	{"math", "pi", 0, "bifMathPi"},
	{"erlang", "make_ref", 0, "bifMakeRef"},
	{"erlang", "error", 1, "bifError1"},
	{"erlang", "error", 2, "bifError2"},
	{"erlang", "exit", 1, "bifExit1"},
	{"erlang", "throw", 1, "bifThrow"},
	{"erlang", "display", 1, "bifDisplay"},
	{"erlang", "monotonic_time", 0, "bifMonotonicTime0"},
	{"erlang", "monotonic_time", 1, "bifMonotonicTime1"},
	{"lists", "reverse", 1, "bifListsReverse1"},
	{"lists", "reverse", 2, "bifListsReverse2"},
	{"lists", "member", 2, "bifListsMember"},
	{"lists", "keyfind", 3, "bifListsKeyfind"},
	{"io", "format", 1, "bifIoFormat1"},
	{"io", "format", 2, "bifIoFormat2"},
	{"io", "put_chars", 1, "bifIoPutChars"},
	{"io", "nl", 0, "bifIoNl"},
	{"p2", "pin_high", 1, "bifP2PinHigh"},
	{"p2", "pin_low", 1, "bifP2PinLow"},
	{"p2", "pin_toggle", 1, "bifP2PinToggle"},
	{"p2", "pin_float", 1, "bifP2PinFloat"},
	{"p2", "pin_in", 1, "bifP2PinIn"},
	{"p2", "pin_write", 2, "bifP2PinWrite"},
	{"p2", "cog", 0, "bifP2Cog"},
	{"p2", "get_ct", 0, "bifP2GetCt"},
	{"p2", "clock_freq", 0, "bifP2ClockFreq"},
	{"p2", "rnd", 0, "bifP2Rnd"},
	{"erlang", "is_map", 1, "bifIsMap"},
	{"erlang", "map_size", 1, "bifMapSize"},
	{"erlang", "is_map_key", 2, "bifIsMapKey"},
	{"erlang", "map_get", 2, "bifMapGet"},
	{"maps", "get", 2, "bifMapGet"},
	{"maps", "get", 3, "bifMapsGet3"},
	{"maps", "find", 2, "bifMapsFind"},
	{"maps", "is_key", 2, "bifIsMapKey"},
	{"maps", "put", 3, "bifMapsPut"},
	{"maps", "update", 3, "bifMapsUpdate"},
	{"maps", "remove", 2, "bifMapsRemove"},
	{"maps", "keys", 1, "bifMapsKeys"},
	{"maps", "values", 1, "bifMapsValues"},
	{"maps", "to_list", 1, "bifMapsToList"},
	{"maps", "from_list", 1, "bifMapsFromList"},
	{"maps", "merge", 2, "bifMapsMerge"},
	{"maps", "size", 1, "bifMapSize"},
	{"maps", "new", 0, "bifMapsNew"},
}

// bifIndex answers the number of a BIF, if there is one.
func bifIndex(m beam.MFA) (int, bool) {
	for i, b := range Bifs {
		if b.Module == m.Module && b.Function == m.Function && b.Arity == m.Arity {
			return i, true
		}
	}
	return 0, false
}

// TableID is a fingerprint of what an image and the VM must agree on: the
// well-known atoms, which the image numbers first, the BIFs, which a call in
// the image names by number, and the core's instructions, which an opcode
// long names by index. obeam gen writes it into the VM and obeam
// pack into the image, and the board program refuses an image whose
// fingerprint is not the VM's, which is an image packed before the tables
// changed.
func TableID() uint32 {
	h := uint32(2166136261)
	add := func(s string) {
		for i := 0; i < len(s); i++ {
			h ^= uint32(s[i])
			h *= 16777619
		}
		h ^= '\n'
		h *= 16777619
	}
	for _, a := range WellKnownAtoms {
		add(a)
	}
	for _, b := range Bifs {
		add(fmt.Sprintf("%s:%s/%d", b.Module, b.Function, b.Arity))
	}
	for _, o := range CoreOps {
		add(o.String())
	}
	return h
}
