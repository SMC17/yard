# mission

Mission spec + eval runner for the Yard Trials: open, physics-gated,
multi-objective ship-design challenges.

A **mission** is a constraint envelope (era limits), an environment (route,
wave climate), and an objective set. A **submission** is a parametric vessel.
Both are plain JSON, so humans, agents, and CI submit the same artifact.

## Usage

```
zig build
./zig-out/bin/yard-mission eval missions/m0-coastal-trader/mission.json \
    missions/m0-coastal-trader/submissions/baseline-coaster.json \
    [--results leaderboard.jsonl] [--append]
```

Prints a canonical JSON report (byte-identical for identical inputs). Exit 0 =
scored; exit 2 = gates failed or vessel rejected. `--append` adds scored
entries to the leaderboard JSONL; `--results` places the submission against
the existing Pareto frontier.

## Evaluation pipeline

1. **Validity gates** — a submission is rejected, never ranked, if it fails:
   era envelope (dimensional caps, L/D strength proxy), freeboard (load-line
   proxy), intact stability (free-surface-corrected GM + IMO IS Code 2008
   Part A 2.2 via the canonical box-barge workflow), and the resistance-model
   validity envelope (Holtrop 1984 — designs outside the model's calibrated
   range are unscoreable by construction).
2. **Seeded Monte Carlo voyage** — great-circle legs, Weibull wave-height
   draws, weather speed loss, storm-loss Bernoulli events. Competition
   missions declare `blake3-counter-v1`, with independent random-access
   weather and damage streams. Early v0 files without `rng_algorithm` retain
   the legacy Zig PRNG sequence for compatibility.
3. **Objectives + Pareto placement** — the leaderboard is a frontier, not a
   scalar ranking. `dominated_by == 0` puts you on the front.

## v0 model assumptions (explicit)

- Stability is evaluated on the box-barge workflow with the submission's B/T
  (canonical yard intact-stability path); hull-form GZ via the panel modules
  replaces this in a later rung.
- Weather speed loss is `1 - min(0.5, 0.02·Hs²)` — a documented placeholder
  pending rao-spectrum added-resistance coupling.
- Attainable speed solves Holtrop required power vs installed × service
  fraction × propulsive efficiency by bisection.

## Next Trials rung

The adjacent `era/`, `sailaero/`, `econ/`, and `trials/` packages now exist.
The next gate is integration: a sourced Age-of-Sail mission that composes
their constraints, square-rig polar, passage economics, and CI-reexecuted
frontier, then validates the voyage distribution against historical records.

Proof level: unit-tested. Depends on: naval-arch, hydro, stability,
resistance, routing, compose (box_barge, cargo_resistance).
