// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package vmbin

import (
	"os"
	"path/filepath"
	"testing"

	"modernc.org/obeam/internal/pack"
)

// TestFresh holds the VMs obeam carries to the sources: a change to the VM
// without make vms fails here, where obeam would otherwise put programs into
// a VM that is not the one the tree describes.
func TestFresh(t *testing.T) {
	root := os.Getenv("OBEAM_ROOT")
	if root == "" {
		root = filepath.Join("..", "..")
	}
	if m, _ := filepath.Glob(filepath.Join(root, "vm", "*.ogo")); len(m) == 0 {
		t.Skip("no VM sources here")
	}
	h, err := SourceHash(root)
	if err != nil {
		t.Fatal(err)
	}
	if got := Field("sources"); got != h {
		t.Fatalf("the VMs in internal/vmbin were built from other sources than the tree's: make vms\n\tbuilt from %s\n\tthe tree   %s", got, h)
	}
}

// TestBootable holds each VM's binary to the 496 KB the P2's ROM loads from
// an SD card: a larger _BOOT_P2.BIX does not boot, and the board then answers
// no serial loader either.
func TestBootable(t *testing.T) {
	const most = 512*1024 - 16*1024
	for name, b := range map[string][]byte{"checked": Checked, "unchecked": Unchecked} {
		if len(b) > most {
			t.Errorf("the %s VM is %d bytes, %d more than the ROM loads from an SD card: make its arena smaller", name, len(b), len(b)-most)
		}
	}
}

// TestRegions finds each VM's arena and checks that the unchecked one has the
// larger.
func TestRegions(t *testing.T) {
	c, err := pack.FindRegion(Checked)
	if err != nil {
		t.Fatalf("checked: %v", err)
	}
	u, err := pack.FindRegion(Unchecked)
	if err != nil {
		t.Fatalf("unchecked: %v", err)
	}
	if u.Longs <= c.Longs {
		t.Errorf("the unchecked VM's arena is %d longs, the checked one's %d", u.Longs, c.Longs)
	}
}
