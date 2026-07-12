# Yard Arena Build Roadmap

## Product spine

One protocol supports two products:

- **Open Design League** for continuous public ship/fleet design;
- **Maritime Agent Benchmark** for controlled, blind evaluation.

The same mission can expose multiple experiences without changing physics:
schema-driven ship builder, CLI, Python bindings, WASM playground, regatta,
agent API, replay viewer, and public Pareto board.

## Phase 1: Sourced merchant challenge

- Complete reviewed daily transcription of the 1778-1779 *Mercury* journal.
  Five licensed route/date anchors exist; exact daily wind, course, remarks,
  and the sailed trajectory remain open evidence work.
- Keep the checked-in 76,184-observation CLIWOC route ensemble reproducible
  from its licensed archive, pinned digest, selection method, and uncertainty
  ledger.
- Deepen the existing `era/` Chapman-period constraints, merchant archetypes,
  and uncertain wood properties with independently reviewed primary sources.
- Extend the executable `yard-mercury` backend beyond its current composition
  of era, stability, resistance, square-rig aero, routing, and economics into
  hydrostatics, cargo, damage, maintenance, and crew-risk coupling.
- Preserve the current deterministic fleet result, 770-event replay chain,
  signed hidden-season tools, and full mission/submission/environment/evaluator
  binding as the minimum artifact contract.

Current deliverable: an executable empirical `Mercury Outbound` reference path
with public development artifacts. A hosted hidden season has not been launched
and must not be presented as historical reconstruction.

The existing `trials/` PR/CI board is the transport for provisional public
entries. Extend it to ingest Arena scorecards and track metadata rather than
building a second submission service.

## Phase 2: Consumer ship builder and regatta

- Generate controls from the submission schema: dimensions, hull form,
  material, rig, cargo, crew, and cost.
- Compile a validated Yard subset to WASM.
- Add live hydrostatics, stability, sail trim, VMG, heel, leeway, and weather
  telemetry.
- Ship course missions, ghost replays, head-to-head races, and AI helmsmen.
- Keep engineering and arcade physics as explicitly separate profiles.

Deliverable: a browser experience with Saltwind-level immediacy and Yard-level
traceability, not a claim that visual polish alone implies simulator fidelity.

## Phase 3: Timeline league

Versioned era packs, never a single hand-waved tech tree:

1. 1600-1800 wind merchant logistics and exploration history.
2. 1800-1914 steam transition, iron/steel, canals, and global liner networks.
3. 1914-1945 convoy logistics and governed historical-conflict packs.
4. 1945-2000 containerization, tanker economics, offshore energy, and rules.
5. 2000-present decarbonization, autonomous survey, ports, and offshore wind.
6. Future counterfactuals: disaster relief, ocean science, and low-carbon fleets.

Every pack carries materials, manufacturing, yards, ports, routes, navigation,
weather, costs/resources, crew, reliability, and source/uncertainty ledgers.

## Phase 4: Naval compiler and agent league

- Mission requirements -> design graph -> spiral optimization -> generated Zig
  vessel/fleet simulator -> official evaluation.
- Genetic global search, gradient refinement, Bayesian optimization, quality
  diversity, and surrogate-assisted exploration all emit the same submission
  bundle.
- Tool-use agents receive bounded Yard APIs and must produce designs, evidence,
  and reproducible traces.
- Publish generalization splits: new weather, ports, failures, objectives,
  technology shocks, and cross-era transfer.

The benchmark measures physical co-design, constraint reasoning, tool use,
robustness, uncertainty calibration, and recovery from invalid designs. It is
not a trivia test over naval terms.

## Phase 5: Fleet and lifecycle simulation

- Multi-vessel wakes, collisions, towing, replenishment, terminals, shipyards,
  maintenance, degradation, finance, insurance, and emissions.
- Human crews, autonomous agents, port operators, and logistics markets share a
  deterministic event ledger.
- Hardware/model-test submissions can earn higher proof tiers when replayable
  data correlates against the same mission artifact.

`historical-conflict/` now provides a fail-closed 1778-only deterministic
screening engine for simultaneous aggregate volleys, command uncertainty,
damage control, morale, surrender, disengagement, conservation, and chained
replay. Its numerical envelopes are not historically calibrated. Deeper
historical conflict must add archival calibration, period maneuvering, sail
state, logistics, and uncertainty without importing contemporary weapons,
targeting, evasion, vulnerabilities, sensitive force posture, or current
operational geography into the open leaderboard.

## Proof ladder

`schema-valid` -> `screened` -> `simulated` -> `replayed` -> `benchmark-hull`
-> `model-test-correlated` -> `hardware-correlated`.

Leaderboard badges expose the proof tier. They do not flatten it into one
marketing score.
