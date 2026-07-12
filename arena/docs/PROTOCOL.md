# Yard Arena Protocol v0

## Core rule

Open-ended design is compatible with a benchmark. An unconstrained evaluator
is not. Every leaderboard identity is the tuple:

```text
mission_id + mission_version + ruleset_id + evaluator_digest + dataset_digest + seed_set_digest
```

Change any element and the result belongs to a new board. Never silently mix
physics versions, era data, or hidden seed sets.

## Evaluation order

1. Parse strict schemas and reject unknown or non-finite values.
2. Bind the exact mission and submission bytes by SHA-256.
3. Enforce era, technology, geometry, mass/displacement, manufacturing, crew,
   fleet, port, budget, and safety constraints.
4. Exclude infeasible entries from objective scoring.
5. Run every feasible entry over the same public or hidden scenario set.
6. Aggregate objectives with the statistic declared by the mission.
7. Apply published epsilon-Pareto dominance.
8. Preserve raw scorecards and replays; render leaderboards downstream.

There is no universal best ship. The primary result is a Pareto archive.
Named prizes may use a frozen hypervolume reference point, head-to-head Elo for
regattas, or a mission-specific scalar, but those are secondary views.

## Tracks

| Track | Submission | Scientific claim |
|---|---|---|
| `declared_human` | Declarative design + method | Honor declaration; finalist audit |
| `human_ai` | Design + model/tool provenance | Co-design system result |
| `autonomous_agent` | Officially launched sandbox image | Agent-system result |
| `exhibition` | Mutable APIs, extra compute, experimental physics | Demonstration only |

A model benchmark and an agent-system competition are different experiments.
For a model benchmark, freeze the harness, prompts, tools, budget, and simulator
and swap only the model snapshot. For an agent league, allow the system to vary
and make no model-only claim.

## Determinism

Arena defines `blake3-counter-v1` over `(seed, stream, draw_index)`. Weather,
demand, damage, traffic, and sensor noise use independent streams. Adding a
weather draw cannot perturb traffic or damage.

Production runs must additionally pin:

- Yard commit and evaluator binary digest;
- Zig version, target, float mode, solver, timestep, and physical constants;
- era-pack and dataset artifact digests;
- ordered public/hidden seed manifests;
- CPU, memory, wall-clock, token, network, and filesystem limits.

The v0 CLI claims repeatability for identical bytes and evaluator inputs. It
does not yet claim cross-architecture bitwise physics determinism.

## Submission bundle

The first public league accepts declarative data only:

```text
submission.json
designs/*.yard.json
fleet.json
METHOD.md
provenance/events.jsonl
submission.lock
LICENSES/
```

The local Mercury v0 path remains declarative. `arena/hosted/` now implements a
pre-deployment autonomous-agent control plane with separate network-disabled
entrant and evaluator Sandbox VM identities, bounded outputs, Queue/DO
coordination, immutable artifacts, and no hidden input in the entrant VM. It
does not yet prove deployed network isolation, virtual-clock control, host
entropy removal, exact resource metering, or cross-tenant security.

Do not require private chain-of-thought or private chat logs. Store hashes,
model snapshots, tool calls, human edit events, budgets, and artifact lineage.

## Hidden evaluation

- Publish development seeds and a SHA-256 commitment to the hidden seed file.
- Use the same hidden seeds for every entry; never derive them from a
  submission hash.
- Reveal the seed file after the season and verify the commitment.
- Rate-limit submissions so the live board cannot be mined as an oracle.
- Reproduce finalists twice before marking them `verified`.

Leaderboard states are `provisional`, `verified`, `exhibition`, `legacy`, and
`red-team`. Responsibly disclosed evaluator exploits belong on a red-team board;
fix the evaluator, version it, and rerun affected entries.

## Historical integrity

Era packs record source URL, license, raw wording, dates, units, calendar,
place-name aliases, transcription/OCR uncertainty, and confidence. Material
properties are distributions with moisture, defect, provenance, and processing
effects, not magic constants.

Use two distinct boards:

- `historical_attested`: documented component sets and practices only;
- `era_constrained_counterfactual`: novel designs using era-feasible materials,
  processes, navigation, yards, and labor.

Do not rank vessels across eras. Preserve historical/current place-name pairs.
Colonial extraction, coercion, crew mortality, and local societies are part of
the system, not free externalities. Mercury remains a civilian mission.
`historical-conflict/` is a separate, fail-closed 1778-only aggregate screening
model with explicit source/assumption ledgers and no modern targeting, sensors,
force posture, current platforms, sensitive routing, or operational claims.
