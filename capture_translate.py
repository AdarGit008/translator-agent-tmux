"""Core engine — monitors Claude Code tmux pane, translates responses.

Target Claude Code version: v2.x (TUI: '> ' user prompts, '❯' cursor).
If Anthropic changes the TUI, update _looks_like_user_input() and
_looks_like_claude_prompt(). Enable debug mode to inspect extracted blocks.
"""
import subprocess, time, hashlib, os, json, sys
from collections import deque
from pathlib import Path
from deepseek_client import translate as llm_translate
from repo_snapshot import build_snapshot

BASE = Path(__file__).parent
CONFIG_FILE = BASE / "translator_config.json"
OUTPUT_FILE = BASE / "latest_translation.txt"
DEBUG_FILE = BASE / "debug_responses.txt"

# Runtime state
last_processed_capture = ""
seen_hashes = deque(maxlen=50)  # deterministic recency
repo_snapshot = ""
config = {}
pane_target = ""

def capture_pane():
    """Capture FULL pane content (no line limit)."""
    result = subprocess.run(
        ["tmux", "capture-pane", "-t", pane_target, "-p"],
        capture_output=True, text=True
    )
    return result.stdout

def extract_claude_responses(text):
    """
    Extract Claude response blocks from captured pane.

    Claude Code v2.x TUI characteristics:
    - User input lines start with '> ' or '▶'
    - The '❯' prompt appears when Claude is waiting for input
    - Claude's output appears between these markers

    This IS TUI-coupled. If Claude's UI changes, update the heuristics below.
    Enable debug mode (config.debug=true) to inspect what the parser extracts.
    """
    lines = text.split('\n')
    responses = []
    in_response = False
    current = []

    for line in lines:
        stripped = line.strip()

        if _looks_like_user_input(stripped):
            if current:
                responses.append('\n'.join(current))
                current = []
            in_response = False
            continue

        if _looks_like_claude_prompt(stripped):
            if current:
                responses.append('\n'.join(current))
                current = []
            in_response = True
            continue

        if in_response:
            current.append(line)

    return responses

def _looks_like_user_input(line: str) -> bool:
    """Heuristic: user input starts with '> ' or '▶'."""
    return line.startswith('> ') or line.startswith('▶')

def _looks_like_claude_prompt(line: str) -> bool:
    """Heuristic: Claude's '❯' prompt is a short line ending the output."""
    return '❯' in line and len(line) < 40

def _debug_log(msg: str):
    """Write debug messages to stderr and append to debug file."""
    print(f"[DEBUG] {msg}", file=sys.stderr)
    with open(DEBUG_FILE, 'a') as f:
        f.write(f"{msg}\n")

def main():
    global last_processed_capture, repo_snapshot, config, pane_target

    # --- Startup: parse args, load config, verify state ---

    if len(sys.argv) < 2:
        print("Usage: capture_translate.py <repo_path> [session_name]", file=sys.stderr)
        sys.exit(1)

    repo_path = os.path.abspath(sys.argv[1])
    session_name = sys.argv[2] if len(sys.argv) > 2 else "dev"
    pane_target = f"{session_name}:.0"

    # Load static config
    try:
        config = json.loads(CONFIG_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"FATAL: Cannot read config: {e}", file=sys.stderr)
        sys.exit(1)

    # Repo snapshot (one-time)
    repo_snapshot = build_snapshot(repo_path)

    # Verify DeepSeek key
    if not os.environ.get("DEEPSEEK_API_KEY"):
        print("FATAL: DEEPSEEK_API_KEY environment variable not set", file=sys.stderr)
        print("Set it with: export DEEPSEEK_API_KEY=sk-...", file=sys.stderr)
        sys.exit(1)

    poll_interval = config.get("poll_interval_seconds", 3)
    stable_polls = config.get("stable_polls_required", 2)
    min_chars = config.get("min_response_chars", 30)
    debug = config.get("debug", False)

    if debug:
        _debug_log(f"Debug mode enabled. Repo={repo_path}, Session={session_name}")
        DEBUG_FILE.write_text("")  # clear debug file for this session

    print(f"Translator engine started.")
    print(f"  Repo: {repo_path}")
    print(f"  Session: {session_name} (pane: {pane_target})")
    print(f"  Poll: {poll_interval}s, stable-after: {stable_polls} polls, debug: {debug}")

    # --- Main loop ---

    stable_count = 0

    while True:
        try:
            current = capture_pane()

            # Stability tracking: count consecutive identical polls
            if current == last_processed_capture:
                # Pane matches the last content we already processed — fully stable
                stable_count = stable_polls  # max out
            elif last_processed_capture and current != last_processed_capture:
                # Pane changed — track stability toward N consecutive matches
                if stable_count == 0:
                    stable_count = 1
                # If we were already stable but content changed again,
                # it means a NEW response appeared — process it, then reset
                if stable_count >= stable_polls:
                    # Extract and translate new content
                    responses = extract_claude_responses(current)
                    if debug and responses:
                        _debug_log(f"Extracted {len(responses)} response block(s)")

                    for i, resp in enumerate(responses):
                        if debug:
                            _debug_log(f"Block {i+1}: {resp[:150]}...")

                        h = hashlib.md5(resp.encode()).hexdigest()
                        if h in seen_hashes:
                            if debug:
                                _debug_log(f"  Skipping (already seen)")
                            continue
                        if len(resp.strip()) < min_chars:
                            if debug:
                                _debug_log(f"  Skipping (too short: {len(resp.strip())} chars)")
                            continue

                        seen_hashes.append(h)
                        translation = llm_translate(resp, repo_snapshot, config)
                        if translation.strip():
                            OUTPUT_FILE.write_text(translation)
                            if debug:
                                _debug_log(f"  Translation: {translation[:120]}...")

                    # Update processed state
                    last_processed_capture = current
                    stable_count = 0  # reset for next response

            time.sleep(poll_interval)

        except (subprocess.SubprocessError, OSError, ConnectionError) as e:
            # Transient: tmux issues, network timeouts on API call
            print(f"Transient error: {e}", file=sys.stderr)
            time.sleep(poll_interval)
        except KeyboardInterrupt:
            break
        except Exception as e:
            # Fatal: unexpected errors — log and exit rather than silent looping
            print(f"FATAL: {e}", file=sys.stderr)
            sys.exit(1)

if __name__ == "__main__":
    main()
