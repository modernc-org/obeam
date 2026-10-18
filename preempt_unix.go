// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build unix

package main

import (
	"os"
	"os/signal"
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
//
// Such a command also ignores Ctrl-Z's signal, SIGTSTP. In loadp2's terminal
// Ctrl-Z leaves it, as Ctrl-] does, the keyboard being raw there; pressed
// before the terminal is up, during the five seconds of a load, it suspended
// obeam, holding the board's port, and the next load failed (2026-10-18, a
// Czech keyboard, where Ctrl-Z is at hand and Ctrl-] is not).
func noPreempt() {
	if len(os.Args) < 2 {
		return
	}
	switch os.Args[1] {
	case "run", "flash", "loadp2":
	default:
		return
	}
	signal.Ignore(syscall.SIGTSTP)
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
