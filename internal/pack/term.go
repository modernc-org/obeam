// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package pack turns the modules Erlang's compiler writes into an image for the
// board: one atom table, one code stream with every operand resolved, the
// literals laid out in the board's own term format, and the tables a crash
// message and a spawn need. DESIGN.md sections 2 and 4 are the specification;
// the constants here are the one copy of the term layout, and obeam gen writes
// the VM's copy of them from here.
package pack

// The term word. The low two bits are the primary tag; 11 splits by bit 2
// into the immediates (011) and the headers and markers (111).
const (
	TagSmall = 0 // a small integer, 30 bits above the tag
	TagList  = 1 // a list cell, its arena index above the tag
	TagBoxed = 2 // a boxed term, its header's arena index above the tag
	TagImm   = 3 // 011 an immediate, 111 a header or a marker

	ImmAtom = 0x03 // 00 011: the atom's index in bits 5 and up
	ImmPid  = 0x0b // 01 011: the process's index in bits 5-12, its generation above
	ImmNil  = 0x13 // 10 011: []
	ImmRef  = 0x1b // 11 011: the reference's number in bits 5 and up
	Nil     = ImmNil

	// A header's kind, in bits 3-5; its size in longs, the header not counted,
	// or its arity, in bits 6 and up.
	HdrTuple    = 0
	HdrFloat    = 1 // one long, the 32-bit float
	HdrInt64    = 2 // two longs, low then high
	HdrFun      = 3 // code offset, arity and free count packed, then the environment
	HdrBinary   = 4 // the length in bytes, then the bytes
	HdrNonValue = 6 // size 0: what a failing BIF returns, never a term
	HdrMoved    = 7 // size 0: a list cell the collector has moved, its new place in the tail

	NonValue = HdrNonValue<<3 | 7
	Moved    = HdrMoved<<3 | 7

	SmallMin = -1 << 29
	SmallMax = 1<<29 - 1

	PidIndexBits = 8  // the process table has 256 entries
	PidGenBits   = 19 // the generation above the index
	FunHeadLongs = 2  // a fun's longs after its header and before its environment: the code offset or BIF number, then FunHead
	MaxArity     = 16 // the most arguments a function may take: what a scheduler saves of the X registers at a switch

	// A fun's kind, in FunHead.
	FunLocal  = 0 // made by make_fun3: its first long is the code offset of its body
	FunExport = 1 // fun m:f/a of a function in the image: the code offset
	FunBif    = 2 // fun m:f/a of a BIF: the BIF's number

	// JumpValue is what a BIF answers to have the handler go on at the code
	// offset it left in bifJump, with x0 and up as it set them: apply's way of
	// calling a function. Like NonValue, never a term.
	JumpValue = 1<<6 | HdrNonValue<<3 | 7

	// BifValue is what a BIF answers to have the handler call the BIF whose
	// number it left in bifJump, with the arguments it put in bargs: apply's
	// way of calling a BIF, so that no BIF calls one.
	BifValue = 2<<6 | HdrNonValue<<3 | 7

	// A register marker, in code only: an x register ends in 0111, a y
	// register in 1111, the number above.
	MarkX = 0x7
	MarkY = 0xf
)

// Small makes the term of a small integer; the caller checks the range.
func Small(v int64) uint32 { return uint32(int32(v) << 2) }

// Atom makes the term of the atom with the index i.
func Atom(i int) uint32 { return uint32(i)<<5 | ImmAtom }

// ListPtr makes the term of the list cell at arena index i.
func ListPtr(i int) uint32 { return uint32(i)<<2 | TagList }

// BoxedPtr makes the term of the boxed object whose header is at arena index i.
func BoxedPtr(i int) uint32 { return uint32(i)<<2 | TagBoxed }

// Header makes the header word of a boxed object of a kind and a size.
func Header(kind, size int) uint32 { return uint32(size)<<6 | uint32(kind)<<3 | 7 }

// XReg and YReg make the register markers of code operands.
func XReg(n int) uint32 { return uint32(n)<<4 | MarkX }
func YReg(n int) uint32 { return uint32(n)<<4 | MarkY }

// Pid makes the term of the process at an index, in a generation.
func Pid(index, gen int) uint32 { return uint32(gen)<<13 | uint32(index)<<5 | ImmPid }

// FunHead makes the second long of a fun: its arity, its free variables and
// its kind.
func FunHead(arity, free, kind int) uint32 {
	return uint32(arity) | uint32(free)<<16 | uint32(kind)<<24
}
