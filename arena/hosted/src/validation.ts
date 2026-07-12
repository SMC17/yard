import type { ArenaScorecard, ArenaSubmission, SeasonManifest } from "./contracts";
import type { ReplaySummary } from "./crypto";

export class RunnerError extends Error {
  constructor(public readonly code: string, message: string, public readonly retryable = false) {
    super(message);
  }
}

export interface ScorecardBindings {
  scorecard: ArenaScorecard;
  submission: ArenaSubmission;
  season: SeasonManifest;
  submissionSha256: string;
  resultSha256: string;
  replay: ReplaySummary;
}

export function validateScorecardBindings(bindings: ScorecardBindings): void {
  const { scorecard, submission, season, submissionSha256, resultSha256, replay } = bindings;
  if (scorecard.mission_id !== season.mission_id || scorecard.mission_version !== season.mission_version || scorecard.ruleset_id !== season.ruleset_id) {
    throw new RunnerError("scorecard_mission_mismatch", "scorecard does not bind the active season", false);
  }
  if (scorecard.submission_id !== submission.submission_id || scorecard.track !== submission.track) {
    throw new RunnerError("scorecard_submission_mismatch", "scorecard identity or track does not bind the evaluated submission", false);
  }
  if (scorecard.evaluator_version !== season.evaluator_version) {
    throw new RunnerError("scorecard_evaluator_mismatch", "scorecard evaluator version does not match the signed season", false);
  }
  if (scorecard.mission_sha256 !== season.mission_artifact_sha256 || scorecard.submission_sha256 !== submissionSha256) {
    throw new RunnerError("scorecard_input_mismatch", "scorecard input hashes do not match hosted artifacts", false);
  }
  if (scorecard.simulation_result_sha256 !== resultSha256) {
    throw new RunnerError("scorecard_result_mismatch", "scorecard result hash does not match result bytes", false);
  }
  if (scorecard.replay_head_sha256 !== replay.headSha256 || scorecard.replay_event_count !== replay.eventCount) {
    throw new RunnerError("scorecard_replay_mismatch", "scorecard replay binding does not match verified replay", false);
  }
  if (scorecard.season_commitment_sha256 !== season.hidden_manifest_sha256) {
    throw new RunnerError("scorecard_season_mismatch", "scorecard hidden-season commitment does not match", false);
  }

  if (!scorecard.feasible) {
    if (scorecard.objectives.length !== 0) {
      throw new RunnerError("scorecard_infeasible_objectives", "infeasible scorecards cannot publish objective values", false);
    }
    return;
  }
  if (scorecard.objectives.length !== season.objectives.length) {
    throw new RunnerError("scorecard_objective_contract", "scorecard objective count does not match the signed season", false);
  }
  const observed = new Map(scorecard.objectives.map((objective) => [objective.name, objective]));
  if (observed.size !== scorecard.objectives.length) {
    throw new RunnerError("scorecard_objective_contract", "scorecard objective names must be unique", false);
  }
  for (const expected of season.objectives) {
    const objective = observed.get(expected.name);
    if (!objective || objective.direction !== expected.direction || objective.epsilon !== expected.epsilon) {
      throw new RunnerError("scorecard_objective_contract", `scorecard objective ${expected.name} does not match the signed season`, false);
    }
  }
}
