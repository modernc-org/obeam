// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package p2 is the part of OctoGo's p2 package the VM uses, in Go, for the
// twin: scripts/twin.sh has a package that imports "p2" import this one. The
// sixteen hardware locks are mutexes, the clocks the host's, a wait lets
// another goroutine run, and the serial line is Sink, the test's buffer.
package p2

import (
	"math/rand"
	"runtime"
	"sync"
	"time"
)

var (
	// Sink is where WriteByte writes, the test's buffer.
	Sink func(b byte)

	rnd   = rand.New(rand.NewSource(1))
	rndMu sync.Mutex

	locks    [16]sync.Mutex
	nextLock int
	newMu    sync.Mutex
	start    = time.Now()
)

// NewLock answers a lock, the last one again once all sixteen are out, as
// the P2's does.
func NewLock() int {
	newMu.Lock()
	defer newMu.Unlock()
	l := nextLock
	if nextLock < len(locks)-1 {
		nextLock++
	}
	return l
}

func TryLock(l int) bool { return locks[l].TryLock() }
func Unlock(l int)       { locks[l].Unlock() }
func GetMs() uint32      { return uint32(time.Since(start).Milliseconds()) }
func GetCt() uint32      { return uint32(time.Since(start).Nanoseconds() * 16 / 100) }
func WaitUs(us int)      { runtime.Gosched() }

// WriteByte writes a byte to the serial line, which is Sink.
func WriteByte(b byte) {
	if Sink != nil {
		Sink(b)
	}
}

// ClockFreq is the board's clock at its default.
func ClockFreq() uint32 { return 160000000 }

// Rnd is a random number, the same sequence on every run.
func Rnd() uint32 {
	rndMu.Lock()
	defer rndMu.Unlock()
	return rnd.Uint32()
}
