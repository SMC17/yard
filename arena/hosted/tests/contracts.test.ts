import { describe, expect, it } from "vitest";
import {
  ArenaSubmissionSchema,
  CreateSubmissionRequestSchema,
  RunJobSchema,
  SeasonManifestSchema
} from "../src/contracts";

const submission = {
  schema_version: "yard.arena.submission.v0",
  submission_id: "reference-fleet",
  mission_id: "mercury-1778-outbound",
  mission_version: "v0",
  ruleset_id: "mercury-empirical-sail-v0",
  track: "human_ai",
  entrant: "Yard test",
  provenance: {
    yard_revision: "test",
    zig_version: "0.16.0",
    authoring_system: "vitest"
  },
  fleet: [{
    design_id: "merchantman-38m",
    class_name: "Merchantman",
    count: 3,
    hull_form: "monohull",
    material: "oak",
    propulsion: "sail",
    length_m: 38,
    beam_m: 10.5,
    draft_m: 4.5,
    block_coefficient: 0.62,
    displacement_t: 1141.04,
    cargo_capacity_t: 180,
    sail_area_m2: 850,
    crew: 70,
    unit_cost_units: 300
  }]
} as const;

describe("hosted contracts", () => {
  it("accepts a strict declarative Arena submission", () => {
    expect(ArenaSubmissionSchema.parse(submission).fleet).toHaveLength(1);
    expect(CreateSubmissionRequestSchema.parse({
      schema_version: "yard.hosted.create-submission.v1",
      season_id: "mercury-season-1",
      idempotency_key: "submission-1",
      source: { kind: "declarative", submission }
    }).source.kind).toBe("declarative");
    expect(() => CreateSubmissionRequestSchema.parse({
      schema_version: "yard.hosted.create-submission.v1",
      season_id: "mercury-season-1",
      idempotency_key: "false-agent-track",
      source: { kind: "declarative", submission: { ...submission, track: "autonomous_agent" } }
    })).toThrow("executed agent_binary");
    expect(RunJobSchema.parse({
      schema_version: "yard.hosted.run-job.v1",
      run_id: "9cb735e8-6552-4d46-8a39-d6339fda6880",
      generation: 2
    }).generation).toBe(2);
  });

  it("rejects unknown fields and non-finite physics values", () => {
    expect(() => ArenaSubmissionSchema.parse({ ...submission, trusted: true })).toThrow();
    expect(() => ArenaSubmissionSchema.parse({
      ...submission,
      fleet: [{ ...submission.fleet[0], displacement_t: Number.POSITIVE_INFINITY }]
    })).toThrow();
  });

  it("requires a network-disabled, bounded season policy", () => {
    const manifest = {
      schema_version: "yard.hosted.season-manifest.v1",
      season_id: "mercury-season-1",
      mission_id: "mercury-1778-outbound",
      mission_version: "v0",
      ruleset_id: "mercury-empirical-sail-v0",
      state: "open",
      tracks: ["human_ai", "autonomous_agent"],
      mission_artifact_sha256: "1".repeat(64),
      evaluator_artifact_sha256: "2".repeat(64),
      hidden_manifest_sha256: "3".repeat(64),
      evaluator_version: "yard-mercury-v1",
      runner_image_digest: `sha256:${"4".repeat(64)}`,
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
    } as const;
    expect(SeasonManifestSchema.parse(manifest).resource_policy.internet_enabled).toBe(false);
    expect(() => SeasonManifestSchema.parse({
      ...manifest,
      resource_policy: { ...manifest.resource_policy, internet_enabled: true }
    })).toThrow();
    expect(() => SeasonManifestSchema.parse({
      ...manifest,
      objectives: [manifest.objectives[0], manifest.objectives[0]]
    })).toThrow("objective names must be unique");
  });
});
