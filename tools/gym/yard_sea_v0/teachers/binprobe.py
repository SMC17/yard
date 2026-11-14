"""Check that an external solver binary actually *loads*, not just exists.

``shutil.which`` / ``os.access(X_OK)`` say a file is executable; they do not
say the dynamic loader can resolve its shared libraries.  A vendored OpenVSP
``.deb`` extract on a box that lost ``libcminpack.so.1`` passes the old
existence check, then every run fails as ``vspaero_script_failed`` and looks
like a physics failure instead of an install failure.

``probe(path)`` launches the binary once with a harmless flag, a short timeout
and an empty temp cwd, and reports ``(ok, reason)``.  Results are cached per
(path, mtime, size) so search loops pay the cost once.
"""

from __future__ import annotations

import functools
import os
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path

_LOADER_MARKERS = (
    "error while loading shared libraries",
    "cannot open shared object file",
    "version `GLIBC",
    "symbol lookup error",
)


@dataclass(frozen=True)
class ProbeResult:
    ok: bool
    reason: str | None = None

    def to_dict(self) -> dict[str, object]:
        return {"ok": self.ok, "reason": self.reason}


@functools.lru_cache(maxsize=64)
def _probe_cached(path: str, _mtime: float, _size: int, flag: str, timeout_s: float) -> ProbeResult:
    try:
        with tempfile.TemporaryDirectory(prefix="yard_binprobe_") as td:
            proc = subprocess.run(
                [path, flag],
                cwd=td,
                stdin=subprocess.DEVNULL,
                capture_output=True,
                text=True,
                timeout=timeout_s,
                check=False,
            )
    except subprocess.TimeoutExpired:
        # It started and is doing something: the loader resolved it.
        return ProbeResult(True, "probe_timeout_assumed_loaded")
    except OSError as exc:  # exec format error, permission, ENOENT
        return ProbeResult(False, f"exec_error:{type(exc).__name__}:{exc}")
    text = (proc.stdout or "") + "\n" + (proc.stderr or "")
    for marker in _LOADER_MARKERS:
        if marker in text:
            line = next((ln for ln in text.splitlines() if marker in ln), marker)
            return ProbeResult(False, f"loader:{line.strip()[:240]}")
    if proc.returncode in (126, 127):
        return ProbeResult(False, f"exit_{proc.returncode}")
    return ProbeResult(True, None)


def probe(path: str | os.PathLike[str] | None, *, flag: str = "-h", timeout_s: float = 10.0) -> ProbeResult:
    """Return whether ``path`` executes far enough for the loader to succeed."""
    if not path:
        return ProbeResult(False, "missing")
    p = Path(path)
    try:
        st = p.stat()
    except OSError:
        return ProbeResult(False, "missing")
    if os.environ.get("YARD_SEA_SKIP_BINPROBE") == "1":
        return ProbeResult(True, "probe_skipped_by_env")
    return _probe_cached(str(p.resolve()), st.st_mtime, st.st_size, flag, float(timeout_s))


def clear_cache() -> None:
    _probe_cached.cache_clear()
