"""Evidence / assurance pack emission for every evaluation."""

from __future__ import annotations

import json
import platform
import time
import uuid
from pathlib import Path
from typing import Any

from . import __version__
from .hull import HullState, L0Report
from .resistance_l1 import ResistanceResult
from .strip_assurance import strip_overlay


def build_evidence(
    *,
    hull: HullState,
    l0: L0Report,
    resistance: ResistanceResult | None,
    seed: int,
    step: int,
    episode_id: str,
    reward: float,
    action: list[float] | None,
    monitor_allowed: bool,
    monitor_reasons: list[str],
    parent_id: str | None = None,
) -> dict[str, Any]:
    odd = {
        "domain": "exploratory_parametric_hull_calm_water",
        "Fn": hull.Fn,
        "draft_m": hull.T,
        "heading": "head_seas_proxy_not_modeled",
        "fluid": "standard_seawater_1025",
        "geometry_family": "box_like_Cb_scaled",
        "limits": {
            "not_ittc_powering": True,
            "not_class_society": True,
            "not_seakeeping_rao": True,
            "learning_in_ops": False,
        },
    }
    claims = []
    if l0.feasible and resistance is not None:
        claims.append(
            {
                "id": "drag_rank_l1",
                "statement": (
                    "Hull is L0-feasible and ranked by L1 Holtrop-simplified Ct; "
                    "NOT an ITTC powering prediction."
                ),
                "status": "supported_at_l1",
                "evidence": ["l0_report", "resistance_l1"],
            }
        )
        claims.append(
            {
                "id": "gm0_floor",
                "statement": (
                    f"GM0={hull.gm0():.3f} m meets exploratory floor 0.15 m "
                    "under box hydrostatics."
                ),
                "status": "supported_at_l0",
                "evidence": ["l0_report"],
            }
        )
    else:
        claims.append(
            {
                "id": "rejected_or_infeasible",
                "statement": "Candidate rejected by runtime monitor or missing L1 eval.",
                "status": "unsupported",
                "evidence": ["monitor"],
            }
        )

    gsn_stub = {
        "top_goal": (
            "Produce a hydrostatically feasible hull with improved L1 "
            "resistance rank vs parent"
        ),
        "strategies": ["L0_monitor", "L1_resistance_rank", "offline_search_only"],
        "solutions": ["yard_sea_v0"],
        "context": ["public_osint_gym", "not_certification"],
    }

    pack: dict[str, Any] = {
        "evidence_id": str(uuid.uuid4()),
        "schema": "yard_sea_v0.evidence.v1",
        "created_unix": time.time(),
        "episode_id": episode_id,
        "parent_id": parent_id,
        "step": step,
        "seed": seed,
        "software": {
            "yard_sea_v0": __version__,
            "python": platform.python_version(),
            "platform": platform.platform(),
        },
        "agent_class": "learned_offline",
        "odd": odd,
        "hull": hull.to_dict(),
        "l0": l0.to_dict(),
        "resistance": None if resistance is None else resistance.to_dict(),
        "reward": reward,
        "action": action,
        "monitor": {"allow": monitor_allowed, "reason_codes": monitor_reasons},
        "claims": claims,
        "gsn_stub": gsn_stub,
    }
    pack["strip_assurance"] = strip_overlay(pack)
    return pack


def write_evidence(pack: dict[str, Any], directory: Path) -> Path:
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{pack['evidence_id']}.json"
    path.write_text(json.dumps(pack, indent=2, sort_keys=True))
    return path
