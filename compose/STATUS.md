# Status

yard-compose-zig v0.1.0. Pre-1.0; bound by Zig 0.16 per `~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `box_barge` | `unit-tested` | validation_fixtures box-barge hydrostatics + IS Code 2.2 |
| `vessel_assessment` | `unit-tested` | stability + Holtrop cargo resistance chain |
| `cargo_resistance` | `unit-tested` | Holtrop fixture at 8 m/s |
| `seakeeping_assessment` | `unit-tested` | strip-theory heave RAO + significant heave |
| `damage_stability` | `unit-tested` | codex T_damaged=1.875 m one-compartment case |
| `time_domain_sim` | `unit-tested` | Fossen RK4 thrust vs coast-down |
| `irregular_wave_sim` | `unit-tested` | ITTC-PM multi-sine motion under Hs=2 |
| `dp_station_keeping` | `unit-tested` | 3-thruster DP excursion within limit |
| `coupled_dp_waves` | `unit-tested` | irregular sway + DP under Hs=2 |
| `design_spiral` | `unit-tested` | mid-fidelity cargo hull via yard-spiral |
| `pareto_report` | `unit-tested` | spiral optimizer front → pareto_svg |

## Composition

Multi-module workflows wiring yard primitives. Weakest-link proof inherits from primitives.