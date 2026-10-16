// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import "modernc.org/obeam/internal/beam"

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
