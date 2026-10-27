import { test, expect } from "@playwright/test";
import { readFileSync } from "node:fs";
import { exercisePose } from "../lib/exercise-motion";
import { guideLabels, guideReferences } from "../lib/exercise-guides";

test("native motion fixtures and guide content follow the web source", () => {
  const samples = JSON.parse(
    readFileSync("contracts/fixtures/exercise-motion.json", "utf8"),
  ) as Array<{
    id: string;
    progress: number;
    pose: ReturnType<typeof exercisePose>;
  }>;
  expect(samples).toHaveLength(147);
  for (const sample of samples)
    expect(exercisePose(sample.id, sample.progress)).toEqual(sample.pose);
  const native = readFileSync(
    "ios/TogetherStrong/Domain/ExerciseGuideInfo.swift",
    "utf8",
  );
  for (const [id, [start, finish, cue]] of Object.entries(guideLabels)) {
    const reference = guideReferences[id];
    expect(new URL(reference.url).protocol).toBe("https:");
    expect(native).toContain(
      `${JSON.stringify(id)}: ExerciseGuideInfo(start: ${JSON.stringify(start)}, finish: ${JSON.stringify(finish)}, cue: ${JSON.stringify(cue)}, camera: ${JSON.stringify(reference.camera)}, reference: ${JSON.stringify(reference.url)}, referenceLabel: ${JSON.stringify(reference.label)})`,
    );
  }
});
