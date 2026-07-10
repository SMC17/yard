# Yard Trials

Open ship-design competition on verifiable physics. Missions are constraint
envelopes over the yard modules; submissions are parametric vessels; the
leaderboard is a Pareto frontier, never a single score.

## How to compete

1. Pick a mission under `mission/missions/<id>/` and read its
   `mission.json` — era limits, route, environment, objectives, gates.
2. Write a submission JSON (copy `submissions/baseline-coaster.json` and
   change what you believe in). Iterate locally:

   ```
   cd mission && zig build
   ./zig-out/bin/yard-mission eval missions/<id>/mission.json your-design.json
   ```

3. Open a PR adding your file to `mission/missions/<id>/submissions/`.

CI rebuilds the runner, re-executes **every** submission deterministically,
requires byte-identical results across two runs, and fails the PR if the
committed leaderboard (`trials/results/*.jsonl`) does not match server-side
re-execution. Nothing on the board is hand-entered; anyone can replay any
entry from its JSON.

## Rules of the yard

- **Gates before glory.** A design that fails intact stability, freeboard,
  the era envelope, or a physics model's validity range is rejected, not
  ranked. Degenerate spec-hacks die here.
- **The frontier is the leaderboard.** `dominated_by == 0` puts you on the
  front; a design that trades speed against loss risk honestly can stand
  next to a faster, riskier one.
- **Found a physics exploit?** A design that scores well by abusing a model
  boundary is a bug report, and a welcome one — open an issue. It becomes a
  regression test and a validity fence; exploit hunters get credited in the
  mission changelog.

## Scoring pipeline

```
score.py            re-runs every submission through yard-mission (Zig,
                    deterministic), rebuilds trials/results/<mission>.jsonl
render_frontier.py  emits static Pareto pages under trials/site/
```

## Roadmap

m0 (modern coastal trader) is the plumbing rung. Next: Age-of-Sail missions
on the `era` + `sailaero` modules — tea-clipper route records with the
historical ships as baseline entries, then East Indiaman fleet economics on
`econ`, then two-sided convoy wargames. Era envelopes, tonnage laws, and
treaty caps are already in the `era` module.
