//go:build twin

// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package vm

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"modernc.org/obeam/internal/pack"
)

// TestErl runs the modules of the corpus the VM can run, packed in memory,
// and holds their output to what erl prints for the same module. It runs in
// the twin, scripts/twin.sh, which says where the corpus is.
func TestErl(t *testing.T) {
	root := os.Getenv("OBEAM_ROOT")
	if root == "" {
		t.Skip("OBEAM_ROOT unset: run through scripts/twin.sh")
	}
	erl, err := exec.LookPath("erl")
	if err != nil {
		t.Skip("no erl on PATH")
	}
	for _, m := range []string{"fac", "fib", "lst", "tuples", "funs", "pingpong", "ring", "sieve", "counter"} {
		t.Run(m, func(t *testing.T) {
			img, err := pack.Pack([]string{filepath.Join(root, "erl", m+".beam")}, pack.Options{Lines: true})
			if err != nil {
				t.Fatal(err)
			}
			want, err := exec.Command(erl, "-noshell", "-pa", filepath.Join(root, "erl"), "-eval", m+":main(), halt().").Output()
			if err != nil {
				t.Fatalf("erl: %v", err)
			}
			got := runImage(img)
			if !bytes.Equal(got, want) {
				t.Errorf("the VM printed:\n%s--- erl printed:\n%s", got, want)
			}
		})
	}
}

var (
	testOut   []byte
	testStart = time.Now()
)

func testWrite(b byte) { testOut = append(testOut, b) }

func testMillis() uint32 { return uint32(time.Since(testStart).Milliseconds()) }

// runImage loads an image, runs its entry and returns what it printed.
func runImage(img *pack.Image) []byte {
	Load(img.Code, img.Literals, img.Atoms, img.Funcs, img.Funs, img.Lines, img.Files)
	Out = testWrite
	Millis = testMillis
	testOut = testOut[:0]
	Run(img.Entry)
	return append([]byte(nil), testOut...)
}
