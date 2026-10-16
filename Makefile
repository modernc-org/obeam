# obeam: the host tool, the corpus, and later the board program. See README.md.

GENOP_TAG = OTP-27.3.4.1
GENOP_URL = https://raw.githubusercontent.com/erlang/otp/$(GENOP_TAG)/lib/compiler/src/genop.tab

ERLC      ?= erlc
ERLCFLAGS  = +deterministic

ERLS  = $(wildcard erl/*.erl)
BEAMS = $(ERLS:.erl=.beam)

.PHONY: all test beam stats generate clean

all: test

# test vets and tests the Go packages. The oracle tests need OTP's escript and
# skip without it.
test:
	test -z "$$(gofmt -l .)"
	go vet ./...
	go test ./...

# beam compiles the corpus with OTP 27's erlc. The .beam files are committed,
# so this is needed only after a .erl file changes.
beam: $(BEAMS)

erl/%.beam: erl/%.erl
	$(ERLC) $(ERLCFLAGS) -o erl $<

# stats regenerates erl/stats.txt, the corpus's opcode and call histogram.
stats: $(BEAMS)
	go run ./cmd/obeam stats $(BEAMS) > erl/stats.txt

# generate regenerates internal/beam/opcodes.go from the genop.tab of the
# pinned OTP release.
generate:
	mkdir -p build
	curl -sSL -o build/genop.tab $(GENOP_URL)
	go run ./internal/beam/gen_opcodes.go -tab build/genop.tab -tag $(GENOP_TAG) -o internal/beam/opcodes.go

clean:
	rm -rf build obeam
