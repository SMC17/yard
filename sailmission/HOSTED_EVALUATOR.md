# Mercury Hosted Evaluator

`yard-mercury` is the trusted Zig evaluator used by the hosted Arena runner.
It executes the real Mercury era, stability, resistance, sail-aerodynamic,
routing, historical-environment, and economic composition. It does not read a
reference result.

## Hidden season v1

`yard.hosted.mercury-hidden-season.v1` is a strict, hermetic JSON artifact. It
contains:

- the exact public mission SHA-256;
- one seed selected from the mission's published seed set;
- exact RFC 4648 base64 bytes and SHA-256 for the licensed environment JSON;
- exact RFC 4648 base64 bytes and SHA-256 for the Mercury backend config;
- the pinned evaluator version and hosted runner protocol.

The embedding is intentional. The evaluator Sandbox VM receives only the
mission, submission, evaluator binary, and hidden-season artifact; references
to files outside that VM would not be reproducible. The hidden artifact's exact
SHA-256 is the season commitment placed in `result.json`, `scorecard.json`, and
the first replay event.

Version 1 is **single-seed only**. Its scenario count is the Monte Carlo count
inside the pinned backend config. It does not claim aggregation across several
independent seeds.

## Build and run

From `sailmission/`:

```sh
zig build -Dfleet=true -Doptimize=ReleaseSafe install-mercury

./zig-out/bin/yard-mercury pack-hidden \
  --mission ../arena/missions/mercury-1778-outbound-v0/mission.json \
  --environment ../arena/missions/mercury-1778-outbound-v0/environment/cliwoc-route-ensemble.v0.json \
  --backend-config ../arena/missions/mercury-1778-outbound-v0/backend-config.json \
  --seed 17781001 \
  --output /tmp/mercury-hidden-season.json

./zig-out/bin/yard-mercury evaluate \
  --mission ../arena/missions/mercury-1778-outbound-v0/mission.json \
  --hidden-season /tmp/mercury-hidden-season.json \
  --submission ../arena/missions/mercury-1778-outbound-v0/submission.example.json \
  --output-dir /tmp/mercury-evaluation
```

The evaluator writes exactly:

- `result.json`: the trusted Mercury simulation result;
- `scorecard.json`: Arena feasibility and objective scoring over that result;
- `replay.jsonl`: a SHA-256 chain beginning with all artifact commitments.

The hosted runner verifies the exact result hash, replay count/head, scorecard
shape, signed-season commitment, and mission/submission identity before it
publishes a result.

## Proof commands

```sh
zig build -Dfleet=true test --summary all
zig build -Dfleet=true -Doptimize=ReleaseSafe install-mercury --summary all
```

The unit path regenerates the hidden artifact, runs the actual 256-scenario
Mercury example twice, compares all three output artifacts byte-for-byte, and
rejects changed embedded content and an exact-byte mission mismatch.
