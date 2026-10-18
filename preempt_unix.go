// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build unix

package main

import (
	"os"
	"strings"
	"syscall"
)

// noPreempt starts a command that drives the loader again with the Go
// runtime's asynchronous preemption off, GODEBUG saying so, which no
// //go:debug line can. The loader is FlexProp's loadp2, C made Go and run in
// this process, and a write of it to the serial port cut short is a failure
// to it: "Error writing port", then "timeout waiting for checksum". On a Mac
// eight loads of ten failed so and none of ten with preemption off
// (2026-10-18); on Linux it was seen twice. The process is the same one, so
// the shell, its job control and the exit status see no difference.
func noPreempt() {
	if len(os.Args) < 2 {
		return
	}
	switch os.Args[1] {
	case "run", "flash", "loadp2":
	default:
		return
	}
	g := os.Getenv("GODEBUG")
	if strings.Contains(","+g+",", ",asyncpreemptoff=1,") {
		return
	}
	self, err := os.Executable()
	if err != nil {
		return
	}
	if g != "" {
		g += ","
	}
	env := []string{"GODEBUG=" + g + "asyncpreemptoff=1"}
	for _, e := range os.Environ() {
		if !strings.HasPrefix(e, "GODEBUG=") {
			env = append(env, e)
		}
	}
	syscall.Exec(self, os.Args, env) // when it fails, the command runs as it is
}
