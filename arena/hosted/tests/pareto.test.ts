import { describe, expect, it } from "vitest";
import { assignParetoRanks, assignTrackSeparatedRanks, epsilonDominates, type ParetoEntry } from "../src/pareto";

const entry = (run_id: string, time: number, cargo: number): ParetoEntry => ({
  run_id,
  objectives: [
    { name: "time", direction: "minimize", epsilon: 0.1, value: time },
    { name: "cargo", direction: "maximize", epsilon: 0.5, value: cargo }
  ]
});

describe("epsilon Pareto leaderboard", () => {
  it("keeps tradeoffs on the first frontier", () => {
    const fast = entry("fast", 100, 400);
    const large = entry("large", 120, 500);
    expect(epsilonDominates(fast, large)).toBe(false);
    expect(epsilonDominates(large, fast)).toBe(false);
    const ranks = assignParetoRanks([fast, large]);
    expect(ranks.get("fast")).toBe(0);
    expect(ranks.get("large")).toBe(0);
  });

  it("ranks a dominated result behind the frontier", () => {
    const winner = entry("winner", 100, 500);
    const loser = entry("loser", 130, 390);
    expect(epsilonDominates(winner, loser)).toBe(true);
    expect(assignParetoRanks([winner, loser]).get("loser")).toBe(1);
  });

  it("never ranks entries from different competition tracks against each other", () => {
    const human = { ...entry("human", 100, 500), track: "declared_human" };
    const agent = { ...entry("agent", 130, 390), track: "autonomous_agent" };
    const ranks = assignTrackSeparatedRanks([human, agent]);
    expect(ranks.get("human")).toBe(0);
    expect(ranks.get("agent")).toBe(0);
  });

  it("cannot form a cyclic epsilon-dominance graph", () => {
    const cyclic = (run_id: string, values: number[]): ParetoEntry => ({
      run_id,
      objectives: values.map((value, index) => ({
        name: `objective-${index}`,
        direction: "minimize",
        epsilon: 1,
        value
      }))
    });
    const entries = [cyclic("a", [0, 1, 2]), cyclic("b", [2, 0, 1]), cyclic("c", [1, 2, 0])];
    expect(assignParetoRanks(entries)).toEqual(new Map([["a", 0], ["b", 0], ["c", 0]]));
  });
});
