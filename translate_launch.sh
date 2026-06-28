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

# Wait for Claude to load (skip trust dialog — user must pre-trust)
sleep 5
tmux send-keys -t "$SESSION" Enter   # best-effort trust dialog fallback
sleep 2

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
# Uses word-wrap (fold -s) and ANSI colors:
#   Green  = normal translations
#   Yellow = ⚠️ NEEDS YOUR DECISION
#   Cyan   = header
DISPLAY_CMD='
clear
echo -e "\033[36m┌─ Translator ─ $(date +%H:%M:%S) ─┐\033[0m"
OUT=$(cat '"$ENGINE_DIR"'/latest_translation.txt 2>/dev/null)
if [ -z "$OUT" ]; then
  echo -e "  \033[90m⏳ Waiting for Claude...\033[0m"
else
  echo "$OUT" | while IFS= read -r line; do
    case "$line" in
      *⚠️*NEEDS*YOUR*DECISION*|*⚠️*)
        echo -e "\033[33m$line\033[0m" ;;
      "")
        echo "" ;;
      *)
        echo -e "\033[32m$line\033[0m" ;;
    esac
  done | fold -s -w 52
fi
echo -e "\033[36m└──────────────────────────────┘\033[0m"
'
tmux send-keys -t "$ENGINE_PANE" \
  "clear && while true; do $DISPLAY_CMD; sleep $DISPLAY_REFRESH; done" Enter

# ── Focus Claude ──
tmux select-pane -t "$CLAUDE_PANE"

echo "✅ Translator ready. Attach: tmux attach -t $SESSION"
echo "   Left pane  = Claude Code"
echo "   Right pane = Plain-language translations"
echo "   Debug: tail -f $ENGINE_LOG"
