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
	"testing"
	"time"

	p2 "modernc.org/obeam/internal/p2twin"
	"modernc.org/obeam/internal/pack"
)

// uses names the modules a module of the corpus calls, which are packed with
// it, and exUses those of an Elixir module of ex/.
var (
	uses = map[string][]string{
		"bench": {"fib", "lst", "tuples", "pingpong", "ring", "sieve"},
	}
	exUses = map[string][]string{
		"Maps": {"Point"},
	}
)

// TestErl runs the modules of the corpus the VM can run, packed in memory,
// and holds their output to what erl prints for the same module. It runs in
// the twin, scripts/twin.sh, which says where the corpus is. Each module runs
// twice: with the general handlers alone, as on the board, and with the fast
// ones, which are what the core is written after.
func TestErl(t *testing.T) {
	root := os.Getenv("OBEAM_ROOT")
	if root == "" {
		t.Skip("OBEAM_ROOT unset: run through scripts/twin.sh")
	}
	erl, err := exec.LookPath("erl")
	if err != nil {
		t.Skip("no erl on PATH")
	}
	for _, m := range []string{"fac", "fib", "lst", "tuples", "funs", "pingpong", "ring", "sieve", "counter", "exc", "links", "sup", "flt", "fmt", "mp", "bin", "bench"} {
		t.Run(m, func(t *testing.T) {
			var files []string
			for _, mod := range append([]string{m}, uses[m]...) {
				files = append(files, filepath.Join(root, "erl", mod+".beam"))
			}
			libs, err := filepath.Glob(filepath.Join(root, "erl", "shim", "*.beam"))
			if err != nil {
				t.Fatal(err)
			}
			img, err := pack.Pack(files, pack.Options{Lines: true, Lib: libs})
			if err != nil {
				t.Fatal(err)
			}
			want, err := exec.Command(erl, "-noshell", "-pa", filepath.Join(root, "erl"), "-eval", m+":main(), halt().").Output()
			if err != nil {
				t.Fatalf("erl: %v", err)
			}
			for _, fast := range []bool{false, true} {
				useFast(fast)
				got := runImage(img)
				if !bytes.Equal(got, want) {
					t.Errorf("the VM printed, fast handlers %v:\n%s--- erl printed:\n%s", fast, got, want)
				}
			}
		})
	}
}

var fastOn bool

// useFast puts the fast handlers in their opcodes' places, or the general ones
// back, while no scheduler runs. It is here, in the twin only, because a
// function whose address the board's program takes is linked even when
// nothing calls the function that takes it.
func useFast(on bool) {
	if on == fastOn {
		return
	}
	fastOn = on
	if !on {
		for op := range slow {
			if slow[op] != nil {
				handlers[op] = slow[op]
				slow[op] = nil
			}
		}
		return
	}
	fast(opMove, fMove)
	fast(opSwap, fSwap)
	fast(opGetList, fGetList)
	fast(opGetHd, fGetHd)
	fast(opGetTl, fGetTl)
	fast(opPutList, fPutList)
	fast(opGetTupleElement, fGetTupleElement)
	fast(opIsNil, fIsNil)
	fast(opIsNonemptyList, fIsNonemptyList)
	fast(opIsTuple, fIsTuple)
	fast(opTestArity, fTestArity)
	fast(opIsTaggedTuple, fIsTaggedTuple)
	fast(opIsEqExact, fIsEqExact)
	fast(opIsNeExact, fIsNeExact)
	fast(opIsEq, fIsEq)
	fast(opIsNe, fIsNe)
	fast(opIsLt, fIsLt)
	fast(opIsGe, fIsGe)
	fast(opSelectVal, fSelectVal)
	fast(opCall, fCall)
	fast(opCallLast, fCallLast)
	fast(opCallOnly, fCallOnly)
	fast(opAllocate, fAllocate)
	fast(opDeallocate, fDeallocate)
	fast(opInitYregs, fInitYregs)
	fast(opTestHeap, fTestHeap)
	fast(opGcBif2, fGcBif2)
}

// The output goes into a buffer; the locks and the clocks are internal/p2twin's.
var testOut []byte

func testWrite(b byte) { testOut = append(testOut, b) }

// The schedulers the tests run on: as many as the board has.
const testSchedulers = 7

// runImage loads an image, runs its entry on testSchedulers schedulers, and
// returns what it printed. A run that takes more than a minute is given up,
// with the process table dumped after what it printed.
func runImage(img *pack.Image) []byte {
	p2.Sink = testWrite
	region, err := img.Region()
	if err != nil {
		return []byte(err.Error() + "\n")
	}
	if len(region) > arenaLongs {
		return []byte("the image is larger than the arena\n")
	}
	copy(arena[:], region)
	if !Load() {
		return []byte("Load found no image\n")
	}
	testOut = testOut[:0]
	if !Start(Entry(), testSchedulers) {
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

// TestElixir runs the Elixir modules of ex/, packed with the shims of
// ex/shim, and holds what they print to what elixir prints for the same
// module, which runs Elixir's own library: the shims are not on its path.
func TestElixir(t *testing.T) {
	root := os.Getenv("OBEAM_ROOT")
	if root == "" {
		t.Skip("OBEAM_ROOT unset: run through scripts/twin.sh")
	}
	elixir, err := exec.LookPath("elixir")
	if err != nil {
		t.Skip("no elixir on PATH")
	}
	shims, err := filepath.Glob(filepath.Join(root, "ex", "shim", "*.beam"))
	if err != nil {
		t.Fatal(err)
	}
	erlShims, err := filepath.Glob(filepath.Join(root, "erl", "shim", "*.beam"))
	if err != nil {
		t.Fatal(err)
	}
	shims = append(shims, erlShims...)
	for _, m := range []string{"Hello", "Fac", "Ping", "Ring", "Enums", "Strings", "Maps"} {
		t.Run(m, func(t *testing.T) {
			var files []string
			for _, mod := range append([]string{m}, exUses[m]...) {
				files = append(files, filepath.Join(root, "ex", "Elixir."+mod+".beam"))
			}
			img, err := pack.Pack(files, pack.Options{Entry: "Elixir." + m + ":main/0", Lines: true, Lib: shims})
			if err != nil {
				t.Fatal(err)
			}
			want, err := exec.Command(elixir, "-pa", filepath.Join(root, "ex"), "-e", m+".main()").Output()
			if err != nil {
				t.Fatalf("elixir: %v", err)
			}
			for _, fast := range []bool{false, true} {
				useFast(fast)
				got := runImage(img)
				if !bytes.Equal(got, want) {
					t.Errorf("the VM printed, fast handlers %v:\n%s--- elixir printed:\n%s", fast, got, want)
				}
			}
		})
	}
}
