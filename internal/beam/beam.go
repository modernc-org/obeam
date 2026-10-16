// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package beam reads .beam files, the modules Erlang's compiler writes: the
// chunks, the atoms, the code with its operands decoded, the imports, the
// exports, the literals, the funs and the line table. It is the front of the
// obeam command, and will be the front of the packer that makes an image for
// the board.
//
// It reads what Erlang/OTP 27 writes; GenopTag names the genop.tab its opcode
// table is generated from. A file a later release wrote is read as long as it
// uses no opcode the table lacks, and refused by name where it does.
package beam

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math/big"
	"os"
	"path/filepath"
)

// A File is a .beam module, read.
type File struct {
	Name        string   // the file's name, for messages
	Module      string   // the module's name, which is atom 1
	Atoms       []string // by index; Atoms[0] is "" and stands for [] where an operand names atom 0
	Code        Code
	Imports     []MFA           // what a call_ext, bif or gc_bif operand indexes
	Exports     []FunctionEntry // the ExpT chunk
	Locals      []FunctionEntry // the LocT chunk, if there is one
	Literals    []Term          // what a literal operand indexes
	Funs        []Lambda        // the FunT chunk, what make_fun3 indexes
	Strings     []byte          // the StrT chunk, the string pool of the bit syntax
	Lines       *LineTable      // the Line chunk, or nil
	Attrs       *Term           // the Attr chunk's term, or nil
	CompileInfo *Term           // the CInf chunk's term, or nil
	Chunks      []Chunk         // every chunk, in the file's order
}

// A Chunk is one of the file's IFF chunks.
type Chunk struct {
	ID     string
	Data   []byte
	Offset int // of the chunk's header, in the file
}

// An MFA names a function of a module, as an import does.
type MFA struct {
	Module, Function string
	Arity            int
}

// String writes the MFA as Erlang writes one, m:f/a, with the atoms quoted
// where Erlang quotes them.
func (m MFA) String() string {
	return fmt.Sprintf("%s:%s/%d", atomString(m.Module), atomString(m.Function), m.Arity)
}

// A FunctionEntry is an export or a local: a function's name and arity, and
// the label it begins at.
type FunctionEntry struct {
	Name  string
	Arity int
	Label int
}

// A Lambda is an entry of the fun table: a fun's name and arity, the free
// variables counted in, the label it begins at, its index, how many free
// variables it has, and the uniq the compiler gave it.
type Lambda struct {
	Name    string
	Arity   int
	Label   int
	Index   int
	NumFree int
	OldUniq uint32
}

// Code is the Code chunk: its header and its instructions.
type Code struct {
	FormatVersion uint32 // the instruction set's version, 0
	MaxOpcode     uint32 // the highest opcode the module uses
	LabelCount    uint32 // one more than the highest label
	FunctionCount uint32 // how many functions there are, module_info/0 and /1 counted
	Instrs        []Instr
}

// An Instr is one instruction: its opcode, its operands, and where it is.
type Instr struct {
	Op     Opcode
	Args   []Arg
	Offset int // of the opcode byte, from the start of the code
}

// ArgKind is what kind of operand an Arg is.
type ArgKind uint8

// The kinds of operand. The first seven are the tags of the compact term
// encoding; the rest are its extended tag's subtags.
const (
	ArgU       ArgKind = iota // an unsigned number: an arity, a count, an index
	ArgI                      // an integer
	ArgAtom                   // an atom, by index; 0 is []
	ArgX                      // an X register
	ArgY                      // a Y register, a slot of the stack frame
	ArgF                      // a label; 0 is no label
	ArgH                      // a character
	ArgList                   // a list of operands: a select_val table, put_tuple2's elements
	ArgFR                     // a floating-point register
	ArgAlloc                  // an allocation list: pairs of a kind (0 words, 1 floats, 2 funs) and a count
	ArgLiteral                // a literal, by index into Literals
	ArgTyped                  // a register with a type: Reg, and the type's index in Val
)

var argKindNames = [...]string{"u", "i", "atom", "x", "y", "f", "h", "list", "fr", "alloc", "literal", "tr"}

func (k ArgKind) String() string {
	if int(k) < len(argKindNames) {
		return argKindNames[k]
	}
	return fmt.Sprintf("argkind%d", k)
}

// An Arg is one operand.
type Arg struct {
	Kind ArgKind
	Val  int64    // the number, index or register of every kind but ArgList and ArgAlloc
	Big  *big.Int // an integer that does not fit Val, which is then 0
	List []Arg    // ArgList's elements; ArgAlloc's kinds and counts, ArgU each, alternating
	Reg  *Arg     // ArgTyped's register
}

// A LineTable is the Line chunk, what a line instruction's operand indexes.
type LineTable struct {
	Flags  uint32
	Count  uint32     // of line instructions in the code, as the chunk says
	Items  []LineItem // by the operand; Items[0] is unused, an operand of 0 naming no location
	Fnames []string   // by LineItem.File; Fnames[0] is the module's own source, named after it
}

// A LineItem is a location: a file, by index into Fnames, and a line.
type LineItem struct {
	File int
	Line int
}

// Location returns the file and line a line operand names, if it names one.
func (t *LineTable) Location(index int64) (file string, line int, ok bool) {
	if t == nil || index <= 0 || index >= int64(len(t.Items)) {
		return "", 0, false
	}
	it := t.Items[index]
	if it.File < 0 || it.File >= len(t.Fnames) {
		return "", 0, false
	}
	return t.Fnames[it.File], it.Line, true
}

// ReadFile reads the .beam file at path.
func ReadFile(path string) (*File, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	return Read(filepath.Base(path), data)
}

// Read reads a .beam file from its bytes; name is for messages.
func Read(name string, data []byte) (*File, error) {
	f := &File{Name: name}
	if err := f.read(data); err != nil {
		return nil, fmt.Errorf("%s: %w", name, err)
	}
	return f, nil
}

func be32(b []byte) uint32 { return binary.BigEndian.Uint32(b) }

func (f *File) read(data []byte) error {
	if len(data) < 12 || string(data[:4]) != "FOR1" || string(data[8:12]) != "BEAM" {
		return errors.New("not a .beam file: no FOR1/BEAM header")
	}
	size := int(be32(data[4:]))
	if size < 4 || size+8 > len(data) {
		return fmt.Errorf("the form says %d bytes, the file has %d", size+8, len(data))
	}
	body := data[12 : 8+size]
	for off := 0; off < len(body); {
		if off+8 > len(body) {
			return fmt.Errorf("a chunk header at %d runs past the end", 12+off)
		}
		id := string(body[off : off+4])
		n := int(be32(body[off+4:]))
		if n < 0 || off+8+n > len(body) {
			return fmt.Errorf("chunk %q of %d bytes at %d runs past the end", id, n, 12+off)
		}
		f.Chunks = append(f.Chunks, Chunk{ID: id, Data: body[off+8 : off+8+n], Offset: 12 + off})
		off += 8 + (n+3)&^3
	}

	chunk := func(id string) ([]byte, bool) {
		for _, c := range f.Chunks {
			if c.ID == id {
				return c.Data, true
			}
		}
		return nil, false
	}
	if c, ok := chunk("AtU8"); ok {
		if err := f.readAtoms(c, true); err != nil {
			return fmt.Errorf("AtU8: %w", err)
		}
	} else if c, ok := chunk("Atom"); ok {
		if err := f.readAtoms(c, false); err != nil {
			return fmt.Errorf("Atom: %w", err)
		}
	} else {
		return errors.New("no atom chunk")
	}
	c, ok := chunk("Code")
	if !ok {
		return errors.New("no Code chunk")
	}
	if err := f.readCode(c); err != nil {
		return fmt.Errorf("Code: %w", err)
	}
	if c, ok := chunk("ImpT"); ok {
		if err := f.readImports(c); err != nil {
			return fmt.Errorf("ImpT: %w", err)
		}
	}
	for _, t := range []struct {
		id string
		to *[]FunctionEntry
	}{{"ExpT", &f.Exports}, {"LocT", &f.Locals}} {
		if c, ok := chunk(t.id); ok {
			es, err := f.readFunctionEntries(c)
			if err != nil {
				return fmt.Errorf("%s: %w", t.id, err)
			}
			*t.to = es
		}
	}
	if c, ok := chunk("LitT"); ok {
		if err := f.readLiterals(c); err != nil {
			return fmt.Errorf("LitT: %w", err)
		}
	}
	if c, ok := chunk("FunT"); ok {
		if err := f.readFuns(c); err != nil {
			return fmt.Errorf("FunT: %w", err)
		}
	}
	if c, ok := chunk("StrT"); ok {
		f.Strings = c
	}
	if c, ok := chunk("Line"); ok {
		if err := f.readLines(c); err != nil {
			return fmt.Errorf("Line: %w", err)
		}
	}
	for _, t := range []struct {
		id string
		to **Term
	}{{"Attr", &f.Attrs}, {"CInf", &f.CompileInfo}} {
		if c, ok := chunk(t.id); ok {
			term, err := DecodeETF(c)
			if err != nil {
				return fmt.Errorf("%s: %w", t.id, err)
			}
			*t.to = &term
		}
	}
	return nil
}

func (f *File) readAtoms(c []byte, utf8 bool) error {
	if len(c) < 4 {
		return errors.New("shorter than its count")
	}
	n := be32(c)
	if int32(n) < 0 {
		return fmt.Errorf("a count of %d: a long-atom table, which this reader does not know", int32(n))
	}
	if n == 0 {
		return errors.New("no atoms, so no module name")
	}
	f.Atoms = make([]string, 1, n+1)
	p := 4
	for i := uint32(1); i <= n; i++ {
		if p >= len(c) {
			return fmt.Errorf("atom %d: the chunk ends", i)
		}
		l := int(c[p])
		p++
		if p+l > len(c) {
			return fmt.Errorf("atom %d of %d bytes: the chunk ends", i, l)
		}
		s := c[p : p+l]
		p += l
		if utf8 {
			f.Atoms = append(f.Atoms, string(s))
		} else {
			f.Atoms = append(f.Atoms, latin1(s))
		}
	}
	f.Module = f.Atoms[1]
	return nil
}

func latin1(b []byte) string {
	r := make([]rune, len(b))
	for i, c := range b {
		r[i] = rune(c)
	}
	return string(r)
}

// atom returns the atom an operand or a table entry names; 0 is [].
func (f *File) atom(i int64) (string, error) {
	if i < 0 || i >= int64(len(f.Atoms)) {
		return "", fmt.Errorf("atom %d of %d", i, len(f.Atoms)-1)
	}
	if i == 0 {
		return "[]", nil
	}
	return f.Atoms[i], nil
}

func (f *File) readCode(c []byte) error {
	if len(c) < 4 {
		return errors.New("shorter than its header")
	}
	sub := int(be32(c))
	if sub < 16 || 4+sub > len(c) {
		return fmt.Errorf("a header of %d bytes", sub)
	}
	f.Code.FormatVersion = be32(c[4:])
	f.Code.MaxOpcode = be32(c[8:])
	f.Code.LabelCount = be32(c[12:])
	f.Code.FunctionCount = be32(c[16:])
	if f.Code.FormatVersion != 0 {
		return fmt.Errorf("instruction set version %d, not 0", f.Code.FormatVersion)
	}
	if f.Code.MaxOpcode > MaxOpcode {
		return fmt.Errorf("the module uses opcodes up to %d and this reader knows them to %d (%s)", f.Code.MaxOpcode, MaxOpcode, GenopTag)
	}
	d := &decoder{b: c[4+sub:]}
	for d.pos < len(d.b) {
		off := d.pos
		op := Opcode(d.b[d.pos])
		d.pos++
		arity, ok := op.Arity()
		if !ok {
			return fmt.Errorf("unknown opcode %d at code offset %d", op, off)
		}
		args := make([]Arg, arity)
		for i := range args {
			a, err := d.arg()
			if err != nil {
				return fmt.Errorf("%s at code offset %d, operand %d: %w", op, off, i+1, err)
			}
			args[i] = a
		}
		f.Code.Instrs = append(f.Code.Instrs, Instr{Op: op, Args: args, Offset: off})
		if op == OpIntCodeEnd {
			if d.pos != len(d.b) {
				return fmt.Errorf("%d bytes after int_code_end", len(d.b)-d.pos)
			}
			break
		}
	}
	if n := len(f.Code.Instrs); n == 0 || f.Code.Instrs[n-1].Op != OpIntCodeEnd {
		return errors.New("the code does not end with int_code_end")
	}
	return nil
}

func (f *File) readImports(c []byte) error {
	n, err := tableCount(c, 12)
	if err != nil {
		return err
	}
	f.Imports = make([]MFA, 0, n)
	for i, p := 0, 4; i < n; i, p = i+1, p+12 {
		m, err := f.atom(int64(be32(c[p:])))
		if err != nil {
			return fmt.Errorf("import %d: %w", i, err)
		}
		fn, err := f.atom(int64(be32(c[p+4:])))
		if err != nil {
			return fmt.Errorf("import %d: %w", i, err)
		}
		f.Imports = append(f.Imports, MFA{Module: m, Function: fn, Arity: int(be32(c[p+8:]))})
	}
	return nil
}

func (f *File) readFunctionEntries(c []byte) ([]FunctionEntry, error) {
	n, err := tableCount(c, 12)
	if err != nil {
		return nil, err
	}
	es := make([]FunctionEntry, 0, n)
	for i, p := 0, 4; i < n; i, p = i+1, p+12 {
		name, err := f.atom(int64(be32(c[p:])))
		if err != nil {
			return nil, fmt.Errorf("entry %d: %w", i, err)
		}
		es = append(es, FunctionEntry{Name: name, Arity: int(be32(c[p+4:])), Label: int(be32(c[p+8:]))})
	}
	return es, nil
}

func (f *File) readFuns(c []byte) error {
	n, err := tableCount(c, 24)
	if err != nil {
		return err
	}
	f.Funs = make([]Lambda, 0, n)
	for i, p := 0, 4; i < n; i, p = i+1, p+24 {
		name, err := f.atom(int64(be32(c[p:])))
		if err != nil {
			return fmt.Errorf("fun %d: %w", i, err)
		}
		f.Funs = append(f.Funs, Lambda{
			Name:    name,
			Arity:   int(be32(c[p+4:])),
			Label:   int(be32(c[p+8:])),
			Index:   int(be32(c[p+12:])),
			NumFree: int(be32(c[p+16:])),
			OldUniq: be32(c[p+20:]),
		})
	}
	return nil
}

// tableCount reads the count a table chunk begins with and checks that the
// chunk holds that many entries of size bytes.
func tableCount(c []byte, size int) (int, error) {
	if len(c) < 4 {
		return 0, errors.New("shorter than its count")
	}
	n := int(be32(c))
	if n < 0 || 4+n*size > len(c) {
		return 0, fmt.Errorf("%d entries of %d bytes in a chunk of %d", n, size, len(c))
	}
	return n, nil
}

func (f *File) readLiterals(c []byte) error {
	if len(c) < 4 {
		return errors.New("shorter than its size")
	}
	size := int(be32(c))
	zr, err := zlib.NewReader(bytes.NewReader(c[4:]))
	if err != nil {
		return err
	}
	data, err := io.ReadAll(io.LimitReader(zr, int64(size)+1))
	if err != nil {
		return err
	}
	if len(data) != size {
		return fmt.Errorf("%d bytes uncompressed, %d announced", len(data), size)
	}
	if len(data) < 4 {
		return errors.New("shorter than its count")
	}
	n := int(be32(data))
	f.Literals = make([]Term, 0, n)
	p := 4
	for i := 0; i < n; i++ {
		if p+4 > len(data) {
			return fmt.Errorf("literal %d: the table ends", i)
		}
		l := int(be32(data[p:]))
		p += 4
		if l < 0 || p+l > len(data) {
			return fmt.Errorf("literal %d of %d bytes: the table ends", i, l)
		}
		t, err := DecodeETF(data[p : p+l])
		if err != nil {
			return fmt.Errorf("literal %d: %w", i, err)
		}
		f.Literals = append(f.Literals, t)
		p += l
	}
	if p != len(data) {
		return fmt.Errorf("%d bytes after the last literal", len(data)-p)
	}
	return nil
}

func (f *File) readLines(c []byte) error {
	if len(c) < 20 {
		return errors.New("shorter than its header")
	}
	if ver := be32(c); ver != 0 {
		return fmt.Errorf("version %d, not 0", ver)
	}
	t := &LineTable{Flags: be32(c[4:]), Count: be32(c[8:])}
	numLines := int(be32(c[12:]))
	numFnames := int(be32(c[16:]))
	d := &decoder{b: c, pos: 20}
	t.Items = make([]LineItem, 1, numLines+1)
	file := 0
	for len(t.Items) <= numLines {
		a, err := d.arg()
		if err != nil {
			return fmt.Errorf("item %d: %w", len(t.Items), err)
		}
		switch a.Kind {
		case ArgAtom:
			file = int(a.Val)
		case ArgI:
			t.Items = append(t.Items, LineItem{File: file, Line: int(a.Val)})
		default:
			return fmt.Errorf("item %d: a %s operand", len(t.Items), a.Kind)
		}
	}
	t.Fnames = make([]string, 1, numFnames+1)
	t.Fnames[0] = f.Module + ".erl"
	p := d.pos
	for i := 0; i < numFnames; i++ {
		if p+2 > len(c) {
			return fmt.Errorf("file name %d: the chunk ends", i+1)
		}
		l := int(binary.BigEndian.Uint16(c[p:]))
		p += 2
		if p+l > len(c) {
			return fmt.Errorf("file name %d of %d bytes: the chunk ends", i+1, l)
		}
		t.Fnames = append(t.Fnames, string(c[p:p+l]))
		p += l
	}
	if p != len(c) {
		return fmt.Errorf("%d bytes after the file names", len(c)-p)
	}
	f.Lines = t
	return nil
}
