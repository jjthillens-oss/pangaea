"""Report repository paths mentioned in Markdown that no longer exist.

This is deliberately a heuristic: it finds path-shaped inline code and res://
references, then leaves deliberate future paths to a small explicit allowlist.
"""

from __future__ import annotations

import argparse
import re
import sys
import tempfile
from pathlib import Path


SUFFIXES = (".gd", ".tscn", ".tres", ".json", ".sh", ".py", ".glb", ".blend", ".md")
INLINE = re.compile(r"(?<!`)`([^`\n]+)`(?!`)")
RESOURCE = re.compile(r"res://[^\s`<>\]\[(){}]+")
EDGE = " \t\r\n.,;:!?()[]{}<>\"'"
LEADING_EDGE = EDGE.replace(".", "")


def documents(root: Path) -> list[Path]:
    paths = [root / "CLAUDE.md"]
    paths.extend((root / "docs").rglob("*.md"))
    paths.extend((root / "prototypes").glob("*/README.md"))
    paths.extend((root / "assets/records").rglob("*.md"))
    return sorted({p for p in paths if p.is_file()}, key=lambda p: p.relative_to(root).as_posix())


def allowlist(path: Path) -> list[str]:
    if not path.exists():
        return []
    return [line.strip() for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip() and not line.lstrip().startswith("#")]


def candidates(line: str) -> set[str]:
    found: set[str] = set()
    for match in INLINE.finditer(line):
        for word in match.group(1).split():
            word = word.lstrip(LEADING_EDGE).rstrip(EDGE)
            if word.startswith("res://") or "/" in word or word.endswith(SUFFIXES):
                found.add(word)
    found.update(match.group(0).lstrip(LEADING_EDGE).rstrip(EDGE) for match in RESOURCE.finditer(line))
    return found


def normalized(raw: str) -> str | None:
    path = raw.lstrip(LEADING_EDGE).rstrip(EDGE).rstrip("/")
    if path.startswith("res://"):
        path = path[6:]
    path = path.lstrip(LEADING_EDGE).rstrip(EDGE).replace("\\", "/")
    if not path or "*" in path or "://" in path or path.startswith(("#", "-", "--", "/")):
        return None
    if path.startswith(("builds/", ".toolchain/")):
        return None
    # Ignore command options and syntax fragments, including shell pipe tokens.
    if any(char in path for char in "|${}=,[]()"):
        return None
    return path


def missing(root: Path, docs: list[Path], allowed: list[str]) -> list[tuple[str, int, str]]:
    output: set[tuple[str, int, str]] = set()
    root = root.resolve()
    for doc in docs:
        label = doc.relative_to(root).as_posix()
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            for raw in candidates(line):
                path = normalized(raw)
                if path is None or path in allowed or any(
                    item.endswith("/") and path.startswith(item) for item in allowed
                ):
                    continue
                target = (root / path).resolve()
                if not target.is_relative_to(root) or not target.exists():
                    output.add((label, number, path))
    return sorted(output)


def selftest() -> None:
    with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent.parent) as directory:
        root = Path(directory)
        (root / "docs").mkdir()
        (root / "game").mkdir()
        (root / "game/existing.gd").write_text("", encoding="utf-8")
        (root / ".github/workflows").mkdir(parents=True)
        (root / ".github/workflows/ci.yml").write_text("", encoding="utf-8")
        doc = root / "docs/example.md"
        doc.write_text(
            "`game/existing.gd` `game/missing.gd`\n"
            "`future/intent.gd` res://game/existing.gd `game/*.gd`\n"
            "`.toolchain/x` `.github/workflows/ci.yml`\n",
            encoding="utf-8",
        )
        assert normalized(".toolchain/x") is None
        assert normalized(".github/workflows/ci.yml") == ".github/workflows/ci.yml"
        result = missing(root, [doc], ["future/"])
        assert result == [("docs/example.md", 1, "game/missing.gd")], result
    print("SELFTEST OK")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report", action="store_true", help="report drift without failing")
    group.add_argument("--strict", action="store_true", help="fail when paths are missing")
    group.add_argument("--selftest", action="store_true", help="run parser cases")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return 0
    root = Path(__file__).resolve().parent.parent
    findings = missing(root, documents(root), allowlist(root / "tools/docs_check_allow.txt"))
    for doc, line, path in findings:
        print(f"{doc}:{line}: {path}")
    print(f"Missing paths: {len(findings)}")
    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
