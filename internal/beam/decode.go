// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package beam

import (
	"errors"
	"fmt"
	"math/big"
)

// Opcode is a BEAM opcode, numbered as genop.tab numbers it.
type Opcode uint8

type opcodeInfo struct {
	name     string
	arity    int
	obsolete bool
}

func (o Opcode) info() (opcodeInfo, bool) {
	if int(o) < len(opcodes) && opcodes[o].name != "" {
		return opcodes[o], true
	}
	return opcodeInfo{}, false
}

// String returns the opcode's name in genop.tab, or its number for one the
// table does not have.
func (o Opcode) String() string {
	if i, ok := o.info(); ok {
		return i.name
	}
	return fmt.Sprintf("opcode%d", uint8(o))
}

// Arity returns how many operands the opcode takes, and whether the table
// knows the opcode at all.
func (o Opcode) Arity() (int, bool) {
	i, ok := o.info()
	return i.arity, ok
}

// Obsolete reports whether genop.tab marks the opcode obsolete.
func (o Opcode) Obsolete() bool {
	i, _ := o.info()
	return i.obsolete
}

// Opcodes returns every opcode the table has, in numerical order.
func Opcodes() []Opcode {
	var ops []Opcode
	for i := range opcodes {
		if opcodes[i].name != "" {
			ops = append(ops, Opcode(i))
		}
	}
	return ops
}

// A decoder reads operands in the compact term encoding, as beam_asm's encode/2
// writes them: a tag in the low three bits of the first byte and the value
// above it when it is below 16; bit 3 set and the value's eleven bits split
// over the first byte's top three and a second byte when it is below 2048;
// bits 3 and 4 set and a byte count in the top three bits, plus two, with the
// value in that many bytes after, big-endian and two's complement, when it is
// larger; and a count of seven standing for a count that follows as an
// unsigned operand, plus nine. Tag 7 is extended: the first byte's high
// nibble says what follows.
type decoder struct {
	b   []byte
	pos int
}

func (d *decoder) byte() (byte, error) {
	if d.pos >= len(d.b) {
		return 0, errors.New("the code ends inside an operand")
	}
	c := d.b[d.pos]
	d.pos++
	return c, nil
}

func (d *decoder) take(n int) ([]byte, error) {
	if n < 0 || d.pos+n > len(d.b) {
		return nil, fmt.Errorf("an operand of %d bytes runs past the end", n)
	}
	s := d.b[d.pos : d.pos+n]
	d.pos += n
	return s, nil
}

// uint reads an operand that must be an unsigned number.
func (d *decoder) uint() (int64, error) {
	a, err := d.arg()
	if err != nil {
		return 0, err
	}
	if a.Kind != ArgU || a.Big != nil {
		return 0, fmt.Errorf("expected an unsigned number, got a %s operand", a.Kind)
	}
	return a.Val, nil
}

func (d *decoder) arg() (Arg, error) {
	b, err := d.byte()
	if err != nil {
		return Arg{}, err
	}
	tag := b & 7
	if tag == 7 {
		return d.extended(b >> 4)
	}
	var val int64
	var bigv *big.Int
	switch {
	case b&0x08 == 0:
		val = int64(b >> 4)
	case b&0x10 == 0:
		next, err := d.byte()
		if err != nil {
			return Arg{}, err
		}
		val = int64(b&0xe0)<<3 | int64(next)
	default:
		n := int(b >> 5)
		if n == 7 {
			m, err := d.uint()
			if err != nil {
				return Arg{}, err
			}
			n = int(m) + 9
		} else {
			n += 2
		}
		bs, err := d.take(n)
		if err != nil {
			return Arg{}, err
		}
		if n <= 8 {
			var v int64
			if bs[0]&0x80 != 0 {
				v = -1
			}
			for _, c := range bs {
				v = v<<8 | int64(c)
			}
			val = v
		} else {
			z := new(big.Int).SetBytes(bs)
			if bs[0]&0x80 != 0 {
				z.Sub(z, new(big.Int).Lsh(big.NewInt(1), uint(8*n)))
			}
			bigv = z
		}
	}
	kinds := [...]ArgKind{ArgU, ArgI, ArgAtom, ArgX, ArgY, ArgF, ArgH}
	return Arg{Kind: kinds[tag], Val: val, Big: bigv}, nil
}

func (d *decoder) extended(sub byte) (Arg, error) {
	switch sub {
	case 1: // a list
		n, err := d.uint()
		if err != nil {
			return Arg{}, err
		}
		if n > int64(len(d.b)) {
			return Arg{}, fmt.Errorf("a list of %d operands in %d bytes", n, len(d.b))
		}
		list := make([]Arg, n)
		for i := range list {
			if list[i], err = d.arg(); err != nil {
				return Arg{}, err
			}
		}
		return Arg{Kind: ArgList, List: list}, nil
	case 2: // a floating-point register
		n, err := d.uint()
		if err != nil {
			return Arg{}, err
		}
		return Arg{Kind: ArgFR, Val: n}, nil
	case 3: // an allocation list
		n, err := d.uint()
		if err != nil {
			return Arg{}, err
		}
		if n > int64(len(d.b)) {
			return Arg{}, fmt.Errorf("an allocation list of %d pairs in %d bytes", n, len(d.b))
		}
		list := make([]Arg, 2*n)
		for i := range list {
			v, err := d.uint()
			if err != nil {
				return Arg{}, err
			}
			list[i] = Arg{Kind: ArgU, Val: v}
		}
		return Arg{Kind: ArgAlloc, List: list}, nil
	case 4: // a literal
		n, err := d.uint()
		if err != nil {
			return Arg{}, err
		}
		return Arg{Kind: ArgLiteral, Val: n}, nil
	case 5: // a register with a type
		reg, err := d.arg()
		if err != nil {
			return Arg{}, err
		}
		if reg.Kind != ArgX && reg.Kind != ArgY {
			return Arg{}, fmt.Errorf("a typed operand that is a %s, not a register", reg.Kind)
		}
		n, err := d.uint()
		if err != nil {
			return Arg{}, err
		}
		return Arg{Kind: ArgTyped, Val: n, Reg: &reg}, nil
	}
	return Arg{}, fmt.Errorf("extended operand tag %d", sub)
}
