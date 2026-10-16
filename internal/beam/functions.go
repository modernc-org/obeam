// Copyright 2026 The obeam Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

package beam

import "fmt"

// A Function is a function of the module, as the code's func_info
// instructions delimit them.
type Function struct {
	Name   string
	Arity  int
	Entry  int     // the label the function's code begins at
	Instrs []Instr // from its first label to the last instruction before the next function's
}

// Functions splits the code into its functions. A function is a func_info
// instruction, the run of label and line instructions just before it, which
// holds the label a failed call reports through, and everything after it up
// to the next function's run. OTP's beam_disasm splits the code so too. The
// int_code_end that closes the code belongs to no function.
func (f *File) Functions() ([]Function, error) {
	in := f.Code.Instrs
	var starts []int
	run := -1
	for i, x := range in {
		if x.Op == OpLabel || x.Op == OpLine {
			if run < 0 {
				run = i
			}
			continue
		}
		if x.Op == OpFuncInfo {
			if run < 0 {
				return nil, fmt.Errorf("%s: func_info at code offset %d has no label before it", f.Name, x.Offset)
			}
			starts = append(starts, run)
		}
		run = -1
	}
	if len(starts) == 0 {
		return nil, fmt.Errorf("%s: no func_info in the code", f.Name)
	}
	if starts[0] != 0 {
		return nil, fmt.Errorf("%s: %d instructions before the first function", f.Name, starts[0])
	}
	end := len(in)
	if end > 0 && in[end-1].Op == OpIntCodeEnd {
		end--
	}
	fns := make([]Function, 0, len(starts))
	for k, s := range starts {
		e := end
		if k+1 < len(starts) {
			e = starts[k+1]
		}
		fn := Function{Instrs: in[s:e]}
		for i, x := range fn.Instrs {
			if x.Op != OpFuncInfo {
				continue
			}
			if len(x.Args) != 3 || x.Args[0].Kind != ArgAtom || x.Args[1].Kind != ArgAtom || x.Args[2].Kind != ArgU {
				return nil, fmt.Errorf("%s: func_info at code offset %d with operands of the wrong kinds", f.Name, x.Offset)
			}
			name, err := f.atom(x.Args[1].Val)
			if err != nil {
				return nil, fmt.Errorf("%s: func_info at code offset %d: %w", f.Name, x.Offset, err)
			}
			fn.Name = name
			fn.Arity = int(x.Args[2].Val)
			if i+1 >= len(fn.Instrs) || fn.Instrs[i+1].Op != OpLabel {
				return nil, fmt.Errorf("%s: %s/%d has no label after its func_info", f.Name, name, fn.Arity)
			}
			fn.Entry = int(fn.Instrs[i+1].Args[0].Val)
			break
		}
		fns = append(fns, fn)
	}
	return fns, nil
}
