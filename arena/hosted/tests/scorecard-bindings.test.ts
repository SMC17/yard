import { describe, expect, it } from "vitest";
import type { ArenaScorecard, ArenaSubmission, SeasonManifest } from "../src/contracts";
import { validateScorecardBindings } from "../src/validation";

const hash = (digit: string): string => digit.repeat(64);

const submission: ArenaSubmission = {
  schema_version: "yard.arena.submission.v0",
  submission_id: "submission-1",
  mission_id: "mercury-1778-outbound",
  mission_version: "v0",
  ruleset_id: "mercury-empirical-sail-v0",
  track: "autonomous_agent",
  entrant: "test entrant",
  provenance: { yard_revision: "test", zig_version: "0.16.0", authoring_system: "test" },
  fleet: [{
    design_id: "merchantman-1",
    class_name: "Merchantman",
    count: 1,
    hull_form: "monohull",
    material: "oak",
    propulsion: "sail",
    length_m: 38,
    beam_m: 10,
    draft_m: 4,
    block_coefficient: 0.62,
    displacement_t: 1_000,
    cargo_capacity_t: 180,
    sail_area_m2: 850,
    crew: 70,
    unit_cost_units: 300
  }]
};

const season: SeasonManifest = {
  schema_version: "yard.hosted.season-manifest.v1",
  season_id: "season-1",
  mission_id: submission.mission_id,
  mission_version: submission.mission_version,
  ruleset_id: submission.ruleset_id,
  state: "open",
  tracks: ["autonomous_agent"],
  mission_artifact_sha256: hash("1"),
  evaluator_artifact_sha256: hash("7"),
  hidden_manifest_sha256: hash("6"),
  evaluator_version: "yard-mercury-v1",
  runner_image_digest: `sha256:${hash("8")}`,
  runner_protocol: "yard-hosted-evaluator-v1",
  objectives: [{ name: "transit_days", direction: "minimize", epsilon: 0.1 }],
  resource_policy: {
    agent_timeout_ms: 60_000,
    evaluator_timeout_ms: 300_000,
    max_output_bytes: 1_048_576,
    max_agent_artifact_bytes: 16_777_216,
    sandbox_instance_type: "lite",
    internet_enabled: false
  }
};

const scorecard: ArenaScorecard = {
  schema_version: "yard.arena.scorecard.v0",
  evaluator_version: season.evaluator_version,
  evaluator_id: "yard-mercury",
  run_id: hash("9"),
  mission_id: season.mission_id,
  mission_version: season.mission_version,
  ruleset_id: season.ruleset_id,
  submission_id: submission.submission_id,
  track: submission.track,
  mission_sha256: season.mission_artifact_sha256,
  submission_sha256: hash("2"),
  simulation_result_sha256: hash("3"),
  backend_version: "yard-mercury-v1",
  environment_sha256: hash("4"),
  replay_algorithm: "sha256-chain-v1",
  replay_head_sha256: hash("5"),
  replay_event_count: 10,
  season_commitment_sha256: season.hidden_manifest_sha256,
  seed: 1,
  scenario_count: 8,
  feasible: true,
  total_vessels: 1,
  total_cost_units: 300,
  total_nominal_cargo_t: 180,
  violations: [],
  objectives: [{ name: "transit_days", direction: "minimize", aggregate: "mean", epsilon: 0.1, value: 210 }]
};

const bindings = (value: ArenaScorecard) => ({
  scorecard: value,
  submission,
  season,
  submissionSha256: hash("2"),
  resultSha256: hash("3"),
  replay: { eventCount: 10, headSha256: hash("5") }
});

describe("hosted scorecard bindings", () => {
  it("accepts the exact signed-season objective and provenance contract", () => {
    expect(() => validateScorecardBindings(bindings(scorecard))).not.toThrow();
  });

  it("rejects track, objective, and infeasible-frontier substitution", () => {
    expect(() => validateScorecardBindings(bindings({ ...scorecard, track: "declared_human" }))).toThrow("identity or track");
    expect(() => validateScorecardBindings(bindings({
      ...scorecard,
      objectives: [{ ...scorecard.objectives[0]!, epsilon: 99 }]
    }))).toThrow("signed season");
    expect(() => validateScorecardBindings(bindings({ ...scorecard, feasible: false }))).toThrow("cannot publish objective");
  });
});
