#!/bin/bash
# Translator display loop — word-wrapped, ANSI-colored output
# Usage: display_translator.sh [refresh_seconds] [translator_dir]

REFRESH="${1:-3}"
DIR="${2:-/opt/translator-agent-tmux}"

while true; do
    clear
    echo -e "\033[36m┌─ Translator ─ $(date +%H:%M:%S) ─┐\033[0m"
    OUT=$(cat "$DIR/latest_translation.txt" 2>/dev/null)
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
    sleep "$REFRESH"
done
