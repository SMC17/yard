# Leaderboard ingestion contract

Ingest only evaluator-produced `yard.arena.scorecard.v0` documents. Partition
by mission version, ruleset, evaluator/data/seed digests, and authoring track.

The board must:

- show feasibility violations separately from feasible entries;
- compute epsilon-Pareto fronts from raw objective vectors;
- expose every objective and aggregation rule;
- link immutable submission, run, replay, method, and provenance artifacts;
- distinguish `provisional`, `verified`, `exhibition`, `legacy`, and
  `red-team` states;
- never accept participant-supplied scores as authoritative.

Database and web UI work begins after the replay and official-runner contracts
are implemented. This avoids cementing a visually attractive leaderboard on
top of unverifiable metrics.

