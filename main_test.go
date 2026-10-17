// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package main

import (
	"bytes"
	"encoding/binary"
	"os"
	"path/filepath"
	"testing"

	"modernc.org/obeam/internal/pack"
	"modernc.org/obeam/internal/vmbin"
)

// TestBuild puts programs into the VMs obeam carries as a user would: flags
// after the files, a pattern, the unchecked VM, and listlib, which reaches
// the lists shim obeam carries without being told of it.
func TestBuild(t *testing.T) {
	dir := t.TempDir()
	for _, c := range []struct {
		args []string
		vm   []byte
		out  string
	}{
		{[]string{"erl/hello.beam", "-o", filepath.Join(dir, "a.binary")}, vmbin.Checked, "a.binary"},
		{[]string{"-unchecked", "erl/hel*.beam", "-o", filepath.Join(dir, "b.binary")}, vmbin.Unchecked, "b.binary"},
		{[]string{"-o", filepath.Join(dir, "c.binary"), "erl/listlib.beam"}, vmbin.Checked, "c.binary"},
	} {
		out, _, err := build("obeam", c.args)
		if err != nil {
			t.Fatalf("%q: %v", c.args, err)
		}
		if filepath.Base(out) != c.out {
			t.Errorf("%q wrote %s", c.args, out)
		}
		b, err := os.ReadFile(out)
		if err != nil {
			t.Fatal(err)
		}
		rg, err := pack.FindRegion(c.vm)
		if err != nil {
			t.Fatal(err)
		}
		if len(b) != len(c.vm) || binary.LittleEndian.Uint32(b[rg.Offset:]) != pack.ImageMagic {
			t.Errorf("%q: no image where the VM's arena is", c.args)
		}
		if !bytes.Equal(b[:rg.Offset], c.vm[:rg.Offset]) {
			t.Errorf("%q: the VM before its arena changed", c.args)
		}
	}
	if _, _, err := build("obeam", []string{"-o", filepath.Join(dir, "d.binary")}); err == nil {
		t.Error("no files, and no error")
	}
}

// TestSD writes the file the P2 boots from an SD card, and refuses -sd where
// obeam would load what it wrote.
func TestSD(t *testing.T) {
	hello, err := filepath.Abs("erl/hello.beam")
	if err != nil {
		t.Fatal(err)
	}
	t.Chdir(t.TempDir())
	out, _, err := build("obeam", []string{"-sd", hello})
	if err != nil {
		t.Fatal(err)
	}
	if out != bootFile {
		t.Errorf("-sd wrote %s", out)
	}
	if b, err := os.ReadFile(bootFile); err != nil || len(b) != len(vmbin.Checked) {
		t.Errorf("%s: %d bytes, %v", bootFile, len(b), err)
	}
	for _, cmd := range []string{"run", "flash"} {
		if _, _, err := build(cmd, []string{"-sd", hello, "-o", "x.binary"}); err == nil {
			t.Errorf("%s -sd: no error", cmd)
		}
		if _, err := os.Stat("x.binary"); err == nil {
			t.Errorf("%s -sd wrote a file", cmd)
		}
	}
}
