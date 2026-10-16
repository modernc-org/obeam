// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package beam

import (
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
)

// String writes the term as Erlang's ~p would, for the shapes a literal takes:
// a list of printable characters as a string, a binary of them as <<"...">>.
func (t Term) String() string {
	var b strings.Builder
	t.write(&b)
	return b.String()
}

func (t Term) write(b *strings.Builder) {
	switch t.Kind {
	case TermNil:
		b.WriteString("[]")
	case TermInt:
		b.WriteString(strconv.FormatInt(t.Int, 10))
	case TermBig:
		b.WriteString(t.Big.String())
	case TermFloat:
		b.WriteString(formatFloat(t.Float))
	case TermAtom:
		writeAtom(b, t.Atom)
	case TermList:
		if t.Tail == nil && isString(t.Elems) {
			writeString(b, t.Elems)
			return
		}
		b.WriteByte('[')
		for i, e := range t.Elems {
			if i > 0 {
				b.WriteByte(',')
			}
			e.write(b)
		}
		if t.Tail != nil {
			b.WriteByte('|')
			t.Tail.write(b)
		}
		b.WriteByte(']')
	case TermTuple:
		b.WriteByte('{')
		for i, e := range t.Elems {
			if i > 0 {
				b.WriteByte(',')
			}
			e.write(b)
		}
		b.WriteByte('}')
	case TermBinary:
		b.WriteString("<<")
		if len(t.Bytes) > 0 && isPrintable(t.Bytes) {
			b.WriteByte('"')
			for _, c := range t.Bytes {
				writeChar(b, rune(c), '"')
			}
			b.WriteByte('"')
		} else {
			for i, c := range t.Bytes {
				if i > 0 {
					b.WriteByte(',')
				}
				b.WriteString(strconv.Itoa(int(c)))
			}
		}
		b.WriteString(">>")
	case TermBitstring:
		b.WriteString("<<")
		for i, c := range t.Bytes {
			if i > 0 {
				b.WriteByte(',')
			}
			if i == len(t.Bytes)-1 {
				fmt.Fprintf(b, "%d:%d", c>>(8-t.Bits), t.Bits)
			} else {
				b.WriteString(strconv.Itoa(int(c)))
			}
		}
		b.WriteString(">>")
	case TermMap:
		b.WriteString("#{")
		for i := 0; i+1 < len(t.Elems); i += 2 {
			if i > 0 {
				b.WriteByte(',')
			}
			t.Elems[i].write(b)
			b.WriteString(" => ")
			t.Elems[i+1].write(b)
		}
		b.WriteByte('}')
	case TermExport:
		b.WriteString("fun ")
		writeAtom(b, t.Atom)
		b.WriteByte(':')
		t.Elems[0].write(b)
		b.WriteByte('/')
		t.Elems[1].write(b)
	default:
		fmt.Fprintf(b, "<term kind %d>", t.Kind)
	}
}

// formatFloat writes a float as Erlang's ~w does: the shortest digits that
// read back as the same float, plainly when the exponent is from -3 to 14,
// and as d.ddde-5 or d.ddde15 outside that, always with a digit after the
// point.
func formatFloat(f float64) string {
	if math.IsInf(f, 0) || math.IsNaN(f) {
		return strconv.FormatFloat(f, 'g', -1, 64) // no such Erlang float
	}
	s := strconv.FormatFloat(f, 'e', -1, 64) // d.ddde+XX
	mant, exp, _ := strings.Cut(s, "e")
	e, _ := strconv.Atoi(exp)
	if e > -4 && e < 15 {
		s = strconv.FormatFloat(f, 'f', -1, 64)
		if !strings.Contains(s, ".") {
			s += ".0"
		}
		return s
	}
	if !strings.Contains(mant, ".") {
		mant += ".0"
	}
	return mant + "e" + strconv.Itoa(e)
}

// erlangReserved are the words an atom spelled like one has to be quoted for.
var erlangReserved = map[string]bool{
	"after": true, "and": true, "andalso": true, "band": true, "begin": true,
	"bnot": true, "bor": true, "bsl": true, "bsr": true, "bxor": true,
	"case": true, "catch": true, "cond": true, "div": true, "else": true,
	"end": true, "fun": true, "if": true, "let": true, "maybe": true,
	"not": true, "of": true, "or": true, "orelse": true, "receive": true,
	"rem": true, "try": true, "when": true, "xor": true,
}

// atomNeedsQuotes reports whether Erlang would write the atom in quotes.
func atomNeedsQuotes(s string) bool {
	if s == "" || erlangReserved[s] {
		return true
	}
	for i, r := range s {
		switch {
		case r >= 'a' && r <= 'z':
		case i > 0 && (r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '_' || r == '@'):
		default:
			return true
		}
	}
	return false
}

func atomString(s string) string {
	var b strings.Builder
	writeAtom(&b, s)
	return b.String()
}

func writeAtom(b *strings.Builder, s string) {
	if !atomNeedsQuotes(s) {
		b.WriteString(s)
		return
	}
	b.WriteByte('\'')
	for _, r := range s {
		writeChar(b, r, '\'')
	}
	b.WriteByte('\'')
}

// writeChar writes a character inside quotes, escaped as Erlang escapes it.
func writeChar(b *strings.Builder, r rune, quote byte) {
	switch r {
	case rune(quote), '\\':
		b.WriteByte('\\')
		b.WriteRune(r)
	case '\n':
		b.WriteString(`\n`)
	case '\t':
		b.WriteString(`\t`)
	case '\r':
		b.WriteString(`\r`)
	case '\b':
		b.WriteString(`\b`)
	case '\f':
		b.WriteString(`\f`)
	case '\v':
		b.WriteString(`\v`)
	case 27:
		b.WriteString(`\e`)
	default:
		if r < 32 || r == 127 {
			fmt.Fprintf(b, `\%o`, r)
			return
		}
		b.WriteRune(r)
	}
}

func printableRune(r rune) bool {
	switch r {
	case '\n', '\t', '\r', '\b', '\f', '\v', 27:
		return true
	}
	return r >= 32 && r <= 126 || r >= 160 && r <= 255
}

func isPrintable(s []byte) bool {
	for _, c := range s {
		if !printableRune(rune(c)) {
			return false
		}
	}
	return true
}

// isString reports whether a list is one Erlang would print as a string: not
// empty, every element a printable character.
func isString(es []Term) bool {
	if len(es) == 0 {
		return false
	}
	for _, e := range es {
		if e.Kind != TermInt || !printableRune(rune(e.Int)) || e.Int > 255 {
			return false
		}
	}
	return true
}

func writeString(b *strings.Builder, es []Term) {
	b.WriteByte('"')
	for _, e := range es {
		writeChar(b, rune(e.Int), '"')
	}
	b.WriteByte('"')
}

// importOperand says which operand of an instruction indexes the import
// table, or -1.
func importOperand(op Opcode) int {
	switch op {
	case OpCallExt, OpCallExtLast, OpCallExtOnly:
		return 1
	case OpBif0:
		return 0
	case OpBif1, OpBif2:
		return 1
	case OpGcBif1, OpGcBif2, OpGcBif3:
		return 2
	}
	return -1
}

// Import returns the import an instruction calls, if it is one that calls one.
func (f *File) Import(in Instr) (MFA, bool) {
	i := importOperand(in.Op)
	if i < 0 || i >= len(in.Args) || in.Args[i].Kind != ArgU {
		return MFA{}, false
	}
	n := in.Args[i].Val
	if n < 0 || n >= int64(len(f.Imports)) {
		return MFA{}, false
	}
	return f.Imports[n], true
}

// Format writes the instruction as the compiler's own listing, erlc -S, would,
// {op,operand,...}, except that the operands are the opcode's own, as genop.tab
// has them, not the compiler's regrouping of them: a test is {is_lt,...}, not
// {test,is_lt,...}. An import is written out, {extfunc,m,f,a}, a line's
// location looked up, and a typed register written with its type's index,
// {tr,{x,0},3}.
func (f *File) Format(in Instr) string {
	var b strings.Builder
	b.WriteByte('{')
	writeAtom(&b, in.Op.String())
	if in.Op == OpLine && len(in.Args) == 1 && in.Args[0].Kind == ArgU {
		if file, line, ok := f.Lines.Location(in.Args[0].Val); ok {
			fmt.Fprintf(&b, ",[{location,%q,%d}]}", file, line)
		} else {
			b.WriteString(",[]}")
		}
		return b.String()
	}
	imp := importOperand(in.Op)
	for i, a := range in.Args {
		b.WriteByte(',')
		if i == imp {
			if m, ok := f.Import(in); ok {
				fmt.Fprintf(&b, "{extfunc,%s,%s,%d}", atomString(m.Module), atomString(m.Function), m.Arity)
				continue
			}
		}
		f.writeArg(&b, a)
	}
	b.WriteByte('}')
	return b.String()
}

func (f *File) writeArg(b *strings.Builder, a Arg) {
	num := func() string {
		if a.Big != nil {
			return a.Big.String()
		}
		return strconv.FormatInt(a.Val, 10)
	}
	switch a.Kind {
	case ArgU:
		b.WriteString(num())
	case ArgI:
		fmt.Fprintf(b, "{integer,%s}", num())
	case ArgAtom:
		if a.Val == 0 {
			b.WriteString("nil")
			return
		}
		name, err := f.atom(a.Val)
		if err != nil {
			fmt.Fprintf(b, "{atom,#%d}", a.Val)
			return
		}
		b.WriteString("{atom,")
		writeAtom(b, name)
		b.WriteByte('}')
	case ArgX:
		fmt.Fprintf(b, "{x,%d}", a.Val)
	case ArgY:
		fmt.Fprintf(b, "{y,%d}", a.Val)
	case ArgF:
		fmt.Fprintf(b, "{f,%d}", a.Val)
	case ArgH:
		fmt.Fprintf(b, "{char,%d}", a.Val)
	case ArgList:
		b.WriteString("{list,[")
		for i, e := range a.List {
			if i > 0 {
				b.WriteByte(',')
			}
			f.writeArg(b, e)
		}
		b.WriteString("]}")
	case ArgFR:
		fmt.Fprintf(b, "{fr,%d}", a.Val)
	case ArgAlloc:
		kinds := [...]string{"words", "floats", "funs"}
		b.WriteString("{alloc,[")
		for i := 0; i+1 < len(a.List); i += 2 {
			if i > 0 {
				b.WriteByte(',')
			}
			k := a.List[i].Val
			if k >= 0 && k < int64(len(kinds)) {
				fmt.Fprintf(b, "{%s,%d}", kinds[k], a.List[i+1].Val)
			} else {
				fmt.Fprintf(b, "{%d,%d}", k, a.List[i+1].Val)
			}
		}
		b.WriteString("]}")
	case ArgLiteral:
		if a.Val >= 0 && a.Val < int64(len(f.Literals)) {
			fmt.Fprintf(b, "{literal,%s}", f.Literals[a.Val])
		} else {
			fmt.Fprintf(b, "{literal,#%d}", a.Val)
		}
	case ArgTyped:
		b.WriteString("{tr,")
		f.writeArg(b, *a.Reg)
		fmt.Fprintf(b, ",%d}", a.Val)
	default:
		fmt.Fprintf(b, "<%s>", a.Kind)
	}
}

// WriteListing writes the module as erlc -S writes one, function by function,
// each instruction as Format writes it.
func (f *File) WriteListing(w io.Writer) error {
	fns, err := f.Functions()
	if err != nil {
		return err
	}
	var b strings.Builder
	fmt.Fprintf(&b, "{module, %s}.  %%%% version = %d\n\n", atomString(f.Module), f.Code.FormatVersion)
	b.WriteString("{exports, [")
	for i, e := range f.Exports {
		if i > 0 {
			b.WriteByte(',')
		}
		fmt.Fprintf(&b, "{%s,%d}", atomString(e.Name), e.Arity)
	}
	b.WriteString("]}.\n\n")
	if f.Attrs != nil {
		fmt.Fprintf(&b, "{attributes, %s}.\n\n", f.Attrs)
	}
	fmt.Fprintf(&b, "{labels, %d}.\n", f.Code.LabelCount)
	for _, fn := range fns {
		fmt.Fprintf(&b, "\n\n{function, %s, %d, %d}.\n", atomString(fn.Name), fn.Arity, fn.Entry)
		for _, in := range fn.Instrs {
			if in.Op == OpLabel {
				b.WriteString("  ")
			} else {
				b.WriteString("    ")
			}
			b.WriteString(f.Format(in))
			b.WriteString(".\n")
		}
	}
	_, err = io.WriteString(w, b.String())
	return err
}
