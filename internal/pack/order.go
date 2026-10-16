// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package pack

import (
	"bytes"
	"sort"

	"modernc.org/obeam/internal/beam"
)

// compareKeys orders literal terms as the VM orders a map's keys: Erlang's
// order of terms, number < atom < reference < fun < port < pid < tuple < map
// < nil < list < binary, but with every integer before every float, which is
// how a map keeps 1 and 1.0 apart. It is vm/compare.ogo's cmp with exact set,
// and a map laid out here is searched there. Funs compare by their names,
// which the VM does not: a literal map keyed by two funs is refused.
func compareKeys(a, b beam.Term) int {
	ra, rb := keyRank(a), keyRank(b)
	if ra != rb {
		return ra - rb
	}
	switch a.Kind {
	case beam.TermInt:
		return cmp3(a.Int < b.Int, a.Int > b.Int)
	case beam.TermFloat:
		return cmp3(a.Float < b.Float, a.Float > b.Float)
	case beam.TermAtom:
		return cmpStrings(a.Atom, b.Atom)
	case beam.TermExport:
		if c := cmpStrings(a.Atom, b.Atom); c != 0 {
			return c
		}
		if c := cmpStrings(a.Elems[0].Atom, b.Elems[0].Atom); c != 0 {
			return c
		}
		return cmp3(a.Elems[1].Int < b.Elems[1].Int, a.Elems[1].Int > b.Elems[1].Int)
	case beam.TermTuple:
		if len(a.Elems) != len(b.Elems) {
			return len(a.Elems) - len(b.Elems)
		}
		for i := range a.Elems {
			if c := compareKeys(a.Elems[i], b.Elems[i]); c != 0 {
				return c
			}
		}
		return 0
	case beam.TermMap:
		if len(a.Elems) != len(b.Elems) {
			return len(a.Elems) - len(b.Elems)
		}
		ka, va := sortedPairs(a)
		kb, vb := sortedPairs(b)
		for i := range ka {
			if c := compareKeys(ka[i], kb[i]); c != 0 {
				return c
			}
		}
		for i := range va {
			if c := compareKeys(va[i], vb[i]); c != 0 {
				return c
			}
		}
		return 0
	case beam.TermList:
		for {
			ha, ta := uncons(a)
			hb, tb := uncons(b)
			if c := compareKeys(ha, hb); c != 0 {
				return c
			}
			if ta.Kind != beam.TermList || tb.Kind != beam.TermList {
				return compareKeys(ta, tb)
			}
			a, b = ta, tb
		}
	case beam.TermBinary:
		return bytes.Compare(a.Bytes, b.Bytes)
	}
	return 0
}

// keyRank is a term's place in the order of terms, integers before floats.
func keyRank(t beam.Term) int {
	switch t.Kind {
	case beam.TermInt, beam.TermBig:
		return 0
	case beam.TermFloat:
		return 1
	case beam.TermAtom:
		return 2
	case beam.TermExport:
		return 4
	case beam.TermTuple:
		return 7
	case beam.TermMap:
		return 8
	case beam.TermNil:
		return 9
	case beam.TermList:
		return 10
	}
	return 11
}

func cmp3(lt, gt bool) int {
	switch {
	case lt:
		return -1
	case gt:
		return 1
	}
	return 0
}

func cmpStrings(a, b string) int {
	switch {
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// uncons splits a non-empty literal list into its head and its tail.
func uncons(t beam.Term) (beam.Term, beam.Term) {
	if len(t.Elems) > 1 {
		return t.Elems[0], beam.Term{Kind: beam.TermList, Elems: t.Elems[1:], Tail: t.Tail}
	}
	if t.Tail != nil {
		return t.Elems[0], *t.Tail
	}
	return t.Elems[0], beam.Term{Kind: beam.TermNil}
}

// sortedPairs answers a literal map's keys in map-key order and their values.
func sortedPairs(m beam.Term) (keys, vals []beam.Term) {
	n := len(m.Elems) / 2
	idx := make([]int, n)
	for i := range idx {
		idx[i] = i
	}
	sort.SliceStable(idx, func(i, j int) bool { return compareKeys(m.Elems[2*idx[i]], m.Elems[2*idx[j]]) < 0 })
	for _, i := range idx {
		keys = append(keys, m.Elems[2*i])
		vals = append(vals, m.Elems[2*i+1])
	}
	return keys, vals
}
