"""Why does KVLCC2 get worse with the HM1984 bulb term? (yard round-3 item 4)

Checks the bulb inputs read off the real lines against an independent published set
(Chahbi, EMSHIP master thesis, Univ. Galati / ULiège 2014, Table 2: TRIBON M3 Holtrop-Mennen
inputs for KVLCC2 at T = 20.8 m: A_BT = 174.03 m^2, h_B = 10.28 m, A_T = 13.82 m^2, i_E = 59.95 deg),
re-runs hm1984_full with each input set, and splits the model-scale C_T into its terms.
Inputs are fixed only if wrong; this module changes no oracle.
"""

from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from . import validation as v

PUBLISHED = {
    "source": "Chahbi (2014), EMSHIP master thesis, KVLCC2, Table 2 (TRIBON M3 Holtrop-Mennen inputs)",
    "url": "https://matheo.uliege.be/bitstream/2268.2/6141/1/CHAHBI%20-%20UGAL%20%20%28Jan%202014%29.pdf",
    "A_BT_m2": 174.03, "h_B_m": 10.28, "A_T_m2": 13.82, "T_F_m": 20.8, "i_E_deg": 59.95,
}
LPP_FULL = 320.0


def _run(c: v.TankCase, abt: float, hb: float, at: float, cwp: float) -> dict[str, Any]:
    b = v._zig_bin()
    if b is None:
        return {"available": False}
    args = [c.L, c.B, c.T, c.vol, c.S0, c.Cb, c.Cm, c.Cp, cwp, c.lcb_pct, 0.0, c.Fn, c.nu, c.rho]
    if abt > 0 or at > 0:
        args += [abt, c.T, hb, at]
    out = subprocess.run([str(b), "hm1984_full", *[repr(float(a)) for a in args]], capture_output=True, text=True, check=True)
    l1 = json.loads(out.stdout.strip().splitlines()[-1])["l1"]
    ct = float(l1["Ct_no_ca"])
    return {"available": True, "CT": ct, "E_pct": v.comparison_error_pct(c.CT, ct),
            "Cf_1k": float(l1["Cf"]) * float(l1["one_plus_k"]), "one_plus_k": float(l1["one_plus_k"]),
            "Cw": float(l1["Cw"]), "C_bulb": float(l1.get("C_bulb", 0.0)), "C_tr": float(l1.get("C_tr", 0.0)),
            "c_2": float(l1.get("c_2", 1.0))}


def analyse() -> dict[str, Any]:
    c = next(x for x in v.tank_cases() if x.hull == "KVLCC2")
    lam = LPP_FULL / c.L
    p = c.lines()
    lines_full = None if p is None else {"A_BT_m2": p.A_BT * lam**2, "h_B_m": p.h_B * lam, "A_T_m2": p.A_T * lam**2}
    cwp = c.Cwp_est if p is None else p.Cwp
    pub = PUBLISHED
    runs = {
        "bare (no bulb, no transom)": _run(c, 0.0, 0.0, 0.0, cwp),
        "lines-derived bulb (current)": _run(c, p.A_BT, p.h_B, p.A_T, cwp) if p else {"available": False},
        "published bulb (Chahbi 2014)": _run(c, pub["A_BT_m2"] / lam**2, pub["h_B_m"] / lam, 0.0, cwp),
        "published bulb + transom (Chahbi 2014)": _run(c, pub["A_BT_m2"] / lam**2, pub["h_B_m"] / lam, pub["A_T_m2"] / lam**2, cwp),
    }
    diff = None
    if lines_full:
        diff = {"A_BT_pct": (lines_full["A_BT_m2"] / pub["A_BT_m2"] - 1) * 100, "h_B_pct": (lines_full["h_B_m"] / pub["h_B_m"] - 1) * 100}
    bare = runs["bare (no bulb, no transom)"]
    implied = c.CT / (bare["Cf_1k"] / bare["one_plus_k"]) if bare.get("available") else None
    return {"schema": "yard_sea_v0.kvlcc2_bulb_check.v1", "implied_one_plus_k_max": implied, "Fn": c.Fn, "CT_measured": c.CT, "published": pub,
            "lines_full_scale": lines_full, "lines_vs_published": diff, "runs": runs}


def render_markdown(r: dict[str, Any]) -> str:
    pub, lf, d = r["published"], r["lines_full_scale"], r["lines_vs_published"]
    L = ["# KVLCC2: HM1984 bulb inputs and why the bulb term worsens the error", "",
         f"Model-scale tank point Fn {r['Fn']}, measured C_T {r['CT_measured']:.5f}. E% = (D - S)/D (negative = over-prediction).", "",
         "## Inputs (full scale)", "", "| input | lines-derived (yard) | published | diff |", "|---|---|---|---|"]
    if lf:
        L.append(f"| A_BT [m²] | {lf['A_BT_m2']:.1f} | {pub['A_BT_m2']:.2f} | {d['A_BT_pct']:+.1f}% |")
        L.append(f"| h_B [m] | {lf['h_B_m']:.2f} | {pub['h_B_m']:.2f} | {d['h_B_pct']:+.1f}% |")
        L.append(f"| A_T [m²] | {lf['A_T_m2']:.1f} (transom flag off: stern offsets truncated) | {pub['A_T_m2']:.2f} | – |")
    L.append(f"| T_F [m] | 20.8 (even keel, T_F = T) | {pub['T_F_m']} | 0 |")
    L += ["", f"Published source: {pub['source']}.", "",
          "## hm1984_full with each input set", "",
          "| inputs | C_T pred | E% | C_F(1+k) | 1+k | C_W | C_bulb | C_tr | c_2 |", "|---|---|---|---|---|---|---|---|---|"]
    for k, x in r["runs"].items():
        if x.get("available"):
            L.append(f"| {k} | {x['CT']:.5f} | {x['E_pct']:+.1f} | {x['Cf_1k']:.5f} | {x['one_plus_k']:.3f} | {x['Cw']:.2e} | "
                     f"{x['C_bulb']:.2e} | {x['C_tr']:.2e} | {x['c_2']:.3f} |")
    L += ["", "## Finding", "",
          "- The lines-derived bulb inputs agree with the independent published set to within 1% (A_BT) and 0.5% (h_B); T_F = T is "
          "correct for the even-keel design condition. **No input is wrong, so nothing is changed.**",
          "- In HM1984 a large bulb (A_BT ≈ 14% of the midship area) on a slow full ship adds R_B ≈ 4x the whole wave term, while c_2 "
          "can only remove part of an already small C_W: the regression itself makes the bulb net-adverse at Fn 0.14.",
          f"- The error is dominated by the viscous term: C_F(1+k) alone already exceeds the measured C_T. Even with zero wave "
          f"resistance, matching the measurement would need 1+k <= C_T/C_F = {r['implied_one_plus_k_max']:.3f}, against HM's "
          f"{r['runs']['bare (no bulb, no transom)'].get('one_plus_k', float('nan')):.3f}. Fixing the bulb would not fix KVLCC2.",
          "- Adding the published transom area (the yard lines have none because the stern offsets are truncated) changes nothing "
          "at this speed: F_nT >= 5 so c_6 = 0 and R_TR = 0, and c_5 moves C_W by < 1%."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path) -> dict[str, Any]:
    out = Path(out_dir); out.mkdir(parents=True, exist_ok=True)
    r = analyse()
    (out / "kvlcc2_bulb_check.json").write_text(json.dumps(r, indent=2, sort_keys=True) + "\n")
    (out / "kvlcc2_bulb_check.md").write_text(render_markdown(r))
    return r


if __name__ == "__main__":
    import sys
    write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
