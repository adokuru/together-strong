"use client";
import {
  ArrowRight,
  Check,
  CheckCheck,
  ChevronDown,
  Clock3,
  Dumbbell,
  Flame,
  Pause,
  Play,
  Save,
  ShieldCheck,
  Trash2,
  Undo2,
} from "lucide-react";
import { useRef, useState } from "react";
import {
  counts,
  isCompleted,
  localDate,
  Profile,
  routine,
  Session,
  sessionStage,
  WorkoutData,
} from "@/lib/workout";
type Props = {
  profile: Profile;
  data: WorkoutData;
  session?: Session;
  week: number;
  opened: boolean;
  save: string;
  demo: boolean;
  thisWeek: number;
  undoId: string | null;
  onOpen: () => void;
  onWarmup: (state: NonNullable<Session["warmupState"]>) => void;
  onSave: () => void;
  onPause: () => void;
  onFinish: () => void;
  onDiscard: () => void;
  onUndo: () => void;
  onSets: (count: 1 | 2) => void;
  onHistory: () => void;
  renderExercises: () => React.ReactNode;
};
export default function WorkoutToday(p: Props) {
  const [warmupExpanded, setWarmupExpanded] = useState(false),
    [discardConfirm, setDiscardConfirm] = useState(false);
  const loggingHeading = useRef<HTMLHeadingElement>(null);
  const { session } = p,
    tally = counts(session),
    stage = sessionStage(session),
    done = isCompleted(session),
    warmup = session?.warmupState ?? (session?.warmup ? "done" : "pending");
  return (
    <div className="workout-v2">
      <div className="training-heading">
        <div>
          <span className="eyebrow">{p.profile}’S TRAINING SPACE</span>
          <h1>{p.opened && !done ? "Your session" : "Today’s workout"}</h1>
          <p>Full-body strength · Week {p.week} · No bench needed</p>
        </div>
        <span className="training-avatar">{p.profile[0]}</span>
      </div>
      {p.undoId && (
        <div className="draft-recovery" role="status">
          <span>Draft discarded. Your copy is retained for recovery.</span>
          <button onClick={p.onUndo}>
            <Undo2 size={16} /> Undo discard
          </button>
        </div>
      )}
      {!p.opened || done ? (
        <>
          <section className={`session-entry ${done ? "entry-complete" : ""}`}>
            <div className="entry-top">
              <span className="entry-icon">
                {done ? <CheckCheck size={26} /> : <Dumbbell size={26} />}
              </span>
              <span className="state-badge">
                {stage === "new"
                  ? "READY WHEN YOU ARE"
                  : stage === "draft"
                    ? "SAVED DRAFT · NO WORKOUT LOGGED"
                    : stage === "paused"
                      ? "PAUSED SESSION"
                      : done
                        ? "WORKOUT COMPLETED"
                        : "SESSION IN PROGRESS"}
              </span>
            </div>
            <h2>
              {done
                ? "Good work. Make room for recovery."
                : stage === "draft"
                  ? "Your plan is saved. Start when you’re ready."
                  : stage === "paused"
                    ? "Pick up where you left off."
                    : stage === "active"
                      ? "Your progress is waiting for you."
                      : "Full-body strength"}
            </h2>
            <p>
              {done
                ? `${tally.done} completed sets are in your history.`
                : session
                  ? `${tally.done} of ${tally.total} sets completed${session.date !== localDate() ? ` · Saved ${new Date(session.date + "T12:00:00").toLocaleDateString("en-GB", { day: "numeric", month: "short" })}` : ""}. ${tally.done === 0 ? "Saving a draft does not count as a workout." : "Your logged sets are preserved."}`
                  : "Seven exercises with clear guidance, a place to log each set, and room to go at your own pace."}
            </p>
            <div className="entry-details">
              <span>
                <Clock3 size={16} /> 40–50 min
              </span>
              <span>
                <Dumbbell size={16} /> 7 exercises
              </span>
              <span>
                {p.week <= 2 ? `${p.data.rampSets} sets each` : "Full plan"}
              </span>
            </div>
            {done ? (
              <button className="session-primary" onClick={p.onHistory}>
                View completed session <ArrowRight size={18} />
              </button>
            ) : (
              <button className="session-primary" onClick={p.onOpen}>
                {stage === "new"
                  ? "Start workout"
                  : stage === "draft"
                    ? "Open saved draft"
                    : "Resume workout"}
                <ArrowRight size={18} />
              </button>
            )}
            {session && !done && tally.done === 0 && (
              <button
                className="draft-discard"
                onClick={() => setDiscardConfirm(true)}
              >
                <Trash2 size={15} /> Discard this empty draft
              </button>
            )}
          </section>
          <div className="plan-summary">
            <div>
              <h2>Your plan</h2>
              <p>
                {p.week <= 2
                  ? "First two weeks: keep it manageable with 1–2 sets."
                  : "Keep 2–3 good reps in reserve. Add weight only when form is controlled."}
              </p>
            </div>
            {!session && p.week <= 2 && (
              <label>
                Sets per exercise
                <select
                  aria-label="Beginner sets per exercise"
                  value={p.data.rampSets}
                  onChange={(e) => p.onSets(Number(e.target.value) as 1 | 2)}
                >
                  <option value="1">1 set</option>
                  <option value="2">2 sets</option>
                </select>
                <small>
                  Plan settings save automatically. No workout is logged.
                </small>
              </label>
            )}
          </div>
          {!done && (
            <div className="routine-preview">
              {routine(p.profile).map((e, i) => (
                <div key={e.id}>
                  <span>{String(i + 1).padStart(2, "0")}</span>
                  <strong>{e.name}</strong>
                  <small>
                    {session?.sets[e.id]?.length ??
                      (p.week <= 2 ? p.data.rampSets : e.sets)}{" "}
                    × {e.reps}
                    {e.side ? " / side" : ""}
                  </small>
                </div>
              ))}
            </div>
          )}
        </>
      ) : (
        <>
          <div className="session-context">
            <span className="state-badge">
              {stage === "draft"
                ? "DRAFT · NO COMPLETED SETS"
                : stage === "paused"
                  ? "PAUSED"
                  : "WORKING SESSION"}
            </span>
            <strong>
              {tally.done}/{tally.total} sets
            </strong>
          </div>
          <div
            className="training-progress"
            role="progressbar"
            aria-label="Completed sets"
            aria-valuenow={tally.done}
            aria-valuemin={0}
            aria-valuemax={tally.total}
          >
            <span
              style={{
                width: `${tally.total ? (tally.done / tally.total) * 100 : 0}%`,
              }}
            />
          </div>
        </>
      )}
      {!done && (
        <section
          className={`warmup-choice ${warmup === "done" ? "warmup-complete" : ""}`}
        >
          <button
            className="warmup-heading"
            aria-expanded={warmupExpanded || !p.opened}
            onClick={() => setWarmupExpanded(!warmupExpanded)}
          >
            <Flame size={21} />
            <span>
              <strong>
                {warmup === "done"
                  ? "Warm-up complete"
                  : warmup === "skipped"
                    ? "Warm-up skipped for now"
                    : warmup === "underway"
                      ? "Warm-up in progress"
                      : "A 5-minute warm-up is recommended"}
              </strong>
              <small>
                {warmup === "skipped"
                  ? "You can come back to this anytime."
                  : "March gently, circle your arms, then try a few unloaded reps."}
              </small>
            </span>
            <ChevronDown size={19} />
          </button>
          {(warmupExpanded || !p.opened) && (
            <div className="warmup-actions">
              <p>
                Warm up at your own pace. There’s no timer or checklist blocking
                your workout.
              </p>
              <div>
                <button
                  onClick={() => {
                    p.onWarmup("underway");
                    setWarmupExpanded(true);
                  }}
                >
                  <Play size={15} /> Start warm-up
                </button>
                <button
                  onClick={() => {
                    p.onWarmup("done");
                    setWarmupExpanded(false);
                  }}
                >
                  <Check size={16} /> I’ve warmed up
                </button>
                <button
                  onClick={() => {
                    p.onWarmup("skipped");
                    setWarmupExpanded(false);
                  }}
                >
                  Skip for now <ArrowRight size={15} />
                </button>
              </div>
              {warmup === "underway" && (
                <button
                  className="start-from-warmup"
                  onClick={() => {
                    setWarmupExpanded(false);
                    p.onOpen();
                    requestAnimationFrame(() => {
                      loggingHeading.current?.focus({ preventScroll: true });
                      loggingHeading.current?.scrollIntoView({
                        block: "start",
                      });
                    });
                  }}
                >
                  Start workout now <ArrowRight size={16} />
                </button>
              )}
            </div>
          )}
        </section>
      )}
      {p.opened && !done && (
        <>
          <div className="logging-intro">
            <h2 ref={loggingHeading} tabIndex={-1}>
              Log your sets
            </h2>
            <p>
              Enter reps and total kg held, then tick the set. For one-sided
              moves, finish both sides before ticking.
            </p>
            <span>
              <ShieldCheck size={15} />
              {p.save === "error"
                ? "Changes need saving — use Retry above."
                : p.save === "saving"
                  ? "Saving your latest changes…"
                  : p.demo
                    ? "Draft and sets saved on this device."
                    : "All changes synced privately."}
            </span>
          </div>
          <div className="exercises">{p.renderExercises()}</div>
          <div className="session-actions">
            <div className="save-pause">
              <button onClick={p.onSave} disabled={p.save === "saving"}>
                <Save size={17} /> Save progress
              </button>
              <button
                onClick={p.onPause}
                disabled={p.save === "saving" || p.save === "error"}
              >
                <Pause size={17} /> Save & pause
              </button>
            </div>
            <button
              className="finish-workout"
              disabled={
                !tally.done || p.save === "saving" || p.save === "error"
              }
              onClick={p.onFinish}
            >
              Finish workout <CheckCheck size={18} />
            </button>
            <p>
              {!tally.done
                ? "No completed sets yet. Save a draft now and come back later."
                : "Finishing records only the sets you actually completed."}
            </p>
            {!tally.done && (
              <button
                className="draft-discard"
                onClick={() => setDiscardConfirm(true)}
              >
                <Trash2 size={14} /> Discard empty draft
              </button>
            )}
          </div>
        </>
      )}
      {(!p.opened || done) && (
        <section className="consistency-strip">
          <span>
            <strong>
              {p.thisWeek}
              <small> / 3</small>
            </strong>{" "}
            workouts this week
          </span>
          <p>
            Suggested: Mon · Wed · Fri.
            <br />
            Leave a recovery day between sessions.
          </p>
        </section>
      )}
      {discardConfirm && (
        <div
          className="discard-confirm"
          role="alertdialog"
          aria-label="Discard empty draft"
        >
          <strong>Discard this draft?</strong>
          <p>
            No completed exercise sets will be removed. A recoverable copy is
            kept, and you can undo.
          </p>
          <div>
            <button onClick={() => setDiscardConfirm(false)}>Keep draft</button>
            <button
              onClick={() => {
                p.onDiscard();
                setDiscardConfirm(false);
              }}
            >
              Discard draft
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
