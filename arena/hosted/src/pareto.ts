export interface ObjectiveValue {
  name: string;
  direction: "minimize" | "maximize";
  epsilon: number;
  value: number;
}

export interface ParetoEntry {
  run_id: string;
  objectives: ObjectiveValue[];
}

export interface TrackParetoEntry extends ParetoEntry {
  track: string;
}

function normalized(entry: ParetoEntry): Map<string, ObjectiveValue> {
  return new Map(entry.objectives.map((objective) => [objective.name, objective]));
}

export function epsilonDominates(candidate: ParetoEntry, other: ParetoEntry): boolean {
  const candidateValues = normalized(candidate);
  const otherValues = normalized(other);
  if (candidateValues.size === 0 || candidateValues.size !== otherValues.size) return false;
  let strictlyBetter = false;
  for (const [name, left] of candidateValues) {
    const right = otherValues.get(name);
    if (!right || right.direction !== left.direction || right.epsilon !== left.epsilon) return false;
    if (left.direction === "minimize") {
      if (left.value > right.value) return false;
      if (left.value < right.value - left.epsilon) strictlyBetter = true;
    } else {
      if (left.value < right.value) return false;
      if (left.value > right.value + left.epsilon) strictlyBetter = true;
    }
  }
  return strictlyBetter;
}

export function assignParetoRanks(entries: ParetoEntry[]): Map<string, number> {
  const remaining = [...entries];
  const ranks = new Map<string, number>();
  let rank = 0;
  while (remaining.length > 0) {
    const frontier = remaining.filter((entry) => !remaining.some(
      (candidate) => candidate.run_id !== entry.run_id && epsilonDominates(candidate, entry)
    ));
    if (frontier.length === 0) throw new Error("Pareto ranking made no progress");
    for (const entry of frontier) ranks.set(entry.run_id, rank);
    const frontierIds = new Set(frontier.map((entry) => entry.run_id));
    for (let index = remaining.length - 1; index >= 0; index -= 1) {
      const entry = remaining[index];
      if (entry && frontierIds.has(entry.run_id)) remaining.splice(index, 1);
    }
    rank += 1;
  }
  return ranks;
}

export function assignTrackSeparatedRanks(entries: TrackParetoEntry[]): Map<string, number> {
  const byTrack = new Map<string, TrackParetoEntry[]>();
  for (const entry of entries) {
    const trackEntries = byTrack.get(entry.track) ?? [];
    trackEntries.push(entry);
    byTrack.set(entry.track, trackEntries);
  }
  const ranks = new Map<string, number>();
  for (const trackEntries of byTrack.values()) {
    for (const [runId, rank] of assignParetoRanks(trackEntries)) ranks.set(runId, rank);
  }
  return ranks;
}
