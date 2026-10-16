// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package beam

import (
	"bytes"
	"compress/zlib"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"math"
	"math/big"
	"strconv"
	"strings"
)

// TermKind is what kind of term a Term is.
type TermKind uint8

// The kinds of term a literal can be. A pid, a port or a reference cannot be
// a literal, and a fun that is one is an external one, fun m:f/a.
const (
	TermNil       TermKind = iota // []
	TermInt                       // Int
	TermBig                       // Big, an integer that does not fit Int
	TermFloat                     // Float
	TermAtom                      // Atom
	TermList                      // Elems, and Tail where the list is improper
	TermTuple                     // Elems
	TermBinary                    // Bytes
	TermBitstring                 // Bytes, of which the last byte has Bits bits
	TermMap                       // Elems, a key and its value in turn
	TermExport                    // fun Atom:Elems[0]/Elems[1]
)

// A Term is an Erlang term, as a literal of a module is one.
type Term struct {
	Kind  TermKind
	Int   int64
	Big   *big.Int
	Float float64
	Atom  string
	Bytes []byte
	Bits  uint8
	Elems []Term
	Tail  *Term
}

// DecodeETF decodes a term in the external term format, version 131, as the
// literal table and the Attr and CInf chunks hold them.
func DecodeETF(b []byte) (Term, error) {
	if len(b) == 0 || b[0] != 131 {
		return Term{}, errors.New("external term format: no version byte 131")
	}
	r := &etfReader{b: b, pos: 1}
	if r.pos < len(r.b) && r.b[r.pos] == 80 { // compressed
		r.pos++
		size, err := r.u32()
		if err != nil {
			return Term{}, err
		}
		zr, err := zlib.NewReader(bytes.NewReader(r.b[r.pos:]))
		if err != nil {
			return Term{}, fmt.Errorf("compressed term: %w", err)
		}
		data, err := io.ReadAll(io.LimitReader(zr, int64(size)+1))
		if err != nil {
			return Term{}, fmt.Errorf("compressed term: %w", err)
		}
		if len(data) != int(size) {
			return Term{}, fmt.Errorf("compressed term: %d bytes uncompressed, %d announced", len(data), size)
		}
		r = &etfReader{b: data}
	}
	t, err := r.term()
	if err != nil {
		return Term{}, fmt.Errorf("external term format: %w", err)
	}
	if r.pos != len(r.b) {
		return Term{}, fmt.Errorf("external term format: %d bytes after the term", len(r.b)-r.pos)
	}
	return t, nil
}

type etfReader struct {
	b   []byte
	pos int
}

func (r *etfReader) take(n int) ([]byte, error) {
	if n < 0 || r.pos+n > len(r.b) {
		return nil, fmt.Errorf("%d bytes wanted at %d of %d", n, r.pos, len(r.b))
	}
	s := r.b[r.pos : r.pos+n]
	r.pos += n
	return s, nil
}

func (r *etfReader) u8() (int, error) {
	s, err := r.take(1)
	if err != nil {
		return 0, err
	}
	return int(s[0]), nil
}

func (r *etfReader) u16() (int, error) {
	s, err := r.take(2)
	if err != nil {
		return 0, err
	}
	return int(binary.BigEndian.Uint16(s)), nil
}

func (r *etfReader) u32() (uint32, error) {
	s, err := r.take(4)
	if err != nil {
		return 0, err
	}
	return binary.BigEndian.Uint32(s), nil
}

func (r *etfReader) atom(n int, utf8 bool) (Term, error) {
	s, err := r.take(n)
	if err != nil {
		return Term{}, err
	}
	if utf8 {
		return Term{Kind: TermAtom, Atom: string(s)}, nil
	}
	return Term{Kind: TermAtom, Atom: latin1(s)}, nil
}

func (r *etfReader) elems(n int) ([]Term, error) {
	if n > len(r.b)-r.pos {
		return nil, fmt.Errorf("%d elements in %d bytes", n, len(r.b)-r.pos)
	}
	es := make([]Term, n)
	for i := range es {
		var err error
		if es[i], err = r.term(); err != nil {
			return nil, err
		}
	}
	return es, nil
}

func (r *etfReader) term() (Term, error) {
	tag, err := r.u8()
	if err != nil {
		return Term{}, err
	}
	switch tag {
	case 97: // SMALL_INTEGER_EXT
		n, err := r.u8()
		return Term{Kind: TermInt, Int: int64(n)}, err
	case 98: // INTEGER_EXT
		n, err := r.u32()
		return Term{Kind: TermInt, Int: int64(int32(n))}, err
	case 99: // FLOAT_EXT, a string of 31 bytes
		s, err := r.take(31)
		if err != nil {
			return Term{}, err
		}
		f, err := strconv.ParseFloat(strings.TrimRight(string(s), "\x00"), 64)
		if err != nil {
			return Term{}, fmt.Errorf("FLOAT_EXT: %w", err)
		}
		return Term{Kind: TermFloat, Float: f}, nil
	case 70: // NEW_FLOAT_EXT
		s, err := r.take(8)
		if err != nil {
			return Term{}, err
		}
		return Term{Kind: TermFloat, Float: math.Float64frombits(binary.BigEndian.Uint64(s))}, nil
	case 100: // ATOM_EXT
		n, err := r.u16()
		if err != nil {
			return Term{}, err
		}
		return r.atom(n, false)
	case 115: // SMALL_ATOM_EXT
		n, err := r.u8()
		if err != nil {
			return Term{}, err
		}
		return r.atom(n, false)
	case 118: // ATOM_UTF8_EXT
		n, err := r.u16()
		if err != nil {
			return Term{}, err
		}
		return r.atom(n, true)
	case 119: // SMALL_ATOM_UTF8_EXT
		n, err := r.u8()
		if err != nil {
			return Term{}, err
		}
		return r.atom(n, true)
	case 104, 105: // SMALL_TUPLE_EXT, LARGE_TUPLE_EXT
		var n int
		if tag == 104 {
			n, err = r.u8()
		} else {
			var m uint32
			m, err = r.u32()
			n = int(m)
		}
		if err != nil {
			return Term{}, err
		}
		es, err := r.elems(n)
		return Term{Kind: TermTuple, Elems: es}, err
	case 106: // NIL_EXT
		return Term{Kind: TermNil}, nil
	case 107: // STRING_EXT, a list of bytes
		n, err := r.u16()
		if err != nil {
			return Term{}, err
		}
		s, err := r.take(n)
		if err != nil {
			return Term{}, err
		}
		es := make([]Term, n)
		for i, c := range s {
			es[i] = Term{Kind: TermInt, Int: int64(c)}
		}
		return Term{Kind: TermList, Elems: es}, nil
	case 108: // LIST_EXT
		n, err := r.u32()
		if err != nil {
			return Term{}, err
		}
		es, err := r.elems(int(n))
		if err != nil {
			return Term{}, err
		}
		tail, err := r.term()
		if err != nil {
			return Term{}, err
		}
		t := Term{Kind: TermList, Elems: es}
		if tail.Kind != TermNil {
			t.Tail = &tail
		}
		return t, nil
	case 109: // BINARY_EXT
		n, err := r.u32()
		if err != nil {
			return Term{}, err
		}
		s, err := r.take(int(n))
		return Term{Kind: TermBinary, Bytes: s}, err
	case 77: // BIT_BINARY_EXT
		n, err := r.u32()
		if err != nil {
			return Term{}, err
		}
		bits, err := r.u8()
		if err != nil {
			return Term{}, err
		}
		s, err := r.take(int(n))
		if err != nil {
			return Term{}, err
		}
		if n == 0 || bits < 1 || bits > 8 {
			return Term{}, fmt.Errorf("BIT_BINARY_EXT of %d bytes with %d bits in the last", n, bits)
		}
		if bits == 8 {
			return Term{Kind: TermBinary, Bytes: s}, nil
		}
		return Term{Kind: TermBitstring, Bytes: s, Bits: uint8(bits)}, nil
	case 110, 111: // SMALL_BIG_EXT, LARGE_BIG_EXT
		var n int
		if tag == 110 {
			n, err = r.u8()
		} else {
			var m uint32
			m, err = r.u32()
			n = int(m)
		}
		if err != nil {
			return Term{}, err
		}
		sign, err := r.u8()
		if err != nil {
			return Term{}, err
		}
		s, err := r.take(n)
		if err != nil {
			return Term{}, err
		}
		le := make([]byte, n) // the digits are little-endian
		for i, c := range s {
			le[n-1-i] = c
		}
		z := new(big.Int).SetBytes(le)
		if sign != 0 {
			z.Neg(z)
		}
		if z.IsInt64() {
			return Term{Kind: TermInt, Int: z.Int64()}, nil
		}
		return Term{Kind: TermBig, Big: z}, nil
	case 116: // MAP_EXT
		n, err := r.u32()
		if err != nil {
			return Term{}, err
		}
		if n > uint32(len(r.b)-r.pos) {
			return Term{}, fmt.Errorf("a map of %d pairs in %d bytes", n, len(r.b)-r.pos)
		}
		es, err := r.elems(2 * int(n))
		return Term{Kind: TermMap, Elems: es}, err
	case 113: // EXPORT_EXT, fun m:f/a
		m, err := r.term()
		if err != nil {
			return Term{}, err
		}
		fn, err := r.term()
		if err != nil {
			return Term{}, err
		}
		a, err := r.term()
		if err != nil {
			return Term{}, err
		}
		if m.Kind != TermAtom || fn.Kind != TermAtom || a.Kind != TermInt {
			return Term{}, errors.New("EXPORT_EXT that is not two atoms and an integer")
		}
		return Term{Kind: TermExport, Atom: m.Atom, Elems: []Term{fn, a}}, nil
	case 88, 103: // NEW_PID_EXT, PID_EXT
		return Term{}, errors.New("a pid, which no literal can be")
	case 89, 102, 120: // NEW_PORT_EXT, PORT_EXT, V4_PORT_EXT
		return Term{}, errors.New("a port, which no literal can be")
	case 90, 101, 114: // NEWER_REFERENCE_EXT, REFERENCE_EXT, NEW_REFERENCE_EXT
		return Term{}, errors.New("a reference, which no literal can be")
	case 112, 117: // NEW_FUN_EXT, FUN_EXT
		return Term{}, errors.New("a local fun, which no literal can be")
	}
	return Term{}, fmt.Errorf("term tag %d", tag)
}
