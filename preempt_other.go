// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

//go:build !unix

package main

// noPreempt does nothing on Windows, which preempts a goroutine without a
// signal; whether its loads fail as the Mac's did is not known yet.
func noPreempt() {}
