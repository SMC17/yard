"""COLREG encounter scenario STUB: geometry-only, for scenario-based testing.

LABEL: ``colreg_stub_v0``. This is a kinematic stub, not a COLREG compliance
check, not a DNV (or any class / flag) method, and not endorsed by anyone. It
borrows only the *layout* of scenario-based collision-avoidance testing
(parameterised encounter → expected role → evaluate one manoeuvre) and a
geometric reading of three rules:

* Rule 13 overtaking: coming up from more than 22.5° abaft the other's beam
  (relative bearing in (112.5°, 247.5°) from the other vessel's heading).
* Rule 14 head-on: each vessel sees the other within ``head_on_deg`` of dead
  ahead. The rule text says "reciprocal or nearly reciprocal"; the numeric
  sector is a *convention parameter*, not rule text.
* Rule 15 crossing: target on own starboard side → own gives way; port → own
  stands on (Rule 17: keep course and speed).

Manoeuvre checks are likewise simplified readings with explicit thresholds:
starboard alteration for head-on / starboard-crossing give-way (Rules 14, 15),
"readily apparent" alteration (Rule 8(b), ``min_apparent_deg`` is a
convention), resulting passing distance, and not crossing ahead of the
stand-on vessel (Rule 15). Not modelled: restricted visibility (Rule 19),
narrow channels / TSS (9, 10), vessel categories (18), sound / light signals,
multi-ship encounters, ship dynamics (course changes are instantaneous),
environmental forces, sensor uncertainty, and good seamanship (Rule 2).

Frame: x east, y north [m]; course clockwise from north [deg]; speed [m/s].
"""

from __future__ import annotations

import math
from dataclasses import dataclass, replace
from typing import Any

LABEL = "colreg_stub_v0"
NOT_A_COMPLIANCE_CLAIM = (
    "Geometry-only stub with convention thresholds. Not COLREG compliance, "
    "not a DNV / class / flag-state method."
)


@dataclass(frozen=True)
class Vessel:
    x: float
    y: float
    course_deg: float
    speed: float

    @property
    def velocity(self) -> tuple[float, float]:
        c = math.radians(self.course_deg)
        return self.speed * math.sin(c), self.speed * math.cos(c)

    def at(self, t: float) -> "Vessel":
        vx, vy = self.velocity
        return replace(self, x=self.x + vx * t, y=self.y + vy * t)


@dataclass(frozen=True)
class Thresholds:
    dcpa_min_m: float = 926.0  # 0.5 nmi passing distance (convention)
    tcpa_max_s: float = 1200.0  # 20 min look-ahead (convention)
    head_on_deg: float = 6.0  # "nearly reciprocal" sector (convention)
    min_apparent_deg: float = 30.0  # Rule 8(b) "readily apparent" (convention)


def _wrap360(a: float) -> float:
    return a % 360.0


def relative_bearing(from_v: Vessel, to_v: Vessel) -> float:
    """Bearing of ``to_v`` seen from ``from_v``, relative to ``from_v``'s heading, in [0, 360)."""
    true_brg = math.degrees(math.atan2(to_v.x - from_v.x, to_v.y - from_v.y))
    return _wrap360(true_brg - from_v.course_deg)


def cpa_tcpa(own: Vessel, tgt: Vessel) -> tuple[float, float]:
    """Distance and time at closest point of approach (straight-line kinematics)."""
    rx, ry = tgt.x - own.x, tgt.y - own.y
    (ox, oy), (tx, ty) = own.velocity, tgt.velocity
    vx, vy = tx - ox, ty - oy
    v2 = vx * vx + vy * vy
    t = 0.0 if v2 < 1e-12 else -(rx * vx + ry * vy) / v2
    return math.hypot(rx + vx * t, ry + vy * t), t


def _abaft_beam(rb: float) -> bool:
    return 112.5 < rb < 247.5


def classify(own: Vessel, tgt: Vessel, th: Thresholds = Thresholds()) -> dict[str, Any]:
    """Encounter type and own-ship role under the geometric reading above."""
    rb_t = relative_bearing(own, tgt)  # where the target is, from own
    rb_o = relative_bearing(tgt, own)  # where own is, from the target
    dcpa, tcpa = cpa_tcpa(own, tgt)
    risk = dcpa < th.dcpa_min_m and 0.0 < tcpa < th.tcpa_max_s

    def ahead(rb: float) -> bool:
        return rb <= th.head_on_deg or rb >= 360.0 - th.head_on_deg

    if _abaft_beam(rb_o) and own.speed > tgt.speed:
        enc, role = "overtaking", "give_way"  # Rule 13: own is overtaking
    elif _abaft_beam(rb_t) and tgt.speed > own.speed:
        enc, role = "overtaken", "stand_on"
    elif ahead(rb_t) and ahead(rb_o):
        enc, role = "head_on", "give_way"  # Rule 14: both alter to starboard
    elif 0.0 < rb_t <= 112.5:
        enc, role = "crossing_starboard", "give_way"  # Rule 15
    elif 247.5 <= rb_t < 360.0:
        enc, role = "crossing_port", "stand_on"  # Rules 15 / 17
    else:
        enc, role = "none", "none"
    return {
        "label": LABEL,
        "encounter": enc,
        "role": role if risk else "none",
        "risk_of_collision": risk,
        "dcpa_m": dcpa,
        "tcpa_s": tcpa,
        "rel_bearing_target_deg": rb_t,
        "rel_bearing_own_deg": rb_o,
        "notes": NOT_A_COMPLIANCE_CLAIM,
    }


def _crosses_ahead(own: Vessel, tgt: Vessel) -> bool | None:
    """Does own cross the target's track line ahead of the target? None if it never crosses."""
    (ox, oy), (tx, ty) = own.velocity, tgt.velocity
    ts = tgt.speed
    if ts < 1e-9:
        return None
    ux, uy = tx / ts, ty / ts  # target track direction
    nx, ny = -uy, ux  # normal to the track
    side0 = (own.x - tgt.x) * nx + (own.y - tgt.y) * ny
    rate = (ox - tx) * nx + (oy - ty) * ny  # target moves along its own track: normal rate is own's
    if abs(rate) < 1e-12 or side0 / -rate <= 0:
        return None
    t = side0 / -rate
    o, g = own.at(t), tgt.at(t)
    return (o.x - g.x) * ux + (o.y - g.y) * uy > 0.0


def evaluate_manoeuvre(
    own: Vessel, tgt: Vessel, alteration_deg: float, th: Thresholds = Thresholds()
) -> dict[str, Any]:
    """Apply an instantaneous own course change now and check the simplified rule readings."""
    before = classify(own, tgt, th)
    new_own = replace(own, course_deg=_wrap360(own.course_deg + alteration_deg))
    dcpa, tcpa = cpa_tcpa(new_own, tgt)
    checks: dict[str, bool] = {}
    role, enc = before["role"], before["encounter"]
    if role == "give_way":
        if enc in ("head_on", "crossing_starboard"):
            checks["starboard_alteration"] = alteration_deg > 0.0
        checks["readily_apparent"] = abs(alteration_deg) >= th.min_apparent_deg
        checks["passing_distance"] = dcpa >= th.dcpa_min_m or tcpa <= 0.0
        if enc == "crossing_starboard":
            checks["not_crossing_ahead"] = _crosses_ahead(new_own, tgt) is not True
    elif role == "stand_on":
        checks["kept_course"] = alteration_deg == 0.0  # Rule 17(a)(i); 17(b) not modelled
    return {
        "label": LABEL,
        "scenario": before,
        "alteration_deg": alteration_deg,
        "dcpa_after_m": dcpa,
        "tcpa_after_s": tcpa,
        "checks": checks,
        "passed": all(checks.values()) if checks else None,
        "notes": NOT_A_COMPLIANCE_CLAIM,
    }


def collision_course_targets(
    own: Vessel, range_m: float, rel_bearing_deg: float, tgt_speed: float
) -> list[Vessel]:
    """Targets at (range, relative bearing) whose course makes CPA = 0 (0, 1 or 2 solutions).

    Two solutions exist when the target is slower than own ship: a fast-closing
    one (e.g. head-on) and a slow-closing one (e.g. own overtaking).
    """
    brg = math.radians(own.course_deg + rel_bearing_deg)
    dx, dy = math.sin(brg), math.cos(brg)
    x, y = own.x + range_m * dx, own.y + range_m * dy
    ox, oy = own.velocity
    # target velocity v_t = v_o - k d̂ with |v_t| = tgt_speed and k > 0 (closing along the LOS)
    b = ox * dx + oy * dy
    disc = b * b - (ox * ox + oy * oy) + tgt_speed * tgt_speed
    if disc < 0:
        return []
    roots = sorted({b + math.sqrt(disc), b - math.sqrt(disc)}, reverse=True)
    out = []
    for k in (k for k in roots if k > 1e-9):
        vx, vy = ox - k * dx, oy - k * dy
        out.append(Vessel(x, y, _wrap360(math.degrees(math.atan2(vx, vy))), tgt_speed))
    return out


def scenario_suite(
    own_speed: float = 6.0,
    range_m: float = 3704.0,
    bearings_deg: tuple[float, ...] = (0.0, 30.0, 60.0, 90.0, 180.0, 270.0, 300.0, 330.0),
    speed_ratios: tuple[float, ...] = (0.5, 1.0, 1.5),
    th: Thresholds = Thresholds(),
) -> list[dict[str, Any]]:
    """Deterministic grid of collision-course encounters (own at origin heading north)."""
    own = Vessel(0.0, 0.0, 0.0, own_speed)
    out = []
    for b in bearings_deg:
        for r in speed_ratios:
            for j, tgt in enumerate(collision_course_targets(own, range_m, b, own_speed * r)):
                c = classify(own, tgt, th)
                out.append({"id": f"brg{int(b):03d}_v{r:g}_{j}", "own": own, "target": tgt, **c})
    return out
