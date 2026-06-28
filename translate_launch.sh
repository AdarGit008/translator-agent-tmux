#!/bin/bash
# Launch Claude Code with translator sidecar in tmux
# Usage: tlate <project-path> [session-name]
#
# PREREQUISITE: Run 'claude' in the project directory at least once before
# using tlate, so the trust dialog is already resolved. The script sends an
# Enter keypress as a best-effort fallback for first-time directories.
#
# Environment:
#   TRANSLATOR_DIR  — install path (default: /opt/translator-agent-tmux)
#   DEEPSEEK_API_KEY — required

set -euo pipefail

PROJECT="${1:?Usage: tlate <project-path> [session-name]}"
SESSION="${2:-dev}"
ENGINE_DIR="${TRANSLATOR_DIR:-/opt/translator-agent-tmux}"

# Validate project path
if [ ! -d "$PROJECT" ]; then
    echo "ERROR: Project directory not found: $PROJECT"
    exit 1
fi
PROJECT="$(realpath "$PROJECT")"

# Ensure DEEPSEEK_API_KEY is available
if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    echo "ERROR: DEEPSEEK_API_KEY is not set"
    echo "Set it with: export DEEPSEEK_API_KEY=sk-..."
    exit 1
fi

# Export key into tmux SESSION environment (not global — scoped to this session only)
tmux setenv -t "$SESSION" DEEPSEEK_API_KEY "$DEEPSEEK_API_KEY" 2>/dev/null || true

# Read display refresh from config for alignment with engine poll interval
DISPLAY_REFRESH=$(python3 -c "import json; print(json.load(open('$ENGINE_DIR/translator_config.json')).get('display_refresh_seconds', 3))" 2>/dev/null || echo 3)

# Check if session already exists (idempotent guard)
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already exists. Attach: tmux attach -t $SESSION"
    echo "Or kill it first: tmux kill-session -t $SESSION"
    exit 1
fi

# Create session with Claude pane
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" "cd $PROJECT && claude" Enter

# Wait for Claude to start, then handle possible trust dialog
sleep 4
tmux send-keys -t "$SESSION" Enter   # Accept trust dialog if it appeared (default: "Yes")
sleep 1

# Verify Claude started (pane should contain recognizable text)
PANE_CONTENT=$(tmux capture-pane -t "$SESSION:.0" -p 2>/dev/null || echo "")
if ! echo "$PANE_CONTENT" | grep -qE 'Claude|claude|❯'; then
    echo "⚠ Claude may not have started in pane $SESSION:.0"
    echo "  Check with: tmux attach -t $SESSION"
    echo "  If this is the first time running 'claude' here, run it manually once to accept the trust dialog."
fi

# Split right for translator (narrow pane, 55 cols)
tmux split-window -h -l 55 -t "$SESSION"

# Start capture engine in background, redirect stderr to a log file for debugging
ENGINE_LOG="$ENGINE_DIR/engine_stderr.log"
tmux send-keys -t "$SESSION:.1" \
  "cd $ENGINE_DIR && python3 capture_translate.py '$PROJECT' '$SESSION' 2>$ENGINE_LOG &" Enter
sleep 2

# Display translator output (refreshing loop, aligned with engine poll interval)
# Note: engine errors go to $ENGINE_LOG — run 'tail -f $ENGINE_LOG' in a separate pane to debug
tmux send-keys -t "$SESSION:.1" \
  "clear && echo '🔍 Translator — $(date +%H:%M:%S)' && echo '---' && while true; do clear; echo '🔍 Translator — $(date +%H:%M:%S)'; echo '---'; cat '$ENGINE_DIR/latest_translation.txt' 2>/dev/null || echo '⏳ Waiting for Claude to respond...'; sleep $DISPLAY_REFRESH; done" Enter

# Focus back on Claude
tmux select-pane -t "$SESSION:.0"

echo "✅ Translator ready. Attach: tmux attach -t $SESSION"
echo "   Left pane  = Claude Code"
echo "   Right pane = Plain-language translations"
