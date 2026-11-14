# Fast forward-speed added resistance: STAwave-2 (`stawave2_v0`)

Module: `tools/gym/yard_sea_v0/added_resistance.py`. Env: `DesignSearchEnv(reward_mode="sea_state")`
(also `--reward-mode sea_state` on the CLI).

## Method (public source)

ITTC Recommended Procedure 7.5-04-01-01.2, *Analysis of Speed/Power Trial Data* (2014, rev. 01),
Annex D.2, STAwave-2 (STA-JIP empirical transfer function), https://ittc.info/media/4210/75-04-01-012.pdf

* `R_AWM = 4ρgζa²(B²/L)·r̄aw(ω̄)`, `r̄aw = ω̄^b1·exp[(b1/d1)(1−ω̄^d1)]·a1·Fr^1.5·exp(−3.5Fr)`,
  `ω̄ = sqrt(L/g)·k_yy^(1/3)/(1.17·Fr^−0.143)·ω`, `a1 = 60.3·C_B^1.34`,
  `b1 = 11.0 | −8.50`, `d1 = 14.0 | −566(L/B)^−2.66` (ω̄ < 1 | elsewhere)
* `R_AWR = ½ρgζa²B·α1`, `α1 = π²I1²(1.5kT)/(π²I1²(1.5kT)+K1²(1.5kT))·f1`,
  `f1 = 0.692(V/sqrt(Tg))^0.769 + 1.81·C_B^6.95`
* Irregular head sea: `R̄aw = 2∫S(ω)·R_aw(ω)/ζa² dω`, Bretschneider `SeaState` from `seakeeping.py`.

Conventions: `L` used for `Lpp`, midship draught = `T`, `k_yy = 0.25` (non-dimensional; convention).
Stated range (checked, reported, and the reward refuses credit outside it): 75 ≤ L ≤ 350 m,
4.0 ≤ L/B ≤ 9.0, 2.2 ≤ B/T ≤ 5.5, 0.10 ≤ Fr ≤ 0.30, 0.50 ≤ C_B ≤ 0.90, head waves within ±45°.

## Numbers (default hull L 120, B 20, T 8, C_B 0.75, Fn 0.20; Hs 2 m, Tp 8 s)

| quantity | value |
|---|---|
| STAwave-2 mean R_AW (Fn 0.20) | 76.7 kN (motion 45.5, reflection 31.2) |
| STAwave-2 mean R_AW (Fr 0.10) | 49.6 kN |
| Capytaine zero-speed far-field drift (wall-sided Cb-matched mesh) | 14.4 kN |
| ratio STAwave-2 (Fn 0.20) / Capytaine (V = 0) | 5.3 |
| motion peak `R_AWM/(ρgB²/L)` | ≈ 7 at ω̄ = 1 |

Reading: the two are different physics — a forward-speed regression fitted to merchant-ship model
tests vs a zero-speed linear potential-flow drift on a simplified wall-sided mesh. Forward speed raises
both the reflection term (`f1`) and the motion peak; a several-fold increase over the zero-speed value
is the expected direction, not a validation. Capytaine remains the search-time / held-out check
(`crosscheck_capytaine`), STAwave-2 is the per-step reward term (~ms).

## Reward mode `sea_state`

Two conditions by default (calm, example head sea). Per condition the total is L1 calm `Rt` (+ mean
STAwave-2 `R_AW` for the sea). Score = weighted mean relative reduction vs parent + worst-case penalty
(same shape as `multi_froude`). Rejected (−1) if L1 acceptance fails or STAwave-2 is outside its range.
Evidence packs carry the full per-condition breakdown under `sea_state`.

Limits: head seas only; no speed loss / involuntary speed reduction; empirical regression, not a
seakeeping prediction for unusual forms; no class or trial-procedure compliance implied.
