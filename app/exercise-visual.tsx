import { ArrowRight } from "lucide-react";
type Pose = {
  head: [number, number];
  body: string;
  arms: string[];
  legs: string[];
  weights: [number, number][];
};
const poses: Record<string, [Pose, Pose]> = {
  press: [
    {
      head: [27, 101],
      body: "38,107 84,107",
      arms: ["46,106 70,109 70,83"],
      legs: ["84,107 105,84 127,111"],
      weights: [[70, 78]],
    },
    {
      head: [27, 101],
      body: "38,107 84,107",
      arms: ["46,106 48,78 49,51"],
      legs: ["84,107 105,84 127,111"],
      weights: [[49, 46]],
    },
  ],
  row: [
    {
      head: [44, 39],
      body: "52,48 93,68",
      arms: ["57,49 60,77 62,100", "60,51 77,78 92,85"],
      legs: ["93,68 104,92 119,120", "93,68 72,93 65,120"],
      weights: [[62, 106]],
    },
    {
      head: [44, 39],
      body: "52,48 93,68",
      arms: ["57,49 85,45 80,68", "60,51 77,78 92,85"],
      legs: ["93,68 104,92 119,120", "93,68 72,93 65,120"],
      weights: [[80, 73]],
    },
  ],
  squat: [
    {
      head: [78, 23],
      body: "78,36 78,76",
      arms: ["77,42 63,57 75,45", "80,42 94,57 82,45"],
      legs: ["78,76 61,98 55,120", "78,76 94,98 103,120"],
      weights: [[79, 45]],
    },
    {
      head: [78, 50],
      body: "78,63 79,95",
      arms: ["77,68 63,82 75,72", "80,68 94,82 82,72"],
      legs: ["79,95 51,99 48,120", "79,95 106,99 110,120"],
      weights: [[79, 72]],
    },
  ],
  rdl: [
    {
      head: [76, 23],
      body: "76,36 80,76",
      arms: ["74,42 64,65 63,84", "78,43 89,65 90,84"],
      legs: ["80,76 73,98 72,120", "80,76 91,99 92,120"],
      weights: [
        [63, 89],
        [90, 89],
      ],
    },
    {
      head: [43, 54],
      body: "54,60 94,78",
      arms: ["57,63 59,85 60,105", "61,63 75,85 76,105"],
      legs: ["94,78 83,98 86,120", "94,78 103,99 106,120"],
      weights: [
        [60, 110],
        [76, 110],
      ],
    },
  ],
  curl: [
    {
      head: [79, 23],
      body: "79,36 79,76",
      arms: ["77,42 61,64 61,88", "81,42 98,64 98,88"],
      legs: ["79,76 67,99 65,120", "79,76 91,99 94,120"],
      weights: [
        [61, 93],
        [98, 93],
      ],
    },
    {
      head: [79, 23],
      body: "79,36 79,76",
      arms: ["77,42 61,64 67,43", "81,42 98,64 92,43"],
      legs: ["79,76 67,99 65,120", "79,76 91,99 94,120"],
      weights: [
        [67, 38],
        [92, 38],
      ],
    },
  ],
  kickback: [
    {
      head: [43, 39],
      body: "51,48 92,68",
      arms: ["57,51 81,48 83,73", "59,53 75,78 87,85"],
      legs: ["92,68 104,91 119,120", "92,68 70,94 64,120"],
      weights: [[83, 78]],
    },
    {
      head: [43, 39],
      body: "51,48 92,68",
      arms: ["57,51 81,48 109,46", "59,53 75,78 87,85"],
      legs: ["92,68 104,91 119,120", "92,68 70,94 64,120"],
      weights: [[115, 46]],
    },
  ],
  heel: [
    {
      head: [26, 101],
      body: "37,108 78,108",
      arms: ["45,107 63,116 79,116"],
      legs: ["78,108 98,83 118,114", "78,108 94,90 111,115"],
      weights: [],
    },
    {
      head: [26, 101],
      body: "37,108 78,108",
      arms: ["45,107 63,116 79,116"],
      legs: ["78,108 98,83 118,114", "78,108 110,113 142,115"],
      weights: [],
    },
  ],
};
const labels: Record<string, [string, string, string]> = {
  press: [
    "Lower with control",
    "Press above chest",
    "Upper arms gently meet the floor. Exhale as you press; feet stay planted.",
  ],
  row: [
    "Reach down",
    "Pull toward your hip",
    "Keep your torso still. Exhale as you pull. Repeat on both sides.",
  ],
  squat: [
    "Stand tall",
    "Sit between your hips",
    "Keep heels down and the weight close. Inhale down; exhale as you stand.",
  ],
  rdl: [
    "Stand with soft knees",
    "Send your hips back",
    "Weights stay close to your legs. Stop at your comfortable hamstring stretch; exhale to stand.",
  ],
  curl: [
    "Arms by your sides",
    "Bend at the elbows",
    "Elbows stay near your ribs. Exhale as you curl; lower slowly.",
  ],
  kickback: [
    "Bend the elbow",
    "Extend the elbow back",
    "Upper arm stays still. Exhale as you straighten; repeat both sides with a light load.",
  ],
  heel: [
    "Both knees bent",
    "Slide one heel away",
    "Core-control variation. Keep a comfortable neutral back and breathe normally. Return, then switch sides.",
  ],
};
export default function ExerciseVisual({
  id,
  name,
}: {
  id: string;
  name: string;
}) {
  return (
    <div className="visual-guide">
      <div className="visual-label">
        HOW TO DO IT <span>START → END</span>
      </div>
      <div className="pose-pair">
        {poses[id].map((pose, i) => (
          <div className="pose" key={i}>
            <svg
              viewBox="0 0 160 140"
              role="img"
              aria-label={`${name}: ${labels[id][i]}`}
            >
              <line
                x1="15"
                y1="124"
                x2="149"
                y2="124"
                stroke="#d1d9cf"
                strokeWidth="2"
              />
              <circle
                cx={pose.head[0]}
                cy={pose.head[1]}
                r="10"
                fill="#d6e4cf"
                stroke="#3f5542"
                strokeWidth="2.5"
              />
              <polyline
                points={pose.body}
                fill="none"
                stroke="#3f5542"
                strokeWidth="9"
                strokeLinecap="round"
              />
              {pose.legs.map((points, j) => (
                <polyline
                  key={`l${j}`}
                  points={points}
                  fill="none"
                  stroke={j ? "#92a38b" : "#3f5542"}
                  strokeWidth="5"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              ))}
              {pose.arms.map((points, j) => (
                <polyline
                  key={`a${j}`}
                  points={points}
                  fill="none"
                  stroke={j ? "#92a38b" : "#3f5542"}
                  strokeWidth="4"
                  strokeLinecap="round"
                  strokeLinejoin="round"
                />
              ))}
              {pose.weights.map(([x, y], j) => (
                <g
                  key={j}
                  stroke="#c2714d"
                  strokeWidth="4"
                  strokeLinecap="round"
                >
                  <path d={`M${x - 9} ${y}h18`} />
                  <path d={`M${x - 7} ${y - 5}v10M${x + 7} ${y - 5}v10`} />
                </g>
              ))}
              {id === "heel" && i === 1 && (
                <path
                  d="M110 132h30m-5-4 5 4-5 4"
                  fill="none"
                  stroke="#c2714d"
                  strokeWidth="2"
                />
              )}
            </svg>
            <span>
              <b>{i === 0 ? "01" : "02"}</b> {labels[id][i]}
            </span>
          </div>
        ))}
        <span className="pose-arrow">
          <ArrowRight size={20} />
        </span>
      </div>
      <p>{labels[id][2]}</p>
      <small>
        Simple position guide. Move only through a comfortable, controlled
        range.
      </small>
    </div>
  );
}
