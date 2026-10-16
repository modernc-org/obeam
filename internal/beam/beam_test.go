// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package beam

import (
	"bytes"
	"fmt"
	"math/big"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
	"testing"
)

// corpus is the modules in erl/, compiled by make beam.
func corpus(t *testing.T) []string {
	t.Helper()
	files, err := filepath.Glob("../../erl/*.beam")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Skip("no corpus: run make beam")
	}
	sort.Strings(files)
	return files
}

func TestCorpus(t *testing.T) {
	for _, path := range corpus(t) {
		t.Run(filepath.Base(path), func(t *testing.T) {
			f, err := ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			if want := strings.TrimSuffix(filepath.Base(path), ".beam"); f.Module != want {
				t.Errorf("module %q, want %q", f.Module, want)
			}
			fns, err := f.Functions()
			if err != nil {
				t.Fatal(err)
			}
			if len(fns) != int(f.Code.FunctionCount) {
				t.Errorf("%d functions, the header says %d", len(fns), f.Code.FunctionCount)
			}
			labels := map[int64]bool{}
			for _, in := range f.Code.Instrs {
				if in.Op == OpLabel {
					l := in.Args[0].Val
					if labels[l] {
						t.Errorf("label %d twice", l)
					}
					if l <= 0 || l >= int64(f.Code.LabelCount) {
						t.Errorf("label %d outside 1..%d", l, f.Code.LabelCount-1)
					}
					labels[l] = true
				}
			}
			if len(labels) != int(f.Code.LabelCount)-1 {
				t.Errorf("%d labels, the header says %d", len(labels), f.Code.LabelCount-1)
			}
			entries := map[string]int{}
			for _, fn := range fns {
				entries[fmt.Sprintf("%s/%d", fn.Name, fn.Arity)] = fn.Entry
			}
			for _, e := range f.Exports {
				key := fmt.Sprintf("%s/%d", e.Name, e.Arity)
				if entry, ok := entries[key]; !ok {
					t.Errorf("export %s is no function", key)
				} else if entry != e.Label {
					t.Errorf("export %s at label %d, its function begins at %d", key, e.Label, entry)
				}
			}
			for _, in := range f.Code.Instrs {
				if imp := importOperand(in.Op); imp >= 0 {
					if _, ok := f.Import(in); !ok {
						t.Errorf("%s at %d: import %v not in the table of %d", in.Op, in.Offset, in.Args[imp], len(f.Imports))
					}
				}
				var check func(a Arg)
				check = func(a Arg) {
					switch a.Kind {
					case ArgLiteral:
						if a.Val < 0 || a.Val >= int64(len(f.Literals)) {
							t.Errorf("%s at %d: literal %d of %d", in.Op, in.Offset, a.Val, len(f.Literals))
						}
					case ArgAtom:
						if _, err := f.atom(a.Val); err != nil {
							t.Errorf("%s at %d: %v", in.Op, in.Offset, err)
						}
					case ArgF:
						if a.Val != 0 && !labels[a.Val] {
							t.Errorf("%s at %d: label %d does not exist", in.Op, in.Offset, a.Val)
						}
					case ArgList:
						for _, e := range a.List {
							check(e)
						}
					}
				}
				for _, a := range in.Args {
					check(a)
				}
				if in.Op == OpLine {
					if _, _, ok := f.Lines.Location(in.Args[0].Val); !ok && in.Args[0].Val != 0 {
						t.Errorf("line %d has no location", in.Args[0].Val)
					}
				}
				if s := f.Format(in); !strings.HasPrefix(s, "{") || !strings.HasSuffix(s, "}") {
					t.Errorf("Format: %q", s)
				}
			}
			if f.Lines != nil {
				n := 0
				for _, in := range f.Code.Instrs {
					if in.Op == OpLine {
						n++
					}
				}
				if n != int(f.Lines.Count) {
					t.Errorf("%d line instructions, the Line chunk says %d", n, f.Lines.Count)
				}
			}
			var buf bytes.Buffer
			if err := f.WriteListing(&buf); err != nil {
				t.Fatal(err)
			}
			if !strings.Contains(buf.String(), "{function, module_info, 0, ") {
				t.Errorf("listing has no module_info/0:\n%s", buf.String())
			}
		})
	}
}

// TestOracle holds the reader to OTP's own disassembler: erl/oracle.escript
// prints each function's opcodes as beam_disasm finds them. beam_disasm writes
// the labels and lines before a func_info in the reverse order for every
// function but the first, so that prefix is compared as a set.
func TestOracle(t *testing.T) {
	escript, err := exec.LookPath("escript")
	if err != nil {
		t.Skip("no escript on PATH")
	}
	for _, path := range corpus(t) {
		t.Run(filepath.Base(path), func(t *testing.T) {
			out, err := exec.Command(escript, "../../erl/oracle.escript", path).Output()
			if err != nil {
				t.Fatalf("oracle: %v", err)
			}
			want := strings.Split(strings.TrimSpace(string(out)), "\n")
			f, err := ReadFile(path)
			if err != nil {
				t.Fatal(err)
			}
			fns, err := f.Functions()
			if err != nil {
				t.Fatal(err)
			}
			var got []string
			for _, fn := range fns {
				var ops []string
				for _, in := range fn.Instrs {
					ops = append(ops, in.Op.String())
				}
				got = append(got, fmt.Sprintf("%s/%d: %s", atomString(fn.Name), fn.Arity, strings.Join(ops, " ")))
			}
			if len(got) != len(want) {
				t.Fatalf("%d functions, the oracle has %d:\n%s\n--- oracle:\n%s", len(got), len(want), strings.Join(got, "\n"), strings.Join(want, "\n"))
			}
			for i := range got {
				if normalize(got[i]) != normalize(want[i]) {
					t.Errorf("function %d differs:\n%s\n--- oracle:\n%s", i, got[i], want[i])
				}
			}
		})
	}
}

// normalize sorts the opcodes before func_info, where beam_disasm's order is
// not the code's.
func normalize(line string) string {
	head, ops, ok := strings.Cut(line, ": ")
	if !ok {
		return line
	}
	words := strings.Fields(ops)
	for i, w := range words {
		if w == "func_info" {
			sort.Strings(words[:i])
			break
		}
	}
	return head + ": " + strings.Join(words, " ")
}

// encodeOperand encodes a value as beam_asm's encode/2 does, to test the
// decoder against.
func encodeOperand(tag byte, n *big.Int) []byte {
	if n.Sign() >= 0 && n.Cmp(big.NewInt(16)) < 0 {
		return []byte{byte(n.Int64())<<4 | tag}
	}
	if n.Sign() >= 0 && n.Cmp(big.NewInt(0x800)) < 0 {
		v := n.Int64()
		return []byte{byte((v>>3)&0xe0) | tag | 0x08, byte(v)}
	}
	var bs []byte
	switch {
	case n.Sign() >= 0:
		bs = n.Bytes()
		if bs[0]&0x80 != 0 {
			bs = append([]byte{0}, bs...)
		}
	case n.Cmp(big.NewInt(-0x8000)) >= 0:
		v := uint16(int16(n.Int64()))
		bs = []byte{byte(v >> 8), byte(v)}
	default:
		size := len(new(big.Int).Neg(n).Bytes())
		tc := new(big.Int).Add(n, new(big.Int).Lsh(big.NewInt(1), uint(8*size)))
		bs = tc.Bytes()
		for len(bs) < size {
			bs = append([]byte{0}, bs...)
		}
		if bs[0]&0x80 == 0 {
			bs = append([]byte{0xff}, bs...)
		}
	}
	if num := len(bs); num <= 8 {
		return append([]byte{byte((num-2)<<5) | 0x18 | tag}, bs...)
	}
	out := append([]byte{0xf8 | tag}, encodeOperand(0, big.NewInt(int64(len(bs)-9)))...)
	return append(out, bs...)
}

func TestCompactTerm(t *testing.T) {
	values := []string{
		"0", "1", "15", "16", "255", "2047", "2048", "32767", "32768", "65535", "65536",
		"1048576", "2147483647", "2147483648", "4294967295", "4294967296",
		"1099511627776", "4611686018427387903", "9223372036854775807",
		"18446744073709551615", "18446744073709551616", "1267650600228229401496703205376",
		"-1", "-15", "-16", "-255", "-256", "-32768", "-32769", "-65536", "-2147483648",
		"-2147483649", "-1099511627776", "-9223372036854775808", "-9223372036854775809",
		"-1267650600228229401496703205376",
	}
	for tag := byte(0); tag < 7; tag++ {
		for _, s := range values {
			n, _ := new(big.Int).SetString(s, 10)
			if n.Sign() < 0 && tag != 1 {
				continue // only an integer operand is negative
			}
			d := &decoder{b: encodeOperand(tag, n)}
			a, err := d.arg()
			if err != nil {
				t.Errorf("tag %d, %s: %v", tag, s, err)
				continue
			}
			if d.pos != len(d.b) {
				t.Errorf("tag %d, %s: %d of %d bytes read", tag, s, d.pos, len(d.b))
			}
			if a.Kind != ArgKind(tag) {
				t.Errorf("tag %d, %s: kind %s", tag, s, a.Kind)
			}
			got := big.NewInt(a.Val)
			if a.Big != nil {
				got = a.Big
			}
			if got.Cmp(n) != 0 {
				t.Errorf("tag %d, %s: decoded %s (%d bytes % x)", tag, s, got, len(d.b), d.b)
			}
		}
	}
}

func TestETF(t *testing.T) {
	for _, c := range []struct {
		in   []byte
		want string
	}{
		{[]byte{131, 97, 5}, "5"},
		{[]byte{131, 98, 255, 255, 255, 255}, "-1"},
		{[]byte{131, 98, 0, 0, 1, 0}, "256"},
		{[]byte{131, 106}, "[]"},
		{[]byte{131, 107, 0, 2, 104, 105}, `"hi"`},
		{[]byte{131, 107, 0, 2, 1, 2}, "[1,2]"},
		{[]byte{131, 108, 0, 0, 0, 1, 97, 1, 106}, "[1]"},
		{[]byte{131, 108, 0, 0, 0, 1, 97, 1, 97, 2}, "[1|2]"},
		{[]byte{131, 104, 2, 119, 2, 111, 107, 97, 1}, "{ok,1}"},
		{[]byte{131, 104, 0}, "{}"},
		{[]byte{131, 100, 0, 3, 'f', 'u', 'n'}, "'fun'"},
		{[]byte{131, 115, 2, 'O', 'k'}, "'Ok'"},
		{[]byte{131, 118, 0, 3, 'a', '_', '1'}, "a_1"},
		{[]byte{131, 109, 0, 0, 0, 2, 104, 105}, `<<"hi">>`},
		{[]byte{131, 109, 0, 0, 0, 2, 1, 2}, "<<1,2>>"},
		{[]byte{131, 109, 0, 0, 0, 0}, "<<>>"},
		{[]byte{131, 77, 0, 0, 0, 1, 3, 160}, "<<5:3>>"},
		{[]byte{131, 110, 1, 0, 255}, "255"},
		{[]byte{131, 110, 1, 1, 255}, "-255"},
		{[]byte{131, 110, 9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1}, "18446744073709551616"},
		{[]byte{131, 70, 63, 248, 0, 0, 0, 0, 0, 0}, "1.5"},
		{[]byte{131, 70, 64, 89, 0, 0, 0, 0, 0, 0}, "100.0"},
		{[]byte{131, 116, 0, 0, 0, 1, 119, 1, 97, 97, 1}, "#{a => 1}"},
		{[]byte{131, 113, 119, 6, 'e', 'r', 'l', 'a', 'n', 'g', 119, 6, 'l', 'e', 'n', 'g', 't', 'h', 97, 1}, "fun erlang:length/1"},
	} {
		got, err := DecodeETF(c.in)
		if err != nil {
			t.Errorf("% x: %v", c.in, err)
			continue
		}
		if s := got.String(); s != c.want {
			t.Errorf("% x: %s, want %s", c.in, s, c.want)
		}
	}
	for _, bad := range [][]byte{
		{}, {130, 97, 5}, {131}, {131, 97}, {131, 104, 1}, {131, 97, 5, 0}, {131, 88, 0},
	} {
		if _, err := DecodeETF(bad); err == nil {
			t.Errorf("% x: no error", bad)
		}
	}
}

func TestFormatFloat(t *testing.T) {
	for _, c := range []struct {
		f    float64
		want string
	}{
		{1.5, "1.5"}, {100, "100.0"}, {0, "0.0"}, {-2.25, "-2.25"}, {0.001, "0.001"},
		{0.0001, "1.0e-4"}, {1e14, "100000000000000.0"}, {1e15, "1.0e15"}, {123456789, "123456789.0"},
		{1.5e-7, "1.5e-7"}, {6.02214076e23, "6.02214076e23"},
	} {
		if got := formatFloat(c.f); got != c.want {
			t.Errorf("%v: %s, want %s", c.f, got, c.want)
		}
	}
}

func TestAtoms(t *testing.T) {
	for _, c := range []struct{ in, want string }{
		{"ok", "ok"}, {"Ok", "'Ok'"}, {"", "''"}, {"a b", "'a b'"}, {"try", "'try'"},
		{"+", "'+'"}, {"a@b", "a@b"}, {"_x", "'_x'"}, {"it's", `'it\'s'`}, {"x\ny", `'x\ny'`},
	} {
		if got := atomString(c.in); got != c.want {
			t.Errorf("%q: %s, want %s", c.in, got, c.want)
		}
	}
}
