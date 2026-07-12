import { DurableObject } from "cloudflare:workers";
import { claimIsRecoverable, type CoordinatorStatus } from "./claims";

export { claimIsRecoverable } from "./claims";
export type { CoordinatorStatus } from "./claims";

export interface CoordinatorSnapshot {
  run_id: string;
  season_id: string;
  submission_id: string;
  status: CoordinatorStatus;
  attempts: number;
  result_key: string | null;
  error_code: string | null;
  updated_at: string;
}

interface CoordinatorRow extends Record<string, SqlStorageValue> {
  run_id: string;
  season_id: string;
  submission_id: string;
  status: string;
  attempts: number;
  result_key: string | null;
  error_code: string | null;
  updated_at: string;
}

export class RunCoordinator extends DurableObject<Env> {
  constructor(ctx: DurableObjectState, env: Env) {
    super(ctx, env);
    ctx.blockConcurrencyWhile(async () => {
      this.ctx.storage.sql.exec(`
        CREATE TABLE IF NOT EXISTS state (
          singleton INTEGER PRIMARY KEY CHECK (singleton = 1),
          run_id TEXT NOT NULL,
          season_id TEXT NOT NULL,
          submission_id TEXT NOT NULL,
          status TEXT NOT NULL,
          attempts INTEGER NOT NULL,
          result_key TEXT,
          error_code TEXT,
          updated_at TEXT NOT NULL
        )
      `);
    });
  }

  initialize(runId: string, seasonId: string, submissionId: string, now: string): CoordinatorSnapshot {
    this.ctx.storage.sql.exec(
      `INSERT OR IGNORE INTO state
       (singleton, run_id, season_id, submission_id, status, attempts, result_key, error_code, updated_at)
       VALUES (1, ?, ?, ?, 'queued', 0, NULL, NULL, ?)`,
      runId,
      seasonId,
      submissionId,
      now
    );
    return this.read();
  }

  claim(attempt: number, now: string): { accepted: boolean; snapshot: CoordinatorSnapshot } {
    const before = this.read();
    // Duplicate deliveries at the same Queue attempt must not launch a second
    // sandbox. A higher attempt may recover a lease abandoned by a crashed
    // Worker invocation.
    if (!claimIsRecoverable(before, attempt)) return { accepted: false, snapshot: before };
    this.ctx.storage.sql.exec(
      "UPDATE state SET status = 'running_agent', attempts = MAX(attempts, ?), updated_at = ? WHERE singleton = 1",
      attempt,
      now
    );
    return { accepted: true, snapshot: this.read() };
  }

  setStage(status: "running_agent" | "running_evaluator", attempt: number, now: string): { accepted: boolean; snapshot: CoordinatorSnapshot } {
    this.ctx.storage.sql.exec(
      "UPDATE state SET status = ?, updated_at = ? WHERE singleton = 1 AND attempts = ? AND status NOT IN ('completed', 'failed')",
      status,
      now,
      attempt
    );
    const snapshot = this.read();
    return { accepted: snapshot.attempts === attempt && snapshot.status === status, snapshot };
  }

  isCurrent(attempt: number): boolean {
    const snapshot = this.read();
    return snapshot.attempts === attempt && snapshot.status !== "completed" && snapshot.status !== "failed";
  }

  complete(resultKey: string, attempt: number, now: string): { accepted: boolean; snapshot: CoordinatorSnapshot } {
    this.ctx.storage.sql.exec(
      "UPDATE state SET status = 'completed', result_key = ?, error_code = NULL, updated_at = ? WHERE singleton = 1 AND attempts = ? AND status NOT IN ('completed', 'failed')",
      resultKey,
      now,
      attempt
    );
    const snapshot = this.read();
    return { accepted: snapshot.attempts === attempt && snapshot.status === "completed", snapshot };
  }

  fail(errorCode: string, terminal: boolean, attempt: number, now: string): { accepted: boolean; snapshot: CoordinatorSnapshot } {
    this.ctx.storage.sql.exec(
      "UPDATE state SET status = ?, error_code = ?, updated_at = ? WHERE singleton = 1 AND attempts = ? AND status NOT IN ('completed', 'failed')",
      terminal ? "failed" : "queued",
      errorCode,
      now,
      attempt
    );
    const snapshot = this.read();
    const expected = terminal ? "failed" : "queued";
    return { accepted: snapshot.attempts === attempt && snapshot.status === expected, snapshot };
  }

  getSnapshot(): CoordinatorSnapshot {
    return this.read();
  }

  private read(): CoordinatorSnapshot {
    const row = this.ctx.storage.sql.exec<CoordinatorRow>(
      `SELECT run_id, season_id, submission_id, status, attempts, result_key, error_code, updated_at
       FROM state WHERE singleton = 1`
    ).one();
    return { ...row, status: row.status as CoordinatorStatus };
  }
}
