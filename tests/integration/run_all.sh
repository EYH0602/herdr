#!/usr/bin/env bash
#
# Run all herdr integration tests in parallel.
#
# Each spec gets its own tmux server (isolated socket).
# Workers are launched with PDEATHSIG so they get SIGTERM if this script dies.
# A stale sweep cleans up sockets from any previous crashed run.
#
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SPECS_DIR="$SCRIPT_DIR/specs"
RESULTS_DIR="$SCRIPT_DIR/results"
TMUX_ROOT="${TMPDIR:-/tmp}/herdr-test-sockets"

mkdir -p "$RESULTS_DIR" "$TMUX_ROOT"

# Clean previous results
rm -f "$RESULTS_DIR"/*.json "$RESULTS_DIR"/*.txt 2>/dev/null

# Sweep stale tmux sockets from crashed previous runs
for dir in "$TMUX_ROOT"/*/; do
    [ -d "$dir" ] || continue
    owner_pid=""
    [ -f "$dir/owner.pid" ] && owner_pid="$(<"$dir/owner.pid")"
    # If owning worker is still alive, leave it
    if [ -n "$owner_pid" ] && kill -0 "$owner_pid" 2>/dev/null; then
        continue
    fi
    # Dead owner — kill the tmux server and remove the dir
    [ -S "$dir/tmux.sock" ] && tmux -S "$dir/tmux.sock" kill-server 2>/dev/null || true
    rm -rf "$dir"
done

# Collect specs
SPECS=("$SPECS_DIR"/*.md)
if [ ${#SPECS[@]} -eq 0 ]; then
    echo "No test specs found in $SPECS_DIR"
    exit 0
fi

echo "Running ${#SPECS[@]} integration tests..."

# Detect PDEATHSIG support
PDEATHSIG_CMD=()
if command -v setpriv >/dev/null 2>&1 && setpriv --help 2>&1 | grep -q -- '--pdeathsig'; then
    PDEATHSIG_CMD=(setpriv --pdeathsig TERM --)
elif [ -f "$SCRIPT_DIR/pdeathsig.py" ]; then
    PDEATHSIG_CMD=(python3 "$SCRIPT_DIR/pdeathsig.py" TERM)
fi

# Launch all specs in parallel — directly from this shell (no subshell wrapper)
PIDS=()
NAMES=()

for spec in "${SPECS[@]}"; do
    name="$(basename "$spec" .md)"
    NAMES+=("$name")

    "${PDEATHSIG_CMD[@]}" "$SCRIPT_DIR/run_spec.sh" "$spec" "$RESULTS_DIR" "$TMUX_ROOT" &
    PIDS+=($!)
done

# Wait for all, ignoring individual exit codes (we read results from files)
for pid in "${PIDS[@]}"; do
    wait "$pid" 2>/dev/null || true
done

echo ""

# Print summary from result files
PASSED=0
FAILED=0
SKIPPED=0

for name in "${NAMES[@]}"; do
    result_file="$RESULTS_DIR/$name.json"

    if [[ ! -f "$result_file" ]]; then
        echo "  ? $name (no result file)"
        FAILED=$((FAILED + 1))
        continue
    fi

    result=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('result','unknown'))" < "$result_file" 2>/dev/null || echo "unknown")

    case "$result" in
        pass)
            echo "  ✓ $name"
            PASSED=$((PASSED + 1))
            ;;
        skip)
            echo "  - $name (skipped)"
            SKIPPED=$((SKIPPED + 1))
            ;;
        *)
            echo "  ✗ $name"
            python3 -c "
import sys, json
data = json.load(sys.stdin)
for c in data.get('checks', []):
    if not c.get('pass', True):
        print(f'      ✗ {c[\"name\"]}: {c.get(\"detail\", \"\")}')
notes = data.get('notes', '')
if notes and data.get('result') == 'error':
    print(f'      {notes}')
" < "$result_file" 2>/dev/null
            FAILED=$((FAILED + 1))
            ;;
    esac
done

echo ""
echo "$PASSED passed, $FAILED failed, $SKIPPED skipped"

[ $FAILED -eq 0 ]
