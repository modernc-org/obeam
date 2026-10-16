// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"errors"
	"fmt"
	"math"
	"sort"
	"strconv"
	"strings"

	"modernc.org/obeam/internal/beam"
)

// An Image is what the board runs: DESIGN.md section 4, in memory. WriteOgo
// writes it as the OctoGo source the board program compiles in, and the host
// tests load it as it is.
type Image struct {
	Entry    uint32   // the code offset of the entry function
	Atoms    []string // by index; WellKnownAtoms first
	Code     []uint32 // the instruction stream; Code[0] is halt
	Literals []uint32 // the literal heap, the arena's first longs
	Funcs    []uint32 // quads, by code offset: offset, module atom, function atom, arity with bit 8 set for an export
	Funs     []uint32 // triples, by make_fun3's index: code offset, arity, free variables
	Lines    []uint32 // triples, by code offset: offset, file index, line
	Files    []string // what Lines index
	Modules  []string // the modules packed, in order
	Dropped  int      // functions left out as unreachable
	EntryMFA string   // for messages
}

// Options say what to pack.
type Options struct {
	Entry string // module:function/arity; the first module's main/0 by default
	Lines bool   // keep the line table
}

type fnKey struct {
	module, name string
	arity        int
}

func (k fnKey) String() string { return fmt.Sprintf("%s:%s/%d", k.module, k.name, k.arity) }

type function struct {
	key    fnKey
	file   *beam.File
	fn     beam.Function
	export bool
	offset uint32 // once laid out
	index  int    // in files' order, for a stable layout
}

type packer struct {
	img       *Image
	opts      Options
	files     []*beam.File
	atoms     map[string]int
	fileIdx   map[string]int
	funcs     map[fnKey]*function
	owners    map[*beam.File]map[int]*function // label -> function
	literals  map[*beam.File][]uint32          // the laid-out term of each literal of a module
	funs      map[*beam.File]map[int]int       // FunT index -> Funs index
	labels    map[*beam.File]map[int]uint32    // label -> code offset
	fixups    []fixup
	funFixups []funFixup
	errs      []string
}

type funFixup struct {
	at    int // in Funs
	file  *beam.File
	label int
}

type fixup struct {
	at    int
	file  *beam.File
	label int
}

// Pack packs the modules of the files into one image.
func Pack(paths []string, opts Options) (*Image, error) {
	if len(paths) == 0 {
		return nil, errors.New("no module to pack")
	}
	p := &packer{
		img:      &Image{},
		opts:     opts,
		atoms:    map[string]int{},
		fileIdx:  map[string]int{},
		funcs:    map[fnKey]*function{},
		owners:   map[*beam.File]map[int]*function{},
		literals: map[*beam.File][]uint32{},
		funs:     map[*beam.File]map[int]int{},
		labels:   map[*beam.File]map[int]uint32{},
	}
	for _, name := range WellKnownAtoms {
		p.atom(name)
	}
	for _, path := range paths {
		f, err := beam.ReadFile(path)
		if err != nil {
			return nil, err
		}
		for _, g := range p.files {
			if g.Module == f.Module {
				return nil, fmt.Errorf("%s: module %s twice", path, f.Module)
			}
		}
		p.files = append(p.files, f)
		p.img.Modules = append(p.img.Modules, f.Module)
	}
	if err := p.collect(); err != nil {
		return nil, err
	}
	entry, err := p.entry()
	if err != nil {
		return nil, err
	}
	kept := p.reach(entry)
	for _, f := range p.files {
		if err := p.layoutLiterals(f); err != nil {
			return nil, err
		}
	}
	p.img.Code = append(p.img.Code, uint32(OpHalt))
	for _, fn := range kept {
		p.emitFunction(fn)
	}
	for _, fx := range p.fixups {
		off, ok := p.labels[fx.file][fx.label]
		if !ok {
			p.errorf("%s: label %d is nowhere", fx.file.Name, fx.label)
			continue
		}
		p.img.Code[fx.at] = off
	}
	for _, fx := range p.funFixups {
		off, ok := p.labels[fx.file][fx.label]
		if !ok {
			p.errorf("%s: a fun's label %d is nowhere", fx.file.Name, fx.label)
			continue
		}
		p.img.Funs[fx.at] = off
	}
	if len(p.errs) > 0 {
		return nil, errors.New(strings.Join(p.errs, "\n"))
	}
	p.img.Entry = p.funcs[entry].offset
	p.img.EntryMFA = entry.String()
	for i := 0; i < len(p.img.Funcs); i += 4 {
		fn := p.funcs[fnKey{p.img.Atoms[p.img.Funcs[i+1]], p.img.Atoms[p.img.Funcs[i+2]], int(p.img.Funcs[i+3] & 0xff)}]
		p.img.Funcs[i] = fn.offset
	}
	sort.Sort(quads(p.img.Funcs))
	return p.img, nil
}

type quads []uint32

func (q quads) Len() int           { return len(q) / 4 }
func (q quads) Less(i, j int) bool { return q[4*i] < q[4*j] }
func (q quads) Swap(i, j int) {
	for k := 0; k < 4; k++ {
		q[4*i+k], q[4*j+k] = q[4*j+k], q[4*i+k]
	}
}

func (p *packer) errorf(format string, args ...any) {
	p.errs = append(p.errs, fmt.Sprintf(format, args...))
}

func (p *packer) atom(name string) int {
	if i, ok := p.atoms[name]; ok {
		return i
	}
	i := len(p.img.Atoms)
	p.atoms[name] = i
	p.img.Atoms = append(p.img.Atoms, name)
	return i
}

func (p *packer) fileIndex(name string) int {
	if i, ok := p.fileIdx[name]; ok {
		return i
	}
	i := len(p.img.Files)
	p.fileIdx[name] = i
	p.img.Files = append(p.img.Files, name)
	return i
}

// collect finds every function of every module, which labels are whose, and
// which are exported.
func (p *packer) collect() error {
	for _, f := range p.files {
		fns, err := f.Functions()
		if err != nil {
			return err
		}
		exported := map[fnKey]bool{}
		for _, e := range f.Exports {
			exported[fnKey{f.Module, e.Name, e.Arity}] = true
		}
		p.owners[f] = map[int]*function{}
		for _, fn := range fns {
			k := fnKey{f.Module, fn.Name, fn.Arity}
			x := &function{key: k, file: f, fn: fn, export: exported[k], index: len(p.funcs)}
			p.funcs[k] = x
			for _, in := range fn.Instrs {
				if in.Op == beam.OpLabel {
					p.owners[f][int(in.Args[0].Val)] = x
				}
			}
		}
	}
	return nil
}

func (p *packer) entry() (fnKey, error) {
	s := p.opts.Entry
	if s == "" {
		s = p.files[0].Module + ":main/0"
	}
	mod, rest, ok := strings.Cut(s, ":")
	name, as, ok2 := strings.Cut(rest, "/")
	arity, err := strconv.Atoi(as)
	if !ok || !ok2 || err != nil {
		return fnKey{}, fmt.Errorf("entry %q is not module:function/arity", s)
	}
	k := fnKey{mod, name, arity}
	fn, found := p.funcs[k]
	if !found {
		return fnKey{}, fmt.Errorf("entry %s: no such function in the modules packed", k)
	}
	if !fn.export {
		return fnKey{}, fmt.Errorf("entry %s is not exported", k)
	}
	return k, nil
}

// reach returns the functions the entry and the exports reach, in a stable
// order, and counts the rest as dropped. module_info/0 and /1 are dropped
// whatever reaches them: nothing on the board answers them.
func (p *packer) reach(entry fnKey) []*function {
	seen := map[fnKey]bool{}
	var work []*function
	add := func(fn *function) {
		if fn == nil || seen[fn.key] {
			return
		}
		if fn.key.name == "module_info" && (fn.key.arity == 0 || fn.key.arity == 1) {
			return
		}
		seen[fn.key] = true
		work = append(work, fn)
	}
	add(p.funcs[entry])
	var all []*function
	for _, fn := range p.funcs {
		all = append(all, fn)
	}
	sort.Slice(all, func(i, j int) bool { return all[i].index < all[j].index })
	for _, fn := range all {
		if fn.export {
			add(fn)
		}
	}
	for i := 0; i < len(work); i++ {
		fn := work[i]
		f := fn.file
		for _, in := range fn.fn.Instrs {
			switch in.Op {
			case beam.OpCall, beam.OpCallLast, beam.OpCallOnly:
				add(p.owners[f][int(in.Args[1].Val)])
			case beam.OpMakeFun3:
				if i := int(in.Args[0].Val); i < len(f.Funs) {
					add(p.owners[f][f.Funs[i].Label])
				}
			case beam.OpCallExt, beam.OpCallExtLast, beam.OpCallExtOnly:
				if m, ok := f.Import(in); ok {
					add(p.funcs[fnKey{m.Module, m.Function, m.Arity}])
				}
			}
		}
	}
	p.img.Dropped = len(p.funcs) - len(work)
	sort.Slice(work, func(i, j int) bool { return work[i].index < work[j].index })
	return work
}

// layoutLiterals lays the literals of a module out in the literal heap.
func (p *packer) layoutLiterals(f *beam.File) error {
	terms := make([]uint32, len(f.Literals))
	for i, t := range f.Literals {
		v, err := p.layoutTerm(t)
		if err != nil {
			return fmt.Errorf("%s: literal %d, %s: %w", f.Name, i, t, err)
		}
		terms[i] = v
	}
	p.literals[f] = terms
	return nil
}

func (p *packer) layoutTerm(t beam.Term) (uint32, error) {
	switch t.Kind {
	case beam.TermNil:
		return Nil, nil
	case beam.TermInt:
		return p.layoutInt(t.Int), nil
	case beam.TermBig:
		return 0, errors.New("an integer beyond 64 bits, which the board has no bignums for")
	case beam.TermFloat:
		at := len(p.img.Literals)
		p.img.Literals = append(p.img.Literals, Header(HdrFloat, 1), math.Float32bits(float32(t.Float)))
		return BoxedPtr(at), nil
	case beam.TermAtom:
		return Atom(p.atom(t.Atom)), nil
	case beam.TermList:
		tail := uint32(Nil)
		if t.Tail != nil {
			v, err := p.layoutTerm(*t.Tail)
			if err != nil {
				return 0, err
			}
			tail = v
		}
		for i := len(t.Elems) - 1; i >= 0; i-- {
			h, err := p.layoutTerm(t.Elems[i])
			if err != nil {
				return 0, err
			}
			at := len(p.img.Literals)
			p.img.Literals = append(p.img.Literals, h, tail)
			tail = ListPtr(at)
		}
		return tail, nil
	case beam.TermTuple:
		elems := make([]uint32, len(t.Elems))
		for i, e := range t.Elems {
			v, err := p.layoutTerm(e)
			if err != nil {
				return 0, err
			}
			elems[i] = v
		}
		at := len(p.img.Literals)
		p.img.Literals = append(p.img.Literals, Header(HdrTuple, len(elems)))
		p.img.Literals = append(p.img.Literals, elems...)
		return BoxedPtr(at), nil
	case beam.TermBinary:
		n := len(t.Bytes)
		longs := (n + 3) / 4
		at := len(p.img.Literals)
		p.img.Literals = append(p.img.Literals, Header(HdrBinary, 1+longs), uint32(n))
		for i := 0; i < longs; i++ {
			var w uint32
			for j := 0; j < 4 && 4*i+j < n; j++ {
				w |= uint32(t.Bytes[4*i+j]) << (8 * j)
			}
			p.img.Literals = append(p.img.Literals, w)
		}
		return BoxedPtr(at), nil
	case beam.TermBitstring:
		return 0, errors.New("a bitstring, which is not in version 1")
	case beam.TermMap:
		return 0, errors.New("a map, which is not in version 1")
	case beam.TermExport:
		return 0, errors.New("a fun of an external function, which is not yet done")
	}
	return 0, fmt.Errorf("a term of kind %d", t.Kind)
}

// layoutInt makes a small integer's term, or lays out a 64-bit one.
func (p *packer) layoutInt(v int64) uint32 {
	if v >= SmallMin && v <= SmallMax {
		return Small(v)
	}
	at := len(p.img.Literals)
	p.img.Literals = append(p.img.Literals, Header(HdrInt64, 2), uint32(v), uint32(v>>32))
	return BoxedPtr(at)
}

func (p *packer) emit(words ...uint32) {
	p.img.Code = append(p.img.Code, words...)
}

func (p *packer) emitLabel(f *beam.File, label int) {
	p.fixups = append(p.fixups, fixup{at: len(p.img.Code), file: f, label: label})
	p.emit(0)
}

// emitFunction lays one function out and translates it.
func (p *packer) emitFunction(fn *function) {
	f := fn.file
	if p.labels[f] == nil {
		p.labels[f] = map[int]uint32{}
	}
	fn.offset = 0
	exported := uint32(0)
	if fn.export {
		exported = 1 << 8
	}
	p.img.Funcs = append(p.img.Funcs, 0, uint32(p.atom(fn.key.module)), uint32(p.atom(fn.key.name)), uint32(fn.key.arity)|exported)
	where := func(in beam.Instr) string {
		return fmt.Sprintf("%s: %s, %s at code offset %d", f.Name, fn.key, in.Op, in.Offset)
	}
	for i, in := range fn.fn.Instrs {
		switch in.Op {
		case beam.OpLabel:
			l := int(in.Args[0].Val)
			p.labels[f][l] = uint32(len(p.img.Code))
			if i+1 < len(fn.fn.Instrs) && fn.fn.Instrs[i+1].Op == beam.OpFuncInfo || i+2 < len(fn.fn.Instrs) && fn.fn.Instrs[i+1].Op == beam.OpLine && fn.fn.Instrs[i+2].Op == beam.OpFuncInfo {
				continue
			}
			if fn.offset == 0 {
				fn.offset = uint32(len(p.img.Code))
			}
			continue
		case beam.OpLine:
			if p.opts.Lines {
				if file, line, ok := f.Lines.Location(in.Args[0].Val); ok {
					off := uint32(len(p.img.Code))
					n := len(p.img.Lines)
					if n >= 3 && p.img.Lines[n-3] == off {
						p.img.Lines = p.img.Lines[:n-3]
					}
					p.img.Lines = append(p.img.Lines, off, uint32(p.fileIndex(file)), uint32(line))
				}
			}
			continue
		case beam.OpIntCodeEnd:
			continue
		case beam.OpFuncInfo:
			p.emit(uint32(beam.OpFuncInfo), Atom(p.atom(fn.key.module)), Atom(p.atom(fn.key.name)), uint32(fn.key.arity))
			continue
		case beam.OpCallExt, beam.OpCallExtLast, beam.OpCallExtOnly:
			m, ok := f.Import(in)
			if !ok {
				p.errorf("%s: an import that is not in the table", where(in))
				continue
			}
			arity := uint32(in.Args[0].Val)
			if bif, ok := bifIndex(m); ok {
				p.emit(uint32(OpCallBif), arity, uint32(bif))
				switch in.Op {
				case beam.OpCallExtLast:
					p.emit(uint32(beam.OpDeallocate), uint32(in.Args[2].Val), uint32(beam.OpReturn))
				case beam.OpCallExtOnly:
					p.emit(uint32(beam.OpReturn))
				}
				continue
			}
			target, ok := p.funcs[fnKey{m.Module, m.Function, m.Arity}]
			if !ok {
				p.errorf("%s: calls %s, which is no BIF and no function of the modules packed", where(in), m)
				continue
			}
			switch in.Op {
			case beam.OpCallExt:
				p.emit(uint32(beam.OpCall), arity)
				p.emitTarget(target)
			case beam.OpCallExtLast:
				p.emit(uint32(beam.OpCallLast), arity)
				p.emitTarget(target)
				p.emit(uint32(in.Args[2].Val))
			case beam.OpCallExtOnly:
				p.emit(uint32(beam.OpCallOnly), arity)
				p.emitTarget(target)
			}
			continue
		case beam.OpBif0, beam.OpBif1, beam.OpBif2, beam.OpGcBif1, beam.OpGcBif2, beam.OpGcBif3:
			m, ok := f.Import(in)
			if !ok {
				p.errorf("%s: an import that is not in the table", where(in))
				continue
			}
			bif, ok := bifIndex(m)
			if !ok {
				p.errorf("%s: calls %s, which is no BIF of the VM", where(in), m)
				continue
			}
			imp := 0
			if in.Op != beam.OpBif0 {
				imp = 1
			}
			if in.Op == beam.OpGcBif1 || in.Op == beam.OpGcBif2 || in.Op == beam.OpGcBif3 {
				imp = 2
			}
			p.emit(uint32(in.Op))
			for j, a := range in.Args {
				if j == imp {
					p.emit(uint32(bif))
					continue
				}
				p.emitArg(f, a, where(in))
			}
			continue
		case beam.OpMakeFun3:
			idx := int(in.Args[0].Val)
			if idx >= len(f.Funs) {
				p.errorf("%s: fun %d of %d", where(in), idx, len(f.Funs))
				continue
			}
			p.emit(uint32(beam.OpMakeFun3), uint32(p.funIndex(f, idx)))
			p.emitArg(f, in.Args[1], where(in))
			p.emitArg(f, in.Args[2], where(in))
			continue
		}
		if !p.supported(in.Op) {
			p.errorf("%s: an instruction the VM does not have", where(in))
			continue
		}
		p.emit(uint32(in.Op))
		for _, a := range in.Args {
			p.emitArg(f, a, where(in))
		}
	}
	if fn.offset == 0 {
		p.errorf("%s: %s has no entry label", f.Name, fn.key)
	}
}

// emitTarget emits the code offset of a function, fixed up once it is known.
func (p *packer) emitTarget(fn *function) {
	p.fixups = append(p.fixups, fixup{at: len(p.img.Code), file: fn.file, label: fn.fn.Entry})
	p.emit(0)
}

// funIndex returns the image's index of a module's fun, making the entry if
// it is new.
func (p *packer) funIndex(f *beam.File, idx int) int {
	if p.funs[f] == nil {
		p.funs[f] = map[int]int{}
	}
	if i, ok := p.funs[f][idx]; ok {
		return i
	}
	l := f.Funs[idx]
	i := len(p.img.Funs) / 3
	p.funs[f][idx] = i
	p.img.Funs = append(p.img.Funs, 0, uint32(l.Arity), uint32(l.NumFree))
	p.funFixups = append(p.funFixups, funFixup{at: len(p.img.Funs) - 3, file: f, label: l.Label})
	return i
}

func (p *packer) emitArg(f *beam.File, a beam.Arg, where string) {
	switch a.Kind {
	case beam.ArgU, beam.ArgH:
		p.emit(uint32(a.Val))
	case beam.ArgI:
		if a.Big != nil {
			p.errorf("%s: an integer beyond 64 bits", where)
			p.emit(0)
			return
		}
		p.emit(p.layoutInt(a.Val))
	case beam.ArgAtom:
		if a.Val == 0 {
			p.emit(Nil)
			return
		}
		p.emit(Atom(p.atom(f.Atoms[a.Val])))
	case beam.ArgX:
		p.emit(XReg(int(a.Val)))
	case beam.ArgY:
		p.emit(YReg(int(a.Val)))
	case beam.ArgF:
		if a.Val == 0 {
			p.emit(0)
			return
		}
		p.emitLabel(f, int(a.Val))
	case beam.ArgLiteral:
		p.emit(p.literals[f][a.Val])
	case beam.ArgList:
		p.emit(uint32(len(a.List)))
		for _, e := range a.List {
			p.emitArg(f, e, where)
		}
	case beam.ArgAlloc:
		n := uint32(0)
		for i := 0; i+1 < len(a.List); i += 2 {
			switch a.List[i].Val {
			case 0: // words
				n += uint32(a.List[i+1].Val)
			case 1: // floats: a header and the float
				n += 2 * uint32(a.List[i+1].Val)
			case 2: // funs: a header and the fun's head, the environment being counted in words
				n += (1 + FunHeadLongs) * uint32(a.List[i+1].Val)
			}
		}
		p.emit(n)
	case beam.ArgTyped:
		p.emitArg(f, *a.Reg, where)
	case beam.ArgFR:
		p.errorf("%s: a floating-point register, which is not yet done", where)
		p.emit(0)
	default:
		p.errorf("%s: an operand of kind %s", where, a.Kind)
		p.emit(0)
	}
}

// supported says which of genop's instructions the VM runs as they are, their
// operands resolved. The ones translated above are not here.
func (p *packer) supported(op beam.Opcode) bool {
	switch op {
	case beam.OpCall, beam.OpCallLast, beam.OpCallOnly,
		beam.OpAllocate, beam.OpAllocateHeap, beam.OpDeallocate, beam.OpInitYregs, beam.OpTrim, beam.OpSwap,
		beam.OpTestHeap, beam.OpReturn, beam.OpMove, beam.OpJump,
		beam.OpSelectVal, beam.OpSelectTupleArity,
		beam.OpIsLt, beam.OpIsGe, beam.OpIsEq, beam.OpIsNe, beam.OpIsEqExact, beam.OpIsNeExact,
		beam.OpIsInteger, beam.OpIsFloat, beam.OpIsNumber, beam.OpIsAtom, beam.OpIsPid, beam.OpIsReference,
		beam.OpIsPort, beam.OpIsNil, beam.OpIsBinary, beam.OpIsList, beam.OpIsNonemptyList, beam.OpIsTuple,
		beam.OpTestArity, beam.OpIsTaggedTuple, beam.OpIsBoolean, beam.OpIsFunction, beam.OpIsFunction2,
		beam.OpIsMap, beam.OpIsBitstr,
		beam.OpGetList, beam.OpGetHd, beam.OpGetTl, beam.OpPutList, beam.OpPutTuple2,
		beam.OpGetTupleElement, beam.OpSetTupleElement, beam.OpUpdateRecord,
		beam.OpCallFun, beam.OpCallFun2,
		beam.OpBadmatch, beam.OpCaseEnd, beam.OpIfEnd, beam.OpBadrecord:
		return true
	}
	return false
}
