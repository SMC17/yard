"""COLREG scenario suite v1: parameterised encounters, sensor-degraded variants,
a simple rule-based baseline controller, and ground-truth metrics.

LABEL: ``colreg_suite_v1``. **Geometry / kinematics only.** Builds on
``colreg_stub_v0`` (same frame, thresholds and geometric rule readings). It is a
test harness for collision-avoidance *controllers*; it is not a COLREG
compliance check, not a DNV / class / flag-state method, and not a replication
of any published scenario catalogue. What it adds over the stub:

* **Generator** for head-on, crossing (give-way / stand-on), overtaking,
  overtaken and multi-ship encounters with seeded ranges, bearings, speed
  ratios, time-to-CPA and initial CPA offsets; each generated target is
  re-classified and rejected unless it lands in the requested encounter type.
* **Variants**: ``nominal``; ``gnss_degraded`` (own-position bias + drift +
  noise — targets arrive as absolute AIS-like tracks, so own-position error
  corrupts the relative picture); ``comms_loss`` (target tracks drop out for a
  window → dead reckoning); ``comms_loss_manoeuvre`` (as comms_loss, and a
  target alters course during the blackout, so dead reckoning goes stale).
  Opt-in (not in the default ``VARIANTS`` table): ``gnss_spoof_ramp`` — GNSS
  correct at first, then a spoofing-like pull-off that grows linearly from an
  onset time during the approach. Every variant also carries a small constant
  heading/speed-log bias on the ``own_velocity`` channel (``DR_SENSOR_BIAS``,
  convention) so a dead-reckoning integrity monitor is never error-free.
* **Target behaviour**: scripted (constant course / speed + scripted
  manoeuvres, the default) or, with ``simulate(..., reciprocal=True)``,
  *rule-following*: each target runs its own copy of the baseline controller
  from its own perspective (true AIS-like picture of own ship and the other
  targets, same rate limit), so a give-way target alters to starboard and a
  stand-on target keeps course until last resort. Scripted manoeuvres shift the
  target's route.
* **Own-ship dynamics**: constant speed, heading rate-limited to
  ``max_rot_deg_s`` (convention). Targets keep course and speed except for
  scripted manoeuvres. No hydrodynamics, wind, current, or ship domain.
* **Baseline controller**: starboard-preferring course alteration (smallest
  alteration ≥ ``min_apparent_deg`` that restores the perceived passing
  distance to every target), Rule 17 stand-on with a last-resort turn, resume
  route when every target is perceived clear.
* **Metrics on ground truth**: minimum range, collision, passing distance,
  rule-consistent manoeuvre (starboard + readily apparent + early for give-way,
  not crossing ahead, stand-on kept course until last resort), time-to-resolve,
  cross-track deviation, return to route.

All thresholds are labelled conventions. Restricted visibility (Rule 19), TSS /
narrow channels, vessel categories, signals and good seamanship are not modelled.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field, replace
from typing import Any, Callable, Sequence

import numpy as np

from .colreg_stub import (
    Thresholds,
    Vessel,
    _crosses_ahead,
    _wrap360,
    classify,
    collision_course_targets,
    cpa_tcpa,
)
from .faults import Fault, FaultInjector

LABEL = "colreg_suite_v1"
NOT_A_COMPLIANCE_CLAIM = (
    "Kinematics-only scenario suite with convention thresholds. Not COLREG "
    "compliance, not a DNV / class / flag-state method, not a published catalogue."
)
KINDS = ("head_on", "crossing_starboard", "crossing_port", "overtaking", "overtaken", "multi_ship")
VARIANTS = ("nominal", "gnss_degraded", "comms_loss", "comms_loss_manoeuvre")
EXTRA_VARIANTS = ("gnss_spoof_ramp",)
ALL_VARIANTS = VARIANTS + EXTRA_VARIANTS
# Constant heading [deg] and speed-log [m/s] bias seen by the own-ship velocity
# sensors (gyro / log) — an evaluation convention, not a sensor specification.
DR_SENSOR_BIAS = (0.5, 0.03)


@dataclass(frozen=True)
class SuiteConventions:
    dt_s: float = 5.0
    max_rot_deg_s: float = 0.6
    collision_radius_m: float = 150.0
    passing_ok_frac: float = 0.8  # true min range ≥ frac · dcpa_min counts as a pass
    early_action_tcpa_s: float = 300.0  # give-way action counted "early" above this TCPA
    last_resort_frac: float = 0.5  # stand-on acts when perceived DCPA < frac·dcpa_min ...
    close_quarters_m: float = 3000.0  # ... and range < this
    clear_margin: float = 0.15  # controller aims for (1+margin)·dcpa_min perceived
    min_hold_s: float = 60.0


# ---------------------------------------------------------------- scenarios
@dataclass
class Scenario:
    id: str
    kind: str
    variant: str
    own: Vessel
    targets: list[Vessel]
    manoeuvres: list[tuple[float, int, float]] = field(default_factory=list)  # (t, idx, Δcourse)
    faults: list[Fault] = field(default_factory=list)
    seed: int = 0
    horizon_s: float = 3600.0

    def to_dict(self) -> dict[str, Any]:
        v = lambda s: {"x": s.x, "y": s.y, "course_deg": s.course_deg, "speed": s.speed}  # noqa: E731
        return {"id": self.id, "kind": self.kind, "variant": self.variant, "seed": self.seed,
                "own": v(self.own), "targets": [v(t) for t in self.targets],
                "manoeuvres": [list(m) for m in self.manoeuvres],
                "faults": [f.to_dict() for f in self.faults], "horizon_s": self.horizon_s}


_SECTORS = {  # (relative bearing range deg, speed-ratio range, solution preference)
    "head_on": ((-3.0, 3.0), (0.7, 1.4)),
    "crossing_starboard": ((15.0, 100.0), (0.6, 1.3)),
    "crossing_port": ((260.0, 345.0), (0.6, 1.3)),
    "overtaking": ((-12.0, 12.0), (0.3, 0.6)),
    "overtaken": ((165.0, 195.0), (1.4, 2.0)),
}


def _one_target(kind: str, own: Vessel, rng: np.random.Generator, th: Thresholds,
                tcpa_s: float, offset_m: float) -> Vessel | None:
    (b0, b1), (r0, r1) = _SECTORS[kind]
    for _ in range(200):
        brg = _wrap360(rng.uniform(b0, b1))
        ratio = rng.uniform(r0, r1)
        for tgt in collision_course_targets(own, 3704.0, brg, own.speed * ratio):
            _, t = cpa_tcpa(own, tgt)
            if t <= 0:
                continue
            s = tcpa_s / t  # constant velocities: geometry scales with range
            tgt = replace(tgt, x=own.x + (tgt.x - own.x) * s, y=own.y + (tgt.y - own.y) * s)
            if offset_m:  # shift perpendicular to the target's track → non-zero initial CPA
                c = math.radians(tgt.course_deg)
                tgt = replace(tgt, x=tgt.x + offset_m * math.cos(c), y=tgt.y - offset_m * math.sin(c))
            c = classify(own, tgt, th)
            if c["encounter"] == kind and c["dcpa_m"] < th.dcpa_min_m and c["tcpa_s"] > 0:
                return tgt  # risk is re-judged by the controller once inside its look-ahead
    return None


_MULTI = (("head_on", "crossing_starboard"), ("crossing_starboard", "crossing_port"),
          ("overtaking", "crossing_port"), ("head_on", "crossing_port", "crossing_starboard"))


def generate(kind: str, seed: int = 0, variant: str = "nominal", *, own_speed: float = 6.0,
             tcpa_range: tuple[float, float] = (900.0, 1500.0),
             offset_range: tuple[float, float] = (0.0, 300.0),
             th: Thresholds = Thresholds(),
             dr_sensor_bias: tuple[float, float] | None = DR_SENSOR_BIAS) -> Scenario:
    if kind not in KINDS:
        raise ValueError(f"kind must be one of {KINDS}")
    if variant not in ALL_VARIANTS:
        raise ValueError(f"variant must be one of {ALL_VARIANTS}")
    rng = np.random.default_rng([seed, KINDS.index(kind), ALL_VARIANTS.index(variant)])
    own = Vessel(0.0, 0.0, 0.0, own_speed)
    parts = _MULTI[int(rng.integers(len(_MULTI)))] if kind == "multi_ship" else (kind,)
    base_tcpa = rng.uniform(*tcpa_range)
    targets = []
    for i, k in enumerate(parts):
        tc = base_tcpa + (rng.uniform(-150.0, 150.0) if i else 0.0)
        if k == "overtaking":
            tc = max(tc, 1200.0)  # slow closing: keep the encounter inside the horizon
        tgt = _one_target(k, own, rng, th, tc, rng.uniform(*offset_range) * rng.choice([-1, 1]))
        if tgt is None:
            raise RuntimeError(f"could not generate {k} target (seed {seed})")
        targets.append(tgt)
    tmax = max(cpa_tcpa(own, t)[1] for t in targets)
    faults: list[Fault] = []
    manoeuvres: list[tuple[float, int, float]] = []
    if variant == "gnss_degraded":
        ang = rng.uniform(0, 2 * math.pi)
        b = rng.uniform(150.0, 400.0)
        faults = [Fault("bias", "own_position", (b * math.cos(ang), b * math.sin(ang))),
                  Fault("drift", "own_position", (0.05, -0.05)),
                  Fault("noise", "own_position", 25.0)]
    elif variant == "gnss_spoof_ramp":
        ang = rng.uniform(0, 2 * math.pi)
        rate = rng.uniform(0.5, 1.5)  # m/s pull-off
        t0 = max(0.0, base_tcpa - rng.uniform(700.0, 1000.0))
        faults = [Fault("drift", "own_position", (rate * math.cos(ang), rate * math.sin(ang)), t0),
                  Fault("noise", "own_position", 25.0)]
    elif variant.startswith("comms_loss"):
        t0 = max(0.0, base_tcpa - rng.uniform(700.0, 900.0))
        faults = [Fault("dropout", "target_track", 0.0, t0, t0 + rng.uniform(400.0, 600.0))]
        if variant == "comms_loss_manoeuvre":
            manoeuvres = [(t0 + 60.0, 0, float(rng.choice([-25.0, 25.0])))]
    if dr_sensor_bias is not None:
        faults = faults + [Fault("bias", "own_velocity", tuple(dr_sensor_bias))]
    return Scenario(id=f"{kind}_{variant}_s{seed}", kind=kind, variant=variant, own=own,
                    targets=targets, manoeuvres=manoeuvres, faults=faults, seed=seed,
                    horizon_s=min(4800.0, 2.0 * tmax + 900.0))


# ---------------------------------------------------------------- controller
Policy = Callable[[float, Vessel, list[Vessel], float], float]


@dataclass
class BaselineColregController:
    """Rule-based baseline: starboard give-way, Rule 17 stand-on + last resort, resume route."""

    th: Thresholds = field(default_factory=Thresholds)
    conv: SuiteConventions = field(default_factory=SuiteConventions)
    alterations: tuple[float, ...] = tuple(range(30, 95, 5))
    mode: str = "transit"
    commanded_alt: float = 0.0
    since: float = 0.0
    log: list[dict[str, Any]] = field(default_factory=list)

    name = "baseline_rule_v1"

    def _clear(self, own: Vessel, targets: list[Vessel]) -> bool:
        need = self.th.dcpa_min_m * (1.0 + self.conv.clear_margin)
        for tg in targets:
            d, t = cpa_tcpa(own, tg)
            if t > 0 and d < need:
                return False
        return True

    def _pick(self, own: Vessel, route: float, targets: list[Vessel]) -> float:
        for a in self.alterations:
            if a < self.commanded_alt:
                continue
            if self._clear(replace(own, course_deg=_wrap360(route + a)), targets):
                return float(a)
        return float(self.alterations[-1])

    def __call__(self, t: float, own: Vessel, targets: list[Vessel], route: float) -> float:
        cls = [classify(own, tg, self.th) for tg in targets]
        give = [c for c in cls if c["risk_of_collision"] and c["role"] == "give_way"]
        stand = [c for c in cls if c["risk_of_collision"] and c["role"] == "stand_on"]
        prev = self.mode
        if self.mode == "transit":
            if give:
                self.mode, self.commanded_alt = "give_way", self._pick(own, route, targets)
            elif stand and any(c["dcpa_m"] < self.conv.last_resort_frac * self.th.dcpa_min_m
                               and _range(own, tg) < self.conv.close_quarters_m
                               for c, tg in zip(cls, targets) if c["role"] == "stand_on"):
                self.mode, self.commanded_alt = "last_resort", self._pick(own, route, targets)
        else:
            on_route = replace(own, course_deg=route)
            if t - self.since >= self.conv.min_hold_s and self._clear(on_route, targets):
                self.mode, self.commanded_alt = "transit", 0.0
            elif not self._clear(replace(own, course_deg=_wrap360(route + self.commanded_alt)), targets):
                self.commanded_alt = self._pick(own, route, targets)
        if self.mode != prev:
            self.since = t
            self.log.append({"t": t, "mode": self.mode, "alteration_deg": self.commanded_alt})
        return _wrap360(route + self.commanded_alt)


def _range(a: Vessel, b: Vessel) -> float:
    return math.hypot(a.x - b.x, a.y - b.y)


def _ang(a: float, b: float) -> float:
    return (a - b + 180.0) % 360.0 - 180.0


# ---------------------------------------------------------------- simulation
def simulate(sc: Scenario, policy: Policy | None = None, *, th: Thresholds = Thresholds(),
             conv: SuiteConventions = SuiteConventions(), wrapper: Any = None,
             reciprocal: bool = False) -> dict[str, Any]:
    """Run one scenario. ``policy(t, own_perceived, targets_perceived, route) -> course``.

    ``wrapper`` (optional) is a runtime-assurance object with
    ``filter(t, own_p, targets_p, route, proposed) -> course`` and ``summary()``;
    if it has ``reset(own0)`` it is called once with the scenario's initial own
    state — modelling a trusted navigation fix taken before the run (convention).
    """
    policy = policy if policy is not None else BaselineColregController(th=th, conv=conv)
    gen = simulate_iter(sc, th=th, conv=conv, wrapper=wrapper, reciprocal=reciprocal, meta=policy)
    try:
        obs = next(gen)
        while True:
            obs = gen.send(policy(*obs))
    except StopIteration as stop:
        return stop.value


def simulate_iter(sc: Scenario, *, th: Thresholds = Thresholds(), conv: SuiteConventions = SuiteConventions(),
                  wrapper: Any = None, reciprocal: bool = False, meta: Any = None,
                  expose_truth: bool = False):
    """Generator form of ``simulate`` for step-wise (e.g. RL) control.

    Yields ``(t, own_perceived, targets_perceived, route)`` every ``dt_s``; send the
    proposed course back. ``StopIteration.value`` is the same result dict as
    ``simulate``. ``meta`` supplies ``name`` / ``log`` for the result (optional).
    ``expose_truth=True`` appends ``(own_true, targets_true)`` to each yield — for
    training-time reward shaping only; a deployed policy must not see it.
    """
    policy = meta
    inj = FaultInjector(list(sc.faults), seed=sc.seed)
    own, route = sc.own, sc.own.course_deg
    tgts = list(sc.targets)
    known: list[tuple[float, Vessel] | None] = [None] * len(tgts)
    own_est: Vessel | None = None
    # roles judged without the look-ahead cap: every generated target is a real encounter
    init = [classify(own, tg, replace(th, tcpa_max_s=math.inf)) for tg in tgts]
    pending = [list(m) for m in sc.manoeuvres]
    t_routes = [tg.course_deg for tg in tgts]
    t_ctrl = [BaselineColregController(th=th, conv=conv) for _ in tgts] if reciprocal else None
    first_risk = 0.0 if any(c["risk_of_collision"] for c in init) else None
    min_rng = [math.inf] * len(tgts)
    trace: list[dict[str, Any]] = []
    first_alt: dict[str, Any] | None = None
    last_resort_ok = [False] * len(tgts)  # true-geometry last-resort condition reached
    resolved_t = None
    max_xtrack = 0.0
    if wrapper is not None and hasattr(wrapper, "reset"):
        wrapper.reset(sc.own)
    t = 0.0
    while t <= sc.horizon_s:
        for m in pending:
            if m[0] is not None and t >= m[0]:
                tgts[m[1]] = replace(tgts[m[1]], course_deg=_wrap360(tgts[m[1]].course_deg + m[2]))
                t_routes[m[1]] = _wrap360(t_routes[m[1]] + m[2])
                m[0] = None
        # perception
        p = inj.apply("own_position", t, (own.x, own.y))
        if p is None:
            own_est = own_est.at(conv.dt_s) if own_est else own
        else:
            own_est = replace(own, x=float(p[0]), y=float(p[1]))
        vel = inj.apply("own_velocity", t, (own.course_deg, own.speed))
        own_est = replace(own_est, course_deg=float(vel[0]) % 360.0 if vel is not None else own.course_deg,
                          speed=float(vel[1]) if vel is not None else own.speed)
        perceived = []
        for i, tg in enumerate(tgts):
            r = inj.apply("target_track", t, (tg.x, tg.y, tg.course_deg, tg.speed))
            if r is not None:
                known[i] = (t, Vessel(float(r[0]), float(r[1]), float(r[2]) % 360.0, float(r[3])))
            if known[i] is None:
                continue
            t_rx, v = known[i]
            perceived.append(v.at(t - t_rx))
        obs = (t, own_est, perceived, route) + (((own, list(tgts)),) if expose_truth else ())
        cmd = float((yield obs))
        if wrapper is not None:
            cmd = wrapper.filter(t, own_est, perceived, route, cmd)
        if first_alt is None and abs(_ang(cmd, route)) > 1.0:
            first_alt = {"t": t, "alteration_deg": _ang(cmd, route),
                         "true_tcpa_s": [cpa_tcpa(own, tg)[1] for tg in tgts],
                         "crosses_ahead": [_crosses_ahead(replace(own, course_deg=cmd), tg) for tg in tgts],
                         "last_resort_true": [
                             cpa_tcpa(own, tg)[0] < conv.last_resort_frac * th.dcpa_min_m
                             and _range(own, tg) < conv.close_quarters_m for tg in tgts]}
        # truth metrics
        for i, tg in enumerate(tgts):
            rr = _range(own, tg)
            min_rng[i] = min(min_rng[i], rr)
        max_xtrack = max(max_xtrack, abs(own.x))  # route is due north through the origin
        if resolved_t is None and first_risk is not None and t > 0:
            if all(cpa_tcpa(own, tg)[1] <= 0 and _range(own, tg) >= conv.passing_ok_frac * th.dcpa_min_m
                   for tg in tgts):
                resolved_t = t
        if int(t) % 60 == 0:
            trace.append({"t": t, "own": (own.x, own.y, own.course_deg), "cmd": cmd})
        # dynamics
        dc = max(-conv.max_rot_deg_s * conv.dt_s, min(conv.max_rot_deg_s * conv.dt_s, _ang(cmd, own.course_deg)))
        if t_ctrl is not None:
            new = []
            for i, tg in enumerate(tgts):
                others = [own] + [o for j, o in enumerate(tgts) if j != i]
                tc = t_ctrl[i](t, tg, others, t_routes[i])
                tdc = max(-conv.max_rot_deg_s * conv.dt_s,
                          min(conv.max_rot_deg_s * conv.dt_s, _ang(tc, tg.course_deg)))
                new.append(replace(tg, course_deg=_wrap360(tg.course_deg + tdc)))
            tgts = new
        own = replace(own, course_deg=_wrap360(own.course_deg + dc)).at(conv.dt_s)
        tgts = [tg.at(conv.dt_s) for tg in tgts]
        t += conv.dt_s
    rules = _rule_checks(init, first_alt, conv, th)
    overall_min = min(min_rng) if min_rng else math.inf
    return {
        "label": LABEL, "scenario": sc.to_dict(), "controller": getattr(policy, "name", "custom"),
        "initial_classification": [{k: c[k] for k in ("encounter", "role", "dcpa_m", "tcpa_s")} for c in init],
        "min_range_m": overall_min, "min_range_per_target_m": min_rng,
        "collision": overall_min < conv.collision_radius_m,
        "passing_ok": overall_min >= conv.passing_ok_frac * th.dcpa_min_m,
        "rule_checks": rules, "rule_consistent": all(rules.values()) if rules else True,
        "first_alteration": first_alt,
        "time_to_resolve_s": (resolved_t - first_risk) if resolved_t is not None else None,
        "max_cross_track_m": max_xtrack,
        "returned_to_route": abs(_ang(own.course_deg, route)) < 1.0,
        "faults": inj.summary(),
        "controller_log": list(getattr(policy, "log", [])),
        "runtime_assurance": wrapper.summary() if wrapper is not None else None,
        "target_behaviour": "rule_following_baseline" if reciprocal else "scripted",
        "target_logs": [list(c.log) for c in t_ctrl] if t_ctrl is not None else None,
        "trace_60s": trace, "notes": NOT_A_COMPLIANCE_CLAIM,
    }


def _rule_checks(init: list[dict[str, Any]], first_alt: dict[str, Any] | None,
                 conv: SuiteConventions, th: Thresholds) -> dict[str, bool]:
    checks: dict[str, bool] = {}
    give = [i for i, c in enumerate(init) if c["risk_of_collision"] and c["role"] == "give_way"]
    stand = [i for i, c in enumerate(init) if c["risk_of_collision"] and c["role"] == "stand_on"]
    for i in give:
        enc = init[i]["encounter"]
        if first_alt is None:
            checks[f"t{i}_{enc}_took_action"] = False
            continue
        a = first_alt["alteration_deg"]
        if enc in ("head_on", "crossing_starboard"):
            checks[f"t{i}_{enc}_starboard"] = a > 0
        checks[f"t{i}_{enc}_readily_apparent"] = abs(a) >= th.min_apparent_deg - 1e-6
        checks[f"t{i}_{enc}_early"] = first_alt["true_tcpa_s"][i] >= conv.early_action_tcpa_s
        if enc == "crossing_starboard":
            checks[f"t{i}_not_crossing_ahead"] = first_alt["crosses_ahead"][i] is not True
    if stand and not give:  # pure stand-on: no alteration unless the last-resort condition held
        for i in stand:
            ok = first_alt is None or first_alt["last_resort_true"][i]
            checks[f"t{i}_{init[i]['encounter']}_kept_course_until_last_resort"] = bool(ok)
    return checks


# ---------------------------------------------------------------- suite
def run_suite(kinds: Sequence[str] = KINDS, variants: Sequence[str] = VARIANTS,
              seeds: Sequence[int] = (0, 1, 2), policy_factory: Callable[[], Policy] | None = None,
              wrapper_factory: Callable[[], Any] | None = None, *, th: Thresholds = Thresholds(),
              conv: SuiteConventions = SuiteConventions(), keep_traces: bool = False,
              reciprocal: bool = False) -> dict[str, Any]:
    rows = []
    for k in kinds:
        for v in variants:
            for s in seeds:
                sc = generate(k, s, v, th=th)
                pol = policy_factory() if policy_factory else BaselineColregController(th=th, conv=conv)
                res = simulate(sc, pol, th=th, conv=conv,
                               wrapper=wrapper_factory() if wrapper_factory else None,
                               reciprocal=reciprocal)
                if not keep_traces:
                    res.pop("trace_60s", None)
                rows.append(res)
    agg: dict[str, dict[str, Any]] = {}
    for r in rows:
        key = f"{r['scenario']['kind']}/{r['scenario']['variant']}"
        agg.setdefault(key, []).append(r)  # type: ignore[arg-type]
    table = {}
    for key, rs in agg.items():
        ttr = [r["time_to_resolve_s"] for r in rs if r["time_to_resolve_s"] is not None]
        table[key] = {
            "n": len(rs),
            "collision_rate": float(np.mean([r["collision"] for r in rs])),
            "passing_ok_rate": float(np.mean([r["passing_ok"] for r in rs])),
            "rule_consistent_rate": float(np.mean([r["rule_consistent"] for r in rs])),
            "min_range_m_min": float(min(r["min_range_m"] for r in rs)),
            "time_to_resolve_s_median": float(np.median(ttr)) if ttr else None,
        }
    return {"label": LABEL, "n": len(rows), "summary": table, "results": rows, "reciprocal": reciprocal,
            "conventions": conv.__dict__, "thresholds": th.__dict__, "notes": NOT_A_COMPLIANCE_CLAIM}


def main(argv: Sequence[str] | None = None) -> int:
    """``python -m yard_sea_v0.colreg_suite --seeds 5 --out out/colreg_suite.json``"""
    import argparse
    import json
    from pathlib import Path

    ap = argparse.ArgumentParser(prog="yard_sea_v0.colreg_suite")
    ap.add_argument("--seeds", type=int, default=5)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--reciprocal", action="store_true", help="targets follow the rules too")
    a = ap.parse_args(argv)
    res = run_suite(seeds=tuple(range(a.seeds)), reciprocal=a.reciprocal)
    for key, row in res["summary"].items():
        print(f"{key:40s} n={row['n']} coll={row['collision_rate']:.2f} "
              f"pass={row['passing_ok_rate']:.2f} rules={row['rule_consistent_rate']:.2f} "
              f"min_range={row['min_range_m_min']:.0f}m")
    if a.out:
        a.out.parent.mkdir(parents=True, exist_ok=True)
        a.out.write_text(json.dumps(res, indent=1, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
