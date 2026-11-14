"""Provenance for evidence packs: harness, optimizer, seeds, replay digests, log export.

Goal: a later certification / audit tool can answer, for any evidence pack,
*which harness build produced it, which optimizer (implementation, version,
settings, budget actually spent) chose the design, and which seeds reproduce it* —
and can check a replay byte-for-byte on the deterministic fields.

Nothing here is a certification artefact; it is the bookkeeping such tools need.
"""

from __future__ import annotations

import functools
import hashlib
import json
import os
import platform
import subprocess
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable

import numpy as np

EPISODE_LOG_SCHEMA = "yard_sea_v0.episode_log.v1"
_NS = uuid.UUID("5d0b5c2e-6f1b-4c1e-9a77-7961726473ea")  # fixed namespace for episode ids

# Keys that legitimately differ between two otherwise identical replays.
VOLATILE_KEYS = frozenset({"evidence_id", "created_unix", "wall_s", "platform", "python", "git_sha"})


@functools.lru_cache(maxsize=1)
def _git_sha() -> str | None:
    env = os.environ.get("YARD_GIT_SHA") or os.environ.get("GITHUB_SHA")
    if env:
        return env
    try:
        out = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=Path(__file__).resolve().parent,
            capture_output=True,
            text=True,
            timeout=2,
        )
        sha = out.stdout.strip()
        return sha or None
    except Exception:  # noqa: BLE001
        return None


def harness_info() -> dict[str, Any]:
    from . import __version__

    return {
        "name": "yard_sea_v0",
        "version": __version__,
        "git_sha": _git_sha(),
        "python": platform.python_version(),
        "numpy": np.__version__,
        "platform": platform.platform(),
    }


@dataclass
class OptimizerRecord:
    """What chose the design, how it was configured, and what it was allowed to spend."""

    implementation: str = "manual"
    version: str | None = None
    settings: dict[str, Any] = field(default_factory=dict)
    max_evals: int | None = None
    max_wall_s: float | None = None
    evals: int = 0
    wall_s: float = 0.0
    _t0: float | None = field(default=None, repr=False)

    def start(self) -> "OptimizerRecord":
        self._t0 = time.monotonic()
        return self

    def tick(self, n: int = 1) -> None:
        self.evals += int(n)
        if self._t0 is not None:
            self.wall_s = time.monotonic() - self._t0

    @property
    def budget_exhausted(self) -> bool:
        if self.max_evals is not None and self.evals >= self.max_evals:
            return True
        return self.max_wall_s is not None and self.wall_s >= self.max_wall_s

    def to_dict(self) -> dict[str, Any]:
        return {
            "implementation": self.implementation,
            "version": self.version,
            "settings": dict(self.settings),
            "budget": {"max_evals": self.max_evals, "max_wall_s": self.max_wall_s},
            "used": {"evals": self.evals, "wall_s": round(self.wall_s, 6)},
        }


def episode_seed(base_seed: int, episode_index: int) -> int:
    """Deterministic per-episode seed via numpy SeedSequence spawning.

    Two policies evaluated with the same ``(base_seed, episode_index)`` see the
    same environment randomness (common random numbers), so differences in
    outcome are attributable to the policy, not the draw.
    """
    ss = np.random.SeedSequence(entropy=int(base_seed), spawn_key=(int(episode_index),))
    return int(ss.generate_state(1, dtype=np.uint32)[0])


def seeds_record(base_seed: int, episode_index: int) -> dict[str, Any]:
    return {
        "base_seed": int(base_seed),
        "episode_index": int(episode_index),
        "episode_seed": episode_seed(base_seed, episode_index),
        "derivation": "numpy.SeedSequence(entropy=base_seed, spawn_key=(episode_index,))",
        "bit_generator": "PCG64",
    }


def deterministic_episode_id(base_seed: int, episode_index: int, parent_vector: Iterable[float]) -> str:
    key = f"{int(base_seed)}:{int(episode_index)}:" + ",".join(f"{float(v):.12g}" for v in parent_vector)
    return str(uuid.uuid5(_NS, key))


def _strip_volatile(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: _strip_volatile(v) for k, v in obj.items() if k not in VOLATILE_KEYS}
    if isinstance(obj, list):
        return [_strip_volatile(v) for v in obj]
    if isinstance(obj, float):
        return float(f"{obj:.12g}")
    return obj


def canonical_digest(record: dict[str, Any]) -> str:
    """sha256 over the deterministic content of a record (volatile keys removed)."""
    blob = json.dumps(_strip_volatile(record), sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(blob.encode()).hexdigest()


def export_episode_log(
    records: list[dict[str, Any]],
    path: str | Path,
    *,
    header: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Write a JSONL log: header, one line per record (with its digest), footer.

    Returns the footer (contains the chained log digest).
    """
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    chain = hashlib.sha256()
    with path.open("w", encoding="utf-8") as fh:
        head = {"type": "header", "schema": EPISODE_LOG_SCHEMA, "harness": harness_info(), **(header or {})}
        fh.write(json.dumps(head, sort_keys=True, default=str) + "\n")
        for rec in records:
            d = canonical_digest(rec)
            chain.update(d.encode())
            fh.write(json.dumps({"type": "record", "digest": d, "record": rec}, sort_keys=True, default=str) + "\n")
        footer = {"type": "footer", "n_records": len(records), "log_digest": chain.hexdigest()}
        fh.write(json.dumps(footer, sort_keys=True) + "\n")
    return footer


def load_episode_log(path: str | Path) -> dict[str, Any]:
    lines = [json.loads(x) for x in Path(path).read_text(encoding="utf-8").splitlines() if x.strip()]
    if not lines or lines[0].get("type") != "header" or lines[-1].get("type") != "footer":
        raise ValueError("not a yard_sea_v0 episode log")
    return {"header": lines[0], "records": [x["record"] for x in lines[1:-1]],
            "digests": [x["digest"] for x in lines[1:-1]], "footer": lines[-1]}


def verify_log(path: str | Path) -> bool:
    """Recompute record digests and the chained digest; False on any tampering."""
    log = load_episode_log(path)
    chain = hashlib.sha256()
    for rec, d in zip(log["records"], log["digests"]):
        if canonical_digest(rec) != d:
            return False
        chain.update(d.encode())
    return chain.hexdigest() == log["footer"]["log_digest"] and log["footer"]["n_records"] == len(log["records"])
