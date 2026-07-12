export type CoordinatorStatus = "queued" | "running_agent" | "running_evaluator" | "completed" | "failed";

export interface ClaimState {
  status: CoordinatorStatus;
  attempts: number;
}

export function claimIsRecoverable(snapshot: ClaimState, incomingAttempt: number): boolean {
  if (snapshot.status === "queued") return incomingAttempt > snapshot.attempts;
  return (snapshot.status === "running_agent" || snapshot.status === "running_evaluator") &&
    incomingAttempt > snapshot.attempts;
}
