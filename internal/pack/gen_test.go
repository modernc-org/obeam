// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"os"
	"path/filepath"
	"testing"
)

// TestCoreGenerated holds core/core.spin2 to what obeam gen writes from
// core/core.pasm and CoreOps: an edit of either without go run ./cmd/obeam gen
// fails here, where the board would otherwise run a core whose table is not
// the packer's.
func TestCoreGenerated(t *testing.T) {
	src := filepath.Join("..", "..", "core")
	tmp := t.TempDir()
	b, err := os.ReadFile(filepath.Join(src, "core.pasm"))
	if os.IsNotExist(err) {
		t.Skip("no core here: the twin leaves it out")
	}
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tmp, "core.pasm"), b, 0o644); err != nil {
		t.Fatal(err)
	}
	if err := GenCore(tmp); err != nil {
		t.Fatal(err)
	}
	want, err := os.ReadFile(filepath.Join(tmp, "core.spin2"))
	if err != nil {
		t.Fatal(err)
	}
	got, err := os.ReadFile(filepath.Join(src, "core.spin2"))
	if err != nil {
		t.Fatal(err)
	}
	if string(got) != string(want) {
		t.Fatal("core/core.spin2 is not what core/core.pasm and CoreOps make: run go run ./cmd/obeam gen -vm vm -names prof")
	}
}
