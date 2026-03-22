#!/usr/bin/env bash
#
# Run a single herdr integration test spec via pi.
#
# Usage: ./run_spec.sh <spec.md> [results_dir] [tmux_socket_root]
#
# Each invocation creates its own tmux server (isolated socket).
# Cleanup kills the entire server — no orphaned sessions possible.
#
set -euo pipefail

SPEC="$1"
SPEC_NAME="$(basename "$SPEC" .md)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
RESULTS_DIR="${2:-$SCRIPT_DIR/results}"
TMUX_ROOT="${3:-${TMPDIR:-/tmp}/herdr-test-sockets}"
SYSTEM_PROMPT_FILE="$SCRIPT_DIR/system.md"
HERDR="$PROJECT_DIR/target/release/herdr"
EXTENSION="$SCRIPT_DIR/ext/herdr-test.ts"
MODEL="${HERDR_TEST_MODEL:-minimax/MiniMax-M2.7}"

mkdir -p "$RESULTS_DIR" "$TMUX_ROOT"

# Per-spec tmux socket — this spec owns its entire tmux server
TMUX_DIR="$(mktemp -d "$TMUX_ROOT/${SPEC_NAME}.XXXXXX")"
TMUX_SOCKET="$TMUX_DIR/tmux.sock"
SESSION_NAME="test"

# Track ownership for stale sweep
printf '%s\n' "$$" > "$TMUX_DIR/owner.pid"

# Temp files (initialized for safe cleanup)
PROMPT_FILE=""
RAW_OUTPUT=""

cleanup() {
    # Kill our entire tmux server — takes everything with it
    tmux -S "$TMUX_SOCKET" kill-server 2>/dev/null || true
    [[ -n "$PROMPT_FILE" ]] && rm -f "$PROMPT_FILE" 2>/dev/null || true
    rm -rf "$TMUX_DIR" 2>/dev/null || true
    # RAW_OUTPUT is moved to results dir, not cleaned here
}
trap cleanup EXIT INT TERM HUP

TMUX=(tmux -S "$TMUX_SOCKET")

# Prerequisites
RESULT_FILE="$RESULTS_DIR/$SPEC_NAME.json"
if ! command -v tmux &>/dev/null; then echo '{"test":"'"$SPEC_NAME"'","result":"skip","checks":[],"notes":"tmux not found"}' > "$RESULT_FILE"; exit 0; fi
if ! command -v pi &>/dev/null; then echo '{"test":"'"$SPEC_NAME"'","result":"skip","checks":[],"notes":"pi not found"}' > "$RESULT_FILE"; exit 0; fi
if [[ ! -x "$HERDR" ]]; then echo '{"test":"'"$SPEC_NAME"'","result":"error","checks":[],"notes":"herdr binary not found"}' > "$RESULT_FILE"; exit 1; fi

# Start herdr in its own tmux server
"${TMUX[@]}" new-session -d -s "$SESSION_NAME" -x 120 -y 50
"${TMUX[@]}" send-keys -t "$SESSION_NAME" "$HERDR --no-session" Enter
HERDR_PANE=$("${TMUX[@]}" list-panes -t "$SESSION_NAME" -F '#{pane_id}' | head -1)
"${TMUX[@]}" set-option -p -t "$HERDR_PANE" @pi_name "herdr"

sleep 1

# Build prompt
PROMPT_FILE=$(mktemp /tmp/herdr-test-prompt-XXXXX.md)
RAW_OUTPUT=$(mktemp /tmp/herdr-test-raw-XXXXX.txt)
cat "$SYSTEM_PROMPT_FILE" > "$PROMPT_FILE"
echo -e "\n---\n" >> "$PROMPT_FILE"
cat "$SPEC" >> "$PROMPT_FILE"

# Run pi in the same tmux server
SESSION_DIR="$RESULTS_DIR/sessions"
mkdir -p "$SESSION_DIR"

"${TMUX[@]}" split-window -t "$SESSION_NAME" -h \
    "cd $PROJECT_DIR && pi -p \
        --session-dir '$SESSION_DIR' \
        --no-extensions --no-skills --no-prompt-templates \
        -e '$EXTENSION' \
        --no-tools \
        --model '$MODEL' \
        --system-prompt '$PROMPT_FILE' \
        'Execute the test now. Use the herdr tool to send keys and read the screen. Output the JSON result block when done.' \
        > '$RAW_OUTPUT' 2>&1; \
     echo '___DONE___' >> '$RAW_OUTPUT'; \
     sleep 1"

# Wait for completion
TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if grep -q '___DONE___' "$RAW_OUTPUT" 2>/dev/null; then
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ $ELAPSED -ge $TIMEOUT ]; then
    echo '{"test":"'"$SPEC_NAME"'","result":"error","checks":[],"notes":"pi timed out after '"$TIMEOUT"'s"}' > "$RESULT_FILE"
    cp "$RAW_OUTPUT" "$RESULTS_DIR/$SPEC_NAME.raw.txt" 2>/dev/null || true
    rm -f "$RAW_OUTPUT"
    exit 1
fi

# Always save raw output
cp "$RAW_OUTPUT" "$RESULTS_DIR/$SPEC_NAME.raw.txt" 2>/dev/null || true
rm -f "$RAW_OUTPUT"

# Extract JSON
JSON_RESULT=$(awk '/^```json$/,/^```$/' "$RESULTS_DIR/$SPEC_NAME.raw.txt" | grep -v '^```')

if [[ -z "$JSON_RESULT" ]]; then
    echo '{"test":"'"$SPEC_NAME"'","result":"error","checks":[],"notes":"no JSON in pi output"}' > "$RESULT_FILE"
    exit 1
fi

if echo "$JSON_RESULT" | python3 -m json.tool > "$RESULT_FILE" 2>/dev/null; then
    RESULT=$(python3 -c "import sys,json; print(json.load(sys.stdin).get('result','unknown'))" < "$RESULT_FILE")
    if [[ "$RESULT" == "pass" ]]; then
        exit 0
    else
        exit 1
    fi
else
    echo '{"test":"'"$SPEC_NAME"'","result":"error","checks":[],"notes":"invalid JSON from pi"}' > "$RESULT_FILE"
    exit 1
fi
