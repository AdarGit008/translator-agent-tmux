"""DeepSeek API client — single-pass translation."""
import os, json, urllib.request
from pathlib import Path

PROMPT_FILE = Path(__file__).parent / "translator_prompt.md"
MAX_INPUT_CHARS = 12000  # generous cap; truncate at paragraph boundary

def translate(claude_output: str, repo_snapshot: str, config: dict) -> str:
    """Call DeepSeek. Returns translation or empty string."""
    system_prompt = PROMPT_FILE.read_text()

    user_msg = (
        f"REPO SNAPSHOT:\n{repo_snapshot}\n\n"
        f"---\n\n"
        f"CLAUDE OUTPUT:\n{claude_output}"
    )

    api_key = os.environ.get("DEEPSEEK_API_KEY")
    if not api_key:
        raise RuntimeError("DEEPSEEK_API_KEY environment variable not set")

    # Cap input at paragraph boundary (not mid-sentence)
    if len(user_msg) > MAX_INPUT_CHARS:
        user_msg = _truncate_at_paragraph(user_msg, MAX_INPUT_CHARS)

    payload = {
        "model": config["model"],
        "messages": [
            {"role": "system", "content": system_prompt},
            {"role": "user", "content": user_msg}
        ],
        "max_tokens": config.get("max_tokens", 300),
        "temperature": config.get("temperature", 0.3)
    }

    headers = {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json"
    }

    req = urllib.request.Request(
        f"{config['api_base']}/chat/completions",
        data=json.dumps(payload).encode(),
        headers=headers
    )

    with urllib.request.urlopen(req, timeout=15) as resp:
        data = json.loads(resp.read())
        return data["choices"][0]["message"]["content"].strip()

def _truncate_at_paragraph(text: str, max_chars: int) -> str:
    """Truncate at the last paragraph break within max_chars."""
    if len(text) <= max_chars:
        return text
    # Find the last double-newline before the cutoff
    truncated = text[:max_chars]
    last_break = truncated.rfind('\n\n')
    if last_break > max_chars * 0.5:  # only use if it's a reasonable cutoff
        return truncated[:last_break] + "\n\n[...truncated after this paragraph]"
    # Fall back to last single newline
    last_newline = truncated.rfind('\n')
    if last_newline > max_chars * 0.5:
        return truncated[:last_newline] + "\n[...truncated]"
    return truncated + "\n[...truncated]"
