"use client";
import { useEffect, useRef, useState, useSyncExternalStore } from "react";
import { ExternalLink, Pause, Play, RotateCcw } from "lucide-react";
import HumanPose from "./human-pose";
import {
  guideLabels as labels,
  guideReferences as references,
} from "@/lib/exercise-guides";
const reducedQuery = "(prefers-reduced-motion: reduce)";
const subscribeMotion = (callback: () => void) => {
  const media = window.matchMedia(reducedQuery);
  media.addEventListener("change", callback);
  return () => media.removeEventListener("change", callback);
};
export default function ExerciseVisual({
  id,
  name,
}: {
  id: string;
  name: string;
}) {
  const [running, setRunning] = useState(false),
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
  const scrub = (value: number) => {
    setRunning(false);
    setProgress(value);
    phase.current = Math.acos(1 - 2 * value) / (Math.PI * 2);
  };
  return (
    <div className="visual-guide human-guide" ref={container}>
      <div className="demo-stage">
        <div className="camera-label">{references[id].camera}</div>
        <HumanPose
          id={id}
          progress={progress}
          label={`${name}: human movement demonstration`}
          animated
        />
        <div className="phase-caption">
          <span>
            {progress < 0.15
              ? "01 · START"
              : progress > 0.85
                ? "02 · FINISH"
                : "MOVE WITH CONTROL"}
          </span>
          <strong>{progress < 0.5 ? labels[id][0] : labels[id][1]}</strong>
        </div>
      </div>
      <div className="demo-timeline">
        <label htmlFor={`scrub-${id}`}>Study the movement</label>
        <input
          id={`scrub-${id}`}
          aria-label={`${name} movement position`}
          type="range"
          min="0"
          max="100"
          step="1"
          value={Math.round(progress * 100)}
          onChange={(e) => scrub(Number(e.target.value) / 100)}
        />
        <div>
          <button onClick={() => scrub(0)}>Start position</button>
          <button onClick={() => scrub(1)}>Finish position</button>
        </div>
      </div>
      <div className="demo-controls">
        <button
          className="demo-play"
          aria-label={`${running ? "Pause" : "Play"} ${name} demonstration`}
          aria-pressed={running}
          onClick={() => setRunning(!running)}
        >
          {running ? <Pause size={16} /> : <Play size={16} />}{" "}
          {running ? "Pause" : "Play movement"}
        </button>
        <label>
          <span>Speed</span>
          <select
            aria-label={`${name} demonstration speed`}
            value={speed}
            onChange={(e) => setSpeed(Number(e.target.value))}
          >
            <option value=".5">Slow · 0.5×</option>
            <option value="1">Normal · 1×</option>
          </select>
        </label>
        <button
          className="demo-reset"
          aria-label={`Reset ${name} demonstration`}
          onClick={() => scrub(0)}
        >
          <RotateCcw size={17} />
        </button>
      </div>
      {reduced && (
        <p className="motion-note">
          Reduced motion is on. Use the slider or choose Play when you’re ready.
        </p>
      )}
      <div className="demo-form-cue">
        <span>KEEP IN MIND</span>
        <p>{labels[id][2]}</p>
      </div>
      <a
        className="instructor-link"
        href={references[id].url}
        target="_blank"
        rel="noreferrer"
      >
        {references[id].label}
        <ExternalLink size={15} />
      </a>
      <small>
        Original movement illustration. Use a comfortable range and light
        practice load. The linked instructor guide provides additional context.
      </small>
    </div>
  );
}
