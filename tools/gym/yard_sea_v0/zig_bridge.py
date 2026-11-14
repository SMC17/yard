"""Python ↔ Zig L0/L1 bridge via subprocess JSON CLI (ctypes-ready path).

Primary path: subprocess to `zig_gym/zig-out/bin/yard_sea_zig`.
Optional ctypes: if a shared library is built later (`zig build -Dshared`),
load via `ctypes.CDLL` — not required for L0/L1 parity today.

L1 fidelity:
  simplified — Holtrop-simplified (Python parity mirror)
  hm1984     — vendored yard Holtrop-Mennen 1984 (holtrop.totalResistance)
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
from pathlib import Path
from typing import Any, Literal

from .hull import HullState
from .resistance_l1 import ResistanceResult

_PKG_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_BIN = _PKG_ROOT / "zig_gym" / "zig-out" / "bin" / "yard_sea_zig"

Fidelity = Literal["simplified", "hm1984"]


def resolve_zig_binary(explicit: str | Path | None = None) -> Path:
    if explicit:
        p = Path(explicit)
        if p.is_file():
            return p
        raise FileNotFoundError(f"Zig binary not found: {p}")
    env = os.environ.get("YARD_SEA_ZIG_BIN")
    if env:
        p = Path(env)
        if p.is_file():
            return p
    which = shutil.which("yard_sea_zig")
    if which:
        return Path(which)
    if _DEFAULT_BIN.is_file():
        return _DEFAULT_BIN
    raise FileNotFoundError(
        "yard_sea_zig not found; build with `cd zig_gym && zig build` "
        f"(expected {_DEFAULT_BIN})"
    )


def _hull_args(h: HullState) -> list[str]:
    return [
        f"{h.L}",
        f"{h.B}",
        f"{h.T}",
        f"{h.Cb}",
        f"{h.lcb_frac}",
        f"{h.kg_frac}",
        f"{h.Fn}",
    ]


def _cli_mode(mode: str, fidelity: Fidelity | None = None) -> str:
    """Map Python mode + fidelity → Zig CLI mode token."""
    fid = fidelity or "simplified"
    if mode == "l0":
        return "l0"
    if mode == "l1":
        return "l1_hm1984" if fid == "hm1984" else "l1"
    if mode == "both":
        return "both_hm1984" if fid == "hm1984" else "both"
    if mode in ("l1_hm1984", "both_hm1984", "hm1984"):
        return "l1_hm1984" if mode == "hm1984" else mode
    return mode


def call_zig(
    h: HullState | None = None,
    mode: str = "both",
    binary: str | Path | None = None,
    fidelity: Fidelity | None = None,
) -> dict[str, Any]:
    """Run Zig CLI and return parsed JSON."""
    hull = h or HullState()
    bin_path = resolve_zig_binary(binary)
    cli_mode = _cli_mode(mode, fidelity)
    cmd = [str(bin_path), cli_mode, *_hull_args(hull)]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    if proc.returncode != 0:
        raise RuntimeError(
            f"zig bridge failed ({proc.returncode}): {proc.stderr or proc.stdout}"
        )
    line = (proc.stdout or "").strip().splitlines()[-1]
    return json.loads(line)


def evaluate_l0_zig(h: HullState | None = None, **kwargs: Any) -> dict[str, Any]:
    data = call_zig(h, mode="l0", **kwargs)
    return data["l0"]


def estimate_resistance_zig(
    h: HullState | None = None,
    fidelity: Fidelity = "simplified",
    **kwargs: Any,
) -> ResistanceResult:
    """Estimate resistance via Zig CLI.

    fidelity:
      'simplified' — L1 Holtrop-simplified (parity with Python resistance_l1)
      'hm1984'     — full HM 1984 via vendored yard holtrop.zig
    """
    data = call_zig(h, mode="l1", fidelity=fidelity, **kwargs)
    l1 = data["l1"]
    if "error" in l1:
        raise RuntimeError(f"zig HM1984 failed: {l1.get('error')}")
    # Evidence-pack fidelity tags: hm1984_zig vs simplified_py (Python fallback).
    if fidelity == "hm1984":
        fid_tag = "hm1984_zig"
        notes = "Vendored yard Holtrop-Mennen 1984 (Zig); not ITTC powering claim."
    else:
        # Zig mirror of Python Holtrop-simplified (parity path).
        fid_tag = str(l1.get("fidelity") or "L1_holtrop_simplified")
        notes = (
            "Exploratory HM-style estimate for ranking only; not ITTC powering claim."
        )
    raw = str(l1.get("fidelity") or "")
    if fidelity == "hm1984" or "hm1984" in raw.lower() or "1984" in raw:
        fid_tag = "hm1984_zig"
    return ResistanceResult(
        Fn=float(l1["Fn"]),
        Rn=float(l1["Rn"]),
        Cf=float(l1["Cf"]),
        k1=float(l1["k1"]),
        Cw=float(l1["Cw"]),
        Rt_N=float(l1["Rt_N"]),
        Ct=float(l1["Ct"]),
        fidelity=fid_tag,
        notes=notes,
    )


def zig_available(binary: str | Path | None = None) -> bool:
    try:
        resolve_zig_binary(binary)
        return True
    except FileNotFoundError:
        return False
