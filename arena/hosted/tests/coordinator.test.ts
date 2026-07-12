import { describe, expect, it } from "vitest";
import { claimIsRecoverable, type CoordinatorStatus } from "../src/claims";

const snapshot = (status: CoordinatorStatus, attempts: number) => ({
  status,
  attempts
});

describe("run coordinator claims", () => {
  it("accepts queued work and rejects a duplicate active delivery", () => {
    expect(claimIsRecoverable(snapshot("queued", 0), 1)).toBe(true);
    expect(claimIsRecoverable(snapshot("queued", 1), 1)).toBe(false);
    expect(claimIsRecoverable(snapshot("running_agent", 1), 1)).toBe(false);
    expect(claimIsRecoverable(snapshot("running_evaluator", 2), 1)).toBe(false);
  });

  it("allows only a higher-attempt crash recovery and never reopens terminal work", () => {
    expect(claimIsRecoverable(snapshot("running_agent", 1), 2)).toBe(true);
    expect(claimIsRecoverable(snapshot("completed", 1), 2)).toBe(false);
    expect(claimIsRecoverable(snapshot("failed", 1), 2)).toBe(false);
  });
});
