# obeam: the host tool, the corpus, and later the board program. See README.md.

GENOP_TAG = OTP-27.3.4.1
GENOP_URL = https://raw.githubusercontent.com/erlang/otp/$(GENOP_TAG)/lib/compiler/src/genop.tab

ERLC      ?= erlc
ERLCFLAGS  = +deterministic

ERLS  = $(wildcard erl/*.erl)
BEAMS = $(ERLS:.erl=.beam)

.PHONY: all test twin beam stats generate image prof prof-run run clean

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
	erl/flt.beam erl/fmt.beam erl/cogs.beam

image: $(BEAMS)
	mkdir -p image
	go run ./cmd/obeam pack -o image/image.ogo -entry $(IMAGE_ENTRY) $(IMAGE_MODULES)

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

# run builds the board program and runs it on the board, under the lock the
# ogo and p2-11 sessions share.
run:
	flock -o -w 900 /tmp/p2-board.lock ogo run

# beam compiles the corpus with OTP 27's erlc. The .beam files are committed,
# so this is needed only after a .erl file changes.
beam: $(BEAMS)

erl/%.beam: erl/%.erl
	$(ERLC) $(ERLCFLAGS) -o erl $<

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
