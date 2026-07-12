# Yard Arena Hosted Evaluator

Proof level: `compiled + local-smoke` after the full local gate; pure contract,
coordination, Pareto, scorecard-binding, and cryptographic logic are covered by
12 unit tests. No Cloudflare resources have been created and no service has
been deployed.

This Worker is the hosted execution and leaderboard boundary for Yard Arena.
It deliberately does not reproduce naval physics in TypeScript. A season pins
an official Yard evaluator binary, mission artifact, hidden-season commitment,
resource policy, and detached Ed25519 signature. The evaluator remains the
sole producer of trusted Arena results and scorecards.

## Architecture

```text
strict HTTP API -> D1 metadata -> per-run Durable Object -> Queue
                                                |
                     +--------------------------+-------------------------+
                     |                                                    |
        agent Sandbox VM (public mission)                   evaluator Sandbox VM
        emits submission.json only                         (trusted binary + hidden season)
                     |                                                    |
                     +---------------- declarative input -----------------+
                                                                          |
                                           verified replay/result -> R2 -> signed envelope
                                                                   -> D1 Pareto board
```

The agent VM is destroyed before the evaluator VM is created. The agent never
receives the hidden manifest, evaluator binary, signing key, D1 binding, R2
binding, or Worker environment. Declarative submissions skip the agent VM.

## API v1

All request objects are strict; unknown fields and non-finite numbers fail.

| Method | Path | Authorization | Behavior |
|---|---|---|---|
| `PUT` | `/v1/artifacts/:sha256` | entrant for `agent-binary`, admin otherwise | Stream a content-addressed artifact with `Content-Length` and `X-Yard-Artifact-Kind` |
| `POST` | `/v1/admin/seasons` | admin | Verify and import an exact-byte signed season manifest |
| `POST` | `/v1/admin/seasons/:id/close` | admin | Close an open season before reveal |
| `POST` | `/v1/admin/seasons/:id/reveal` | admin | Reveal only the precommitted hidden artifact digest |
| `GET` | `/v1/seasons/:id` | public | Return public manifest/signature; reveal pointer only after reveal |
| `GET` | `/v1/seasons/:id/hidden` | public | Stream the committed hidden artifact only after reveal |
| `POST` | `/v1/submissions` | entrant | Register declarative data or a single executable agent artifact |
| `POST` | `/v1/runs` | entrant | Idempotently enqueue an official run |
| `GET` | `/v1/runs/:id` | public | Return bounded run state without private season material |
| `GET` | `/v1/runs/:id/result` | public | Stream the immutable signed result envelope |
| `GET` | `/v1/runs/:id/replay` | public | Stream the verified replay chain |
| `GET` | `/v1/leaderboards?season_id=...&track=...` | public | Return track-separated epsilon-Pareto ranks |

The autonomous-agent artifact contract is intentionally small: one Linux
executable receives `request.json` and an output path, then writes a strict
`yard.arena.submission.v0` JSON document. Multi-file systems must be compiled
or packaged into that executable. This avoids archive traversal and symlink
ambiguities inside the public upload API.

The trusted evaluator contract is:

```text
evaluator evaluate \
  --mission /workspace/input/mission.json \
  --hidden-season /workspace/input/hidden-season.json \
  --submission /workspace/input/submission.json \
  --output-dir /workspace/output
```

It must emit `result.json`, `scorecard.json`, and `replay.jsonl`. The Worker
verifies mission/submission/result hashes, the full SHA-256 replay chain,
event count/head, hidden-season commitment, and strict scorecard shape before
signing or publishing anything.

## Local proof

Requires Node 20+, Docker, and Wrangler 4. Do not put real secrets in files.

```sh
npm ci
npm run typecheck
npm test
npm run config:check
npm run db:local
npm run build
```

`npm run build` is a Wrangler dry run; it does not deploy. The checked-in D1 ID
is a non-resource placeholder and must be replaced only during an explicit
infrastructure provisioning step. Production secrets are configured with
interactive `wrangler secret put`: `API_BEARER_TOKEN`,
`ADMIN_BEARER_TOKEN`, `SEASON_SIGNING_KEY_ID`,
`SEASON_SIGNING_PUBLIC_KEY_HEX`, `RESULT_SIGNING_KEY_ID`,
`RESULT_SIGNING_PRIVATE_KEY_PKCS8_B64`, and
`RESULT_SIGNING_PUBLIC_KEY_HEX`.

The Sandbox SDK package and Docker base are both pinned to `0.12.3`; the
amd64 base manifest is pinned by digest in `Dockerfile`. The reproducible local
custom-image digest is also a Worker variable and a required signed-season
field. Rebuild it during provisioning and reject a season if its signed digest
does not equal the deployed configuration.

See [THREAT_MODEL.md](THREAT_MODEL.md) before provisioning resources.
