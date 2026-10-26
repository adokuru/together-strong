"use client";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { ArrowRight, Pause, Play, RotateCcw } from "lucide-react";
import { exercisePose, Pose } from "@/lib/exercise-motion";
const reducedQuery = "(prefers-reduced-motion: reduce)";
const subscribeMotion = (callback: () => void) => {
  const media = window.matchMedia(reducedQuery);
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
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
  const [running, setRunning] = useState(false),
    [started, setStarted] = useState(false),
    [progress, setProgress] = useState(0),
    [speed, setSpeed] = useState(0.5);
  const phase = useRef(0),
    container = useRef<HTMLDivElement>(null);
  const reduced = useSyncExternalStore(
    subscribeMotion,
    () => window.matchMedia(reducedQuery).matches,
    () => true,
  );
  useEffect(() => {
    if (!running) return;
    let frame = 0,
      last = 0,
      lastDraw = 0;
    const tick = (now: number) => {
      if (last)
        phase.current =
          (phase.current + Math.min(now - last, 100) / (6000 / speed)) % 1;
      last = now;
      if (now - lastDraw >= 32) {
        setProgress((1 - Math.cos(phase.current * Math.PI * 2)) / 2);
        lastDraw = now;
      }
      frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [running, speed]);
  useEffect(() => {
    const element = container.current;
    const visibility = () => {
      if (document.hidden) setRunning(false);
    };
    const observer = new IntersectionObserver((entries) => {
      if (!entries[0].isIntersecting) setRunning(false);
    });
    if (element) observer.observe(element);
    document.addEventListener("visibilitychange", visibility);
    return () => {
      observer.disconnect();
      document.removeEventListener("visibilitychange", visibility);
    };
  }, []);
  return (
    <div className="visual-guide" ref={container}>
      <div className="visual-label">
        HOW TO DO IT <span>START → END</span>
      </div>
      <div className="demo-controls">
        <button
          className="demo-play"
          aria-label={`${running ? "Pause" : "Play"} ${name} demonstration`}
          aria-pressed={running}
          onClick={() => {
            setStarted(true);
            setRunning(!running);
          }}
        >
          {running ? <Pause size={15} /> : <Play size={15} />}{" "}
          {running ? "Pause demo" : "Play demo"}
        </button>
        <label>
          <span>Demo speed</span>
          <select
            aria-label={`${name} demonstration speed`}
            value={speed}
            onChange={(e) => setSpeed(Number(e.target.value))}
          >
            <option value="0.5">Slow · 0.5×</option>
            <option value="1">Controlled · 1×</option>
          </select>
        </label>
        <button
          className="demo-reset"
          aria-label={`Reset ${name} demonstration`}
          onClick={() => {
            setRunning(false);
            phase.current = 0;
            setProgress(0);
          }}
        >
          <RotateCcw size={16} />
        </button>
      </div>
      {reduced && (
        <p className="motion-note">
          Reduced motion is on. Positions stay still until you choose Play.
        </p>
      )}
      {started && (
        <div className="animated-pose">
          <PoseSvg
            pose={exercisePose(id, progress)}
            label={`${name}: controlled animated demonstration`}
            animated
          />
          <span>
            {running
              ? "Move with control. Keep breathing."
              : "Paused · study the position at your own pace."}
          </span>
        </div>
      )}
      <div className="pose-pair">
        {[0, 1].map((position, i) => (
          <div className="pose" key={i}>
            <PoseSvg
              pose={exercisePose(id, position)}
              label={`${name}: ${labels[id][i]}`}
            />
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
        range. Side views show one side where the limbs overlap.
      </small>
    </div>
  );
}
function PoseSvg({
  pose,
  label,
  animated = false,
}: {
  pose: Pose;
  label: string;
  animated?: boolean;
}) {
  return (
    <svg
      viewBox="0 0 160 145"
      role="img"
      aria-label={label}
      data-animated={animated ? "true" : undefined}
    >
      <line
        x1="15"
        y1="125"
        x2="149"
        y2="125"
        stroke="#d1d9cf"
        strokeWidth="2"
      />
      <circle
        cx={pose.head[0]}
        cy={pose.head[1]}
        r="9"
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
        <g key={j} stroke="#c2714d" strokeWidth="4" strokeLinecap="round">
          <path d={`M${x - 9} ${y}h18`} />
          <path d={`M${x - 7} ${y - 5}v10M${x + 7} ${y - 5}v10`} />
        </g>
      ))}
    </svg>
  );
}
