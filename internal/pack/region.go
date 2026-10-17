// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"bytes"
	"encoding/binary"
	"errors"
	"fmt"
)

// The image as the board holds it: the bottom of the arena, a header, the
// literals at the arena indexes the packer gave them, then the code and the
// tables, and the atoms' and the files' names as bytes. The processes' heaps
// take the rest of the arena. A VM binary comes with its arena marked, and
// Patch writes an image over the mark; a VM that finds no image there says so.
const (
	ImageMagic  = 0x4d49424f // "OBIM", the header's first long
	ImageLayout = 1          // the header's layout, part of TableID
	HeaderLongs = 24         // the header's longs, of which the Img* slots are used
	LitBase     = HeaderLongs
	NameLenBits = 10 // a name's long: the byte offset in the arena above, the length below

	// What an unmarked arena begins with: these four longs, then the arena's
	// length in longs and the VM's TableID.
	RegionMark0 = 0x4f42e1a7
	RegionMark1 = 0x9c3d5b21
	RegionMark2 = 0x77a0c4e9
	RegionMark3 = 0x1d2f8b63
)

// The header's slots. A table is two: its arena index and its length.
const (
	ImgMagic      = iota // ImageMagic
	ImgTableID           // the TableID the image was packed for
	ImgLongs             // the longs the image takes, header and all
	ImgEntry             // the entry function's code offset
	ImgEntryMod          // its module, an atom index
	ImgEntryFun          // its function, an atom index
	ImgEntryArity        // its arity
	ImgLitEnd            // where the literals end; they begin at LitBase
	ImgCode              // the instruction stream
	ImgCodeLen
	ImgFuncs
	ImgFuncsLen
	ImgFuns
	ImgFunsLen
	ImgLines
	ImgLinesLen
	ImgStructs
	ImgStructsLen
	ImgAtoms // the atoms' names, a long each
	ImgAtomsLen
	ImgFiles // the files' names, a long each
	ImgFilesLen
	imgSlots
)

const maxName = 1<<NameLenBits - 1

// Region lays the image out as the board's arena begins: the header, the
// literals, the code, the tables, and the names.
func (img *Image) Region() ([]uint32, error) {
	if imgSlots > HeaderLongs {
		return nil, errors.New("the header has more slots than longs")
	}
	r := make([]uint32, HeaderLongs)
	r = append(r, img.Literals...)
	r[ImgLitEnd] = uint32(len(r))
	put := func(slot int, ws []uint32) {
		r[slot] = uint32(len(r))
		r[slot+1] = uint32(len(ws))
		r = append(r, ws...)
	}
	put(ImgCode, img.Code)
	put(ImgFuncs, img.Funcs)
	put(ImgFuns, img.Funs)
	put(ImgLines, img.Lines)
	put(ImgStructs, img.Structs)
	put(ImgAtoms, make([]uint32, len(img.Atoms)))
	put(ImgFiles, make([]uint32, len(img.Files)))
	var names []byte
	at := 4 * len(r)
	name := func(slot, i int, s string) error {
		if len(s) > maxName {
			return fmt.Errorf("a name of %d bytes, more than %d: %.40q...", len(s), maxName, s)
		}
		r[int(r[slot])+i] = uint32(at+len(names))<<NameLenBits | uint32(len(s))
		names = append(names, s...)
		return nil
	}
	for i, s := range img.Atoms {
		if err := name(ImgAtoms, i, s); err != nil {
			return nil, err
		}
	}
	for i, s := range img.Files {
		if err := name(ImgFiles, i, s); err != nil {
			return nil, err
		}
	}
	for len(names)%4 != 0 {
		names = append(names, 0)
	}
	for i := 0; i < len(names); i += 4 {
		r = append(r, binary.LittleEndian.Uint32(names[i:]))
	}
	if uint64(4*len(r)) > 1<<(32-NameLenBits) {
		return nil, fmt.Errorf("an image of %d longs, more than a name's offset reaches", len(r))
	}
	r[ImgMagic] = ImageMagic
	r[ImgTableID] = TableID()
	r[ImgLongs] = uint32(len(r))
	r[ImgEntry] = img.Entry
	r[ImgEntryMod] = img.EntryModule
	r[ImgEntryFun] = img.EntryFunction
	r[ImgEntryArity] = img.EntryArity
	return r, nil
}

// Bytes writes longs as the board holds them, little-endian.
func Bytes(ws []uint32) []byte {
	b := make([]byte, 4*len(ws))
	for i, w := range ws {
		binary.LittleEndian.PutUint32(b[4*i:], w)
	}
	return b
}

// A Region is where a VM binary's arena is.
type Region struct {
	Offset int // in the binary, in bytes
	Longs  int // the arena's length
}

// FindRegion finds the arena of a VM binary by its mark, and checks that the
// VM was built with the tables the packer packs for.
func FindRegion(vm []byte) (Region, error) {
	mark := Bytes([]uint32{RegionMark0, RegionMark1, RegionMark2, RegionMark3})
	i := bytes.Index(vm, mark)
	switch {
	case i < 0:
		return Region{}, errors.New("no arena mark: not a VM binary obeam can put an image into")
	case bytes.Index(vm[i+1:], mark) >= 0:
		return Region{}, errors.New("two arena marks")
	case i%4 != 0 || i+24 > len(vm):
		return Region{}, errors.New("an arena mark out of place")
	}
	rg := Region{Offset: i, Longs: int(binary.LittleEndian.Uint32(vm[i+16:]))}
	if id := binary.LittleEndian.Uint32(vm[i+20:]); id != TableID() {
		return Region{}, fmt.Errorf("the VM was built with tables 0x%08x, obeam packs for 0x%08x", id, TableID())
	}
	if rg.Offset+4*rg.Longs > len(vm) {
		return Region{}, errors.New("an arena that ends past the binary's end")
	}
	return rg, nil
}

// Patch answers a copy of a VM binary with the image in its arena, and how
// many longs of the arena are left to the processes' heaps.
func Patch(vm []byte, region []uint32) ([]byte, int, error) {
	rg, err := FindRegion(vm)
	if err != nil {
		return nil, 0, err
	}
	if len(region) > rg.Longs {
		return nil, 0, fmt.Errorf("the image takes %d longs, and the VM's arena has %d", len(region), rg.Longs)
	}
	out := append([]byte(nil), vm...)
	copy(out[rg.Offset:], Bytes(region))
	return out, rg.Longs - len(region), nil
}
