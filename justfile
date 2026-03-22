# herdr task runner

# Run unit tests
test:
    cargo test

# Run integration tests (LLM-based, requires pi + tmux)
test-integration:
    ./tests/integration/run_all.sh

# Run all tests
test-all: test test-integration

# Build release binary
build:
    cargo build --release

# Kill any leftover test tmux sessions and clean results
clean-tests:
    @for sock in ${TMPDIR:-/tmp}/herdr-test-sockets/*/tmux.sock; do \
        [ -S "$$sock" ] && tmux -S "$$sock" kill-server 2>/dev/null || true; \
    done
    @rm -rf ${TMPDIR:-/tmp}/herdr-test-sockets 2>/dev/null || true
    @rm -f tests/integration/results/*.json tests/integration/results/*.txt 2>/dev/null || true
    @echo "cleaned"

# Print default config
default-config:
    cargo run --release -- --default-config
