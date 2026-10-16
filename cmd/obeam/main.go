// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Command obeam is the host side of obeam, a BEAM for the Propeller 2: it reads
// the modules Erlang's compiler writes, and will pack them into an image for the
// board.
//
//	obeam dis FILE.beam...      list each module's code, as erlc -S would
//	obeam stats FILE.beam...    count the opcodes and the external calls over the modules
//	obeam chunks FILE.beam...   list each file's chunks
//	obeam pack [-o image.ogo] [-entry m:f/a] [-lines=false] [-lib LIB.beam,...] FILE.beam...
//	                            pack the modules into an image for the board
//	obeam gen [-vm DIR]         write the VM's copies of the opcodes, tags, atoms and BIFs
//	obeam version
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
)

const version = "0.0.0"

func main() {
	if len(os.Args) < 2 {
		usage()
	}
	cmd, args := os.Args[1], os.Args[2:]
	var err error
	switch cmd {
	case "dis":
		err = each(args, dis)
	case "stats":
		err = stats(args)
	case "chunks":
		err = each(args, chunks)
	case "pack":
		err = packCmd(args)
	case "gen":
		err = genCmd(args)
	case "version":
		fmt.Printf("obeam %s, opcodes of Erlang/OTP %s\n", version, beam.GenopTag)
	case "help", "-h", "--help":
		usage()
	default:
		fmt.Fprintf(os.Stderr, "obeam: unknown command %q\n", cmd)
		usage()
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "obeam: %v\n", err)
		os.Exit(1)
	}
}

func usage() {
	fmt.Fprint(os.Stderr, `usage: obeam <command> [arguments]

The commands are:

	dis FILE.beam...      list each module's code, as erlc -S would
	stats FILE.beam...    count the opcodes and the external calls over the modules
	chunks FILE.beam...   list each file's chunks
	pack FILE.beam...     pack the modules into an image for the board:
	                      -o image.ogo (the standard output by default),
	                      -entry m:f/a (the first module's main/0), -lines=false
	gen                   write the VM's copies of the opcodes, tags, atoms and
	                      BIFs: -vm DIR (vm)
	version               print the version and the opcode table's
`)
	os.Exit(2)
}

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

func packCmd(args []string) error {
	fs := flag.NewFlagSet("pack", flag.ContinueOnError)
	out := fs.String("o", "", "write the image here, as the OctoGo package image")
	entry := fs.String("entry", "", "the entry function, module:function/arity")
	lines := fs.Bool("lines", true, "keep the line table for crash messages")
	lib := fs.String("lib", "", "library modules, comma separated: packed by what the program reaches, as the shims are")
	if err := fs.Parse(args); err != nil {
		return err
	}
	var libs []string
	if *lib != "" {
		libs = strings.Split(*lib, ",")
	}
	img, err := pack.Pack(fs.Args(), pack.Options{Entry: *entry, Lines: *lines, Lib: libs})
	if err != nil {
		return err
	}
	w := os.Stdout
	if *out != "" {
		f, err := os.Create(*out)
		if err != nil {
			return err
		}
		defer f.Close()
		w = f
	}
	if err := img.WriteOgo(w); err != nil {
		return err
	}
	fmt.Fprintf(os.Stderr, "obeam pack: %s: %d longs of code, %d of literals, %d atoms, %d functions (%d dropped), %d funs, %d lines\n",
		img.EntryMFA, len(img.Code), len(img.Literals), len(img.Atoms), len(img.Funcs)/4, img.Dropped, len(img.Funs)/3, len(img.Lines)/3)
	return nil
}

func genCmd(args []string) error {
	fs := flag.NewFlagSet("gen", flag.ContinueOnError)
	dir := fs.String("vm", "vm", "the VM's package directory")
	names := fs.String("names", "", "also write the opcodes' and BIFs' names into this directory, for the profiler")
	coreDir := fs.String("core", "core", "the PASM core's directory, whose core.spin2 to write from core.pasm, or empty")
	if err := fs.Parse(args); err != nil {
		return err
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
