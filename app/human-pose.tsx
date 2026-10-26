import { useId } from "react";
import { exercisePose, Point } from "@/lib/exercise-motion";
const points = (line: string): Point[] =>
  line.split(" ").map((p) => p.split(",").map(Number) as Point);
function limb(a: Point, b: Point, wa: number, wb: number) {
  const dx = b[0] - a[0],
    dy = b[1] - a[1],
    length = Math.hypot(dx, dy) || 1,
    nx = -dy / length,
    ny = dx / length;
  return `M ${a[0] + nx * wa} ${a[1] + ny * wa} Q ${a[0] + dx * 0.48 + nx * wa * 1.08} ${a[1] + dy * 0.48 + ny * wa * 1.08} ${b[0] + nx * wb} ${b[1] + ny * wb} Q ${b[0] + dx * 0.05} ${b[1] + dy * 0.05} ${b[0] - nx * wb} ${b[1] - ny * wb} Q ${a[0] + dx * 0.48 - nx * wa * 1.08} ${a[1] + dy * 0.48 - ny * wa * 1.08} ${a[0] - nx * wa} ${a[1] - ny * wa} Q ${a[0] - dx * 0.08} ${a[1] - dy * 0.08} ${a[0] + nx * wa} ${a[1] + ny * wa} Z`;
}
function Limb({
  nodes,
  widths,
  fill,
}: {
  nodes: Point[];
  widths: number[];
  fill: string;
}) {
  return (
    <g>
      {nodes.slice(1).map((p, i) => (
        <path
          key={i}
          d={limb(nodes[i], p, widths[i], widths[i + 1])}
          fill={fill}
          stroke="#213d4e"
          strokeOpacity=".13"
          strokeWidth=".5"
        />
      ))}
      {nodes.slice(1, -1).map((p, i) => (
        <ellipse
          key={i}
          cx={p[0]}
          cy={p[1]}
          rx={widths[i + 1]}
          ry={widths[i + 1] * 0.9}
          fill={fill}
        />
      ))}
    </g>
  );
}
function Shoe({ point: p, far = false }: { point: Point; far?: boolean }) {
  return (
    <g>
      <ellipse
        cx={p[0] + 1}
        cy="127.5"
        rx="12"
        ry="1.8"
        fill="#314452"
        opacity=".12"
      />
      <path
        d={`M${p[0] - 4},${p[1] - 3} Q${p[0] - 7},${p[1] + 1} ${p[0] - 6},${p[1] + 4} L${p[0] + 10},${p[1] + 4} Q${p[0] + 11},${p[1] + 1} ${p[0] + 5},${p[1]} L${p[0] + 3},${p[1] - 3} Z`}
        fill={far ? "#aebbc2" : "#e8eff1"}
        stroke="#485e69"
        strokeWidth=".7"
      />
      <path d={`M${p[0] - 6} ${p[1] + 4}h16`} stroke="#fff" strokeWidth="1.3" />
    </g>
  );
}
function Weight({ point: p, far = false }: { point: Point; far?: boolean }) {
  return (
    <g transform={`translate(${p[0]} ${p[1]})`}>
      <rect x="-10" y="-2" width="20" height="4" rx="1" fill="#9cacb4" />
      <path
        d="M-11-6h6v12h-6l-2-2v-8zM5-6h6l2 2v8l-2 2H5z"
        fill={far ? "#74848c" : "#304956"}
        stroke="#213843"
        strokeWidth=".6"
      />
      <path d="M-11-6h6v2h-6zM5-6h6v2H5z" fill="#afbec5" />
      <path d="M-12-4v8M12-4v8" stroke="#6c8390" strokeWidth="1" />
      <ellipse
        cx="0"
        cy="-1"
        rx="3.5"
        ry="3"
        fill={far ? "#c78f70" : "#e5b08c"}
      />
      <path d="M-2-1v3M0-1v3M2-1v3" stroke="#a96f53" strokeWidth=".5" />
    </g>
  );
}
export default function HumanPose({
  id,
  progress,
  label,
  animated = false,
  small = false,
}: {
  id: string;
  progress: number;
  label: string;
  animated?: boolean;
  small?: boolean;
}) {
  const uid = useId().replaceAll(":", ""),
    pose = exercisePose(id, progress),
    [shoulder, hip] = points(pose.body),
    front = id === "squat",
    floor = id === "press" || id === "heel",
    legs = pose.legs.map(points),
    arms = pose.arms.map(points);
  const torsoWidth = front ? 13 : floor ? 7 : 10;
  const [hx, hy] = pose.head;
  const nearLeg = id === "heel" ? 1 : 0;
  const farArm =
    id === "press" ? arms[0].map(([x, y]) => [x + 5, y - 3] as Point) : arms[1];
  const start = exercisePose(id, 0),
    end = exercisePose(id, 1),
    motionStart =
      id === "rdl"
        ? points(start.body)[1]
        : id === "heel"
          ? points(start.legs[1]).at(-1)!
          : start.weights[0],
    motionEnd =
      id === "rdl"
        ? points(end.body)[1]
        : id === "heel"
          ? points(end.legs[1]).at(-1)!
          : end.weights[0];
  return (
    <svg
      className="human-demo"
      viewBox="5 2 155 142"
      role="img"
      aria-label={label}
      data-animated={animated ? "true" : undefined}
      data-progress={progress.toFixed(3)}
    >
      <defs>
        <linearGradient id={uid + "skin"} x1="0" x2="1">
          <stop stopColor="#eac09d" />
          <stop offset=".55" stopColor="#e1a982" />
          <stop offset="1" stopColor="#bd805d" />
        </linearGradient>
        <linearGradient id={uid + "shirt"} x1="0" x2="1">
          <stop stopColor="#397e85" />
          <stop offset=".5" stopColor="#276873" />
          <stop offset="1" stopColor="#194a59" />
        </linearGradient>
        <linearGradient id={uid + "pants"} x1="0" x2="1">
          <stop stopColor="#53687b" />
          <stop offset=".65" stopColor="#344c61" />
          <stop offset="1" stopColor="#253d52" />
        </linearGradient>
        <marker
          id={uid + "arrow"}
          viewBox="0 0 10 10"
          refX="8"
          refY="5"
          markerWidth="5"
          markerHeight="5"
          orient="auto-start-reverse"
        >
          <path
            d="M0 0 10 5 0 10"
            fill="none"
            stroke="#cf815b"
            strokeWidth="2"
          />
        </marker>
      </defs>
      <path d="M10 128h145" stroke="#d4e0e2" strokeWidth="1" />
      {floor ? (
        <g>
          <path d="M15 125h136l5 4H11z" fill="#cadbdf" />
          <path d="M11 129h145v2H11z" fill="#a9c0c7" />
          <ellipse
            cx="75"
            cy="125"
            rx="58"
            ry="2"
            fill="#243e4c"
            opacity=".1"
          />
        </g>
      ) : (
        <ellipse cx="88" cy="128" rx="55" ry="3" fill="#304653" opacity=".08" />
      )}
      {legs.map(
        (nodes, i) =>
          i !== nearLeg && (
            <g key={i}>
              <Limb nodes={nodes} widths={[6.5, 4.6, 3]} fill="#788c9b" />
              <Shoe point={nodes.at(-1)!} far />
            </g>
          ),
      )}
      {farArm && <Limb nodes={farArm} widths={[5.5, 4, 2.4]} fill="#bf8e74" />}
      {id === "press" && (
        <Weight point={[pose.weights[0][0] + 5, pose.weights[0][1] - 3]} far />
      )}
      <Limb
        nodes={legs[nearLeg]}
        widths={[7, 5, 3.2]}
        fill={`url(#${uid}pants)`}
      />
      <Shoe point={legs[nearLeg].at(-1)!} />
      <path
        d={limb(shoulder, hip, torsoWidth, front ? 10 : 8)}
        fill={`url(#${uid}shirt)`}
        stroke="#244f5b"
        strokeWidth=".7"
      />
      <path
        d={limb(
          [
            shoulder[0] + (hip[0] - shoulder[0]) * 0.77,
            shoulder[1] + (hip[1] - shoulder[1]) * 0.77,
          ],
          hip,
          front ? 10 : 8,
          front ? 11 : 8,
        )}
        fill="#2b4259"
      />
      {!floor && (
        <path
          d={`M${shoulder[0] - 3} ${shoulder[1] + 9} L${hip[0] - 3} ${hip[1] - 10}`}
          fill="none"
          stroke="#80b2b3"
          opacity=".3"
          strokeWidth="1"
        />
      )}
      <path d={limb(pose.head, shoulder, 3.2, 4.3)} fill={`url(#${uid}skin)`} />
      <g transform={floor ? `rotate(70 ${hx} ${hy})` : undefined}>
        <ellipse cx={hx} cy={hy} rx="7.8" ry="9" fill={`url(#${uid}skin)`} />
        <path
          d={`M${hx - 7.8} ${hy - 1} Q${hx - 9} ${hy - 11} ${hx} ${hy - 10} Q${hx + 9} ${hy - 10} ${hx + 7.5} ${hy + 1} L${hx + 5} ${hy - 4} Q${hx - 1} ${hy - 7} ${hx - 7.8} ${hy - 1}`}
          fill="#34424b"
        />
        {front ? (
          <g>
            <path
              d={`M${hx - 3} ${hy + 1}h1M${hx + 2} ${hy + 1}h1`}
              stroke="#544137"
              strokeWidth=".9"
            />
            <path
              d={`M${hx - 1} ${hy + 5}q2 1 3-.5`}
              fill="none"
              stroke="#a36f56"
              strokeWidth=".7"
            />
          </g>
        ) : (
          <g>
            <path d={`M${hx - 6} ${hy - 1}l-3 3 3 1`} fill="#d99b76" />
            <path
              d={`M${hx - 5} ${hy - 1}h1.2`}
              stroke="#4c3d34"
              strokeWidth="1"
            />
            <ellipse cx={hx + 4} cy={hy + 2} rx="1.5" ry="2.3" fill="#d49a78" />
          </g>
        )}
      </g>
      <Limb nodes={arms[0]} widths={[6, 4.2, 2.5]} fill={`url(#${uid}skin)`} />
      <path
        d={limb(
          arms[0][0],
          [
            arms[0][0][0] + (arms[0][1][0] - arms[0][0][0]) * 0.3,
            arms[0][0][1] + (arms[0][1][1] - arms[0][0][1]) * 0.3,
          ],
          6.4,
          5.8,
        )}
        fill={`url(#${uid}shirt)`}
      />
      {pose.weights.map((p, i) => (
        <Weight key={i} point={p} far={i > 0} />
      ))}
      {!pose.weights.length && (
        <ellipse
          cx={arms[0].at(-1)![0]}
          cy={arms[0].at(-1)![1]}
          rx="4"
          ry="2.3"
          fill="#dca27d"
        />
      )}
      {!small && motionStart && motionEnd && (
        <path
          d={
            id === "heel"
              ? `M111 138h32`
              : id === "rdl"
                ? `M${motionStart[0]} 74Q110 65 ${motionEnd[0] + 4} 74`
                : `M${motionStart[0] + 18} ${motionStart[1]}Q${(motionStart[0] + motionEnd[0]) / 2 + 25} ${(motionStart[1] + motionEnd[1]) / 2} ${motionEnd[0] + 18} ${motionEnd[1]}`
          }
          fill="none"
          stroke="#cf815b"
          strokeWidth="1.3"
          strokeDasharray="2 2"
          markerEnd={`url(#${uid}arrow)`}
        />
      )}
    </svg>
  );
}
