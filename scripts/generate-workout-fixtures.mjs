import { writeFileSync } from "node:fs";
import {
  routine,
  emptyData,
  makeSession,
  validSet,
  weekNumber,
  sessionStage,
  sessionDay,
} from "../lib/workout.ts";
process.env.TZ = "UTC";
const quote = JSON.stringify;
const base = routine("David");
const entries = base
  .map(
    (e) =>
      `        Exercise(id: ${quote(e.id)}, name: ${quote(e.name)}, group: ${quote(e.group)}, reps: ${quote(e.reps)}, maxReps: ${e.maxReps}, sets: ${e.sets}, rest: ${e.rest}, instructions: ${quote(e.instructions)}, cue: ${quote(e.cue)}, side: ${Boolean(e.side)}, bodyweight: ${Boolean(e.bodyweight)})`,
  )
  .join(",\n");
writeFileSync(
  "ios/TogetherStrong/Domain/Exercise.swift",
  `// Generated from lib/workout.ts by scripts/generate-workout-fixtures.mjs.\nimport Foundation\n\nstruct Exercise: Codable, Equatable {\n    let id: String\n    let name: String\n    let group: String\n    let reps: String\n    let maxReps: Int\n    var sets: Int\n    let rest: Int\n    let instructions: String\n    let cue: String\n    let side: Bool\n    let bodyweight: Bool\n\n    static let all: [Exercise] = [\n${entries}\n    ]\n\n    static func routine(_ profile: Profile) -> [Exercise] {\n        let order = profile == .david ? ["press", "row", "squat", "rdl", "curl", "kickback", "heel"] : ["row", "squat", "press", "rdl", "curl", "kickback", "heel"]\n        return order.compactMap { id in\n            guard var exercise = all.first(where: { $0.id == id }) else { return nil }\n            exercise.sets = (profile == .david && id == "press") || (profile == .mary && id == "row") ? 3 : 2\n            return exercise\n        }\n    }\n}\n`,
);
const now = new Date("2026-10-27T12:00:00.000Z");
const draft = makeSession("David", emptyData());
draft.id = "older-draft";
draft.date = "2026-09-20";
draft.startedAt = "2026-09-20T12:00:00.000Z";
draft.completedAt = "2026-09-20T12:01:00.000Z";
const trained = structuredClone(draft);
trained.id = "trained";
trained.sets.press[0] = { reps: "10", kg: "12.50", done: true };
const variants = [
  emptyData(),
  { ...emptyData(), startedAt: draft.startedAt, sessions: [draft] },
  {
    ...emptyData(),
    startedAt: "2026-10-20T12:00:00.000Z",
    sessions: [trained],
  },
  {
    ...emptyData(),
    startedAt: "2026-10-12T12:00:00.000Z",
    sessions: [trained],
  },
];
const cases = variants.map((data) => ({
  data,
  week: weekNumber(data, now),
  stage: sessionStage(data.sessions[0]),
  day: data.sessions[0] ? sessionDay(data.sessions[0]) : null,
}));
const sets = [
  ["", "", false],
  ["10", "12.50", false],
  ["0", "12", false],
  ["101", "12", false],
  ["10", "", true],
  ["10", "0", false],
  ["10", "200", false],
  ["10", "200.01", false],
  ["10", "1.001", false],
  ["1.5", "10", false],
  ["10", "-1", false],
  ["10", "", false],
  ["10", "1e2", false],
  ["010", "01.20", false],
].map(([reps, kg, bodyweight]) => ({
  set: { reps, kg, done: false },
  bodyweight,
  valid: validSet({ reps, kg, done: false }, bodyweight),
}));
const routines = Object.fromEntries(
  ["David", "Mary"].map((p) => [
    p,
    routine(p).map((e) => ({
      ...e,
      side: Boolean(e.side),
      bodyweight: Boolean(e.bodyweight),
    })),
  ]),
);
writeFileSync(
  "contracts/fixtures/workout-rules.json",
  JSON.stringify({ now: now.toISOString(), routines, cases, sets }, null, 2) +
    "\n",
);
console.log(
  "Generated Swift exercise content and shared workout rule fixtures.",
);
