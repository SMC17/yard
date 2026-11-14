import numpy as np
import pytest

from yard_sea_v0.colreg_stub import Vessel
from yard_sea_v0.colreg_suite import ALL_VARIANTS, VARIANTS, generate, run_suite, simulate
from yard_sea_v0.runtime_assurance import ColregRTA, GnssIntegrityMonitor, HoldCoursePolicy


def _rta():
    return ColregRTA(gnss_monitor=GnssIntegrityMonitor())


def test_monitor_flags_step_and_passes_consistent_fixes():
    m = GnssIntegrityMonitor()
    m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    for k in range(60):  # consistent fixes along the DR track
        out = m.update(5.0 * k, Vessel(0.0, 30.0 * k, 0.0, 6.0))
    assert not m.suspect and out.y == pytest.approx(30.0 * 59)
    out = m.update(300.0, Vessel(250.0, 1800.0, 0.0, 6.0))  # 250 m jump
    assert m.suspect and m.t_detect == 300.0
    assert abs(out.x) < 5.0  # RTA now navigates on DR, not the jumped fix


def test_window_test_catches_slow_ramp():
    m = GnssIntegrityMonitor()
    m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    rng = np.random.default_rng(0)
    t_det = None
    for k in range(400):
        t = 5.0 * k
        ramp = 0.0 if t < 300 else 0.6 * (t - 300)
        n = rng.normal(0, 25, 2)
        m.update(t, Vessel(ramp + n[0], 6.0 * t + n[1], 0.0, 6.0))
        if m.suspect:
            t_det = t
            break
    assert t_det is not None and 300 < t_det < 1300


def test_no_false_alarms_on_unfaulted_gnss():
    res = run_suite(("head_on", "crossing_starboard", "multi_ship"), ("nominal", "comms_loss"), range(4),
                    wrapper_factory=_rta)
    assert not any(r["runtime_assurance"]["gnss_integrity"]["suspect"] for r in res["results"])


def test_spoof_ramp_variant_is_opt_in_and_corrupts_after_onset():
    assert "gnss_spoof_ramp" in ALL_VARIANTS and "gnss_spoof_ramp" not in VARIANTS
    sc = generate("head_on", 0, "gnss_spoof_ramp")
    drift = [f for f in sc.faults if f.kind == "drift"][0]
    assert drift.t_start > 0 and any(f.channel == "own_velocity" for f in sc.faults)


@pytest.mark.parametrize("seed", [4, 20, 29])
def test_gnss_monitor_prevents_spoof_collisions_that_baseline_suffers(seed):
    sc = generate("crossing_port", seed, "gnss_spoof_ramp")
    bare = simulate(sc)
    held = simulate(sc, HoldCoursePolicy(), wrapper=ColregRTA())
    guarded = simulate(sc, HoldCoursePolicy(), wrapper=_rta())
    assert bare["collision"] and held["collision"]
    g = guarded["runtime_assurance"]["gnss_integrity"]
    assert g["suspect"] and not guarded["collision"]
    assert guarded["runtime_assurance"]["fallback_steps"] > 0


def test_degraded_gnss_detected_at_start_with_trusted_prefix():
    sc = generate("head_on", 1, "gnss_degraded")
    out = simulate(sc, wrapper=_rta())
    g = out["runtime_assurance"]["gnss_integrity"]
    assert g["suspect"] and g["t_detect"] == 0.0
