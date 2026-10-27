import { writeFileSync } from "node:fs";
import { exercisePose } from "../lib/exercise-motion.ts";
import { guideLabels, guideReferences } from "../lib/exercise-guides.ts";
const ids = ["press", "row", "squat", "rdl", "curl", "kickback", "heel"];
const samples = ids.flatMap((id) =>
  Array.from({ length: 21 }, (_, index) => ({
    id,
    progress: index / 20,
    pose: exercisePose(id, index / 20),
  })),
);
writeFileSync(
  "contracts/fixtures/exercise-motion.json",
  JSON.stringify(samples, null, 2) + "\n",
);
const q = JSON.stringify;
const rows = ids
  .map((id) => {
    const [start, finish, cue] = guideLabels[id];
    const ref = guideReferences[id];
    return `        ${q(id)}: ExerciseGuideInfo(start: ${q(start)}, finish: ${q(finish)}, cue: ${q(cue)}, camera: ${q(ref.camera)}, reference: ${q(ref.url)}, referenceLabel: ${q(ref.label)})`;
  })
  .join(",\n");
writeFileSync(
  "ios/TogetherStrong/Domain/ExerciseGuideInfo.swift",
  `// Generated from lib/exercise-guides.ts by scripts/generate-motion-fixtures.mjs.\nimport Foundation\n\nstruct ExerciseGuideInfo {\n    let start: String\n    let finish: String\n    let cue: String\n    let camera: String\n    let reference: String\n    let referenceLabel: String\n    static let all: [String: ExerciseGuideInfo] = [\n${rows}\n    ]\n}\n`,
);
console.log(
  "Generated motion parity fixtures and native exercise guide content.",
);
