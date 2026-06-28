"""Core engine — monitors Claude Code tmux pane, translates responses.

Usage: capture_translate.py <repo_path> [session_name] [pane_target]

  repo_path    — project directory for snapshot context
  session_name — tmux session name (default: "dev")
  pane_target  — explicit tmux pane target (default: session_name:.0)
                 Use tmux pane IDs from 'tmux list-panes -F \"#{pane_id}\"'
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

last_processed_capture = ""
seen_hashes = deque(maxlen=50)
repo_snapshot = ""
config = {}
pane_target = ""


def capture_pane():
    """Capture FULL pane content. Returns empty string on failure."""
    result = subprocess.run(
        ["tmux", "capture-pane", "-t", pane_target, "-p"],
        capture_output=True, text=True,
    )
    if result.returncode != 0:
        print(
            f"WARNING: capture-pane failed (rc={result.returncode}): "
            f"{result.stderr.strip()}",
            file=sys.stderr,
        )
        return ""
    return result.stdout


def extract_claude_responses(text):
    """Extract Claude response blocks from captured pane."""
    lines = text.split("\n")
    responses = []
    in_response = False
    current = []

    for line in lines:
        stripped = line.strip()

        if stripped.startswith("> ") or stripped.startswith("▶"):
            if current:
                responses.append("\n".join(current))
                current = []
            in_response = False
            continue

        if "❯" in stripped and len(stripped) < 40:
            if current:
                responses.append("\n".join(current))
                current = []
            in_response = True
            continue

        if in_response:
            current.append(line)

    return responses


def main():
    global last_processed_capture, seen_hashes, repo_snapshot, config, pane_target

    # ── Parse args ──
    if len(sys.argv) < 2:
        print(
            "Usage: capture_translate.py <repo_path> [session_name] [pane_target]",
            file=sys.stderr,
        )
        sys.exit(1)

    repo_path = os.path.abspath(sys.argv[1])
    session_name = sys.argv[2] if len(sys.argv) > 2 else "dev"

    # Use explicit pane target if provided, otherwise build from session
    if len(sys.argv) > 3 and sys.argv[3]:
        pane_target = sys.argv[3]
    else:
        pane_target = f"{session_name}:.0"

    # ── Load config ──
    try:
        config = json.loads(CONFIG_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError) as e:
        print(f"FATAL: Cannot read config: {e}", file=sys.stderr)
        sys.exit(1)

    # ── Build repo snapshot ──
    repo_snapshot = build_snapshot(repo_path)

    # ── Verify API key ──
    if not os.environ.get("DEEPSEEK_API_KEY"):
        print("FATAL: DEEPSEEK_API_KEY not set", file=sys.stderr)
        sys.exit(1)

    poll_interval = config.get("poll_interval_seconds", 3)
    stable_polls = config.get("stable_polls_required", 2)
    min_chars = config.get("min_response_chars", 30)
    debug = config.get("debug", False)

    print(f"Translator engine started.", file=sys.stderr)
    print(f"  Repo: {repo_path}", file=sys.stderr)
    print(f"  Session: {session_name}", file=sys.stderr)
    print(f"  Pane: {pane_target}", file=sys.stderr)
    print(f"  Poll: {poll_interval}s, stable: {stable_polls}p", file=sys.stderr)

    # ── Main loop ──
    last_capture = ""
    stable_count = 0

    while True:
        try:
            current = capture_pane()

            if not current:
                time.sleep(poll_interval)
                continue

            # ── Stability tracking ──
            if current == last_capture:
                stable_count += 1
            else:
                stable_count = 1
            last_capture = current

            # ── Process when stable AND new ──
            if stable_count >= stable_polls and current != last_processed_capture:
                responses = extract_claude_responses(current)

                for resp in responses:
                    h = hashlib.md5(resp.encode(), usedforsecurity=False).hexdigest()
                    if h in seen_hashes:
                        continue
                    if len(resp.strip()) < min_chars:
                        continue

                    seen_hashes.append(h)
                    try:
                        translation = llm_translate(resp, repo_snapshot, config)
                        if translation.strip():
                            OUTPUT_FILE.write_text(translation)
                            if debug:
                                print(f"[DEBUG] Translated: {translation[:120]}...", file=sys.stderr)
                    except Exception as e:
                        print(f"Translation error: {e}", file=sys.stderr)

                last_processed_capture = current

            time.sleep(poll_interval)

        except KeyboardInterrupt:
            break
        except (subprocess.SubprocessError, OSError, ConnectionError) as e:
            print(f"Transient: {e}", file=sys.stderr)
            time.sleep(poll_interval)
        except Exception as e:
            print(f"FATAL: {e}", file=sys.stderr)
            sys.exit(1)


if __name__ == "__main__":
    main()
