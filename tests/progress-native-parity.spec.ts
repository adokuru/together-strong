import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import {
  progressSummary,
  weeklyProgress,
  exerciseRecords,
  sessionDay,
  routine,
  parseData,
  type WorkoutData,
} from "../lib/workout";

const fixtures = JSON.parse(
  readFileSync("contracts/fixtures/workout-progress.json", "utf8"),
) as Array<{
  zone: string;
  now: string;
  data: WorkoutData;
  summary: ReturnType<typeof progressSummary>;
  weekly: ReturnType<typeof weeklyProgress>;
  records: Record<string, ReturnType<typeof exerciseRecords>>;
  days: Record<string, string>;
}>;

test("native progress and calendar fixtures follow the web rules in every time zone", () => {
  const prior = process.env.TZ;
  try {
    for (const fixture of fixtures) {
      process.env.TZ = fixture.zone;
      expect(parseData(fixture.data)).not.toBeNull();
      expect(progressSummary(fixture.data, new Date(fixture.now))).toEqual(
        fixture.summary,
      );
      expect(weeklyProgress(fixture.data, new Date(fixture.now))).toEqual(
        fixture.weekly,
      );
      for (const exercise of routine("David"))
        expect(exerciseRecords(fixture.data, exercise)).toEqual(
          fixture.records[exercise.id],
        );
      for (const session of fixture.data.sessions.filter((s) => !s.discardedAt))
        expect(sessionDay(session)).toEqual(fixture.days[session.id]);
    }
  } finally {
    if (prior === undefined) delete process.env.TZ;
    else process.env.TZ = prior;
  }
});
