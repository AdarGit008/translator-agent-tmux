"""Build a compact repo snapshot for translation context."""
import os, json
from pathlib import Path

def build_snapshot(repo_path: str) -> str:
    root = Path(repo_path).resolve()
    parts = [f"REPO SNAPSHOT:\n- Path: {root}"]

    # 1. CLAUDE.md (highest priority — up to 250 words)
    claude_md = root / "CLAUDE.md"
    if claude_md.exists():
        text = claude_md.read_text()[:1200]  # ~250 words
        parts.append(f"- CLAUDE.md: {text}")

    # 2. README.md (up to 100 words)
    readme = root / "README.md"
    if readme.exists():
        text = readme.read_text()[:500]
        parts.append(f"- README: {text}")

    # 3. Stack detection
    for fname in ["pyproject.toml", "package.json", "Cargo.toml", "go.mod"]:
        sf = root / fname
        if sf.exists():
            parts.append(f"- Stack file: {fname}")
            if fname == "pyproject.toml":
                deps = _extract_python_deps(sf)
                if deps:
                    parts.append(f"- Key deps: {', '.join(deps[:10])}")
            elif fname == "package.json":
                deps = _extract_node_deps(sf)
                if deps:
                    parts.append(f"- Key deps: {', '.join(deps[:10])}")
            break  # One stack file is enough for v1

    # 4. Top-level directory listing
    try:
        entries = sorted(os.listdir(root))
        dirs = [e for e in entries if (root / e).is_dir() and not e.startswith('.')]
        files = [e for e in entries if (root / e).is_file() and not e.startswith('.')]
        parts.append(f"- Directories: {', '.join(dirs[:12])}")
        if files:
            parts.append(f"- Root files: {', '.join(files[:15])}")
    except PermissionError:
        pass

    return '\n'.join(parts)

def _extract_python_deps(path: Path) -> list[str]:
    try:
        text = path.read_text()
        deps = []
        in_deps = False
        for line in text.split('\n'):
            if 'dependencies' in line and '[' in line:
                in_deps = True
                continue
            if in_deps:
                if line.strip().startswith(']'):
                    break
                dep = line.strip().strip('"').strip("'").strip(',')
                if dep and not dep.startswith('[') and not dep.startswith('#'):
                    name = dep.split('>')[0].split('<')[0].split('=')[0].split('~')[0].strip().strip('"').strip("'")
                    if name:
                        deps.append(name)
        return deps
    except Exception:
        return []

def _extract_node_deps(path: Path) -> list[str]:
    try:
        data = json.loads(path.read_text())
        return list(data.get("dependencies", {}).keys())[:10]
    except Exception:
        return []
