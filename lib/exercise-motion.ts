export type Point = [number, number];
export type Pose = {
  head: Point;
  body: string;
  arms: string[];
  legs: string[];
  weights: Point[];
};
const point = (origin: Point, length: number, degrees: number): Point => [
  origin[0] + length * Math.cos((degrees * Math.PI) / 180),
  origin[1] + length * Math.sin((degrees * Math.PI) / 180),
];
const shift = (p: Point, x: number, y: number): Point => [p[0] + x, p[1] + y];
const line = (...points: Point[]) =>
  points.map((p) => p.map((v) => v.toFixed(3)).join(",")).join(" ");
// Two rigid leg segments meet at the knee; the heel remains a fixed contact.
function knee(
  hip: Point,
  ankle: Point,
  upper: number,
  lower: number,
  side: number,
): Point {
  const dx = ankle[0] - hip[0],
    dy = ankle[1] - hip[1],
    d = Math.hypot(dx, dy);
  const along = (upper * upper - lower * lower + d * d) / (2 * d),
    height = Math.sqrt(Math.max(0, upper * upper - along * along));
  return [
    hip[0] + (dx / d) * along - (dy / d) * height * side,
    hip[1] + (dy / d) * along + (dx / d) * height * side,
  ];
}
export function exercisePose(id: string, progress: number): Pose {
  const t = Math.max(0, Math.min(1, progress));
  if (id === "press") {
    const shoulder: Point = [45, 118],
      elbow = point(shoulder, 26, -88 * t),
      wrist = point(elbow, 26, -90);
    return {
      head: [27, 113],
      body: line([38, 118], [86, 118]),
      arms: [line(shoulder, elbow, wrist)],
      legs: [line([86, 118], [105, 94], [125, 122])],
      weights: [shift(wrist, 0, -4)],
    };
  }
  if (id === "row" || id === "kickback") {
    const shoulder: Point = [58, 50];
    const elbow =
      id === "row" ? point(shoulder, 27, 90 - 65 * t) : point(shoulder, 27, 30);
    const wrist = point(elbow, 26, id === "row" ? 90 - 20 * t : 90 - 60 * t);
    return {
      head: [45, 40],
      body: line([54, 49], [104, 78]),
      arms: [line(shoulder, elbow, wrist), line([61, 52], [76, 78], [87, 87])],
      legs: [
        line([104, 78], [76, 96], [67, 122]),
        line([104, 78], [117, 98], [130, 122]),
      ],
      weights: [shift(wrist, 0, 4)],
    };
  }
  if (id === "squat") {
    const hip: Point = [80, 69 + 26 * t],
      shoulder = shift(hip, 0, -40);
    const left: Point = [54, 122],
      right: Point = [106, 122];
    return {
      head: shift(shoulder, 0, -13),
      body: line(shoulder, hip),
      arms: [
        line(
          shift(shoulder, -11, 5),
          shift(shoulder, -16, 22),
          shift(shoulder, -1, 10),
        ),
        line(
          shift(shoulder, 11, 5),
          shift(shoulder, 16, 22),
          shift(shoulder, 1, 10),
        ),
      ],
      legs: [
        line(shift(hip, -6, 0), knee(shift(hip, -6, 0), left, 29, 29, 1), left),
        line(
          shift(hip, 6, 0),
          knee(shift(hip, 6, 0), right, 29, 29, -1),
          right,
        ),
      ],
      weights: [shift(shoulder, 0, 10)],
    };
  }
  if (id === "rdl") {
    const hip: Point = [95 + 14 * t, 71 + 2 * t],
      shoulder = point(hip, 34, -90 - 50 * t);
    const head = point(shoulder, 13, -90 - 50 * t),
      near = shift(shoulder, 4, 3),
      far = shift(shoulder, -4, 1);
    const ankle: Point = [100, 122],
      other: Point = [112, 122],
      otherHip = shift(hip, 7, 0);
    return {
      head,
      body: line(shoulder, hip),
      arms: [
        line(near, shift(near, 0, 24), shift(near, 0, 46)),
        line(far, shift(far, 0, 24), shift(far, 0, 46)),
      ],
      legs: [
        line(hip, knee(hip, ankle, 27, 25, 1), ankle),
        line(otherHip, knee(otherHip, other, 27, 25, 1), other),
      ],
      weights: [shift(near, 0, 50), shift(far, 0, 50)],
    };
  }
  if (id === "curl") {
    const near: Point = [79, 65],
      far: Point = [87, 62];
    const nearWrist = point(near, 25, 90 + 150 * t),
      farWrist = point(far, 25, 90 + 150 * t);
    return {
      head: [80, 23],
      body: line([80, 36], [84, 78]),
      arms: [line([79, 41], near, nearWrist), line([87, 38], far, farWrist)],
      legs: [
        line([82, 78], [80, 100], [81, 122]),
        line([89, 78], [93, 100], [96, 122]),
      ],
      weights: [nearWrist, farWrist],
    };
  }
  const hip: Point = [78, 118],
    movingHeel: Point = [112 + 30 * t, 122],
    otherHeel: Point = [118, 122];
  return {
    head: [26, 113],
    body: line([37, 118], hip),
    arms: [line([45, 118], [63, 123], [79, 123])],
    legs: [
      line(hip, knee(hip, otherHeel, 34, 34, -1), otherHeel),
      line(hip, knee(hip, movingHeel, 34, 34, -1), movingHeel),
    ],
    weights: [],
  };
}
