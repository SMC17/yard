# Yard Arena

Proof level: core protocol `unit-tested`; Mercury reference path
`integration-tested`.

Yard Arena is the versioned protocol for open naval design competitions and
maritime-agent evaluations. It keeps the design space open while freezing the
mission, era pack, evaluator, random streams, constraints, and objective
definitions required for comparable results.

This module is intentionally separate from:

- `benchmark/`, which validates Yard physics against reference hulls;
- `spiral/`, which synthesizes and optimizes designs;
- `compose/`, which owns multi-physics workflows;
- visualization and leaderboard services, which consume Arena scorecards.

`mission/` is the current single-vessel physics evaluator and `era/` is the
historical constraint catalog. Arena is their outer fleet, provenance,
competition, and leaderboard protocol; it does not replace either module.

## What exists

- Strict mission, submission, evaluator-result, and scorecard wire types.
- Era/material/propulsion/hull-form screening.
- Geometry, ratio, displacement-closure, budget, cargo, transit, vessel-loss,
  and crew-casualty feasibility gates.
- A stream-separated `blake3-counter-v1` random-access RNG contract.
- Epsilon-Pareto dominance and non-dominated front ranking.
- SHA-256-bound CLI scorecards.
- JSON Schemas and a sourced executable historical merchant reference mission.
- A licensed CLIWOC route/month environment derived from 76,184 observations.
- A 256-scenario Mercury fleet backend with passage economics.
- Append-only SHA-256 replay chains and Ed25519 hidden-season tools.

Infeasible designs never receive an objective vector or Pareto rank. A design
cannot buy its way onto the frontier with impossible physics or forbidden
technology.

## Run

```sh
zig build test --summary all
zig build score -- \
  missions/mercury-1778-outbound-v0/mission.json \
  missions/mercury-1778-outbound-v0/submission.example.json \
  missions/mercury-1778-outbound-v0/simulation-result.reference.json
```

Run those commands from `arena/`. `scripts/verify.sh` additionally regenerates
the reference evaluator result and 770-event replay through `yard-mercury`, verifies the
CLIWOC/QDL ledgers, and exercises hidden-season signing.

The complete local proof gate is:

```sh
scripts/verify.sh
```

The optional networked source-reproduction gate is:

```sh
scripts/verify-corpus.sh
```

It fetches the official PANGAEA archive, checks the pinned SHA-256, regenerates
the route ensemble, and requires byte identity with the checked-in artifact.

## Local ship builder and board

Open [web/index.html](web/index.html) directly in a browser. The dependency-free
app provides live mission screening, submission JSON export, track-filtered
Pareto visualization, evaluator-scorecard import, and the mission source/proof
ledger. Demo entries are labeled and imported files remain unofficial.

Browser validation is documented in [web/README.md](web/README.md).

## Hosted evaluator control plane

[`hosted/`](hosted/) contains the Cloudflare Worker boundary for signed seasons,
immutable artifacts, per-run Durable Object coordination, Queue execution,
separate entrant/evaluator Sandbox VMs, D1 metadata, R2 replays/results, and
track-separated Pareto boards. It compiles and runs locally but is not deployed.

```sh
cd hosted
npm ci
npm run check
npm run db:local
npm run build
```

The entrant VM receives only the public mission and emits a declarative
submission. It is destroyed before a separately identified evaluator VM gets
the hidden-season artifact. See [hosted/THREAT_MODEL.md](hosted/THREAT_MODEL.md)
for the deployment tests still required.

The simulation-result file is an evaluator artifact, not participant input.
The public leaderboard must rerun submissions with a pinned Yard backend and
must never trust entrant-supplied metrics.

## Two surfaces

1. **Yard Open Design League**: continuous public missions, designs, replays,
   Pareto archives, and community red-teaming.
2. **Yard Maritime Agent Benchmark**: seasonal blind holdouts, fixed compute,
   official runners, audited finalists, and signed results.

Human, human+AI, autonomous-agent, and exhibition entries remain separate.
Model-only claims require a controlled harness; an open agent-system track
cannot isolate model quality from tools, prompts, search, or compute.

The repository's [Yard Trials](../trials/) directory is the current
GitHub-native provisional league: PR submissions, server-side re-execution,
committed JSONL results, and static frontier pages. Arena supplies the broader
fleet/provenance/track protocol that Trials can adopt incrementally.

See [docs/PROTOCOL.md](docs/PROTOCOL.md) and
[docs/ROADMAP.md](docs/ROADMAP.md). The cross-language RNG contract and golden
vector are in [docs/RNG.md](docs/RNG.md).

License: Apache-2.0 for code. Each mission source retains its own license;
mission manifests must record those licenses before data is redistributed.
