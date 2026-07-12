# Status

Yard Arena v0.1.0.

| Component | Proof level | Evidence |
|---|---|---|
| Mission/submission/result contracts | `unit-tested` | strict Zig types + envelope tests |
| Feasibility screening | `unit-tested` | material, displacement, finite-value, and artifact-binding tests |
| RNG contract | `unit-tested` | repeatability, stream separation, and range tests |
| Epsilon-Pareto ranking | `unit-tested` | tradeoff, dominance, epsilon, and infeasible-entry tests |
| `yard-arena-score` CLI | `integration-tested` | generated Mercury result scores twice to byte-identical output |
| CLIWOC route environment | `audited` | 76,184 licensed observations; pinned archive digest, selection method, uncertainty ledger |
| QDL route-anchor ledger | `audited` | five OGL catalogue anchors, chronological/confidence checks; daily page transcription remains open |
| `yard-mercury` fleet backend | `integration-tested` | 256 scenarios compose era, stability, resistance, square-rig aero, routing, and economics |
| Replay hash chain | `integration-tested` | 770-event reference replay regenerates byte-identically and rejects payload tampering |
| Hidden-season signing CLI | `integration-tested` | SHA-256 commitment plus Ed25519 sign/verify/tamper tests; no organizer season launched yet |
| Local web ship builder / Pareto board | `integration-tested` | direct-file Playwright smoke: gates, tabs, import, SVG, desktop/mobile, clean console |
| GitHub-native provisional Trials board | `integration-tested` | local `trials/score.py --check`; committed results match evaluator rerun |
| Governed 1778 conflict screening | `unit-tested` | ReleaseSafe adversarial gates, conservation, exact scenario binding, deterministic 206-event Arena replay |
| Hosted signed/hidden leaderboard | `compiled + local-smoke` | strict Worker contracts, 12 unit tests, fresh D1 migration, pinned Sandbox image dry-run, local health check; no cloud deployment claimed |

`mercury-1778-outbound-v0` is now an executable empirical reference mission.
It does not reconstruct the East Indiaman *Mercury*, historical prices, or its
exact sailed trajectory. The next evidence gate is reviewed daily-log
transcription and calibration against additional independently sourced voyages.
The hosted service likewise remains pre-deployment until isolation, retry,
credential, quota, and tamper acceptance tests pass on provisioned resources.
