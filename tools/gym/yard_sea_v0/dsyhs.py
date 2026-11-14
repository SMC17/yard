"""Delft Systematic Yacht Hull Series (DSYHS) as a second validation set.

Data (CC0, TU Delft / 4TU.ResearchData, Keuning et al.):

* hydrostatics  — doi:10.4121/21501375  ``DSYHS_hydrostatics_modelscale.xlsx``
* measurements  — doi:10.4121/21501402  ``DSYHS_all_measurements_modelscale.xlsx``

Both are CC0, so the upright bare-hull subset is vendored as CSV
(``data/vendored/dsyhs_*.csv``, built by ``build_vendored``). Model scale, L_WL 1.6 m (mostly)..2 m.

Measured C_T = R_T / (0.5 rho V^2 S_c) with S_c the canoe-body wetted area at rest.
Water properties from the recorded tank temperature: density by Tanaka et al. (2001,
Metrologia 38:301), kinematic viscosity by the ITTC (1978) fresh-water formula
nu = ((0.585e-3 (t-12) - 0.03361)(t-12) + 1.235) e-6. The data are already corrected
for turbulence-stimulator drag (dataset description).

Sailing-yacht canoe bodies sit outside the Holtrop-Mennen parent population
(B/T 3..5+, C_P ~0.53-0.60, high Fn), so this set measures how the gym's oracles and
its applicability check behave *outside* their declared range.
"""

from __future__ import annotations

import csv
import math
from pathlib import Path
from typing import Any

HYDRO_COLS = ("sysser", "series", "lwl", "bwl", "tc", "volc", "lcb", "aw", "sc", "cb", "cm", "cp", "cw")
RES_COLS = ("sysser", "T_C", "V", "Rt")


def _vendored() -> Path:
    from .validation import repo_root

    return repo_root() / "data" / "vendored"


def rho_fresh(t: float) -> float:
    """Tanaka et al. (2001) density of air-free standard water [kg/m^3], t in deg C."""
    a1, a2, a3, a4, a5 = -3.983035, 301.797, 522528.9, 69.34881, 999.974950
    return a5 * (1.0 - (t + a1) ** 2 * (t + a2) / (a3 * (t + a4)))


def nu_fresh(t: float) -> float:
    """ITTC (1978) fresh-water kinematic viscosity [m^2/s], t in deg C."""
    d = t - 12.0
    return ((0.585e-3 * d - 0.03361) * d + 1.2350) * 1e-6


def build_vendored(hydro_xlsx: str | Path, meas_xlsx: str | Path, out_dir: str | Path | None = None) -> None:
    """Extract upright bare-hull hydrostatics + resistance (original overhang) to CSV."""
    import openpyxl

    out = Path(out_dir) if out_dir else _vendored()
    wb = openpyxl.load_workbook(hydro_xlsx, read_only=True, data_only=True)
    rows = list(wb["Canoe body hydrostatics"].iter_rows(values_only=True))
    hdr = list(rows[0])
    keep = []
    for r in rows[1:]:
        d = dict(zip(hdr, r))
        if d.get("Sysser") is None or float(d.get("Overhang") or 0) != 1.0:
            continue
        keep.append([int(d["Sysser"]), int(d["Series"]), d["lwl0"], d["bwl0"], d["tc0"], d["volc0"], d["lcb0"],
                     d["aw0"], d["sc0"], d["cb0"], d["cm0"], d["cp0"], d["cw0"]])
    with (out / "dsyhs_hydrostatics_upright_modelscale.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(HYDRO_COLS)
        w.writerows(keep)
    wb = openpyxl.load_workbook(meas_xlsx, read_only=True, data_only=True)
    res = []
    for ws in wb.worksheets:
        if not ws.title.startswith("Sys"):
            continue
        sysser = int(ws.title.split()[1])
        it = list(ws.iter_rows(values_only=True))
        for i, r in enumerate(it):
            if r and r[0] == "Bare hull upright":
                cells = list(r)
                ti = next((j for j, c in enumerate(cells) if c == "[°C]"), None)
                if ti is None or cells[ti + 1] is None:
                    break  # no recorded temperature -> cannot form C_T honestly; skip this model
                t = float(cells[ti + 1])
                for rr in it[i + 2:]:
                    if not rr or rr[0] is None:
                        break
                    res.append([sysser, t, float(rr[0]), float(rr[1])])
                break
    with (out / "dsyhs_bare_upright_resistance_modelscale.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(RES_COLS)
        w.writerows(res)


def load() -> list[dict[str, Any]]:
    """Joined points: hydrostatics + one measured speed each, with Fn, Re, C_T."""
    v = _vendored()
    hyd = {}
    with (v / "dsyhs_hydrostatics_upright_modelscale.csv").open() as f:
        for r in csv.DictReader(f):
            hyd[int(r["sysser"])] = {k: (int(r[k]) if k in ("sysser", "series") else float(r[k])) for k in HYDRO_COLS}
    pts = []
    with (v / "dsyhs_bare_upright_resistance_modelscale.csv").open() as f:
        for r in csv.DictReader(f):
            h = hyd.get(int(r["sysser"]))
            if h is None:
                continue
            t, V, Rt = float(r["T_C"]), float(r["V"]), float(r["Rt"])
            rho, nu = rho_fresh(t), nu_fresh(t)
            pts.append({**h, "T_C": t, "V": V, "Rt": Rt, "rho": rho, "nu": nu,
                        "Fn": V / math.sqrt(9.81 * h["lwl"]), "Re": V * h["lwl"] / nu,
                        "CT": Rt / (0.5 * rho * V * V * h["sc"])})
    return pts


# ------------------------------------------------------------------ validation
DSYHS_SCHEMA = "yard_sea_v0.validation.dsyhs.v1"
DSYHS_ORACLES = ("hm1984_full", "hm1984_gym_bare", "simplified_py_bare", "michell_l15")
FN_BANDS = ((0.0, 0.2), (0.2, 0.3), (0.3, 0.4), (0.4, 0.5), (0.5, 0.8))


def tank_cases() -> list[Any]:
    from .validation import TankCase

    return [
        TankCase(hull=f"DSYHS-{p['sysser']}", Fn=p["Fn"], CT=p["CT"], L=p["lwl"], B=p["bwl"], T=p["tc"],
                 vol=p["volc"], S0=p["sc"], Cb=p["cb"], Cm=p["cm"], lcb_pct=p["lcb"] / p["lwl"] * 100.0,
                 nu=p["nu"], rho=p["rho"], g=9.81, dataset_id="dsyhs_4tu")
        for p in load()
    ]


def validate(oracles: tuple[str, ...] = DSYHS_ORACLES) -> dict[str, Any]:
    import numpy as np

    from . import validation as V
    from .applicability import assess

    cases = tank_cases()
    rows = []
    for c in cases:
        row = {"hull": c.hull, "Fn": c.Fn, "Re": c.Re, "CT": c.CT, "params": c.params(), "E_pct": {}}
        h = c.hull_state(appendages=False)
        row["S_gym_over_Sc"] = h.wetted_approx() / c.S0
        app = assess(h, "hm1984_zig")
        row["hm_in_declared_range"] = app.get("in_declared_range")
        row["hm_in_validated_envelope"] = app.get("in_validated_envelope")
        for o in oracles:
            p = V.PREDICTORS[o](c)
            if p.get("available"):
                row["E_pct"][o] = V.comparison_error_pct(c.CT, p["CT"])
        rows.append(row)

    def stats(vals: list[float]) -> dict[str, Any]:
        e = np.asarray([x for x in vals if math.isfinite(x)], float)
        if e.size == 0:
            return {"n": 0}
        return {"n": int(e.size), "mean_E_pct": float(e.mean()), "median_abs_E_pct": float(np.median(np.abs(e))),
                "mean_abs_E_pct": float(np.abs(e).mean()), "p90_abs_E_pct": float(np.quantile(np.abs(e), 0.9)),
                "within_10pct": float(np.mean(np.abs(e) <= 10.0))}

    per = {}
    for o in oracles:
        per[o] = {
            "overall": stats([r["E_pct"].get(o, float("nan")) for r in rows]),
            "by_Fn": {f"{lo:.1f}-{hi:.1f}": stats([r["E_pct"].get(o, float("nan")) for r in rows if lo <= r["Fn"] < hi])
                      for lo, hi in FN_BANDS},
            "hm_declared_range": {
                "inside": stats([r["E_pct"].get(o, float("nan")) for r in rows if r["hm_in_declared_range"]]),
                "outside": stats([r["E_pct"].get(o, float("nan")) for r in rows if r["hm_in_declared_range"] is False]),
            },
            "tank_validated_envelope": {
                "inside": stats([r["E_pct"].get(o, float("nan")) for r in rows if r["hm_in_validated_envelope"]]),
                "outside": stats([r["E_pct"].get(o, float("nan")) for r in rows if r["hm_in_validated_envelope"] is False]),
            },
        }
    s_ratio = np.asarray([r["S_gym_over_Sc"] for r in rows])
    return {
        "schema": DSYHS_SCHEMA,
        "source": "DSYHS (TU Delft, 4TU.ResearchData doi:10.4121/21501375 + 10.4121/21501402), CC0; model scale",
        "convention": "E%D = (D - S)/D*100 with C_T on canoe-body wetted area S_c; C_F ITTC-57 at tank Re; no C_A",
        "n_points": len(rows),
        "n_models": len({r["hull"] for r in rows}),
        "Fn_range": [min(r["Fn"] for r in rows), max(r["Fn"] for r in rows)],
        "per_oracle": per,
        "gym_wetted_area_ratio": {"median": float(np.median(s_ratio)), "min": float(s_ratio.min()),
                                  "max": float(s_ratio.max()),
                                  "note": "HullState.wetted_approx() / measured S_c (gym's S approximation on yachts)"},
        "share_in_hm_declared_range": float(np.mean([bool(r["hm_in_declared_range"]) for r in rows])),
        "share_in_tank_validated_envelope": float(np.mean([bool(r["hm_in_validated_envelope"]) for r in rows])),
        "rows": [{k: (round(v, 6) if isinstance(v, float) else v) for k, v in r.items() if k != "params"}
                 | {"E_pct": {o: round(e, 3) for o, e in r["E_pct"].items()}} for r in rows],
    }


def render_markdown(rep: dict[str, Any]) -> str:
    L = ["# Oracle check on the Delft Systematic Yacht Hull Series (out-of-population set)", "",
         f"Schema `{rep['schema']}`. {rep['n_points']} measured points on {rep['n_models']} canoe bodies, "
         f"Fn {rep['Fn_range'][0]:.2f}–{rep['Fn_range'][1]:.2f}. Source: {rep['source']}.", "",
         f"Convention: {rep['convention']}.", "",
         "| oracle | n | mean E% | median abs E% | p90 abs E% | share within ±10% |", "|---|---|---|---|---|---|"]
    for o, s in rep["per_oracle"].items():
        ov = s["overall"]
        L.append(f"| `{o}` | {ov['n']} | {ov['mean_E_pct']:+.1f} | {ov['median_abs_E_pct']:.1f} | "
                 f"{ov['p90_abs_E_pct']:.1f} | {ov['within_10pct']:.0%} |")
    L += ["", "## By Froude band (median abs E%)", ""]
    bands = list(next(iter(rep["per_oracle"].values()))["by_Fn"])
    L.append("| oracle | " + " | ".join(bands) + " |")
    L.append("|---|" + "---|" * len(bands))
    for o, s in rep["per_oracle"].items():
        L.append(f"| `{o}` | " + " | ".join(
            f"{v['median_abs_E_pct']:.1f} (n={v['n']})" if v.get("n") else "–" for v in s["by_Fn"].values()) + " |")
    L += ["", "## Does the applicability check separate good from bad predictions?", "",
          f"Share of DSYHS points inside the HM declared range: {rep['share_in_hm_declared_range']:.0%}; "
          f"inside the tank-validated envelope: {rep['share_in_tank_validated_envelope']:.0%}.", "",
          "| oracle | declared range: inside | outside | tank envelope: inside | outside |", "|---|---|---|---|---|"]
    for o, s in rep["per_oracle"].items():
        d, t = s["hm_declared_range"], s["tank_validated_envelope"]
        f = lambda x: f"{x['median_abs_E_pct']:.1f}% (n={x['n']})" if x.get("n") else "–"  # noqa: E731
        L.append(f"| `{o}` | {f(d['inside'])} | {f(d['outside'])} | {f(t['inside'])} | {f(t['outside'])} |")
    w = rep["gym_wetted_area_ratio"]
    L += ["", "## Gym wetted-area approximation on yachts", "",
          f"`HullState.wetted_approx()` / measured S_c: median {w['median']:.2f}, range {w['min']:.2f}–{w['max']:.2f}. "
          "The validation assembles C_T with the measured S_c; the gym itself uses its approximation.",
          "", "## Caveats", "",
          "- Holtrop-Mennen and the gym's simplified model were built for ships, not yacht canoe bodies: this is "
          "an out-of-population check, not a calibration. Results are not used in rewards.",
          "- Models without a recorded water temperature (Sys 24, 28, 42–46, 48) are skipped rather than "
          "assuming a temperature.",
          "- Fn above ~0.45 involves large sinkage / trim (recorded in the source, not modelled by any L1 oracle)."]
    return "\n".join(L) + "\n"


def write_reports(out_dir: str | Path) -> dict[str, Any]:
    import json

    out = Path(out_dir)
    out.mkdir(parents=True, exist_ok=True)
    rep = validate()
    (out / "dsyhs_validation.json").write_text(json.dumps(rep, indent=1, sort_keys=True) + "\n")
    (out / "dsyhs_validation.md").write_text(render_markdown(rep))
    return rep


if __name__ == "__main__":  # pragma: no cover
    import sys

    r = write_reports(sys.argv[1] if len(sys.argv) > 1 else "reports/validation")
    for o, s in r["per_oracle"].items():
        print(o, s["overall"])
