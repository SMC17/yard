"""Sensor / comms fault-injection hooks for evaluation (``faults_v0``).

Faults are applied to what a controller *perceives*, never to the true state,
so metrics are always computed on ground truth. All parameters are evaluation
conventions chosen by the user; nothing here is a sensor specification,
an IMO / IEC performance standard, or a model of a particular receiver.

* ``bias``      constant additive offset (e.g. GNSS spoof-like drift held fixed)
* ``drift``     offset that grows linearly with time (slowly walking position)
* ``noise``     zero-mean Gaussian, seeded
* ``dropout``   in a time window (or with probability per sample) the reading
                is missing → consumer must hold / dead-reckon
* ``freeze``    in a time window the last good reading is repeated silently
                (stale data that *looks* valid — the harder failure)
"""

from __future__ import annotations

from dataclasses import asdict, dataclass, field
from typing import Any, Sequence

import numpy as np

LABEL = "faults_v0"
FAULT_KINDS = ("bias", "drift", "noise", "dropout", "freeze")


@dataclass(frozen=True)
class Fault:
    kind: str
    channel: str  # e.g. "own_position", "target_track", "action"
    magnitude: Sequence[float] | float = 0.0  # bias vector, drift rate per s, or noise sigma
    t_start: float = 0.0
    t_end: float = float("inf")
    probability: float = 1.0  # dropout per-sample probability inside the window

    def __post_init__(self) -> None:
        if self.kind not in FAULT_KINDS:
            raise ValueError(f"fault kind must be one of {FAULT_KINDS}")

    def active(self, t: float) -> bool:
        return self.t_start <= t < self.t_end

    def to_dict(self) -> dict[str, Any]:
        d = asdict(self)
        d["magnitude"] = list(np.atleast_1d(self.magnitude).astype(float))
        return d


@dataclass
class FaultInjector:
    """Applies a list of faults per channel; keeps a log of every corrupted sample."""

    faults: list[Fault] = field(default_factory=list)
    seed: int = 0
    log: list[dict[str, Any]] = field(default_factory=list)

    def __post_init__(self) -> None:
        self._rng = np.random.default_rng(self.seed)
        self._last_good: dict[str, np.ndarray] = {}

    def apply(self, channel: str, t: float, value: Sequence[float]) -> np.ndarray | None:
        """Return the perceived value, or ``None`` when the sample is dropped."""
        v = np.asarray(value, dtype=float).copy()
        out: np.ndarray | None = v
        applied: list[str] = []
        for f in self.faults:
            if f.channel != channel or not f.active(t) or out is None:
                continue
            mag = np.resize(np.atleast_1d(np.asarray(f.magnitude, dtype=float)), v.shape)
            if f.kind == "bias":
                out = out + mag
            elif f.kind == "drift":
                out = out + mag * (t - f.t_start)
            elif f.kind == "noise":
                out = out + self._rng.normal(0.0, 1.0, v.shape) * mag
            elif f.kind == "dropout":
                if self._rng.random() < f.probability:
                    out = None
            elif f.kind == "freeze":
                out = self._last_good.get(channel, out).copy()
            applied.append(f.kind)
        if applied:
            self.log.append({"t": float(t), "channel": channel, "faults": applied,
                             "dropped": out is None})
        if out is not None and "freeze" not in applied:
            self._last_good[channel] = out.copy()
        return out

    def summary(self) -> dict[str, Any]:
        by: dict[str, int] = {}
        for rec in self.log:
            for k in rec["faults"]:
                by[f"{rec['channel']}:{k}"] = by.get(f"{rec['channel']}:{k}", 0) + 1
        return {"label": LABEL, "faults": [f.to_dict() for f in self.faults], "seed": self.seed,
                "n_corrupted_samples": len(self.log), "by_channel_kind": by,
                "n_dropped": sum(1 for r in self.log if r["dropped"])}
