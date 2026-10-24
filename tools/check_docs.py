"""Report drift in repository paths mentioned by Markdown.

This is a heuristic, deliberately limited to inline code and res:// references.
All file and directory decisions use Git's tracked tree, so results are stable.
"""

from __future__ import annotations

import argparse
import json
import posixpath
import re
import subprocess
import sys
import tempfile
from collections import defaultdict
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


def allowlist(path: Path) -> tuple[list[str], list[str]]:
    paths: list[str] = []
    documents_to_skip: list[str] = []
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("@document "):
                documents_to_skip.append(line.removeprefix("@document "))
            else:
                paths.append(line)
    return paths, documents_to_skip


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
    if any(char in path for char in "|\u0024{}=,[]()"):
        return None
    return re.sub(r":\d+(?:-\d+)?$", "", path)


def tracked_index(root: Path) -> tuple[set[str], dict[str, list[str]], set[str]]:
    raw = subprocess.check_output(["git", "-C", str(root), "ls-files", "-z"])
    files = {name.decode("utf-8").replace("\\", "/") for name in raw.split(b"\0") if name}
    basenames: dict[str, list[str]] = defaultdict(list)
    directories: set[str] = set()
    for name in sorted(files):
        basenames[Path(name).name].append(name)
        parts = name.split("/")
        for depth in range(1, len(parts)):
            directories.add("/".join(parts[:depth]))
    return files, dict(basenames), directories


def classify(path: str, document: str, files: set[str], basenames: dict[str, list[str]],
             directories: set[str]) -> tuple[str, list[str]] | None:
    if path in files or path in directories:
        return None
    relative = posixpath.normpath(posixpath.join(posixpath.dirname(document), path))
    if relative in files or relative in directories:
        return None
    if path.startswith(("../", "./")) and relative.startswith("../"):
        return ("prose", [])
    if any(mark in path for mark in ("<", ">", "%")):
        return ("prose", [])
    if "/" not in path:
        if not Path(path).suffix or path.startswith("."):
            return ("prose", [])
        matches = basenames.get(path, [])
        if len(matches) == 1:
            return None
        return ("ambiguous" if matches else "missing", matches)
    directory, _, name = path.rpartition("/")
    if Path(name).suffix not in SUFFIXES and directory not in directories:
        return ("prose", [])
    return ("missing", [])


def find(root: Path, docs: list[Path], allowed: list[str], skipped_docs: list[str],
         files: set[str], basenames: dict[str, list[str]], directories: set[str]) -> tuple[list[dict], list[dict]]:
    findings: list[dict] = []
    prose: list[dict] = []
    for doc in docs:
        label = doc.relative_to(root).as_posix()
        if any(label == item or item.endswith("/") and label.startswith(item) for item in skipped_docs):
            continue
        for number, line in enumerate(doc.read_text(encoding="utf-8").splitlines(), 1):
            for raw in sorted(candidates(line)):
                path = normalized(raw)
                if path is None or path in allowed or any(
                    item.endswith("/") and path.startswith(item) for item in allowed
                ):
                    continue
                result = classify(path, label, files, basenames, directories)
                if result is None:
                    continue
                kind, matches = result
                entry = {"document": label, "line": number, "path": path, "kind": kind}
                if matches:
                    entry["candidates"] = matches
                (prose if kind == "prose" else findings).append(entry)
    key = lambda e: (e["document"], e["line"], e["path"], e["kind"])
    return sorted(findings, key=key), sorted(prose, key=key)


def selftest() -> None:
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        (root / "docs").mkdir()
        (root / "game/one").mkdir(parents=True)
        (root / "game/two").mkdir(parents=True)
        files = {"game/one/unique.gd", "game/one/shared.gd", "game/two/shared.gd",
                 ".github/workflows/ci.yml"}
        basenames: dict[str, list[str]] = defaultdict(list)
        directories = {"game", "game/one", "game/two", ".github", ".github/workflows"}
        for name in sorted(files):
            basenames[Path(name).name].append(name)
        doc = root / "docs/example.md"
        doc.write_text(
            "`unique.gd` `shared.gd` `lost.gd` `wander/return`\n"
            "`.toolchain/x` `.github/workflows/ci.yml`\n",
            encoding="utf-8",
        )
        assert normalized(".toolchain/x") is None
        assert normalized(".github/workflows/ci.yml") == ".github/workflows/ci.yml"
        findings, prose = find(root, [doc], [], [], files, dict(basenames), directories)
        assert [(f["kind"], f["path"]) for f in findings] == [
            ("missing", "lost.gd"), ("ambiguous", "shared.gd")], findings
        assert findings[1]["candidates"] == ["game/one/shared.gd", "game/two/shared.gd"]
        assert [p["path"] for p in prose] == ["wander/return"], prose
    print("SELFTEST OK")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--report", action="store_true", help="sorted human report")
    group.add_argument("--strict", action="store_true", help="fail when drift is found")
    group.add_argument("--json", action="store_true", help="machine-readable report")
    group.add_argument("--selftest", action="store_true", help="run synthetic cases")
    parser.add_argument("--show-prose", action="store_true", help="also list prose-like tokens")
    args = parser.parse_args()
    if args.selftest:
        selftest()
        return 0
    root = Path(__file__).resolve().parent.parent
    allowed, skipped_docs = allowlist(root / "tools/docs_check_allow.txt")
    files, basenames, directories = tracked_index(root)
    findings, prose = find(root, documents(root), allowed, skipped_docs, files, basenames, directories)
    if args.json:
        print(json.dumps({"count": len(findings), "prose_count": len(prose), "findings": findings,
                          "prose": prose if args.show_prose else []}, indent=2, ensure_ascii=False))
    else:
        for entry in findings + (prose if args.show_prose else []):
            note = " -> " + ", ".join(entry["candidates"]) if "candidates" in entry else ""
            print(f'{entry["document"]}:{entry["line"]}: {entry["kind"]}: {entry["path"]}{note}')
        print(f"Findings: {len(findings)} (prose hidden: {len(prose)})")
    return 1 if args.strict and findings else 0


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
