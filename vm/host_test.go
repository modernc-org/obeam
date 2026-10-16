//go:build twin

// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package vm

import (
	"bytes"
	"math"
	"math/rand"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strconv"
	"strings"
	"sync"
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
	for _, m := range []string{"fac", "fib", "lst", "tuples", "funs", "pingpong", "ring", "sieve", "counter", "exc", "links", "flt", "fmt"} {
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

// The host's hooks: the output into a buffer, the clock, the locks as
// mutexes with TryLock, and a pause that lets another goroutine run.
var (
	testOut   []byte
	testStart = time.Now()
	testMus   [16]sync.Mutex
	testLocks int
)

func testWrite(b byte)       { testOut = append(testOut, b) }
func testMillis() uint32     { return uint32(time.Since(testStart).Milliseconds()) }
func testIdle()              { runtime.Gosched() }
func testTryLock(l int) bool { return testMus[l].TryLock() }
func testUnlock(l int)       { testMus[l].Unlock() }

func testNewLock() int {
	l := testLocks
	testLocks++
	return l
}

// The schedulers the tests run on: as many as the board has.
const testSchedulers = 7

// runImage loads an image, runs its entry on testSchedulers schedulers, and
// returns what it printed. A run that takes more than a minute is given up,
// with the process table dumped after what it printed.
func runImage(img *pack.Image) []byte {
	Out = testWrite
	Millis = testMillis
	Idle = testIdle
	NewLock = testNewLock
	TryLock = testTryLock
	Unlock = testUnlock
	Load(img.Code, img.Literals, img.Atoms, img.Funcs, img.Funs, img.Lines, img.Files)
	testOut = testOut[:0]
	if !Start(img.Entry, testSchedulers) {
		return []byte("no room for the first process\n")
	}
	deadline := time.Now().Add(time.Minute)
	for !Finished() {
		if time.Now().After(deadline) {
			Dump()
			lock(lockRun)
			stopping = true
			unlock(lockRun)
			break
		}
		runtime.Gosched()
	}
	for Running() > 0 {
		runtime.Gosched()
	}
	return append([]byte(nil), testOut...)
}

// TestShortest holds the digit search of writeFloat to Go's, which finds the
// fewest digits that read back as the same 32-bit float when asked for
// strconv.FormatFloat(f, 'e', -1, 32): the digits and the exponent must be
// the same, for the powers of ten and of two, the ends of the range, and a
// hundred thousand floats of random bits.
func TestShortest(t *testing.T) {
	var fs []float32
	for e := -45; e <= 38; e++ {
		f := float32(math.Pow(10, float64(e)))
		fs = append(fs, f, math.Nextafter32(f, 0), math.Nextafter32(f, math.MaxFloat32))
	}
	for e := -149; e <= 127; e++ {
		fs = append(fs, float32(math.Ldexp(1, e)))
	}
	fs = append(fs, math.MaxFloat32, math.SmallestNonzeroFloat32, 0.1, 0.3, 1.0/3, 0.0015, 16777216, 16777215)
	rng := rand.New(rand.NewSource(1))
	for len(fs) < 100000 {
		f := math.Float32frombits(rng.Uint32() & 0x7fffffff)
		if f != 0 && !math.IsInf(float64(f), 0) && !math.IsNaN(float64(f)) {
			fs = append(fs, f)
		}
	}
	s := &scheds[0]
	for _, f := range fs {
		if f == 0 {
			continue
		}
		want := strconv.FormatFloat(float64(f), 'e', -1, 32)
		mant, exp, _ := strings.Cut(want, "e")
		mant = strings.Replace(mant, ".", "", 1)
		wantE, _ := strconv.Atoi(exp)
		var d [12]byte
		n, e := shortest(s, math.Float32bits(f), &d)
		if got := string(d[:n]); got != mant || e != wantE {
			t.Fatalf("%v (%#08x): digits %s e%d, Go's %s e%d", f, math.Float32bits(f), got, e, mant, wantE)
		}
	}
}
