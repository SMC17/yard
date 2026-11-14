import numpy as np
import pytest

from yard_sea_v0.colreg_stub import Vessel
from yard_sea_v0.colreg_suite import ALL_VARIANTS, VARIANTS, BaselineColregController, generate, run_suite, simulate
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
    # pre-Rule-17(a)(ii) fallback: these were collisions before the stand-on fix
    old = lambda: BaselineColregController(rule17a=False)  # noqa: E731
    bare = simulate(sc, old())
    held = simulate(sc, HoldCoursePolicy(), wrapper=ColregRTA(fallback=old()))
    guarded = simulate(sc, HoldCoursePolicy(), wrapper=ColregRTA(fallback=old(), gnss_monitor=GnssIntegrityMonitor()))
    assert bare["collision"] and held["collision"]
    g = guarded["runtime_assurance"]["gnss_integrity"]
    assert g["suspect"] and not guarded["collision"]
    assert guarded["runtime_assurance"]["fallback_steps"] > 0


def test_degraded_gnss_detected_at_start_with_trusted_prefix():
    sc = generate("head_on", 1, "gnss_degraded")
    out = simulate(sc, wrapper=_rta())
    g = out["runtime_assurance"]["gnss_integrity"]
    assert g["suspect"] and g["t_detect"] == 0.0


def _drive(m, bias_fn, n=300, seed=0, noise=25.0):
    rng = np.random.default_rng(seed)
    for k in range(n):
        t = 5.0 * k
        b = bias_fn(t)
        e = rng.normal(0, noise, 2)
        m.update(t, Vessel(b[0] + e[0], 6.0 * t + b[1] + e[1], 0.0, 6.0))
    return m


def test_retrust_after_transient_clears_with_hysteresis():
    m = GnssIntegrityMonitor()
    m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    _drive(m, lambda t: (250.0, 0.0) if 200 <= t < 400 else (0.0, 0.0))
    ev = [e for e in m.events]
    assert ev[0]["event"] == "suspect" and 200 <= ev[0]["t"] < 220
    rt = [e for e in ev if e["event"] == "retrust"]
    assert rt and rt[0]["t"] >= 400 + 5.0 * (m.retrust_n - 1)  # needs N consistent fixes after it clears
    assert not m.suspect


def test_no_retrust_while_bias_persists_and_latch_mode():
    m = GnssIntegrityMonitor()
    m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    _drive(m, lambda t: (250.0, 0.0) if t >= 200 else (0.0, 0.0))
    assert m.suspect and not any(e["event"] == "retrust" for e in m.events)
    latch = GnssIntegrityMonitor(retrust_n=None)
    latch.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    _drive(latch, lambda t: (250.0, 0.0) if 200 <= t < 400 else (0.0, 0.0))
    assert latch.suspect and latch.summary()["n_retrust"] == 0


def test_no_retrust_once_dr_uncertainty_exceeds_cap():
    m = GnssIntegrityMonitor(retrust_max_sigma_m=20.0)
    m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
    _drive(m, lambda t: (250.0, 0.0) if 100 <= t < 700 else (0.0, 0.0), n=400)
    assert m.suspect and m.summary()["n_retrust"] == 0  # 600 s of coasting → σ_DR ≈ 60 m > cap


def test_no_false_alarm_on_noisy_unbiased_gnss():
    flags = 0
    for seed in range(20):
        m = GnssIntegrityMonitor()
        m.reset(Vessel(0.0, 0.0, 0.0, 6.0))
        flags += _drive(m, lambda t: (0.0, 0.0), n=600, seed=seed).t_detect is not None
    assert flags <= 1
