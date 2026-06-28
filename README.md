# translator-agent-tmux

Real-time plain-language translator sidecar for Claude Code CLI sessions in tmux.

A Python engine captures Claude Code's tmux pane, waits for the pane to stabilize, isolates the latest response, pipes it through DeepSeek for plain-language translation, and displays the result in a split tmux pane.

## Important: Privacy Notice

The engine sends captured tmux pane content (including Claude Code's output and your prompts) to DeepSeek's API for translation. Do not use this tool with projects that display secrets, tokens, or sensitive data in the terminal. The translations are ephemeral — not saved or logged.

## Install

```bash
git clone https://github.com/AdarGit008/translator-agent-tmux.git /opt/translator-agent-tmux
cd /opt/translator-agent-tmux
./install.sh
```

## Prerequisites

- `tmux`, `python3`, `claude` CLI
- `DEEPSEEK_API_KEY` environment variable
- Pre-trust your project directory by running `claude` in it once

## Usage

```bash
# Set up environment
export DEEPSEEK_API_KEY=sk-...

# Launch Claude Code with translator sidecar
tlate ~/my-project

# Or with a custom session name
tlate ~/my-project my-session

# Attach to existing session
tlate-attach
```

## Troubleshooting

See README section in the implementation plan.
