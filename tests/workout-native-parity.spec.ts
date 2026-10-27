import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import {
  routine,
  validSet,
  weekNumber,
  sessionStage,
  sessionDay,
  parseData,
  type WorkoutData,
  type SetLog,
} from "../lib/workout";

const fixtures = JSON.parse(
  readFileSync("contracts/fixtures/workout-rules.json", "utf8"),
) as {
  now: string;
  routines: Record<string, unknown>;
  cases: Array<{
    data: WorkoutData;
    week: number;
    stage: string;
    day: string | null;
  }>;
  sets: Array<{ set: SetLog; bodyweight: boolean; valid: boolean }>;
};

test("native exercise content and shared rule expectations match the owning web rules", () => {
  for (const profile of ["David", "Mary"] as const)
    expect(
      routine(profile).map((exercise) => ({
        ...exercise,
        side: Boolean(exercise.side),
        bodyweight: Boolean(exercise.bodyweight),
      })),
    ).toEqual(fixtures.routines[profile]);
  for (const sample of fixtures.cases) {
    expect(parseData(sample.data)).not.toBeNull();
    expect(weekNumber(sample.data, new Date(fixtures.now))).toBe(sample.week);
    expect(sessionStage(sample.data.sessions[0])).toBe(sample.stage);
    expect(
      sample.data.sessions[0] ? sessionDay(sample.data.sessions[0]) : null,
    ).toBe(sample.day);
  }
  for (const sample of fixtures.sets)
    expect(validSet(sample.set, sample.bodyweight)).toBe(sample.valid);
});
