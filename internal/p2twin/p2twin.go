// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package p2 is the part of OctoGo's p2 package the VM uses, in Go, for the
// twin: scripts/twin.sh has a package that imports "p2" import this one. The
// sixteen hardware locks are mutexes, the clocks the host's, and a wait lets
// another goroutine run.
package p2

import (
	"runtime"
	"sync"
	"time"
)

var (
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
