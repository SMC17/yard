"""Zig L1 resistance teacher — prefer HM1984 when yard_sea_zig is built.

Falls back to Python Holtrop-simplified if the Zig binary is missing or HM1984 fails.
"""

from __future__ import annotations

import os
from typing import Any

from ..hull import HullState
from ..resistance_l1 import ResistanceResult, estimate_resistance


def prefer_zig_hm1984() -> bool:
    """True unless YARD_SEA_PREFER_ZIG_HM1984=0/false/no."""
    v = os.environ.get("YARD_SEA_PREFER_ZIG_HM1984", "1").strip().lower()
    return v not in ("0", "false", "no", "off")


def estimate_l1(
    h: HullState | None = None,
    *,
    fidelity: str = "hm1984",
    prefer_zig: bool | None = None,
) -> ResistanceResult:
    """L1 teacher entry: Zig HM1984 when available, else Python simplified.

    fidelity: 'hm1984' | 'simplified' (Zig path) — Python path is always simplified.
    """
    hull = h or HullState()
    use_zig = prefer_zig_hm1984() if prefer_zig is None else prefer_zig
    if use_zig:
        try:
            from ..zig_bridge import estimate_resistance_zig, zig_available

            if zig_available():
                fid = "hm1984" if fidelity == "hm1984" else "simplified"
                return estimate_resistance_zig(hull, fidelity=fid)  # type: ignore[arg-type]
        except Exception:
            pass
    return estimate_resistance(hull, prefer_zig_hm1984=False)


def teacher_meta() -> dict[str, Any]:
    from ..zig_bridge import zig_available

    return {
        "name": "zig_l1",
        "zig_available": zig_available(),
        "prefer_hm1984": prefer_zig_hm1984(),
        "default_fidelity": "hm1984_zig" if zig_available() and prefer_zig_hm1984() else "simplified_py",
    }
