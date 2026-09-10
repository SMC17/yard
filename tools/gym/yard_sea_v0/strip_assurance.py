"""Strip-inspired assurance vocabulary (public OSINT alignment).

Maps Yard-Sea-v0 packs onto field names used in Strip-style trust/evidence
thinking — without claiming FAA/class/operational approval.
"""

from __future__ import annotations

from typing import Any


ASSURANCE_LEVELS = ("L0_reject", "L1_rank", "L2_panel", "L3_cfd", "L4_ops")  # L4 out of scope


def strip_overlay(evidence: dict[str, Any]) -> dict[str, Any]:
    """Attach a Strip-flavored assurance block to an evidence pack."""
    monitor_ok = evidence.get("monitor", {}).get("allow", False)
    l0_ok = evidence.get("l0", {}).get("feasible", False)
    has_l1 = evidence.get("resistance") is not None
    if not monitor_ok or not l0_ok:
        level = "L0_reject"
        disposition = "reject_before_eval"
    elif has_l1:
        level = "L1_rank"
        disposition = "rank_only"
    else:
        level = "L0_reject"
        disposition = "incomplete"

    claims = evidence.get("claims") or []
    return {
        "schema": "strip_assurance.overlay.v0",
        "product_line": "yard_sea",
        "not_certification": True,
        "not_operational": True,
        "learning_in_ops": False,
        "assurance_level": level,
        "disposition": disposition,
        "odd_ref": "odd",
        "claim_ids": [c.get("id") for c in claims if isinstance(c, dict)],
        "validation_gates": {
            "runtime_monitor": monitor_ok,
            "hydrostatic_l0": l0_ok,
            "resistance_l1": has_l1 and l0_ok,
            "panel_l2": False,
            "cfd_l3": False,
        },
        "next_gate": "L2_panel_or_ShipD_surface" if level == "L1_rank" else "repair_l0",
    }
