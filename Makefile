# obeam: the host tool, the corpus, and later the board program. See README.md.

GENOP_TAG = OTP-27.3.4.1
GENOP_URL = https://raw.githubusercontent.com/erlang/otp/$(GENOP_TAG)/lib/compiler/src/genop.tab

ERLC      ?= erlc
ERLCFLAGS  = +deterministic

ERLS  = $(wildcard erl/*.erl) $(wildcard erl/shim/*.erl)
BEAMS = $(ERLS:.erl=.beam)

comma := ,
empty :=
space := $(empty) $(empty)

.PHONY: all test twin beam exbeam stats generate image prof prof-run run budget clean

all: test

# test vets and tests the Go packages, then the VM's packages under Go through
# the twin. The oracle tests need OTP's escript and erl, and skip without them.
test:
	test -z "$$(find . -name '*.go' -not -path './build/*' | xargs gofmt -l)"
	test -z "$$(ogo fmt -l --exclude='/build/' .)"
	go vet ./...
	go test ./...
	scripts/twin.sh

# twin runs the VM's packages under Go alone, and keeps the twin in build/twin.
twin:
	scripts/twin.sh -k build/twin $(ARGS)

# image regenerates image/image.ogo, what the board runs, from the corpus.
IMAGE_ENTRY   = demo:main/0
IMAGE_MODULES = erl/demo.beam erl/fac.beam erl/fib.beam erl/lst.beam erl/tuples.beam erl/funs.beam \
	erl/pingpong.beam erl/ring.beam erl/sieve.beam erl/counter.beam erl/exc.beam erl/links.beam \
	erl/sup.beam erl/flt.beam erl/fmt.beam erl/mp.beam erl/bin.beam erl/cogs.beam \
	ex/Elixir.Hello.beam ex/Elixir.Fac.beam ex/Elixir.Ping.beam ex/Elixir.Ring.beam \
	ex/Elixir.Enums.beam ex/Elixir.Strings.beam ex/Elixir.Maps.beam ex/Elixir.Point.beam
# IMAGE_LIBS are the shims, Erlang's of OTP's and Erlang's of Elixir's
# library, which a program takes by what it reaches.
IMAGE_LIBS = $(wildcard erl/shim/*.beam) $(wildcard ex/shim/*.beam)

image: $(BEAMS)
	mkdir -p image
	go run ./cmd/obeam pack -o image/image.ogo -entry $(IMAGE_ENTRY) -lib $(subst $(space),$(comma),$(strip $(IMAGE_LIBS))) $(IMAGE_MODULES)

# prof packs erl/bench.erl into prof/image, writes the names the profiler
# prints, and builds the profiler, prof/prof.binary; prof-run runs it on the
# board under the shared lock.
PROF_MODULES = erl/bench.beam erl/fib.beam erl/lst.beam erl/tuples.beam erl/pingpong.beam \
	erl/ring.beam erl/sieve.beam

prof: $(BEAMS)
	mkdir -p prof/image
	go run ./cmd/obeam pack -o prof/image/image.ogo -entry bench:main/0 $(PROF_MODULES)
	go run ./cmd/obeam gen -vm vm -names prof
	ogo build --unchecked -o prof/prof.binary ./prof

prof-run: prof
	flock -o -w 900 /tmp/p2-board.lock ogo loadp2 -t -b 230400 prof/prof.binary

# budget builds the board program, checked, and says how much of the hub's
# 512 KB it leaves for main's stack and what comes next; ogo build refuses a
# program whose main stack does not fit.
budget:
	ogo build
	@n=$$(stat -c %s obeam.binary); echo "obeam.binary: $$n bytes, $$((524288 - n)) of the hub's 524288 left beside it"

# run builds the board program and runs it on the board, under the lock the
# ogo and p2-11 sessions share.
run:
	flock -o -w 900 /tmp/p2-board.lock ogo run

# beam compiles the corpus with OTP 27's erlc. The .beam files are committed,
# so this is needed only after a .erl file changes.
beam: $(BEAMS)

erl/%.beam: erl/%.erl
	$(ERLC) $(ERLCFLAGS) -o $(@D) $<

# exbeam compiles the Elixir corpus, ex/*.ex, with elixirc, and the shims,
# ex/shim/*.erl, with erlc. The .beam files are committed, so this is needed
# only after a source changes.
EXS   = $(wildcard ex/*.ex)
SHIMS = $(wildcard ex/shim/*.erl)

exbeam:
	elixirc --no-docs --no-debug-info -o ex $(EXS)
	$(ERLC) $(ERLCFLAGS) -o ex/shim $(SHIMS)

# stats regenerates erl/stats.txt, the corpus's opcode and call histogram.
stats: $(BEAMS)
	go run ./cmd/obeam stats $(BEAMS) > erl/stats.txt

# generate regenerates internal/beam/opcodes.go from the genop.tab of the
# pinned OTP release, and the VM's copies of the packer's tables.
generate:
	mkdir -p build
	curl -sSL -o build/genop.tab $(GENOP_URL)
	go run ./internal/beam/gen_opcodes.go -tab build/genop.tab -tag $(GENOP_TAG) -o internal/beam/opcodes.go
	go run ./cmd/obeam gen -vm vm

clean:
	rm -rf build obeam
