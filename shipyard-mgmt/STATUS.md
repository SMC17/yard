# Status

yard-shipyard-mgmt-zig v0.0.0. Pre-1.0; bound by Zig 0.16 per
`~/CONVENTIONS.md` C2.

## Proof-vocabulary index

| Component | Proof level | Evidence |
|---|---|---|
| `cpm.forwardPass` | `unit-tested` | linear chain ES accumulates; diamond D starts after max(B, C) |
| `cpm.projectFinish` | `unit-tested` | max(EF) closed form |
| `cpm.backwardPass` | `unit-tested` | linear-chain backward leaves zero float; diamond C gets 2-day float |
| `cpm.totalFloat` | `unit-tested` | LS - ES closed form |
| `pert.mean` | `unit-tested` | (a + 4m + b)/6; degenerate a=m=b returns m |
| `pert.standardDeviation` | `unit-tested` | (b - a)/6; zero when a = b |
| `pert.variance` | `unit-tested` | sigma^2 closed form |
| `pert.projectMean`, `projectVariance` | `unit-tested` | sums of critical-path triples |
| `pert.zScore` | `unit-tested` | (T - mu)/sigma; mu at zero; +2 sigma |
| `resource.buildHistogram` | `unit-tested` | single-activity rectangle; two-activity overlap |
| `resource.peakLoad`, `averageLoad`, `totalResourceDays`, `smoothnessRatio` | `unit-tested` | 18 peak; 9 average; 90 total resource-days; 0.5 smoothness ratio |

## Constraint inheritance (C2)

Bound by Zig 0.16. Strongest available claim: `stable-on-zig-0.16-today`.

## Test discipline (C5)

Claim: `32/32 tests pass`.

## Banned-vocabulary discipline (C7)

This repository does not use "production-grade", "battle-tested",
"robust", "stable" (unqualified), or other banned-set terms outside
narrative-historical context.

## Error taxonomy (C6)

- Type-I overclaim guard: deterministic CPM / single-point PERT
  Gaussian only; the kernel does not claim Monte-Carlo accuracy
  for the project-completion distribution. The Z-score returns the
  Gaussian probability gateway; the actual P[T_finish <= T] requires
  an external normal CDF (deferred).
- Type-II missed risk guard: typed-error rejection for negative
  duration, invalid triple ordering, activity extending past
  horizon, empty network / histogram, buffer-too-small.
- Type-III category guard: scheduling primitives only; not a
  resource-constrained solver (RCPSP); not an earned-value engine;
  not a multi-mode activity / risk-register lookup.

## What is not covered (v0.0.0)

- Monte-Carlo critical-path simulation.
- Resource-constrained project scheduling (RCPSP).
- Earned-value / cost integration.
- Multi-mode activities.
- Risk register / probabilistic criticality.
- Dynamic graph allocator (caller pre-allocates topological order
  and buffers).

## Composition

- CPM forward / backward pass output feeds the PERT module: the
  critical-path triples (those with zero total float) determine
  the project-completion Gaussian.
- Resource histogram feeds capacity-planning decisions across
  shipyard sub-blocks; couples externally to a manpower / crane /
  berth ledger.
- Project finish T couples to commercial milestones and the
  block-construction sequence.
