// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// TestRegion lays out an image as the board's arena begins and reads it back
// as the VM does: the header, the literals at LitBase, the tables where the
// header says, and every atom's and file's name from its long.
func TestRegion(t *testing.T) {
	path := filepath.Join("..", "..", "erl", "exc.beam")
	if _, err := os.Stat(path); err != nil {
		t.Skip("no corpus here")
	}
	img, err := Pack([]string{path}, Options{Lines: true})
	if err != nil {
		t.Fatal(err)
	}
	r, err := img.Region()
	if err != nil {
		t.Fatal(err)
	}
	if r[ImgMagic] != ImageMagic || r[ImgTableID] != TableID() || int(r[ImgLongs]) != len(r) || r[ImgEntry] != img.Entry {
		t.Fatalf("header %#x", r[:imgSlots])
	}
	if got, want := r[ImgLitEnd], uint32(LitBase+len(img.Literals)); got != want {
		t.Errorf("literals end at %d, want %d", got, want)
	}
	table := func(slot int) []uint32 { return r[r[slot] : r[slot]+r[slot+1]] }
	for _, c := range []struct {
		slot int
		want []uint32
	}{{ImgCode, img.Code}, {ImgFuncs, img.Funcs}, {ImgFuns, img.Funs}, {ImgLines, img.Lines}, {ImgStructs, img.Structs}} {
		if got := table(c.slot); !equal(got, c.want) {
			t.Errorf("slot %d: %d longs, want %d", c.slot, len(got), len(c.want))
		}
	}
	b := Bytes(r)
	name := func(nm uint32) string {
		at, n := nm>>NameLenBits, nm&maxName
		return string(b[at : at+n])
	}
	for slot, want := range map[int][]string{ImgAtoms: img.Atoms, ImgFiles: img.Files} {
		got := table(slot)
		if len(got) != len(want) {
			t.Fatalf("slot %d: %d names, want %d", slot, len(got), len(want))
		}
		for i, nm := range got {
			if name(nm) != want[i] {
				t.Errorf("slot %d, name %d: %q, want %q", slot, i, name(nm), want[i])
			}
		}
	}
	if got := name(table(ImgAtoms)[r[ImgEntryMod]]) + ":" + name(table(ImgAtoms)[r[ImgEntryFun]]); got != "exc:main" || r[ImgEntryArity] != 0 {
		t.Errorf("entry %s/%d, want exc:main/0", got, r[ImgEntryArity])
	}
}

func equal(a, b []uint32) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// fakeVM makes what Patch looks for in a VM binary: an arena of longs longs
// marked as the VM marks it, with bytes before and after.
func fakeVM(longs int, id uint32) []byte {
	arena := make([]uint32, longs)
	copy(arena, []uint32{RegionMark0, RegionMark1, RegionMark2, RegionMark3, uint32(longs), id})
	b := append(bytes.Repeat([]byte{0xa5}, 64), Bytes(arena)...)
	return append(b, bytes.Repeat([]byte{0x5a}, 32)...)
}

// TestPatch puts an image into a VM binary, and refuses a binary with no
// mark, two, other tables, or too small an arena.
func TestPatch(t *testing.T) {
	region := []uint32{ImageMagic, TableID(), 3}
	vm := fakeVM(100, TableID())
	out, room, err := Patch(vm, region)
	if err != nil {
		t.Fatal(err)
	}
	if room != 97 || len(out) != len(vm) || !bytes.Equal(out[64:76], Bytes(region)) || binary.LittleEndian.Uint32(out[76:]) != RegionMark3 {
		t.Errorf("room %d, %d bytes, arena %x", room, len(out), out[64:84])
	}
	if !bytes.Equal(vm[:64], out[:64]) || !bytes.Equal(vm[64+400:], out[64+400:]) {
		t.Error("Patch changed what is not the arena")
	}
	for _, c := range []struct {
		vm    []byte
		longs int
		want  string
	}{
		{bytes.Repeat([]byte{1}, 500), 3, "no arena mark"},
		{append(fakeVM(10, TableID()), fakeVM(10, TableID())...), 3, "two arena marks"},
		{fakeVM(100, TableID()+1), 3, "built with tables"},
		{fakeVM(6, TableID()), 7, "the image takes 7 longs, and the VM's arena has 6"},
		{fakeVM(100, TableID())[:200], 3, "ends past the binary's end"},
	} {
		if _, _, err := Patch(c.vm, append(region, make([]uint32, c.longs-len(region))...)); err == nil || !strings.Contains(err.Error(), c.want) {
			t.Errorf("%v, want %q", err, c.want)
		}
	}
}
