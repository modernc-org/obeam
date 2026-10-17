// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package vmbin is the VM as the obeam command carries it, built once by make
// vms from the board program, board/, and committed: obeam.binary, checked,
// and obeam-unchecked.binary, without the runtime checks and with the arena
// they leave room for, each with its arena empty and marked, and BUILD, what
// they were built from. obeam puts a program's image into a copy of one.
package vmbin

import (
	"crypto/sha256"
	_ "embed"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
)

var (
	//go:embed obeam.binary
	Checked []byte

	//go:embed obeam-unchecked.binary
	Unchecked []byte

	// Build is two lines: "sources" and the SourceHash the VMs were built
	// from, and "ogo" and the version of the ogo that built them.
	//
	//go:embed BUILD
	Build string
)

// sourceGlobs are the files the VM is built from, under the repository's
// root.
var sourceGlobs = []string{"ogo.mod", "board/*.ogo", "vm/*.ogo", "core/*.ogo", "core/*.spin2"}

// SourceHash answers the SHA-256 of the VM's sources under root: each file's
// path, length and bytes, in the order of their paths.
func SourceHash(root string) (string, error) {
	var paths []string
	for _, g := range sourceGlobs {
		m, err := filepath.Glob(filepath.Join(root, g))
		if err != nil {
			return "", err
		}
		paths = append(paths, m...)
	}
	if len(paths) == 0 {
		return "", fmt.Errorf("no VM sources under %s", root)
	}
	sort.Strings(paths)
	h := sha256.New()
	for _, p := range paths {
		b, err := os.ReadFile(p)
		if err != nil {
			return "", err
		}
		rel, err := filepath.Rel(root, p)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(h, "%s\x00%d\x00", filepath.ToSlash(rel), len(b))
		h.Write(b)
	}
	return fmt.Sprintf("%x", h.Sum(nil)), nil
}

// Field answers the value of a line of Build: "sources" or "ogo".
func Field(name string) string {
	for _, line := range strings.Split(Build, "\n") {
		if k, v, ok := strings.Cut(line, " "); ok && k == name {
			return v
		}
	}
	return ""
}

// WriteBuild writes BUILD for the sources under root and the ogo version that
// built the VMs.
func WriteBuild(path, root, ogo string) error {
	h, err := SourceHash(root)
	if err != nil {
		return err
	}
	return os.WriteFile(path, []byte(fmt.Sprintf("sources %s\nogo %s\n", h, strings.TrimSpace(ogo))), 0o644)
}
