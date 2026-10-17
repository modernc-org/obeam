// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Command obeam is OctoBeam's tool: it puts the modules Erlang's and
// Elixir's compilers write into the VM for the Parallax Propeller 2 it
// carries, as a binary any P2 loader loads, and loads it onto the board.
//
//	obeam [flags] FILE.beam...       write NAME.binary: the VM with the modules in it
//	obeam run [flags] FILE.beam...   the same, then load it onto the board and show what it prints
//	obeam loadp2 ARGS...             the P2 loader, loadp2, as it is
//	obeam version                    what this obeam is
//
// The flags may come before or after the files:
//
//	-o FILE          the binary to write; NAME.binary in the current directory,
//	                 after the entry's module, by default
//	-entry m:f/a     the function to start; the first module's main/0 by default
//	-unchecked       the VM without its runtime checks: 52 KB more for the heaps,
//	                 and faster, but a fault of the VM's corrupts memory silently
//	                 where the checked VM stops with a panic message
//	-lines=false     leave out the line numbers a crash report names
//	-lib A.beam,...  more library modules, packed by what the program reaches
//	-vm FILE         a VM binary of one's own, built by ogo build ./board
//	-p PORT          (run) the serial port; the loader looks for the board by itself
//
// obeam carries the VM built twice, checked and unchecked, and the shims, the
// Erlang modules that stand for the functions of OTP's and Elixir's libraries
// the VM runs: lists, maps, Enum, Map. The board needs nothing else: the
// binary is the whole program, and the VM starts the entry function as its
// first process when it is loaded.
//
// For OctoBeam's developers there are also
//
//	obeam dis FILE.beam...      list each module's code, as erlc -S would
//	obeam stats FILE.beam...    count the opcodes and the external calls over the modules
//	obeam chunks FILE.beam...   list each file's chunks
//	obeam gen [-vm DIR]         write the VM's copies of the opcodes, tags, atoms and BIFs
package main

import (
	"embed"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"runtime"
	"runtime/debug"
	"strings"

	"modernc.org/obeam/internal/beam"
	"modernc.org/obeam/internal/pack"
	"modernc.org/obeam/internal/vmbin"
	"modernc.org/ogo/loadp2"
)

// version, when non-empty, is the release tag stamped into a published binary
// by make release, -ldflags "-X main.version=vX.Y.Z"; otherwise the Go build
// information names the module version or the commit.
var version string

//go:embed erl/shim/*.beam ex/shim/*.beam
var shimFS embed.FS

func main() {
	// loadp2's flags are not obeam's: they go to it untouched.
	if len(os.Args) >= 2 && os.Args[1] == "loadp2" {
		os.Exit(loadp2.SubCommand(os.Args[2:]))
	}
	if len(os.Args) < 2 {
		usage(os.Stderr)
		os.Exit(2)
	}
	cmd, args := os.Args[1], os.Args[2:]
	var err error
	switch cmd {
	case "run":
		var out string
		var o options
		if out, o, err = build("run", args); err == nil {
			fmt.Fprintf(os.Stderr, "obeam: loading %s; Ctrl-] leaves the terminal\n", out)
			if rc := loadp2.Load(loadp2.Options{Binary: out, Port: o.port, Terminal: true}); rc != 0 {
				os.Exit(rc)
			}
		}
	case "build":
		_, _, err = build("build", args)
	case "dis":
		err = each(args, dis)
	case "stats":
		err = stats(args)
	case "chunks":
		err = each(args, chunks)
	case "gen":
		err = genCmd(args)
	case "version":
		printVersion(os.Stdout)
	case "help", "-h", "-help", "--help":
		usage(os.Stdout)
	default:
		if strings.HasPrefix(cmd, "-") || strings.HasSuffix(cmd, ".beam") {
			_, _, err = build("obeam", os.Args[1:])
			break
		}
		fmt.Fprintf(os.Stderr, "obeam: unknown command %q\n", cmd)
		usage(os.Stderr)
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "obeam: %v\n", err)
		os.Exit(1)
	}
}

func usage(w io.Writer) {
	fmt.Fprint(w, `usage: obeam [flags] FILE.beam...      write NAME.binary: the VM with the modules in it
       obeam run [flags] FILE.beam...  the same, then load it onto the board and show what it prints
       obeam loadp2 ARGS...            the P2 loader, loadp2, as it is
       obeam version                   what this obeam is

The flags may come before or after the files:

  -o FILE          the binary to write; NAME.binary in the current directory, after
                   the entry's module, by default
  -entry m:f/a     the function to start; the first module's main/0 by default
  -unchecked       the VM without its runtime checks: 52 KB more for the heaps, and
                   faster, but a fault of the VM's corrupts memory silently where
                   the checked VM stops with a panic message
  -lines=false     leave out the line numbers a crash report names
  -lib A.beam,...  more library modules, packed by what the program reaches
  -vm FILE         a VM binary of one's own, built by ogo build ./board
  -p PORT          (run) the serial port; the loader looks for the board by itself

For example, with a P2 board on a USB port:

  erlc hello.erl && obeam run hello.beam

For OctoBeam's developers: obeam dis, stats, chunks and gen.
`)
}

// options are what build was asked for beside the files.
type options struct {
	out, entry, lib, vm, port string
	unchecked, lines          bool
}

// build packs the modules into a copy of the VM and writes it. It answers the
// binary's path, and the options for run.
func build(name string, args []string) (string, options, error) {
	var o options
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	fs.SetOutput(io.Discard)
	fs.StringVar(&o.out, "o", "", "")
	fs.StringVar(&o.entry, "entry", "", "")
	fs.BoolVar(&o.unchecked, "unchecked", false, "")
	fs.BoolVar(&o.lines, "lines", true, "")
	fs.StringVar(&o.lib, "lib", "", "")
	fs.StringVar(&o.vm, "vm", "", "")
	fs.StringVar(&o.port, "p", "", "")
	var files []string
	for {
		if err := fs.Parse(args); err != nil {
			return "", o, fmt.Errorf("%v (obeam help lists the flags)", err)
		}
		if args = fs.Args(); len(args) == 0 {
			break
		}
		files, args = append(files, args[0]), args[1:]
	}
	// A pattern is expanded here, for the shells that do not, cmd.exe's.
	var expanded []string
	for _, f := range files {
		if !strings.ContainsAny(f, "*?[") {
			expanded = append(expanded, f)
			continue
		}
		m, err := filepath.Glob(f)
		if err != nil || len(m) == 0 {
			return "", o, fmt.Errorf("%s: no such files", f)
		}
		expanded = append(expanded, m...)
	}
	if files = expanded; len(files) == 0 {
		return "", o, errors.New("no .beam file named")
	}
	var libs []string
	if o.lib != "" {
		libs = strings.Split(o.lib, ",")
	}
	shims, err := shims()
	if err != nil {
		return "", o, err
	}
	img, err := pack.Pack(files, pack.Options{Entry: o.entry, Lines: o.lines, Lib: libs, Shims: shims})
	if err != nil {
		return "", o, err
	}
	region, err := img.Region()
	if err != nil {
		return "", o, err
	}
	vm, which := vmbin.Checked, "checked"
	switch {
	case o.vm != "":
		if vm, err = os.ReadFile(o.vm); err != nil {
			return "", o, err
		}
		which = o.vm
	case o.unchecked:
		vm, which = vmbin.Unchecked, "unchecked"
	}
	b, room, err := pack.Patch(vm, region)
	if err != nil {
		return "", o, fmt.Errorf("the VM, %s: %w", which, err)
	}
	if o.out == "" {
		mod, _, _ := strings.Cut(img.EntryMFA, ":")
		o.out = mod + ".binary"
	}
	if err := os.WriteFile(o.out, b, 0o644); err != nil {
		return "", o, err
	}
	fmt.Fprintf(os.Stderr, "obeam: %s: %s, the VM %s; the image %d longs, %d of them code; %d KB of the arena left for the heaps\n",
		o.out, img.EntryMFA, which, len(region), len(img.Code), room*4/1024)
	return o.out, o, nil
}

// shims answers the shims obeam carries.
func shims() ([]pack.Beam, error) {
	var r []pack.Beam
	for _, dir := range []string{"erl/shim", "ex/shim"} {
		es, err := shimFS.ReadDir(dir)
		if err != nil {
			return nil, err
		}
		for _, e := range es {
			b, err := shimFS.ReadFile(path.Join(dir, e.Name()))
			if err != nil {
				return nil, err
			}
			r = append(r, pack.Beam{Name: e.Name(), Data: b})
		}
	}
	return r, nil
}

// printVersion says what a bug report needs: the release or the commit, the
// platform, the opcode table, the ogo that built the VMs, and the Go that
// built obeam.
func printVersion(w io.Writer) {
	ver, revision, modified := "(devel)", "", false
	if version != "" {
		ver = version
	}
	if bi, ok := debug.ReadBuildInfo(); ok {
		if version == "" && bi.Main.Version != "" {
			ver = bi.Main.Version
		}
		for _, s := range bi.Settings {
			switch s.Key {
			case "vcs.revision":
				revision = s.Value
			case "vcs.modified":
				modified = s.Value == "true"
			}
		}
	}
	if ver == "(devel)" && revision != "" {
		if len(revision) > 12 {
			revision = revision[:12]
		}
		ver = revision
	}
	if modified && !strings.HasSuffix(ver, "+dirty") {
		ver += "+dirty"
	}
	fmt.Fprintf(w, "obeam version %s %s/%s\n", ver, runtime.GOOS, runtime.GOARCH)
	fmt.Fprintf(w, "opcodes of Erlang/OTP %s, the VM's tables 0x%08x\n", strings.TrimPrefix(beam.GenopTag, "OTP-"), pack.TableID())
	fmt.Fprintf(w, "the VMs built by %s\n", vmbin.Field("ogo"))
	fmt.Fprintf(w, "built with %s\n", runtime.Version())
}
