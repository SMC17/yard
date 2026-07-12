import { z } from "zod";

export const Sha256Schema = z.string().regex(/^[a-f0-9]{64}$/);
const IdentifierSchema = z.string().min(1).max(128).regex(/^[A-Za-z0-9][A-Za-z0-9._:-]*$/);
const NonEmptySchema = z.string().min(1).max(512);
const FiniteNonnegativeSchema = z.number().finite().nonnegative();
const TrackSchema = z.enum(["declared_human", "human_ai", "autonomous_agent", "exhibition"]);

const ProvenanceSchema = z.strictObject({
  yard_revision: NonEmptySchema,
  zig_version: NonEmptySchema,
  authoring_system: NonEmptySchema,
  ai_system: z.string().max(512).nullable().optional(),
  method_uri: z.string().max(2048).nullable().optional()
});

const VesselSchema = z.strictObject({
  design_id: IdentifierSchema,
  class_name: NonEmptySchema,
  count: z.number().int().min(1).max(10_000),
  hull_form: z.enum(["monohull", "catamaran", "trimaran", "submersible"]),
  material: z.enum(["oak", "teak", "softwood", "iron", "steel", "aluminum", "composite"]),
  propulsion: z.enum(["sail", "sail_and_oar", "steam", "diesel", "hybrid", "electric", "nuclear"]),
  length_m: FiniteNonnegativeSchema,
  beam_m: FiniteNonnegativeSchema,
  draft_m: FiniteNonnegativeSchema,
  block_coefficient: z.number().finite().min(0).max(1),
  displacement_t: FiniteNonnegativeSchema,
  cargo_capacity_t: FiniteNonnegativeSchema,
  sail_area_m2: FiniteNonnegativeSchema,
  crew: z.number().int().min(0).max(100_000),
  unit_cost_units: FiniteNonnegativeSchema,
  depth_m: z.number().finite().positive().nullable().optional(),
  kg_m: FiniteNonnegativeSchema.nullable().optional(),
  wetted_surface_m2: z.number().finite().positive().nullable().optional(),
  residuary_coefficient: FiniteNonnegativeSchema.nullable().optional(),
  form_factor: z.number().finite().positive().nullable().optional(),
  min_brace_deg: z.number().finite().min(0).max(90).nullable().optional()
});

export const ArenaSubmissionSchema = z.strictObject({
  schema_version: z.literal("yard.arena.submission.v0"),
  submission_id: IdentifierSchema,
  mission_id: IdentifierSchema,
  mission_version: IdentifierSchema,
  ruleset_id: IdentifierSchema,
  track: TrackSchema,
  entrant: NonEmptySchema,
  provenance: ProvenanceSchema,
  fleet: z.array(VesselSchema).min(1).max(256)
});

const DeclarativeSourceSchema = z.strictObject({
  kind: z.literal("declarative"),
  submission: ArenaSubmissionSchema
});

const AgentSourceSchema = z.strictObject({
  kind: z.literal("agent_binary"),
  artifact_sha256: Sha256Schema,
  artifact_size_bytes: z.number().int().positive().max(33_554_432),
  entrant: NonEmptySchema,
  authoring_system: NonEmptySchema
});

export const CreateSubmissionRequestSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.create-submission.v1"),
  season_id: IdentifierSchema,
  idempotency_key: IdentifierSchema,
  source: z.discriminatedUnion("kind", [DeclarativeSourceSchema, AgentSourceSchema])
}).superRefine((request, context) => {
  if (request.source.kind === "declarative" && request.source.submission.track === "autonomous_agent") {
    context.addIssue({
      code: "custom",
      path: ["source", "submission", "track"],
      message: "autonomous_agent entries require an executed agent_binary artifact"
    });
  }
});

export const CreateRunRequestSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.create-run.v1"),
  season_id: IdentifierSchema,
  submission_id: IdentifierSchema,
  idempotency_key: IdentifierSchema
});

const ObjectiveDefinitionSchema = z.strictObject({
  name: IdentifierSchema,
  direction: z.enum(["minimize", "maximize"]),
  epsilon: FiniteNonnegativeSchema
});

export const ResourcePolicySchema = z.strictObject({
  agent_timeout_ms: z.number().int().min(1_000).max(240_000),
  evaluator_timeout_ms: z.number().int().min(1_000).max(480_000),
  max_output_bytes: z.number().int().min(1_024).max(16_777_216),
  max_agent_artifact_bytes: z.number().int().min(1_024).max(33_554_432),
  sandbox_instance_type: z.literal("lite"),
  internet_enabled: z.literal(false)
});

export const SeasonManifestSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.season-manifest.v1"),
  season_id: IdentifierSchema,
  mission_id: IdentifierSchema,
  mission_version: IdentifierSchema,
  ruleset_id: IdentifierSchema,
  state: z.enum(["draft", "open", "closed"]),
  tracks: z.array(TrackSchema).min(1),
  mission_artifact_sha256: Sha256Schema,
  evaluator_artifact_sha256: Sha256Schema,
  hidden_manifest_sha256: Sha256Schema,
  evaluator_version: NonEmptySchema,
  runner_image_digest: z.string().regex(/^sha256:[a-f0-9]{64}$/),
  runner_protocol: z.literal("yard-hosted-evaluator-v1"),
  objectives: z.array(ObjectiveDefinitionSchema).min(1).max(32),
  resource_policy: ResourcePolicySchema
}).superRefine((manifest, context) => {
  const tracks = new Set<string>();
  for (const [index, track] of manifest.tracks.entries()) {
    if (tracks.has(track)) context.addIssue({ code: "custom", path: ["tracks", index], message: "tracks must be unique" });
    tracks.add(track);
  }
  const objectives = new Set<string>();
  for (const [index, objective] of manifest.objectives.entries()) {
    if (objectives.has(objective.name)) context.addIssue({ code: "custom", path: ["objectives", index, "name"], message: "objective names must be unique" });
    objectives.add(objective.name);
  }
});

export const SignatureEnvelopeSchema = z.strictObject({
  algorithm: z.literal("ed25519-detached-sha256-v1"),
  key_id: IdentifierSchema,
  payload_sha256: Sha256Schema,
  public_key_hex: z.string().regex(/^[a-f0-9]{64}$/),
  signature_hex: z.string().regex(/^[a-f0-9]{128}$/)
});

export const ImportSeasonRequestSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.import-season.v1"),
  manifest_base64: z.string().min(4).max(1_048_576),
  signature: SignatureEnvelopeSchema
});

export const ArtifactKindSchema = z.enum([
  "agent-binary",
  "evaluator-binary",
  "mission",
  "hidden-season",
  "season-manifest"
]);

export const RunJobSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.run-job.v1"),
  run_id: z.string().uuid(),
  generation: z.number().int().positive()
});

const ObjectiveResultSchema = z.strictObject({
  name: IdentifierSchema,
  direction: z.enum(["minimize", "maximize"]),
  aggregate: z.enum(["fixed", "mean", "median", "p95", "cvar90"]),
  epsilon: FiniteNonnegativeSchema,
  value: z.number().finite()
});

const ViolationSchema = z.strictObject({
  code: IdentifierSchema,
  subject: NonEmptySchema,
  detail: NonEmptySchema
});

export const ArenaScorecardSchema = z.strictObject({
  schema_version: z.literal("yard.arena.scorecard.v0"),
  evaluator_version: NonEmptySchema,
  evaluator_id: IdentifierSchema,
  run_id: Sha256Schema,
  mission_id: IdentifierSchema,
  mission_version: IdentifierSchema,
  ruleset_id: IdentifierSchema,
  submission_id: IdentifierSchema,
  track: TrackSchema,
  mission_sha256: Sha256Schema,
  submission_sha256: Sha256Schema,
  simulation_result_sha256: Sha256Schema,
  backend_version: NonEmptySchema,
  environment_sha256: Sha256Schema,
  replay_algorithm: z.literal("sha256-chain-v1"),
  replay_head_sha256: Sha256Schema,
  replay_event_count: z.number().int().positive(),
  season_commitment_sha256: Sha256Schema,
  seed: z.number().int().nonnegative(),
  scenario_count: z.number().int().positive(),
  feasible: z.boolean(),
  total_vessels: z.number().int().nonnegative(),
  total_cost_units: FiniteNonnegativeSchema,
  total_nominal_cargo_t: FiniteNonnegativeSchema,
  violations: z.array(ViolationSchema).max(10_000),
  objectives: z.array(ObjectiveResultSchema).max(64)
});

export type ArenaSubmission = z.infer<typeof ArenaSubmissionSchema>;
export type CreateSubmissionRequest = z.infer<typeof CreateSubmissionRequestSchema>;
export type CreateRunRequest = z.infer<typeof CreateRunRequestSchema>;
export type SeasonManifest = z.infer<typeof SeasonManifestSchema>;
export type SignatureEnvelope = z.infer<typeof SignatureEnvelopeSchema>;
export type ArtifactKind = z.infer<typeof ArtifactKindSchema>;
export type RunJob = z.infer<typeof RunJobSchema>;
export type ArenaScorecard = z.infer<typeof ArenaScorecardSchema>;
