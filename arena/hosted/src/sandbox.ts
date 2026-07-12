import { ContainerProxy, Sandbox, getSandbox } from "@cloudflare/sandbox";
import {
  ArenaScorecardSchema,
  ArenaSubmissionSchema,
  type ArenaScorecard,
  type ArenaSubmission,
  type ArtifactKind,
  type CreateSubmissionRequest,
  type SeasonManifest
} from "./contracts";
import { canonicalJson, sha256Hex, verifyReplayNdjson, type ReplaySummary } from "./crypto";
import { RunnerError, validateScorecardBindings } from "./validation";

export { ContainerProxy };
export { RunnerError, validateScorecardBindings } from "./validation";

export class YardAgentSandbox extends Sandbox<Env> {
  override enableInternet = false;
  override allowedHosts: string[] = [];
  override sleepAfter: string | number = "1m";
}

export interface ArtifactRecord {
  sha256: string;
  kind: ArtifactKind;
  size_bytes: number;
  r2_key: string;
}

export interface ExecutionArtifacts {
  submission: ArenaSubmission;
  submissionBytes: string;
  resultBytes: string;
  replayBytes: string;
  scorecardBytes: string;
  scorecard: ArenaScorecard;
}

async function artifactObject(env: Env, artifact: ArtifactRecord): Promise<R2ObjectBody> {
  const object = await env.ARTIFACTS.get(artifact.r2_key);
  if (!object) throw new RunnerError("artifact_missing", `artifact ${artifact.sha256} is missing`, false);
  if (object.size !== artifact.size_bytes || object.customMetadata?.sha256 !== artifact.sha256) {
    throw new RunnerError("artifact_integrity", `artifact ${artifact.sha256} metadata mismatch`, false);
  }
  return object;
}

async function copyArtifact(env: Env, sandbox: YardAgentSandbox, artifact: ArtifactRecord, path: string): Promise<void> {
  const object = await artifactObject(env, artifact);
  await sandbox.writeFile(path, object.body);
}

async function readTextBounded(sandbox: YardAgentSandbox, path: string, maxBytes: number): Promise<string> {
  const measured = await sandbox.exec(`wc -c < ${path}`, { timeout: 5_000 });
  if (!measured.success) throw new RunnerError("missing_output", `runner did not create ${path}`, false);
  const size = Number.parseInt(measured.stdout.trim(), 10);
  if (!Number.isSafeInteger(size) || size < 0 || size > maxBytes) {
    throw new RunnerError("output_limit", `${path} exceeds the ${maxBytes}-byte output limit`, false);
  }
  const result = await sandbox.readFile(path, { encoding: "utf-8" });
  if (!result.success) throw new RunnerError("missing_output", `unable to read ${path}`, false);
  return result.content;
}

async function prepareFilesystem(sandbox: YardAgentSandbox): Promise<void> {
  await sandbox.mkdir("/workspace/bin", { recursive: true });
  await sandbox.mkdir("/workspace/input", { recursive: true });
  await sandbox.mkdir("/workspace/output", { recursive: true });
}

async function runAgent(
  env: Env,
  runId: string,
  request: CreateSubmissionRequest,
  season: SeasonManifest,
  missionArtifact: ArtifactRecord,
  agentArtifact: ArtifactRecord
): Promise<{ submission: ArenaSubmission; bytes: string }> {
  const sandbox = getSandbox(env.AGENT_SANDBOX, `agent-${runId}`, {
    enableDefaultSession: false,
    sleepAfter: "1m",
    transport: "rpc"
  });
  try {
    await prepareFilesystem(sandbox);
    await copyArtifact(env, sandbox, agentArtifact, "/workspace/bin/agent");
    await copyArtifact(env, sandbox, missionArtifact, "/workspace/input/mission.json");
    const agentRequest = canonicalJson({
      schema_version: "yard.hosted.agent-request.v1",
      season_id: season.season_id,
      mission_id: season.mission_id,
      mission_version: season.mission_version,
      ruleset_id: season.ruleset_id,
      mission_path: "/workspace/input/mission.json",
      output_path: "/workspace/output/submission.json",
      entrant: request.source.kind === "agent_binary" ? request.source.entrant : ""
    });
    await sandbox.writeFile("/workspace/input/request.json", `${agentRequest}\n`);
    const fileBlocks = Math.max(2, Math.ceil(season.resource_policy.max_output_bytes / 512));
    const command = `chmod 0500 /workspace/bin/agent && ulimit -f ${fileBlocks}; exec /workspace/bin/agent /workspace/input/request.json /workspace/output/submission.json > /workspace/output/stdout.log 2> /workspace/output/stderr.log`;
    const execution = await sandbox.exec(command, { timeout: season.resource_policy.agent_timeout_ms });
    if (!execution.success) throw new RunnerError("agent_failed", `agent exited with code ${execution.exitCode}`, false);
    const raw = await readTextBounded(sandbox, "/workspace/output/submission.json", season.resource_policy.max_output_bytes);
    let submission: ArenaSubmission;
    try {
      submission = ArenaSubmissionSchema.parse(JSON.parse(raw));
    } catch (error) {
      throw new RunnerError("agent_output_invalid", `agent output is not a strict Arena submission: ${String(error)}`, false);
    }
    if (submission.mission_id !== season.mission_id || submission.mission_version !== season.mission_version || submission.ruleset_id !== season.ruleset_id) {
      throw new RunnerError("agent_mission_mismatch", "agent output does not target the active season", false);
    }
    if (submission.track !== "autonomous_agent") {
      throw new RunnerError("agent_track_mismatch", "agent output track must be autonomous_agent", false);
    }
    const bytes = `${canonicalJson(submission)}\n`;
    return { submission, bytes };
  } catch (error) {
    if (error instanceof RunnerError) throw error;
    throw new RunnerError("agent_runtime", String(error), true);
  } finally {
    try {
      await sandbox.destroy();
    } catch (error) {
      throw new RunnerError("agent_cleanup_failed", `agent sandbox destruction failed: ${String(error)}`, true);
    }
  }
}

async function runEvaluator(
  env: Env,
  runId: string,
  season: SeasonManifest,
  submission: ArenaSubmission,
  submissionBytes: string,
  missionArtifact: ArtifactRecord,
  hiddenArtifact: ArtifactRecord,
  evaluatorArtifact: ArtifactRecord
): Promise<Omit<ExecutionArtifacts, "submission">> {
  const sandbox = getSandbox(env.AGENT_SANDBOX, `evaluator-${runId}`, {
    enableDefaultSession: false,
    sleepAfter: "1m",
    transport: "rpc"
  });
  try {
    await prepareFilesystem(sandbox);
    await copyArtifact(env, sandbox, evaluatorArtifact, "/workspace/bin/evaluator");
    await copyArtifact(env, sandbox, missionArtifact, "/workspace/input/mission.json");
    await copyArtifact(env, sandbox, hiddenArtifact, "/workspace/input/hidden-season.json");
    await sandbox.writeFile("/workspace/input/submission.json", submissionBytes);
    const fileBlocks = Math.max(2, Math.ceil(season.resource_policy.max_output_bytes / 512));
    const command = `chmod 0500 /workspace/bin/evaluator && ulimit -f ${fileBlocks}; exec /workspace/bin/evaluator evaluate --mission /workspace/input/mission.json --hidden-season /workspace/input/hidden-season.json --submission /workspace/input/submission.json --output-dir /workspace/output > /workspace/output/stdout.log 2> /workspace/output/stderr.log`;
    const execution = await sandbox.exec(command, { timeout: season.resource_policy.evaluator_timeout_ms });
    if (!execution.success) throw new RunnerError("evaluator_failed", `evaluator exited with code ${execution.exitCode}`, false);

    const [resultBytes, replayBytes, scorecardBytes] = await Promise.all([
      readTextBounded(sandbox, "/workspace/output/result.json", season.resource_policy.max_output_bytes),
      readTextBounded(sandbox, "/workspace/output/replay.jsonl", season.resource_policy.max_output_bytes),
      readTextBounded(sandbox, "/workspace/output/scorecard.json", season.resource_policy.max_output_bytes)
    ]);
    let scorecard: ArenaScorecard;
    let replay: ReplaySummary;
    try {
      scorecard = ArenaScorecardSchema.parse(JSON.parse(scorecardBytes));
      replay = await verifyReplayNdjson(replayBytes);
    } catch (error) {
      throw new RunnerError("evaluator_output_invalid", `evaluator output failed strict verification: ${String(error)}`, false);
    }
    const submissionSha256 = await sha256Hex(submissionBytes);
    const resultSha256 = await sha256Hex(resultBytes);
    validateScorecardBindings({ scorecard, submission, season, submissionSha256, resultSha256, replay });
    return { submissionBytes, resultBytes, replayBytes, scorecardBytes, scorecard };
  } catch (error) {
    if (error instanceof RunnerError) throw error;
    throw new RunnerError("evaluator_runtime", String(error), true);
  } finally {
    try {
      await sandbox.destroy();
    } catch (error) {
      throw new RunnerError("evaluator_cleanup_failed", `evaluator sandbox destruction failed: ${String(error)}`, true);
    }
  }
}

export async function executeHostedRun(
  env: Env,
  runId: string,
  request: CreateSubmissionRequest,
  season: SeasonManifest,
  missionArtifact: ArtifactRecord,
  hiddenArtifact: ArtifactRecord,
  evaluatorArtifact: ArtifactRecord,
  agentArtifact: ArtifactRecord | null,
  onEvaluatorStart: () => Promise<void>
): Promise<ExecutionArtifacts> {
  let submission: ArenaSubmission;
  let submissionBytes: string;
  if (request.source.kind === "agent_binary") {
    if (!agentArtifact) throw new RunnerError("agent_artifact_missing", "agent submission has no artifact", false);
    const generated = await runAgent(env, runId, request, season, missionArtifact, agentArtifact);
    submission = generated.submission;
    submissionBytes = generated.bytes;
  } else {
    submission = request.source.submission;
    if (submission.mission_id !== season.mission_id || submission.mission_version !== season.mission_version || submission.ruleset_id !== season.ruleset_id) {
      throw new RunnerError("submission_mission_mismatch", "submission does not target the active season", false);
    }
    submissionBytes = `${canonicalJson(submission)}\n`;
  }
  if (!season.tracks.includes(submission.track)) throw new RunnerError("track_closed", "submission track is not open in this season", false);

  await onEvaluatorStart();
  const evaluated = await runEvaluator(
    env,
    runId,
    season,
    submission,
    submissionBytes,
    missionArtifact,
    hiddenArtifact,
    evaluatorArtifact
  );
  return { submission, ...evaluated };
}
