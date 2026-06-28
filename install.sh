#!/bin/bash
# Install translator-agent-tmux on a new machine
# Run from the repo root: ./install.sh
# Idempotent — safe to re-run.

set -euo pipefail

INSTALL_DIR="${TRANSLATOR_DIR:-/opt/translator-agent-tmux}"
ENGINE_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing translator-agent-tmux..."
echo "  Source: $ENGINE_DIR"
echo "  Target: $INSTALL_DIR"

# Create and populate install directory (idempotent)
if [ "$ENGINE_DIR" != "$INSTALL_DIR" ]; then
    sudo mkdir -p "$INSTALL_DIR"
    sudo cp -r "$ENGINE_DIR"/* "$INSTALL_DIR/"
    # Fix ownership so the user can write latest_translation.txt
    sudo chown -R "$(whoami):$(id -gn)" "$INSTALL_DIR"
    echo "  Copied files to $INSTALL_DIR"
else
    echo "  Already in install directory — skipping copy"
fi

# Set restrictive permissions on output file
touch "$INSTALL_DIR/latest_translation.txt"
chmod 600 "$INSTALL_DIR/latest_translation.txt"
echo "  Set permissions on latest_translation.txt"

# Verify dependencies
echo ""
echo "Checking dependencies..."
command -v tmux >/dev/null 2>&1 || echo "  ⚠ tmux not found — install it"
command -v python3 >/dev/null 2>&1 || echo "  ⚠ python3 not found — install it"
command -v claude >/dev/null 2>&1 || echo "  ⚠ claude CLI not found — install it"

# Check DEEPSEEK_API_KEY
if [ -z "${DEEPSEEK_API_KEY:-}" ]; then
    echo "  ⚠ DEEPSEEK_API_KEY not set — set it in your shell rc"
    echo "    export DEEPSEEK_API_KEY=sk-..."
else
    echo "  ✓ DEEPSEEK_API_KEY is set"
fi

echo ""
echo "Done. Add this alias to your shell rc:"
echo "  alias tlate='$INSTALL_DIR/translate_launch.sh'"
echo "  alias tlate-attach='tmux attach -t dev'"
