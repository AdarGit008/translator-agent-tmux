#!/bin/bash
# Translator display loop — word-wrapped, ANSI-colored output
# Usage: display_translator.sh [refresh_seconds] [translator_dir]

REFRESH="${1:-3}"
DIR="${2:-/opt/translator-agent-tmux}"

while true; do
    clear
    printf '\033[36m┌─ Translator ─ %s ─┐\033[0m\n' "$(date +%H:%M:%S)"
    OUT=$(cat "$DIR/latest_translation.txt" 2>/dev/null)
    if [ -z "$OUT" ]; then
        printf '  \033[90m⏳ Waiting for Claude...\033[0m\n'
    else
        printf '%s\n' "$OUT" | while IFS= read -r line; do
            case "$line" in
                *⚠️*NEEDS*YOUR*DECISION*|*⚠️*)
                    printf '\033[33m%s\033[0m\n' "$line" ;;
                "")
                    printf '\n' ;;
                *)
                    printf '\033[32m%s\033[0m\n' "$line" ;;
            esac
        done | fold -s -w 52
    fi
    printf '\033[36m└──────────────────────────────┘\033[0m\n'
    sleep "$REFRESH"
done
