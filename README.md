# translator-agent-tmux

Real-time plain-language translator sidecar for Claude Code CLI sessions in tmux.

A Python engine captures Claude Code's tmux pane, waits for the pane to stabilize, isolates the latest response, pipes it through DeepSeek for plain-language translation, and displays the result in a split tmux pane.

## Important: Privacy Notice

The engine sends captured tmux pane content (including Claude Code's output and your prompts) to DeepSeek's API for translation. Do not use this tool with projects that display secrets, tokens, or sensitive data in the terminal. The translations are ephemeral — not saved or logged.

## Install

The engine is fully self-referencing — just clone it anywhere:

```bash
git clone https://github.com/AdarGit008/translator-agent-tmux.git ~/translator-agent-tmux
```

Then add to your `~/.bashrc` or `~/.bash_aliases`:

```bash
alias tlate='~/translator-agent-tmux/translate_launch.sh'
alias tlate-attach='tmux attach -t dev'
alias tl='tlate .'
```

Source it and you're done. No `sudo`, no `/opt`, no install script needed.

## Prerequisites

- `tmux`, `python3`, `claude` CLI
- `DEEPSEEK_API_KEY` environment variable set in your shell rc
- Pre-trust your project directory by running `claude` in it once

## Usage

```bash
# Set up environment (add to ~/.bashrc or ~/.bash_aliases)
export DEEPSEEK_API_KEY=sk-...

# Launch Claude Code with translator sidecar
tlate ~/my-project

# Or just run from the current directory
tl

# With a custom session name
tlate ~/my-project my-session

# Attach to existing session
tlate-attach
```

Layout:

```
┌────────────────────┬──────────────────┐
│  Left pane         │  Right pane      │
│  Claude Code       │  Translator      │
│                    │  (plain English) │
└────────────────────┴──────────────────┘
```

## Troubleshooting

- **No translations appearing**: Make sure `DEEPSEEK_API_KEY` is exported in your shell rc (not just in the current terminal). The tmux session needs it in the global environment.
- **Claude trust dialog**: Run `claude` once manually in the project directory first.
- **Engine errors**: `tail -f ~/translator-agent-tmux/engine_stderr.log`
