# Hosted Evaluator Threat Model

Proof level: `audited` only after the checks below have been run against an
actual Cloudflare deployment. This document describes intended controls; it is
not evidence that the deployed system enforces them.

## Protected assets

- hidden-season manifests and seeds before reveal;
- result-signing private keys;
- official evaluator and mission artifact identity;
- immutable submissions, scorecards, results, and replays;
- cross-entrant isolation and leaderboard integrity.

## Trust boundaries

The HTTP client and uploaded agent executable are hostile. The Worker,
Cloudflare bindings, signed season manifest, pinned evaluator binary, and
result signer are trusted. Physics correctness is outside this service and is
owned by the pinned Yard evaluator and its validation evidence.

## Implemented controls

- Separate Sandbox SDK VM identities for entrant and evaluator execution.
- Entrant VM is destroyed before hidden data enters a different evaluator VM.
- `enableInternet = false` and an empty allowed-host list on the Sandbox class.
- No Worker secret or binding is copied into either container.
- Content-addressed R2 artifacts with upload checksum verification.
- Exact-byte Ed25519 season verification and canonical signed result envelopes.
- Organizer season signatures are anchored to a configured key identity, and
  result signing verifies that the configured public/private key pair matches.
- Strict JSON schemas, bounded request bodies, fixed commands/paths, no
  participant-controlled shell interpolation, command timeouts, output-size
  checks, Queue retry limits, and per-run Durable Object serialization.
- Replay chain verification before publication and separate leaderboard tracks.
- Retry-aware Durable Object claims reject same-attempt duplicate Queue
  deliveries while allowing higher-attempt recovery after an abandoned run.
- Queue batches contain one run, and the signed policy caps agent plus evaluator
  commands at 12 minutes to leave cleanup/publication headroom inside the
  platform's 15-minute consumer wall-time limit.
- Scorecards must bind the exact submission identity/track, evaluator version,
  result, replay, hidden commitment, and signed-season objective contract.
- Open seasons must close before reveal; committed hidden bytes become public
  only through the post-reveal endpoint.

## Explicit limitations

- Cloudflare Sandbox SDK is beta. `enableInternet = false` is the documented
  outbound policy, but it must be verified from inside a deployed container;
  local compilation is not network-isolation evidence.
- The SDK container filesystem is isolated, not globally read-only. Processes
  can write anywhere their container user permits. Safety comes from separate
  VMs, absence of hidden inputs in the agent VM, bounded accepted outputs, and
  destruction, not from a claimed read-only root filesystem.
- `instance_type = lite` is a coarse platform resource class. This code does
  not enforce an exact CPU instruction budget or per-process memory ceiling.
- An SDK command timeout closes the caller connection but does not kill the
  underlying process. `finally` destroys the entire sandbox; deployment tests
  must prove that cleanup happens during timeout and Worker failure paths.
- `ulimit -f` limits individual files and can be bypassed by writing many files.
  Only named output files are accepted and size-checked, and the VM is then
  destroyed. Disk-exhaustion behavior remains a platform test requirement.
- The pinned Docker `FROM` digest fixes the upstream amd64 base. It does not
  identify the final custom image produced by Cloudflare; deployment automation
  must capture and bind that digest into the season manifest.
- Shared bearer tokens are a bootstrap authentication boundary, not a mature
  tenant identity system. Production needs Cloudflare Access or mTLS, per-team
  credentials, WAF/rate limits, quotas, revocation, and audit retention.
- D1 and R2 writes are not one cross-product transaction. Immutable objects can
  be orphaned if a later D1 update fails. Attempt-specific R2 prefixes prevent
  a stale retry from poisoning the published pointers; lifecycle cleanup must
  only delete unreferenced objects after a conservative retention window.
- A malicious trusted evaluator can leak hidden data into outputs. Evaluator
  review, reproducible builds, artifact signing, and output semantic audits are
  required outside this Worker.

## Deployment acceptance gates

1. Run network egress probes for DNS, TCP, HTTP, HTTPS, IPv4, and IPv6 from the
   agent VM; all public destinations must fail.
2. Attempt filesystem traversal, symlink attacks, process inspection, fork and
   disk exhaustion, oversized output, timeout continuation, and VM-to-VM access.
3. Confirm no agent-visible file, process environment, log, error, or timing API
   discloses hidden-season content or signer material.
4. Tamper with every artifact digest, season byte, replay event/order, scorecard
   binding, Queue message, and result envelope; each must fail closed.
5. Execute duplicate and reordered Queue deliveries and prove exactly one
   published result per run.
6. Rotate entrant/admin/signing credentials, revoke a team, close/reveal a
   season, and reproduce the board from D1 plus immutable R2 artifacts.
7. Capture the deployed Worker version, custom image digest, Wrangler version,
   binding IDs, migration state, and Cloudflare test evidence without exposing
   secrets or private account identifiers.
