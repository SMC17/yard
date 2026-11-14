"""Oracle applicability: declared method range + empirically validated envelope.

Two separate questions are answered for a design and the oracle that scored it:

1. **Declared range** — is the hull inside the range the *method* claims?
   For the Holtrop-Mennen family that is the parent-dataset range as commonly
   quoted from Holtrop & Mennen (1982) (verify against the paper before relying
   on it for anything beyond flagging). For Michell thin-ship theory the gym
   uses a stated convention (slender hull), not a published limit.
2. **Validated envelope** — is the hull inside the parameter box spanned by the
   towing-tank points where this oracle matched measured C_T within the report
   tolerance (``reports/validation/oracle_tank_validation.json``, produced by
   ``yard_sea_v0.validation``)? Outside it, the oracle's number is an
   extrapolation with no measured backing in this repo.

Michell results are keyed on their offset source (``oracle_for_result``): the synthetic Wigley
grid maps to ``michell_l15``, and Ship-D HP waterlines map to ``michell_shipd_hp``. The latter has its own
envelope, which is empty because no tank case has Ship-D offsets. The real-lines Michell result
(``michell_lines``) is attached only as context.

The result is *advisory*: it is recorded in evidence and as advisory acceptance
checks, it never changes the reward or the acceptance verdict. Validation was
done at model-scale Reynolds numbers; full-scale designs rely on the ITTC-57
friction line for the Re extrapolation (flagged as ``reynolds_extrapolated``).
"""

from __future__ import annotations

import json
import math
from functools import lru_cache
from pathlib import Path
from typing import Any

from .hull import HullState

APPLICABILITY_SCHEMA = "yard_sea_v0.applicability.v1"

REPORT_PATH = Path(__file__).resolve().parents[1] / "reports" / "validation" / "oracle_tank_validation.json"

# Oracle tag (as carried by ResistanceResult.fidelity / holdout wave_model) -> validation-report name.
ORACLE_ALIASES = {
    "hm1984_zig": "hm1984_gym",
    "hm1984": "hm1984_gym",
    "hm1984_gym": "hm1984_gym",
    "simplified_py": "simplified_py",
    "L1_holtrop_simplified": "simplified_py",
    "michell": "michell_l15",
    "michell_l15": "michell_l15",
    "L1.5_michell": "michell_l15",
    # Michell on Ship-D HP waterlines (the vector's own offsets, not the synthetic Wigley grid): its own entry.
    "shipd_hp_waterlines": "michell_shipd_hp",
    "michell_shipd_hp": "michell_shipd_hp",
}

# Michell offset sources -> applicability oracle. ``wigley_synthetic`` is what ``michell_l15`` in the
# tank report validates; Ship-D HP waterlines are a different geometry and must not borrow that envelope.
MICHELL_OFFSET_ORACLE = {"wigley_synthetic": "michell_l15", "shipd_hp_waterlines": "michell_shipd_hp"}


def oracle_for_result(r: dict[str, Any]) -> str | None:
    """Applicability oracle tag for a resistance / teacher dict, honouring the Michell offset source."""
    src = r.get("offset_source")
    if src in MICHELL_OFFSET_ORACLE and str(r.get("fidelity", "")).startswith("L1.5_michell"):
        return MICHELL_OFFSET_ORACLE[src]
    return r.get("fidelity")

_HM_RANGE = {
    "Fn": (0.0, 0.45),
    "Cp": (0.55, 0.85),
    "L_B": (3.9, 14.9),
    "B_T": (2.1, 4.0),
}
DECLARED_RANGES: dict[str, dict[str, Any]] = {
    "hm1984_gym": {
        "ranges": _HM_RANGE,
        "source": "Holtrop & Mennen (1982) parent-dataset range as commonly quoted (verify before relying)",
    },
    "simplified_py": {
        "ranges": _HM_RANGE,
        "source": "inherits the Holtrop-Mennen range (HM-structured simplification)",
    },
    "michell_l15": {
        "ranges": {"L_B": (5.0, math.inf), "Fn": (0.1, 0.6)},
        "source": "gym convention for thin-ship (slender-hull) validity; not a published limit",
    },
    "michell_shipd_hp": {
        "ranges": {"L_B": (5.0, math.inf), "Fn": (0.1, 0.6)},
        "source": "same thin-ship convention as michell_l15; not a published limit",
    },
}

CM_ASSUMED = 0.98  # HullState carries no C_M; mirrors zig_gym CM_DEFAULT


def hull_params(h: HullState) -> dict[str, float]:
    return {
        "Fn": float(h.Fn),
        "Cb": float(h.Cb),
        "Cp": float(h.Cb) / CM_ASSUMED,
        "L_B": float(h.L) / float(h.B),
        "B_T": float(h.B) / float(h.T),
        "lcb_frac": float(h.lcb_frac),
    }


@lru_cache(maxsize=4)
def _load_report(path: str) -> dict[str, Any] | None:
    p = Path(path)
    if not p.is_file():
        return None
    return json.loads(p.read_text())


def load_report(path: str | Path | None = None) -> dict[str, Any] | None:
    return _load_report(str(path or REPORT_PATH))


def canonical_oracle(tag: str | None) -> str | None:
    if tag is None:
        return None
    return ORACLE_ALIASES.get(str(tag), ORACLE_ALIASES.get(str(tag).lower()))


def _outside(params: dict[str, float], box: dict[str, Any]) -> list[str]:
    out = []
    for k, (lo, hi) in box.items():
        v = params.get(k)
        if v is None:
            continue
        if not (lo <= v <= hi):
            out.append(f"{k}={v:.4g} not in [{lo:.4g}, {hi:.4g}]")
    return out


def assess(h: HullState, oracle: str | None, *, report_path: str | Path | None = None) -> dict[str, Any]:
    """Applicability record for one design under one oracle (advisory)."""
    name = canonical_oracle(oracle)
    rep = load_report(report_path)
    # A hull without bulb / transom in its state is validated against the "_bare" composition.
    if name in ("hm1984_gym", "simplified_py") and not (getattr(h, "abt_m2", 0.0) > 0 or getattr(h, "at_m2", 0.0) > 0):
        if f"{name}_bare" in (rep or {}).get("per_oracle", {}):
            name = f"{name}_bare"
    params = hull_params(h)
    out: dict[str, Any] = {
        "schema": APPLICABILITY_SCHEMA,
        "oracle": oracle,
        "oracle_validated_as": name,
        "params": params,
        "affects_reward": False,
        "reynolds_extrapolated": True,
    }
    decl = DECLARED_RANGES.get((name or "").removesuffix("_bare"))
    if decl is None:
        out.update(in_declared_range=None, declared_violations=[], declared_source=None)
    else:
        dv = _outside(params, decl["ranges"])
        out.update(in_declared_range=not dv, declared_violations=dv, declared_source=decl["source"])

    po = (rep or {}).get("per_oracle", {}).get(name or "")
    if name == "michell_shipd_hp" and not po:
        # No tank point has Ship-D HP waterline offsets, so nothing validates this path. The nearest
        # evidence is the same Michell integral on real hull lines (``michell_lines``), recorded as context.
        out.update(in_validated_envelope=False,
                   envelope_violations=["no tank-validated point for Michell on Ship-D HP waterlines"],
                   validation_status="no_validated_points")
        ml = (rep or {}).get("per_oracle", {}).get("michell_lines")
        out["validation"] = {"report_schema": (rep or {}).get("schema"), "n_validated": 0,
                             "own_envelope": "michell_shipd_hp (empty: no Ship-D-offset tank cases)"}
        if ml and ml.get("overall", {}).get("n"):
            out["validation"]["real_hull_lines"] = {
                "oracle": "michell_lines",
                "mean_E_pct": ml["overall"].get("mean_E_pct"),
                "mean_abs_E_pct": ml["overall"].get("mean_abs_E_pct"),
                "n_validated": ml["envelope"].get("n_validated"),
                "n": ml["overall"].get("n"),
            }
        return out
    if not po:
        out.update(
            in_validated_envelope=None,
            envelope_violations=[],
            validation_status="unvalidated" if rep else "report_missing",
        )
        return out
    env = po["envelope"]
    box = env.get("box")
    if box is None:
        out.update(in_validated_envelope=False, envelope_violations=["no validated reference point"],
                   validation_status="no_validated_points")
    else:
        ev = _outside(params, box)
        out.update(in_validated_envelope=not ev, envelope_violations=ev, validation_status="validated_report")
    nearest = _nearest(params, rep, name)
    tol = env.get("tol_pct")
    if nearest is not None and tol is not None and abs(nearest["E_pct"]) > tol:
        # Inside the box spanned by validated points is not enough when the closest
        # measured hull/speed is one where this oracle failed.
        out["in_validated_envelope"] = False
        out["envelope_violations"] = list(out["envelope_violations"]) + [
            f"nearest reference {nearest['point']} failed (E={nearest['E_pct']:+.1f}% > ±{tol:.0f}%)"
        ]
    ov = po["overall"]
    out["validation"] = {
        "report_schema": rep.get("schema"),
        "tol_pct": env.get("tol_pct"),
        "n_validated": env.get("n_validated"),
        "n_failed": env.get("n_failed"),
        "mean_abs_E_pct": ov.get("mean_abs_E_pct"),
        "max_abs_E_pct": ov.get("max_abs_E_pct"),
        "nearest_reference": nearest,
    }
    ml = (rep or {}).get("per_oracle", {}).get("michell_lines")
    if name == "michell_l15" and ml and ml.get("overall", {}).get("n"):
        # Same Michell integral on the real hull lines: the synthetic-offset agreement does not carry over.
        out["validation"]["real_hull_lines"] = {
            "oracle": "michell_lines",
            "mean_E_pct": ml["overall"].get("mean_E_pct"),
            "mean_abs_E_pct": ml["overall"].get("mean_abs_E_pct"),
            "n_validated": ml["envelope"].get("n_validated"),
            "n": ml["overall"].get("n"),
        }
    return out


_SCALES = {"Fn": 0.1, "Cb": 0.1, "Cp": 0.1, "L_B": 1.0, "B_T": 0.5, "lcb_frac": 0.02}


def _nearest(params: dict[str, float], rep: dict[str, Any], name: str) -> dict[str, Any] | None:
    best = None
    for r in rep.get("rows", []):
        o = r["oracles"].get(name, {})
        if "E_pct" not in o:
            continue
        d = math.sqrt(sum(((params[k] - r["params"][k]) / s) ** 2 for k, s in _SCALES.items()))
        if best is None or d < best["distance"]:
            best = {"point": f"{r['hull']}@Fn={r['Fn']:.3f}", "distance": d, "E_pct": o["E_pct"]}
    return best
