"""Every build.zig in the repo must reference files that exist.

Guards against dangling module paths like the old repo-root gym/build.zig,
which pointed at ../vendor/yard_zig/... (nonexistent) and could not compile.
"""

from __future__ import annotations

import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
_PATH_RE = re.compile(r'b\.path\("([^"]+)"\)')


def test_build_zig_paths_exist():
    files = [
        f for f in REPO.rglob("build.zig")
        if ".zig-cache" not in f.parts and "zig-out" not in f.parts
    ]
    assert files, "no build.zig found; repo layout changed?"
    dangling = [
        (str(f.relative_to(REPO)), m.group(1))
        for f in files
        for m in _PATH_RE.finditer(f.read_text(encoding="utf-8"))
        if not (f.parent / m.group(1)).exists()
    ]
    assert dangling == []
