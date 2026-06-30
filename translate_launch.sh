#!/bin/bash
# Launch Claude Code with translator sidecar in tmux
# Usage: tlate <project-path> [session-name]
#
# PREREQUISITE: Run 'claude' manually once in the project directory
# to accept the trust dialog before using tlate.
#
# Environment:
#   TRANSLATOR_DIR  — install path (default: /opt/translator-agent-tmux)
#   DEEPSEEK_API_KEY — required

set -euo pipefail

PROJECT="${1:?Usage: tlate <project-path> [session-name]}"
SESSION="${2:-dev}"
ENGINE_DIR="${TRANSLATOR_DIR:-/opt/translator-agent-tmux}"
CLAUDE_BOOT_TIMEOUT=30

# ── Validate inputs ──
[ -d "$PROJECT" ] || { echo "ERROR: Directory not found: $PROJECT"; exit 1; }
PROJECT="$(realpath "$PROJECT")"
[ -n "${DEEPSEEK_API_KEY:-}" ] || { echo "ERROR: DEEPSEEK_API_KEY not set"; exit 1; }

# ── Idempotency guard ──
if tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Session '$SESSION' already exists."
    echo "  Attach: tmux attach -t $SESSION"
    echo "  Kill:   tmux kill-session -t $SESSION"
    exit 1
fi

# ── Read config ──
DISPLAY_REFRESH=$(python3 -c "
import json
print(json.load(open('$ENGINE_DIR/translator_config.json')).get('display_refresh_seconds', 3))
" 2>/dev/null || echo 3)

# ── Export API key ──
tmux setenv -g DEEPSEEK_API_KEY "$DEEPSEEK_API_KEY" 2>/dev/null || true

# ── Create session & launch Claude ──
tmux new-session -d -s "$SESSION" -x 200 -y 50
tmux send-keys -t "$SESSION" "cd '$PROJECT' && claude" Enter

# ── Wait for Claude to be ready (poll for known prompt patterns) ──
echo "Waiting for Claude to boot..."
boot_start=$SECONDS
claude_ready=0
while [ $((SECONDS - boot_start)) -lt "$CLAUDE_BOOT_TIMEOUT" ]; do
    pane_content=$(tmux capture-pane -t "$SESSION" -p 2>/dev/null || true)

    # Claude is ready when we see its prompt or a response indicator
    if echo "$pane_content" | grep -qE '❯|claude|Claude|CLAUDE'; then
        # Give it a moment to settle, then send Enter for any trust dialog
        sleep 2
        tmux send-keys -t "$SESSION" Enter
        sleep 1
        claude_ready=1
        break
    fi
    sleep 1
done

if [ "$claude_ready" -eq 0 ]; then
    echo "WARNING: Claude may not be fully ready after ${CLAUDE_BOOT_TIMEOUT}s"
    echo "  If the translator pane shows no output, re-run Claude first with: claude"
    # Best-effort fallback
    sleep 3
    tmux send-keys -t "$SESSION" Enter
fi

# ── Get real pane IDs (tmux may re-index windows) ──
CLAUDE_PANE=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | head -1)
echo "Claude pane: $CLAUDE_PANE"

# ── Split right for translator ──
tmux split-window -h -l 55 -t "$CLAUDE_PANE"
ENGINE_PANE=$(tmux list-panes -t "$SESSION" -F '#{pane_id}' | tail -1)
echo "Engine pane: $ENGINE_PANE"

# ── Start capture engine ──
ENGINE_LOG="$ENGINE_DIR/engine_stderr.log"
tmux send-keys -t "$ENGINE_PANE" \
  "cd $ENGINE_DIR && python3 capture_translate.py '$PROJECT' '$SESSION' '$CLAUDE_PANE' 2>$ENGINE_LOG &" Enter
sleep 2

# ── Display loop ──
tmux send-keys -t "$ENGINE_PANE" \
  "bash $ENGINE_DIR/display_translator.sh $DISPLAY_REFRESH $ENGINE_DIR" Enter

# ── Focus Claude ──
tmux select-pane -t "$CLAUDE_PANE"

echo "✅ Translator ready. Attach: tmux attach -t $SESSION"
echo "   Left pane  = Claude Code"
echo "   Right pane = Plain-language translations"
echo "   Debug: tail -f $ENGINE_LOG"
