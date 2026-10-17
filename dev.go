// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"sort"
	"strings"

	"modernc.org/obeam/internal/beam"
	"modernc.org/obeam/internal/pack"
	"modernc.org/obeam/internal/vmbin"
)

// The commands for OctoBeam's developers: listings, counts, and the VM's
// generated sources.

func each(paths []string, do func(w *bufio.Writer, f *beam.File) error) error {
	if len(paths) == 0 {
		return fmt.Errorf("no file named")
	}
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	for _, path := range paths {
		f, err := beam.ReadFile(path)
		if err != nil {
			return err
		}
		if err := do(w, f); err != nil {
			return fmt.Errorf("%s: %w", path, err)
		}
	}
	return nil
}

func dis(w *bufio.Writer, f *beam.File) error {
	return f.WriteListing(w)
}

func chunks(w *bufio.Writer, f *beam.File) error {
	fmt.Fprintf(w, "%s: module %s, %d chunks\n", f.Name, f.Module, len(f.Chunks))
	for _, c := range f.Chunks {
		fmt.Fprintf(w, "  %-4s %6d bytes at %d\n", c.ID, len(c.Data), c.Offset)
	}
	fmt.Fprintf(w, "  %d atoms, %d instructions, %d functions, %d labels, %d imports, %d exports, %d literals, %d funs\n",
		len(f.Atoms)-1, len(f.Code.Instrs), f.Code.FunctionCount, f.Code.LabelCount-1, len(f.Imports), len(f.Exports), len(f.Literals), len(f.Funs))
	return nil
}

// A tally counts occurrences of a thing over the modules, and in how many of
// them it occurs.
type tally struct {
	name    string
	count   int
	modules map[string]bool
}

type tallies map[string]*tally

func (ts tallies) add(name, module string) {
	t := ts[name]
	if t == nil {
		t = &tally{name: name, modules: map[string]bool{}}
		ts[name] = t
	}
	t.count++
	t.modules[module] = true
}

// sorted returns the tallies, the most counted first and by name among equals.
func (ts tallies) sorted() []*tally {
	s := make([]*tally, 0, len(ts))
	for _, t := range ts {
		s = append(s, t)
	}
	sort.Slice(s, func(i, j int) bool {
		if s[i].count != s[j].count {
			return s[i].count > s[j].count
		}
		return s[i].name < s[j].name
	})
	return s
}

func stats(paths []string) error {
	if len(paths) == 0 {
		return fmt.Errorf("no file named")
	}
	ops, calls := tallies{}, tallies{}
	var modules []string
	instrs := 0
	for _, path := range paths {
		f, err := beam.ReadFile(path)
		if err != nil {
			return err
		}
		modules = append(modules, f.Module)
		for _, in := range f.Code.Instrs {
			instrs++
			ops.add(in.Op.String(), f.Module)
			if m, ok := f.Import(in); ok {
				calls.add(m.String(), f.Module)
			}
		}
	}
	live := 0
	for _, op := range beam.Opcodes() {
		if !op.Obsolete() {
			live++
		}
	}
	w := bufio.NewWriter(os.Stdout)
	defer w.Flush()
	fmt.Fprintf(w, "%d modules (%s): %d instructions, %d distinct opcodes of the %d live ones in %s\n\n",
		len(modules), strings.Join(modules, " "), instrs, len(ops), live, beam.GenopTag)
	fmt.Fprintf(w, "%7s  %-26s %s\n", "count", "opcode", "modules")
	for _, t := range ops.sorted() {
		fmt.Fprintf(w, "%7d  %-26s %d\n", t.count, t.name, len(t.modules))
	}
	fmt.Fprintf(w, "\n%7s  %-26s %s\n", "sites", "external call", "modules")
	for _, t := range calls.sorted() {
		fmt.Fprintf(w, "%7d  %-26s %d\n", t.count, t.name, len(t.modules))
	}
	return nil
}

func genCmd(args []string) error {
	fs := flag.NewFlagSet("gen", flag.ContinueOnError)
	dir := fs.String("vm", "vm", "the VM's package directory")
	names := fs.String("names", "", "also write the opcodes' and BIFs' names into this directory, for the profiler")
	coreDir := fs.String("core", "core", "the PASM core's directory, whose core.spin2 to write from core.pasm, or empty")
	build := fs.String("build", "", "write only this file, internal/vmbin/BUILD: the hash of the VM's sources and -ogo")
	ogo := fs.String("ogo", "", "with -build: the version of the ogo that built the VMs")
	if err := fs.Parse(args); err != nil {
		return err
	}
	if *build != "" {
		return vmbin.WriteBuild(*build, ".", *ogo)
	}
	if *coreDir != "" {
		if err := pack.GenCore(*coreDir); err != nil {
			return err
		}
	}
	if *names != "" {
		if err := pack.GenNames(*names); err != nil {
			return err
		}
	}
	return pack.GenVM(*dir)
}
