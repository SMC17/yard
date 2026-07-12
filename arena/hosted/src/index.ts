import { z } from "zod";
import {
  ArtifactKindSchema,
  CreateRunRequestSchema,
  CreateSubmissionRequestSchema,
  ImportSeasonRequestSchema,
  RunJobSchema,
  SeasonManifestSchema,
  type ArtifactKind,
  type CreateSubmissionRequest,
  type RunJob,
  type SeasonManifest
} from "./contracts";
import {
  base64ToBytes,
  canonicalJson,
  sha256Hex,
  signResultPayload,
  verifyDetachedSignature
} from "./crypto";
import { RunCoordinator } from "./coordinator";
import { errorResponse, HttpError, jsonResponse, parsePositiveInt, readJsonBounded, requireAdmin, requireEntrant } from "./http";
import { assignTrackSeparatedRanks, type ObjectiveValue, type TrackParetoEntry } from "./pareto";
import {
  executeHostedRun,
  RunnerError,
  YardAgentSandbox,
  ContainerProxy,
  type ArtifactRecord
} from "./sandbox";

export { ContainerProxy, RunCoordinator, YardAgentSandbox };

interface SeasonRow {
  season_id: string;
  mission_id: string;
  mission_version: string;
  ruleset_id: string;
  state: "draft" | "open" | "closed" | "revealed";
  manifest_json: string;
  manifest_sha256: string;
  signature_json: string;
  mission_artifact_sha256: string;
  evaluator_artifact_sha256: string;
  hidden_manifest_sha256: string;
  evaluator_version: string;
  resource_policy_json: string;
  created_at: string;
  revealed_at: string | null;
  reveal_artifact_sha256: string | null;
}

interface SubmissionRow {
  submission_id: string;
  season_id: string;
  idempotency_key: string;
  source_kind: "declarative" | "agent_binary";
  track: "declared_human" | "human_ai" | "autonomous_agent" | "exhibition";
  entrant: string;
  request_json: string;
  request_sha256: string;
  agent_artifact_sha256: string | null;
  created_at: string;
}

interface RunRow {
  run_id: string;
  season_id: string;
  submission_id: string;
  idempotency_key: string;
  status: "queued" | "running_agent" | "running_evaluator" | "completed" | "failed";
  attempts: number;
  submission_sha256: string | null;
  submission_r2_key: string | null;
  result_r2_key: string | null;
  replay_r2_key: string | null;
  scorecard_r2_key: string | null;
  envelope_r2_key: string | null;
  envelope_sha256: string | null;
  error_code: string | null;
  error_detail: string | null;
  enqueued_at: string | null;
  created_at: string;
  started_at: string | null;
  finished_at: string | null;
}

interface BoardRow extends RunRow {
  track: SubmissionRow["track"];
  entrant: string;
}

interface ObjectiveRow {
  run_id: string;
  name: string;
  direction: "minimize" | "maximize";
  epsilon: number;
  value: number;
}

const RevealSeasonRequestSchema = z.strictObject({
  schema_version: z.literal("yard.hosted.reveal-season.v1"),
  hidden_manifest_sha256: z.string().regex(/^[a-f0-9]{64}$/)
});

const isoNow = (): string => new Date().toISOString();
const artifactKey = (digest: string): string => `artifacts/sha256/${digest}`;
const maxRankedLeaderboardEntries = 2_000;
const outboxRetryAfterMs = 10 * 60 * 1_000;

class StaleLeaseError extends Error {}

async function getSeason(env: Env, seasonId: string): Promise<SeasonRow> {
  const row = await env.DB.prepare("SELECT * FROM seasons WHERE season_id = ?").bind(seasonId).first<SeasonRow>();
  if (!row) throw new HttpError(404, "season_not_found", "season does not exist");
  return row;
}

async function getSubmission(env: Env, submissionId: string): Promise<SubmissionRow> {
  const row = await env.DB.prepare("SELECT * FROM submissions WHERE submission_id = ?").bind(submissionId).first<SubmissionRow>();
  if (!row) throw new HttpError(404, "submission_not_found", "submission does not exist");
  return row;
}

async function getRun(env: Env, runId: string): Promise<RunRow> {
  const row = await env.DB.prepare("SELECT * FROM runs WHERE run_id = ?").bind(runId).first<RunRow>();
  if (!row) throw new HttpError(404, "run_not_found", "run does not exist");
  return row;
}

async function getArtifact(env: Env, digest: string, expectedKind?: ArtifactKind): Promise<ArtifactRecord> {
  const row = await env.DB.prepare(
    "SELECT sha256, kind, size_bytes, r2_key FROM artifacts WHERE sha256 = ?"
  ).bind(digest).first<ArtifactRecord>();
  if (!row) throw new HttpError(422, "artifact_not_found", `artifact ${digest} has not been registered`);
  if (expectedKind && row.kind !== expectedKind) throw new HttpError(422, "artifact_kind_mismatch", `artifact ${digest} is not ${expectedKind}`);
  return row;
}

async function uploadArtifact(request: Request, env: Env, digest: string): Promise<Response> {
  const kind = ArtifactKindSchema.parse(request.headers.get("x-yard-artifact-kind"));
  if (kind === "agent-binary") await requireEntrant(request, env);
  else await requireAdmin(request, env);
  const contentLength = Number(request.headers.get("content-length"));
  const maxBytes = parsePositiveInt(env.MAX_ARTIFACT_BYTES, "MAX_ARTIFACT_BYTES");
  if (!Number.isSafeInteger(contentLength) || contentLength <= 0) {
    throw new HttpError(411, "content_length_required", "artifact uploads require a positive content-length");
  }
  if (contentLength > maxBytes) throw new HttpError(413, "artifact_too_large", "artifact exceeds the configured upload limit");
  if (!request.body) throw new HttpError(400, "missing_body", "artifact body is required");

  const key = artifactKey(digest);
  const existing = await env.ARTIFACTS.head(key);
  if (existing) {
    if (existing.size !== contentLength || existing.customMetadata?.sha256 !== digest || existing.customMetadata?.kind !== kind) {
      throw new HttpError(409, "artifact_conflict", "content address already exists with different metadata");
    }
  } else {
    const stored = await env.ARTIFACTS.put(key, request.body, {
      sha256: digest,
      onlyIf: new Headers({ "if-none-match": "*" }),
      httpMetadata: { contentType: "application/octet-stream" },
      customMetadata: { sha256: digest, kind, size_bytes: String(contentLength) }
    });
    if (!stored) throw new HttpError(409, "artifact_race", "artifact was concurrently uploaded; retry the request");
  }
  await env.DB.prepare(
    `INSERT OR IGNORE INTO artifacts (sha256, kind, size_bytes, r2_key, uploaded_at)
     VALUES (?, ?, ?, ?, ?)`
  ).bind(digest, kind, contentLength, key, isoNow()).run();
  const registered = await getArtifact(env, digest);
  if (registered.kind !== kind || registered.size_bytes !== contentLength) {
    throw new HttpError(409, "artifact_registry_conflict", "artifact registry metadata conflicts with the upload");
  }
  return jsonResponse({ artifact: registered }, existing ? 200 : 201);
}

async function importSeason(request: Request, env: Env): Promise<Response> {
  await requireAdmin(request, env);
  const parsed = ImportSeasonRequestSchema.parse(await readJsonBounded(request, parsePositiveInt(env.MAX_JSON_BODY_BYTES, "MAX_JSON_BODY_BYTES")));
  const manifestBytes = base64ToBytes(parsed.manifest_base64);
  if (parsed.signature.key_id !== env.SEASON_SIGNING_KEY_ID || parsed.signature.public_key_hex !== env.SEASON_SIGNING_PUBLIC_KEY_HEX) {
    throw new HttpError(422, "untrusted_season_signer", "season signature is not from the configured organizer key");
  }
  if (!(await verifyDetachedSignature(manifestBytes, parsed.signature))) {
    throw new HttpError(422, "invalid_season_signature", "season signature does not bind the exact manifest bytes");
  }
  let manifest: SeasonManifest;
  try {
    manifest = SeasonManifestSchema.parse(JSON.parse(new TextDecoder("utf-8", { fatal: true, ignoreBOM: false }).decode(manifestBytes)));
  } catch (error) {
    if (error instanceof z.ZodError) throw error;
    throw new HttpError(422, "invalid_season_manifest", "manifest is not strict UTF-8 JSON");
  }
  await Promise.all([
    getArtifact(env, manifest.mission_artifact_sha256, "mission"),
    getArtifact(env, manifest.evaluator_artifact_sha256, "evaluator-binary"),
    getArtifact(env, manifest.hidden_manifest_sha256, "hidden-season")
  ]);
  if (manifest.runner_image_digest !== env.RUNNER_IMAGE_DIGEST) {
    throw new HttpError(422, "runner_image_mismatch", "season does not pin the configured runner image digest");
  }
  const now = isoNow();
  const manifestText = new TextDecoder().decode(manifestBytes);
  await env.DB.prepare(
    `INSERT INTO seasons
     (season_id, mission_id, mission_version, ruleset_id, state, manifest_json, manifest_sha256,
      signature_json, mission_artifact_sha256, evaluator_artifact_sha256, hidden_manifest_sha256,
      evaluator_version, resource_policy_json, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    manifest.season_id,
    manifest.mission_id,
    manifest.mission_version,
    manifest.ruleset_id,
    manifest.state,
    manifestText,
    parsed.signature.payload_sha256,
    canonicalJson(parsed.signature),
    manifest.mission_artifact_sha256,
    manifest.evaluator_artifact_sha256,
    manifest.hidden_manifest_sha256,
    manifest.evaluator_version,
    canonicalJson(manifest.resource_policy),
    now
  ).run();
  return jsonResponse({ season: { ...manifest, signature: parsed.signature, created_at: now } }, 201);
}

async function closeSeason(request: Request, env: Env, seasonId: string): Promise<Response> {
  await requireAdmin(request, env);
  const season = await getSeason(env, seasonId);
  if (season.state === "closed") return jsonResponse({ season_id: seasonId, state: "closed" });
  if (season.state !== "open") throw new HttpError(409, "season_not_open", "only an open season can be closed");
  await env.DB.prepare("UPDATE seasons SET state = 'closed' WHERE season_id = ? AND state = 'open'").bind(seasonId).run();
  return jsonResponse({ season_id: seasonId, state: "closed" });
}

async function revealSeason(request: Request, env: Env, seasonId: string): Promise<Response> {
  await requireAdmin(request, env);
  const body = RevealSeasonRequestSchema.parse(await readJsonBounded(request, parsePositiveInt(env.MAX_JSON_BODY_BYTES, "MAX_JSON_BODY_BYTES")));
  const season = await getSeason(env, seasonId);
  if (season.state === "revealed") {
    if (body.hidden_manifest_sha256 !== season.hidden_manifest_sha256) {
      throw new HttpError(422, "reveal_commitment_mismatch", "revealed artifact does not match the precommitted hidden manifest");
    }
    return jsonResponse({ season_id: seasonId, state: "revealed", revealed_at: season.revealed_at, hidden_manifest_sha256: season.hidden_manifest_sha256 });
  }
  if (season.state !== "closed") throw new HttpError(409, "season_not_closed", "a season must be closed before hidden artifacts are revealed");
  if (body.hidden_manifest_sha256 !== season.hidden_manifest_sha256) {
    throw new HttpError(422, "reveal_commitment_mismatch", "revealed artifact does not match the precommitted hidden manifest");
  }
  await getArtifact(env, body.hidden_manifest_sha256, "hidden-season");
  const now = isoNow();
  await env.DB.prepare(
    "UPDATE seasons SET state = 'revealed', revealed_at = ?, reveal_artifact_sha256 = ? WHERE season_id = ?"
  ).bind(now, body.hidden_manifest_sha256, seasonId).run();
  return jsonResponse({ season_id: seasonId, state: "revealed", revealed_at: now, hidden_manifest_sha256: body.hidden_manifest_sha256 });
}

async function streamRevealedHidden(env: Env, seasonId: string): Promise<Response> {
  const season = await getSeason(env, seasonId);
  if (season.state !== "revealed") throw new HttpError(404, "hidden_season_unavailable", "hidden season is not public");
  const artifact = await getArtifact(env, season.hidden_manifest_sha256, "hidden-season");
  const object = await env.ARTIFACTS.get(artifact.r2_key);
  if (!object || object.size !== artifact.size_bytes || object.customMetadata?.sha256 !== artifact.sha256) {
    throw new HttpError(500, "hidden_season_integrity", "revealed hidden-season artifact failed integrity checks");
  }
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "public, max-age=31536000, immutable");
  headers.set("x-content-type-options", "nosniff");
  return new Response(object.body, { headers });
}

async function createSubmission(request: Request, env: Env): Promise<Response> {
  await requireEntrant(request, env);
  const parsed = CreateSubmissionRequestSchema.parse(await readJsonBounded(request, parsePositiveInt(env.MAX_JSON_BODY_BYTES, "MAX_JSON_BODY_BYTES")));
  const season = await getSeason(env, parsed.season_id);
  if (season.state !== "open") throw new HttpError(409, "season_not_open", "season is not accepting submissions");
  const manifest = SeasonManifestSchema.parse(JSON.parse(season.manifest_json));
  let track: SubmissionRow["track"];
  let entrant: string;
  let agentDigest: string | null = null;
  if (parsed.source.kind === "agent_binary") {
    const artifact = await getArtifact(env, parsed.source.artifact_sha256, "agent-binary");
    if (artifact.size_bytes !== parsed.source.artifact_size_bytes || artifact.size_bytes > manifest.resource_policy.max_agent_artifact_bytes) {
      throw new HttpError(422, "agent_artifact_size", "agent artifact size does not match the registered resource policy");
    }
    track = "autonomous_agent";
    entrant = parsed.source.entrant;
    agentDigest = parsed.source.artifact_sha256;
  } else {
    track = parsed.source.submission.track;
    entrant = parsed.source.submission.entrant;
    if (parsed.source.submission.mission_id !== season.mission_id || parsed.source.submission.mission_version !== season.mission_version || parsed.source.submission.ruleset_id !== season.ruleset_id) {
      throw new HttpError(422, "submission_mission_mismatch", "submission does not target this season");
    }
  }
  if (!manifest.tracks.includes(track)) throw new HttpError(409, "track_closed", "submission track is not active in this season");
  const requestJson = canonicalJson(parsed);
  const requestSha256 = await sha256Hex(requestJson);
  const submissionId = crypto.randomUUID();
  const createdAt = isoNow();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO submissions
     (submission_id, season_id, idempotency_key, source_kind, track, entrant, request_json,
      request_sha256, agent_artifact_sha256, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
  ).bind(
    submissionId,
    parsed.season_id,
    parsed.idempotency_key,
    parsed.source.kind,
    track,
    entrant,
    requestJson,
    requestSha256,
    agentDigest,
    createdAt
  ).run();
  const stored = await env.DB.prepare(
    "SELECT * FROM submissions WHERE season_id = ? AND idempotency_key = ?"
  ).bind(parsed.season_id, parsed.idempotency_key).first<SubmissionRow>();
  if (!stored) throw new Error("submission insert did not produce a row");
  if (stored.request_sha256 !== requestSha256) throw new HttpError(409, "idempotency_conflict", "idempotency key was already used for a different submission");
  return jsonResponse({ submission: stored }, stored.submission_id === submissionId ? 201 : 200);
}

async function createRun(request: Request, env: Env): Promise<Response> {
  await requireEntrant(request, env);
  const parsed = CreateRunRequestSchema.parse(await readJsonBounded(request, parsePositiveInt(env.MAX_JSON_BODY_BYTES, "MAX_JSON_BODY_BYTES")));
  const [season, submission] = await Promise.all([getSeason(env, parsed.season_id), getSubmission(env, parsed.submission_id)]);
  if (season.state !== "open") throw new HttpError(409, "season_not_open", "season is not accepting runs");
  if (submission.season_id !== season.season_id) throw new HttpError(422, "run_season_mismatch", "submission belongs to another season");
  const runId = crypto.randomUUID();
  const now = isoNow();
  await env.DB.prepare(
    `INSERT OR IGNORE INTO runs
     (run_id, season_id, submission_id, idempotency_key, status, created_at)
     VALUES (?, ?, ?, ?, 'queued', ?)`
  ).bind(runId, season.season_id, submission.submission_id, parsed.idempotency_key, now).run();
  const stored = await env.DB.prepare(
    "SELECT * FROM runs WHERE season_id = ? AND idempotency_key = ?"
  ).bind(season.season_id, parsed.idempotency_key).first<RunRow>();
  if (!stored) throw new Error("run insert did not produce a row");
  if (stored.submission_id !== submission.submission_id) throw new HttpError(409, "idempotency_conflict", "idempotency key was already used for a different run");
  if (stored.status === "queued" && stored.enqueued_at === null) {
    const coordinator = env.RUN_COORDINATOR.getByName(stored.run_id);
    await coordinator.initialize(stored.run_id, stored.season_id, stored.submission_id, now);
    await env.RUN_QUEUE.send({ schema_version: "yard.hosted.run-job.v1", run_id: stored.run_id, generation: 1 } satisfies RunJob, { contentType: "json" });
    await env.DB.prepare("UPDATE runs SET enqueued_at = COALESCE(enqueued_at, ?) WHERE run_id = ?").bind(isoNow(), stored.run_id).run();
  }
  return jsonResponse({ run: stored }, stored.run_id === runId ? 202 : 200);
}

function publicRun(row: RunRow): Record<string, unknown> {
  return {
    run_id: row.run_id,
    season_id: row.season_id,
    submission_id: row.submission_id,
    status: row.status,
    attempts: row.attempts,
    envelope_sha256: row.envelope_sha256,
    error: row.status === "failed" ? { code: row.error_code } : null,
    created_at: row.created_at,
    started_at: row.started_at,
    finished_at: row.finished_at
  };
}

async function getSeasonResponse(env: Env, seasonId: string): Promise<Response> {
  const season = await getSeason(env, seasonId);
  return jsonResponse({
    season: JSON.parse(season.manifest_json),
    signature: JSON.parse(season.signature_json),
    state: season.state,
    revealed_at: season.revealed_at,
    reveal_artifact_sha256: season.state === "revealed" ? season.reveal_artifact_sha256 : null
  });
}

async function streamRunArtifact(env: Env, runId: string, column: "envelope_r2_key" | "replay_r2_key"): Promise<Response> {
  const run = await getRun(env, runId);
  if (run.status !== "completed") throw new HttpError(409, "run_not_completed", "run has no completed artifact");
  const key = run[column];
  if (!key) throw new HttpError(404, "run_artifact_missing", "run artifact pointer is missing");
  const object = await env.ARTIFACTS.get(key);
  if (!object) throw new HttpError(404, "run_artifact_missing", "run artifact object is missing");
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("cache-control", "public, max-age=31536000, immutable");
  headers.set("x-content-type-options", "nosniff");
  return new Response(object.body, { headers });
}

async function leaderboard(env: Env, url: URL): Promise<Response> {
  const seasonId = url.searchParams.get("season_id");
  if (!seasonId) throw new HttpError(400, "season_id_required", "season_id query parameter is required");
  const rawTrack = url.searchParams.get("track");
  const requestedTrack = rawTrack === null
    ? null
    : z.enum(["declared_human", "human_ai", "autonomous_agent", "exhibition"]).parse(rawTrack);
  const rawLimit = url.searchParams.get("limit") ?? "100";
  if (!/^\d{1,3}$/.test(rawLimit)) throw new HttpError(400, "invalid_limit", "limit must be an integer from 1 to 500");
  const limit = Math.min(500, Math.max(1, Number.parseInt(rawLimit, 10)));
  const query = requestedTrack
    ? `SELECT r.*, s.track, s.entrant FROM runs r JOIN submissions s ON s.submission_id = r.submission_id
       WHERE r.season_id = ? AND r.status = 'completed' AND s.track = ? ORDER BY r.finished_at LIMIT ?`
    : `SELECT r.*, s.track, s.entrant FROM runs r JOIN submissions s ON s.submission_id = r.submission_id
       WHERE r.season_id = ? AND r.status = 'completed' ORDER BY r.finished_at LIMIT ?`;
  const bindings = requestedTrack
    ? [seasonId, requestedTrack, maxRankedLeaderboardEntries + 1]
    : [seasonId, maxRankedLeaderboardEntries + 1];
  const rows = (await env.DB.prepare(query).bind(...bindings).all<BoardRow>()).results;
  if (rows.length > maxRankedLeaderboardEntries) {
    throw new HttpError(503, "leaderboard_capacity", "season exceeds the live ranking capacity; publish a materialized board snapshot");
  }
  const runIds = rows.map((row) => row.run_id);
  if (runIds.length === 0) return jsonResponse({ season_id: seasonId, track: requestedTrack, entries: [] });
  const objectiveQuery = requestedTrack
    ? `SELECT o.run_id, o.name, o.direction, o.epsilon, o.value FROM objectives o
       JOIN runs r ON r.run_id = o.run_id JOIN submissions s ON s.submission_id = r.submission_id
       WHERE r.season_id = ? AND r.status = 'completed' AND s.track = ?`
    : `SELECT o.run_id, o.name, o.direction, o.epsilon, o.value FROM objectives o
       JOIN runs r ON r.run_id = o.run_id
       WHERE r.season_id = ? AND r.status = 'completed'`;
  const objectiveBindings = requestedTrack ? [seasonId, requestedTrack] : [seasonId];
  const objectives = (await env.DB.prepare(objectiveQuery).bind(...objectiveBindings).all<ObjectiveRow>()).results;
  const byRun = new Map<string, ObjectiveValue[]>();
  for (const objective of objectives) {
    const values = byRun.get(objective.run_id) ?? [];
    values.push(objective);
    byRun.set(objective.run_id, values);
  }
  const paretoEntries: TrackParetoEntry[] = rows.map((row) => ({
    run_id: row.run_id,
    track: row.track,
    objectives: byRun.get(row.run_id) ?? []
  }));
  const ranks = assignTrackSeparatedRanks(paretoEntries.filter((entry) => entry.objectives.length > 0));
  return jsonResponse({
    season_id: seasonId,
    track: requestedTrack,
    entries: rows.slice(0, limit).map((row) => ({
      run_id: row.run_id,
      submission_id: row.submission_id,
      entrant: row.entrant,
      track: row.track,
      pareto_rank: ranks.get(row.run_id) ?? null,
      objectives: byRun.get(row.run_id) ?? [],
      envelope_sha256: row.envelope_sha256,
      finished_at: row.finished_at
    }))
  });
}

async function route(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname.replace(/\/+$/, "") || "/";
  if (request.method === "GET" && path === "/healthz") {
    return jsonResponse({ service: env.SERVICE_VERSION, status: "ok" });
  }
  const artifactMatch = path.match(/^\/v1\/artifacts\/([a-f0-9]{64})$/);
  if (request.method === "PUT" && artifactMatch?.[1]) return uploadArtifact(request, env, artifactMatch[1]);
  if (request.method === "POST" && path === "/v1/admin/seasons") return importSeason(request, env);
  const closeMatch = path.match(/^\/v1\/admin\/seasons\/([A-Za-z0-9][A-Za-z0-9._:-]*)\/close$/);
  if (request.method === "POST" && closeMatch?.[1]) return closeSeason(request, env, closeMatch[1]);
  const revealMatch = path.match(/^\/v1\/admin\/seasons\/([A-Za-z0-9][A-Za-z0-9._:-]*)\/reveal$/);
  if (request.method === "POST" && revealMatch?.[1]) return revealSeason(request, env, revealMatch[1]);
  if (request.method === "POST" && path === "/v1/submissions") return createSubmission(request, env);
  if (request.method === "POST" && path === "/v1/runs") return createRun(request, env);
  const runMatch = path.match(/^\/v1\/runs\/([0-9a-f-]{36})$/);
  if (request.method === "GET" && runMatch?.[1]) return jsonResponse({ run: publicRun(await getRun(env, runMatch[1])) });
  const resultMatch = path.match(/^\/v1\/runs\/([0-9a-f-]{36})\/result$/);
  if (request.method === "GET" && resultMatch?.[1]) return streamRunArtifact(env, resultMatch[1], "envelope_r2_key");
  const replayMatch = path.match(/^\/v1\/runs\/([0-9a-f-]{36})\/replay$/);
  if (request.method === "GET" && replayMatch?.[1]) return streamRunArtifact(env, replayMatch[1], "replay_r2_key");
  const seasonMatch = path.match(/^\/v1\/seasons\/([A-Za-z0-9][A-Za-z0-9._:-]*)$/);
  if (request.method === "GET" && seasonMatch?.[1]) return getSeasonResponse(env, seasonMatch[1]);
  const hiddenSeasonMatch = path.match(/^\/v1\/seasons\/([A-Za-z0-9][A-Za-z0-9._:-]*)\/hidden$/);
  if (request.method === "GET" && hiddenSeasonMatch?.[1]) return streamRevealedHidden(env, hiddenSeasonMatch[1]);
  if (request.method === "GET" && path === "/v1/leaderboards") return leaderboard(env, url);
  throw new HttpError(404, "not_found", "route does not exist");
}

async function storeImmutable(env: Env, key: string, bytes: string, contentType: string): Promise<{ key: string; sha256: string }> {
  const digest = await sha256Hex(bytes);
  const stored = await env.ARTIFACTS.put(key, bytes, {
    sha256: digest,
    onlyIf: new Headers({ "if-none-match": "*" }),
    httpMetadata: { contentType },
    customMetadata: { sha256: digest }
  });
  if (!stored) {
    const existing = await env.ARTIFACTS.head(key);
    if (!existing || existing.customMetadata?.sha256 !== digest) throw new RunnerError("run_artifact_conflict", `immutable key conflict at ${key}`);
  }
  return { key, sha256: digest };
}

async function processRun(job: RunJob, attempt: number, env: Env): Promise<void> {
  const coordinator = env.RUN_COORDINATOR.getByName(job.run_id);
  const claim = await coordinator.claim(attempt, isoNow());
  if (!claim.accepted) return;
  const run = await getRun(env, job.run_id);
  if (run.status === "completed") {
    if (!run.envelope_r2_key) throw new RunnerError("completed_run_missing_envelope", "completed run has no signed-result pointer", false);
    await coordinator.complete(run.envelope_r2_key, attempt, isoNow());
    return;
  }
  if (run.status === "failed") {
    await coordinator.fail(run.error_code ?? "failed", true, attempt, isoNow());
    return;
  }
  const [seasonRow, submissionRow] = await Promise.all([getSeason(env, run.season_id), getSubmission(env, run.submission_id)]);
  const season = SeasonManifestSchema.parse(JSON.parse(seasonRow.manifest_json));
  const submissionRequest = CreateSubmissionRequestSchema.parse(JSON.parse(submissionRow.request_json));
  const [missionArtifact, hiddenArtifact, evaluatorArtifact] = await Promise.all([
    getArtifact(env, season.mission_artifact_sha256, "mission"),
    getArtifact(env, season.hidden_manifest_sha256, "hidden-season"),
    getArtifact(env, season.evaluator_artifact_sha256, "evaluator-binary")
  ]);
  const agentArtifact = submissionRow.agent_artifact_sha256
    ? await getArtifact(env, submissionRow.agent_artifact_sha256, "agent-binary")
    : null;
  const startStatus = submissionRow.source_kind === "agent_binary" ? "running_agent" : "running_evaluator";
  const initialStage = await coordinator.setStage(startStatus, attempt, isoNow());
  if (!initialStage.accepted) return;
  await env.DB.prepare(
    "UPDATE runs SET status = ?, attempts = ?, started_at = COALESCE(started_at, ?) WHERE run_id = ? AND attempts <= ? AND status NOT IN ('completed', 'failed')"
  ).bind(startStatus, attempt, isoNow(), run.run_id, attempt).run();
  const started = await getRun(env, run.run_id);
  if (started.attempts !== attempt || started.status !== startStatus) throw new StaleLeaseError("run lease changed before execution");

  const artifacts = await executeHostedRun(
    env,
    run.run_id,
    submissionRequest,
    season,
    missionArtifact,
    hiddenArtifact,
    evaluatorArtifact,
    agentArtifact,
    async () => {
      const evaluatorStage = await coordinator.setStage("running_evaluator", attempt, isoNow());
      if (!evaluatorStage.accepted) throw new StaleLeaseError("run lease changed before evaluator execution");
      await env.DB.prepare(
        "UPDATE runs SET status = 'running_evaluator' WHERE run_id = ? AND attempts = ? AND status NOT IN ('completed', 'failed')"
      ).bind(run.run_id, attempt).run();
      const current = await getRun(env, run.run_id);
      if (current.attempts !== attempt || current.status !== "running_evaluator") throw new StaleLeaseError("run lease changed before evaluator execution");
    }
  );
  if (!(await coordinator.isCurrent(attempt))) throw new StaleLeaseError("run lease changed before artifact publication");
  const prefix = `runs/${run.run_id}/attempts/${attempt}`;
  const [hostedSubmission, result, replay, scorecard] = await Promise.all([
    storeImmutable(env, `${prefix}/submission.json`, artifacts.submissionBytes, "application/json"),
    storeImmutable(env, `${prefix}/result.json`, artifacts.resultBytes, "application/json"),
    storeImmutable(env, `${prefix}/replay.jsonl`, artifacts.replayBytes, "application/x-ndjson"),
    storeImmutable(env, `${prefix}/scorecard.json`, artifacts.scorecardBytes, "application/json")
  ]);
  const completedAt = isoNow();
  const signed = await signResultPayload({
    run_id: run.run_id,
    attempt,
    season_id: season.season_id,
    submission_id: artifacts.submission.submission_id,
    host_submission_id: run.submission_id,
    evaluator_version: season.evaluator_version,
    evaluator_artifact_sha256: season.evaluator_artifact_sha256,
    runner_image_digest: season.runner_image_digest,
    runner_base_image_digest: env.RUNNER_BASE_IMAGE_DIGEST,
    submission_sha256: await sha256Hex(artifacts.submissionBytes),
    result_sha256: result.sha256,
    replay_sha256: replay.sha256,
    scorecard_sha256: scorecard.sha256,
    scorecard: artifacts.scorecard
  }, {
    keyId: env.RESULT_SIGNING_KEY_ID,
    privateKeyPkcs8Base64: env.RESULT_SIGNING_PRIVATE_KEY_PKCS8_B64,
    publicKeyHex: env.RESULT_SIGNING_PUBLIC_KEY_HEX
  });
  const envelopeBytes = `${canonicalJson(signed)}\n`;
  const envelope = await storeImmutable(env, `${prefix}/signed-result.json`, envelopeBytes, "application/json");
  if (!(await coordinator.isCurrent(attempt))) throw new StaleLeaseError("run lease changed before metadata publication");
  const statements: D1PreparedStatement[] = [
    env.DB.prepare(
      `DELETE FROM objectives WHERE run_id = ? AND EXISTS
       (SELECT 1 FROM runs WHERE run_id = ? AND attempts = ? AND status = 'running_evaluator')`
    ).bind(run.run_id, run.run_id, attempt),
    env.DB.prepare(
      `INSERT INTO audit_events (run_id, event_type, detail_json, created_at)
       SELECT ?, 'run_completed', ?, ? WHERE EXISTS
       (SELECT 1 FROM runs WHERE run_id = ? AND attempts = ? AND status = 'running_evaluator')`
    ).bind(run.run_id, canonicalJson({ envelope_sha256: envelope.sha256 }), completedAt, run.run_id, attempt)
  ];
  for (const objective of artifacts.scorecard.objectives) {
    statements.push(env.DB.prepare(
      `INSERT INTO objectives (run_id, name, direction, epsilon, value)
       SELECT ?, ?, ?, ?, ? WHERE EXISTS
       (SELECT 1 FROM runs WHERE run_id = ? AND attempts = ? AND status = 'running_evaluator')`
    ).bind(run.run_id, objective.name, objective.direction, objective.epsilon, objective.value, run.run_id, attempt));
  }
  statements.push(env.DB.prepare(
    `UPDATE runs SET status = 'completed', submission_sha256 = ?, submission_r2_key = ?, result_r2_key = ?, replay_r2_key = ?,
     scorecard_r2_key = ?, envelope_r2_key = ?, envelope_sha256 = ?, error_code = NULL,
     error_detail = NULL, finished_at = ? WHERE run_id = ? AND attempts = ? AND status = 'running_evaluator'`
  ).bind(
    await sha256Hex(artifacts.submissionBytes),
    hostedSubmission.key,
    result.key,
    replay.key,
    scorecard.key,
    envelope.key,
    envelope.sha256,
    completedAt,
    run.run_id,
    attempt
  ));
  await env.DB.batch(statements);
  const published = await getRun(env, run.run_id);
  if (published.status !== "completed" || published.attempts !== attempt || published.envelope_sha256 !== envelope.sha256) {
    throw new StaleLeaseError("run lease changed during metadata publication");
  }
  const completed = await coordinator.complete(envelope.key, attempt, completedAt);
  if (!completed.accepted) {
    console.warn(JSON.stringify({ level: "warn", event: "coordinator_completion_deferred", run_id: run.run_id, attempt }));
  }
  console.log(JSON.stringify({ level: "info", event: "run_completed", run_id: run.run_id, envelope_sha256: envelope.sha256 }));
}

async function failRun(job: RunJob, attempt: number, error: unknown, env: Env): Promise<boolean> {
  const retryable = error instanceof RunnerError && error.retryable && attempt < 3;
  const code = error instanceof RunnerError ? error.code : "internal_error";
  const detail = (error instanceof Error ? error.message : String(error)).slice(0, 2_048);
  const status = retryable ? "queued" : "failed";
  const now = isoNow();
  await env.DB.prepare(
    "UPDATE runs SET status = ?, error_code = ?, error_detail = ?, finished_at = ? WHERE run_id = ? AND attempts = ? AND status NOT IN ('completed', 'failed')"
  ).bind(status, code, detail, retryable ? null : now, job.run_id, attempt).run();
  const failed = await env.RUN_COORDINATOR.getByName(job.run_id).fail(code, !retryable, attempt, now);
  console.error(JSON.stringify({ level: "error", event: "run_failed", run_id: job.run_id, attempt, retryable, code }));
  return retryable && failed.accepted;
}

async function reconcileOutbox(env: Env): Promise<void> {
  const staleBefore = new Date(Date.now() - outboxRetryAfterMs).toISOString();
  const rows = (await env.DB.prepare(
    `SELECT * FROM runs WHERE status = 'queued' AND (enqueued_at IS NULL OR enqueued_at < ?)
     ORDER BY created_at LIMIT 20`
  ).bind(staleBefore).all<RunRow>()).results;
  for (const run of rows) {
    const generation = run.attempts + 1;
    const coordinator = env.RUN_COORDINATOR.getByName(run.run_id);
    await coordinator.initialize(run.run_id, run.season_id, run.submission_id, isoNow());
    await env.RUN_QUEUE.send({
      schema_version: "yard.hosted.run-job.v1",
      run_id: run.run_id,
      generation
    } satisfies RunJob, { contentType: "json" });
    await env.DB.prepare(
      "UPDATE runs SET enqueued_at = ? WHERE run_id = ? AND status = 'queued' AND attempts = ?"
    ).bind(isoNow(), run.run_id, run.attempts).run();
  }
  if (rows.length > 0) console.log(JSON.stringify({ level: "info", event: "outbox_reconciled", runs: rows.length }));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const requestId = crypto.randomUUID();
    try {
      const response = await route(request, env);
      response.headers.set("x-request-id", requestId);
      return response;
    } catch (error) {
      return errorResponse(error, requestId);
    }
  },

  async queue(batch: MessageBatch<unknown>, env: Env): Promise<void> {
    for (const message of batch.messages) {
      let job: RunJob;
      try {
        job = RunJobSchema.parse(message.body);
      } catch (error) {
        console.error(JSON.stringify({ level: "error", event: "invalid_queue_message", id: message.id, error: String(error) }));
        message.ack();
        continue;
      }
      try {
        const attempt = Math.max(message.attempts, job.generation);
        await processRun(job, attempt, env);
        message.ack();
      } catch (error) {
        const attempt = Math.max(message.attempts, job.generation);
        if (error instanceof StaleLeaseError) {
          console.warn(JSON.stringify({ level: "warn", event: "stale_run_lease", run_id: job.run_id, attempt }));
          message.ack();
          continue;
        }
        if (await failRun(job, attempt, error, env)) message.retry({ delaySeconds: 15 * message.attempts });
        else message.ack();
      }
    }
  },

  async scheduled(_controller: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(reconcileOutbox(env));
  }
} satisfies ExportedHandler<Env, unknown, RunJob>;
