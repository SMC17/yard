# Yard Historical Conflict

`historical-conflict` is a governed, deterministic **1778-only aggregate
screening model**. It exists to test period-constrained fleet decisions,
logistics, command delay, uncertainty, damage control, morale, surrender, and
disengagement. It is not a modern operational simulator, an exterior-ballistics
solver, a reconstruction of a named engagement, or evidence for present-day
platform performance.

## Safety and era boundary

The validator fails closed unless `year == 1778`. Every vessel must use wooden
primary structure, canvas sail propulsion, human lookout, manual pumps,
smoothbore muzzle-loading cannon, black powder, and solid round shot. Radio,
radar, sonar, electronic fire control, guided weapons, satellite navigation,
modern propulsion, and metal primary hull structure are explicit anachronism
errors. The public schema contains no contemporary platforms, ports, sensor
signatures, targeting systems, vulnerabilities, or evasion doctrine.

The model resolves gunnery only as uncertain aggregate volleys. It does not
calculate firing solutions, projectile trajectories, penetration, or modern
weapons effects.

## Evidence contract

- Every uncertain value has `minimum`, `central`, `maximum`, and `source_id`.
- Every vessel carries provenance IDs resolved against the scenario source
  registry.
- Ammunition, powder, and crew are conserved and reported explicitly.
- Random draws use Yard Arena's random-access `blake3-counter-v1` streams.
- Replays use Arena's append-only `sha256-chain-v1`; payload or order tampering
  invalidates verification.
- Damage is applied simultaneously per step to avoid attacker-order advantage.

Run the sourced counterfactual screening case:

```sh
zig build test
zig build run -- scenarios/atlantic-convoy-1778.json \
  --replay /tmp/yard-1778-replay.jsonl
```

## Source posture

The example cites the Qatar Digital Library's *Mercury* journal, the Library of
Congress scan of Chapman's 1775 shipbuilding work, Royal Museums Greenwich's
catalogue record for Knowles's 1778 signal system, and a US National Park
Service black-powder reference. Those sources establish period context. They do
**not** validate the numerical combat envelopes, which are plainly registered
as `yard-aggregate-assumptions-v0`.

## Proof level and limitations

Current proof level: **deterministic, unit-tested screening model**.

Proved locally: schema parsing, fail-closed era policy, source resolution,
anachronism rejection, deterministic run hash, replay-chain verification and
tamper rejection, simultaneous damage application, and crew/ammunition/powder
conservation.

Not proved: historical calibration, ship-specific reconstruction, gunnery
accuracy, hydrodynamic maneuvering, sail-state geometry, line-of-sight, command
doctrine, crew behavior, fire/flood physics, or archival weather reconstruction.
No result should be described as historically authoritative until its numerical
assumptions have been replaced by reviewed primary-source or experimental
evidence with uncertainty propagation.
