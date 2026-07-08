#!/usr/bin/env python3
"""
yard-seakeeping-oracle — Python reference mirroring compose/seakeeping_assessment.zig.

Ground truth for dataset generation and agent harness verification.
Formulas trace to:
  - seakeeping/src/spectra.zig (ITTC modified PM)
  - strip-theory/src/heave.zig (RAO modulus)
  - rao-spectrum/src/spectrum.zig (response spectrum, moments)
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from enum import Enum
from typing import Sequence


G = 9.80665
RHO_SEAWATER = 1025.0


class ValidityFlag(str, Enum):
    SMALL_ANGLE_REGIME = "small_angle_regime"
    WALL_SIDED_VALID = "wall_sided_assumption_valid"
    OUTSIDE_ENVELOPE = "outside_validity_envelope"


@dataclass
class SeaState:
    Hs_m: float
    Tz_s: float


@dataclass
class HeaveCoeffs:
    M_kg: float
    A_33: float
    B_33: float
    C_33: float
    F_mag: float


@dataclass
class OperabilityLimits:
    max_heave_m: float = 2.0
    max_roll_deg: float = 15.0


@dataclass
class SeakeepingInput:
    L: float
    B: float
    T: float
    sea: SeaState
    heave: HeaveCoeffs
    limits: OperabilityLimits = field(default_factory=OperabilityLimits)
    omega_min: float = 0.2
    omega_max: float = 2.0
    omega_step: float = 0.1


@dataclass
class MotionStats:
    m0_wave: float
    m0_response: float
    significant_heave_m: float
    mean_zero_crossing_period_s: float
    peak_rao: float
    peak_omega_rad_s: float


@dataclass
class SimulationStats:
    max_heave_m: float
    max_roll_rad: float
    operability_pass: bool


@dataclass
class SeakeepingOutput:
    stats: MotionStats
    simulation: SimulationStats
    flags: list[str]


def ittc_modified_pm(omega: float, Hs_m: float, Tz_s: float) -> float:
    if omega <= 0.0:
        return 0.0
    pi3 = math.pi**3
    tz4 = Tz_s**4
    A = 4.0 * pi3 * Hs_m * Hs_m / tz4
    B = 16.0 * pi3 / tz4
    w4 = omega**4
    w5 = w4 * omega
    return (A / w5) * math.exp(-B / w4)


def rao_modulus(M: float, A_33: float, B_33: float, C_33: float, F_mag: float, omega: float) -> float:
    m_eff = M + A_33
    if m_eff <= 0.0 or C_33 <= 0.0:
        raise ValueError("non-positive mass or restoring")
    d_re = -m_eff * omega * omega + C_33
    d_im = B_33 * omega
    d_mag_sq = d_re * d_re + d_im * d_im
    x_re = F_mag * d_re / d_mag_sq
    x_im = -F_mag * d_im / d_mag_sq
    return math.hypot(x_re, x_im)


def simpson_uniform(f: Sequence[float], h: float) -> float:
    n = len(f)
    if n < 4 or h <= 0.0:
        raise ValueError("insufficient points or invalid spacing")
    intervals = n - 1
    use_3_8_tail = (intervals % 2) != 0
    total = 0.0
    last_for_13 = n - 4 if use_3_8_tail else n - 1
    if last_for_13 >= 2:
        s = f[0] + f[last_for_13]
        for i in range(1, last_for_13):
            s += (4.0 if i % 2 == 1 else 2.0) * f[i]
        total += s * h / 3.0
    if use_3_8_tail:
        a, b, c, d = f[-4], f[-3], f[-2], f[-1]
        total += (3.0 * h / 8.0) * (a + 3.0 * b + 3.0 * c + d)
    return total


def spectral_moment(n: int, omega: Sequence[float], S: Sequence[float]) -> float:
    if len(omega) != len(S) or len(omega) < 4:
        raise ValueError("invalid spectrum arrays")
    h = omega[1] - omega[0]
    tol = 1e-9 * max(abs(h), 1.0)
    for i in range(1, len(omega)):
        if not omega[i] > omega[i - 1]:
            raise ValueError("omega not sorted")
        if i < len(omega) - 1 and abs((omega[i + 1] - omega[i]) - h) > tol:
            raise ValueError("non-uniform spacing")
    integrand = [(w**n) * s for w, s in zip(omega, S)]
    return simpson_uniform(integrand, h)


def significant_response_amplitude(m0: float) -> float:
    return 4.0 * math.sqrt(m0)


def mean_zero_crossing_period(m0: float, m2: float) -> float:
    return 2.0 * math.pi * math.sqrt(m0 / m2)


def _derivative(eta: list[float], nu: list[float], M: list[float], D: list[float], K: list[float], tau: list[float]) -> tuple[list[float], list[float]]:
    d_eta = list(nu)
    g = [0.0, 0.0, K[0] * eta[2], K[1] * eta[3], K[2] * eta[4], 0.0]
    d_nu = [(tau[i] - D[i] * nu[i] - g[i]) / M[i] for i in range(6)]
    return d_eta, d_nu


def _add_scaled(eta: list[float], nu: list[float], d_eta: list[float], d_nu: list[float], scale: float) -> tuple[list[float], list[float]]:
    return (
        [eta[i] + scale * d_eta[i] for i in range(6)],
        [nu[i] + scale * d_nu[i] for i in range(6)],
    )


def rk4_step(eta: list[float], nu: list[float], M: list[float], D: list[float], K: list[float], tau: list[float], h: float) -> tuple[list[float], list[float]]:
    k1_e, k1_n = _derivative(eta, nu, M, D, K, tau)
    e2, n2 = _add_scaled(eta, nu, k1_e, k1_n, 0.5 * h)
    k2_e, k2_n = _derivative(e2, n2, M, D, K, tau)
    e3, n3 = _add_scaled(eta, nu, k2_e, k2_n, 0.5 * h)
    k3_e, k3_n = _derivative(e3, n3, M, D, K, tau)
    e4, n4 = _add_scaled(eta, nu, k3_e, k3_n, h)
    k4_e, k4_n = _derivative(e4, n4, M, D, K, tau)
    new_eta = [eta[i] + (h / 6.0) * (k1_e[i] + 2 * k2_e[i] + 2 * k3_e[i] + k4_e[i]) for i in range(6)]
    new_nu = [nu[i] + (h / 6.0) * (k1_n[i] + 2 * k2_n[i] + 2 * k3_n[i] + k4_n[i]) for i in range(6)]
    return new_eta, new_nu


def evaluate_seakeeping(inp: SeakeepingInput) -> SeakeepingOutput:
    if inp.sea.Hs_m <= 0.0 or inp.sea.Tz_s <= 0.0 or inp.omega_step <= 0.0:
        raise ValueError("invalid sea state")

    n = int(math.floor((inp.omega_max - inp.omega_min) / inp.omega_step)) + 1
    omega: list[float] = []
    s_wave: list[float] = []
    h_mag_sq: list[float] = []
    peak_rao = 0.0
    peak_omega = inp.omega_min

    w = inp.omega_min
    for _ in range(n):
        omega.append(w)
        s_wave.append(ittc_modified_pm(w, inp.sea.Hs_m, inp.sea.Tz_s))
        rao = rao_modulus(
            inp.heave.M_kg,
            inp.heave.A_33,
            inp.heave.B_33,
            inp.heave.C_33,
            inp.heave.F_mag,
            w,
        )
        h_mag_sq.append(rao * rao)
        if rao > peak_rao:
            peak_rao = rao
            peak_omega = w
        w += inp.omega_step

    s_response = [h * s for h, s in zip(h_mag_sq, s_wave)]
    m0_wave = spectral_moment(0, omega, s_wave)
    m0_resp = spectral_moment(0, omega, s_response)
    m2_resp = spectral_moment(2, omega, s_response)
    sig_heave = significant_response_amplitude(m0_resp)
    tz_resp = mean_zero_crossing_period(m0_resp, m2_resp)

    V = inp.L * inp.B * inp.T
    K_z = RHO_SEAWATER * G * (inp.B * inp.L)
    K_phi = RHO_SEAWATER * G * 0.5 * V * inp.B / inp.T

    M_diag = [
        inp.heave.M_kg,
        inp.heave.M_kg,
        inp.heave.M_kg,
        inp.heave.M_kg * inp.B * inp.B / 12.0,
        inp.heave.M_kg * inp.L * inp.L / 12.0,
        inp.heave.M_kg * inp.L * inp.L / 12.0,
    ]
    D_lin = [1.0e4, 1.0e4, inp.heave.B_33, 1.0e5, 1.0e5, 1.0e5]
    K = [K_z, K_phi, K_phi]

    eta = [0.0] * 6
    nu = [0.0] * 6
    sim_duration_s = 60.0
    sim_dt_s = 0.1
    n_steps = int(sim_duration_s / sim_dt_s)
    wave_force_z = inp.heave.F_mag * inp.sea.Hs_m / 2.0
    max_heave = 0.0
    max_roll = 0.0
    t = 0.0
    for _ in range(n_steps):
        tau = [0.0, 0.0, wave_force_z * math.sin(peak_omega * t), 0.0, 0.0, 0.0]
        eta, nu = rk4_step(eta, nu, M_diag, D_lin, K, tau, sim_dt_s)
        t += sim_dt_s
        max_heave = max(max_heave, abs(eta[2]))
        max_roll = max(max_roll, abs(eta[3]))

    max_roll_deg = math.degrees(max_roll)
    op_pass = max_heave <= inp.limits.max_heave_m and max_roll_deg <= inp.limits.max_roll_deg

    flags: list[str] = [ValidityFlag.SMALL_ANGLE_REGIME.value]
    if peak_omega * sig_heave < 0.5:
        flags.append(ValidityFlag.WALL_SIDED_VALID.value)
    if not op_pass:
        flags.append(ValidityFlag.OUTSIDE_ENVELOPE.value)

    return SeakeepingOutput(
        stats=MotionStats(
            m0_wave=m0_wave,
            m0_response=m0_resp,
            significant_heave_m=sig_heave,
            mean_zero_crossing_period_s=tz_resp,
            peak_rao=peak_rao,
            peak_omega_rad_s=peak_omega,
        ),
        simulation=SimulationStats(
            max_heave_m=max_heave,
            max_roll_rad=max_roll,
            operability_pass=op_pass,
        ),
        flags=flags,
    )


def to_answer_dict(out: SeakeepingOutput) -> dict:
    return {
        "significant_heave_m": out.stats.significant_heave_m,
        "mean_zero_crossing_period_s": out.stats.mean_zero_crossing_period_s,
        "peak_rao": out.stats.peak_rao,
        "peak_omega_rad_s": out.stats.peak_omega_rad_s,
        "m0_response": out.stats.m0_response,
        "max_heave_m": out.simulation.max_heave_m,
        "max_roll_deg": math.degrees(out.simulation.max_roll_rad),
        "operability_pass": out.simulation.operability_pass,
        "flags": out.flags,
    }


def default_barge_input(
    L: float = 100.0,
    B: float = 16.0,
    T: float = 6.0,
    Hs_m: float = 2.0,
    Tz_s: float = 8.0,
) -> SeakeepingInput:
    V = L * B * T
    Aw = L * B
    C_33 = RHO_SEAWATER * G * Aw
    return SeakeepingInput(
        L=L,
        B=B,
        T=T,
        sea=SeaState(Hs_m=Hs_m, Tz_s=Tz_s),
        heave=HeaveCoeffs(
            M_kg=RHO_SEAWATER * V,
            A_33=0.2 * RHO_SEAWATER * V,
            B_33=5.0e5,
            C_33=C_33,
            F_mag=C_33,
        ),
    )


if __name__ == "__main__":
    out = evaluate_seakeeping(default_barge_input())
    import json

    print(json.dumps(to_answer_dict(out), indent=2))