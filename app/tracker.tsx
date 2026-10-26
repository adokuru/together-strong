"use client";
import { useCallback, useEffect, useRef, useState } from "react";
import {
  ArrowLeft,
  ArrowRight,
  Check,
  CheckCheck,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  Clock3,
  Dumbbell,
  Flame,
  House,
  Leaf,
  LoaderCircle,
  LockKeyhole,
  LogOut,
  Pause,
  Play,
  Plus,
  RotateCcw,
  ShieldCheck,
  Sparkles,
  Timer,
  TrendingUp,
  X,
  CalendarDays,
  CircleHelp,
} from "lucide-react";
import ExerciseVisual from "./exercise-visual";
import AuthGate from "./auth-gate";
import { authClient } from "@/lib/auth-client";
import {
  CloudWorkoutStorage,
  LocalWorkoutStorage,
  WorkoutStorage,
} from "@/lib/storage";
import {
  counts,
  emptyData,
  Exercise,
  localDate,
  makeSession,
  Profile,
  routine,
  Session,
  SetLog,
  validSet,
  weekNumber,
  WorkoutData,
} from "@/lib/workout";
type View = "today" | "history" | "progress";
type SaveState = "saved" | "saving" | "error";
const localStore = new LocalWorkoutStorage();
const cloudStore = new CloudWorkoutStorage();
const formatDate = (
  date: string,
  options: Intl.DateTimeFormatOptions = { month: "short", day: "numeric" },
) => new Date(date + "T12:00:00").toLocaleDateString("en-GB", options);
const route = (p: Profile | null, v: View = "today") => {
  window.history.pushState(null, "", `#${p ? `${p}/${v}` : ""}`);
  window.dispatchEvent(new HashChangeEvent("hashchange"));
};
const timeText = (seconds: number) =>
  `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;

export default function Tracker({
  cloudConfigured,
  emailConfigured,
  allowDemo,
}: {
  cloudConfigured: boolean;
  emailConfigured: boolean;
  allowDemo: boolean;
}) {
  const [profile, setProfile] = useState<Profile | null>(null),
    [view, setView] = useState<View>("today"),
    [data, setData] = useState<WorkoutData>(emptyData),
    [demo, setDemo] = useState(false),
    [loading, setLoading] = useState(false),
    [authorized, setAuthorized] = useState(false),
    [error, setError] = useState(""),
    [save, setSave] = useState<SaveState>("saved");
  const [expanded, setExpanded] = useState<string | null>(null),
    [guide, setGuide] = useState(false),
    [finishConfirm, setFinishConfirm] = useState(false),
    [historySession, setHistorySession] = useState<Session | null>(null),
    [month, setMonth] = useState(
      () => new Date(new Date().getFullYear(), new Date().getMonth(), 1),
    );
  const profileRef = useRef<Profile | null>(null);
  const dataRef = useRef(data),
    revision = useRef(0),
    queue = useRef(Promise.resolve()),
    pending = useRef(0),
    failed = useRef(false),
    generation = useRef(0),
    store = useRef<WorkoutStorage>(localStore);
  const [timer, setTimer] = useState({
    remaining: 0,
    running: false,
    duration: 120,
    visible: false,
  });
  const deadline = useRef(0);
  const [notice, setNotice] = useState("");
  useEffect(() => {
    if (!timer.running) return;
    const tick = () => {
      const left = Math.max(
        0,
        Math.ceil((deadline.current - Date.now()) / 1000),
      );
      setTimer((t) => ({ ...t, remaining: left, running: left > 0 }));
      if (left === 0)
        setNotice("Rest complete. Ready for your next set when you are.");
    };
    const id = setInterval(tick, 250);
    return () => clearInterval(id);
  }, [timer.running]);
  const startTimer = useCallback((duration: number) => {
    deadline.current = Date.now() + duration * 1000;
    setTimer({ remaining: duration, running: true, duration, visible: true });
  }, []);
  const load = useCallback(async (p: Profile, isDemo: boolean) => {
    const run = ++generation.current;
    setLoading(true);
    setError("");
    failed.current = false;
    try {
      await queue.current;
      store.current = isDemo ? localStore : cloudStore;
      const result = await store.current.load(p);
      if (run !== generation.current) return;
      dataRef.current = result.data;
      revision.current = result.revision;
      setData(result.data);
      setSave("saved");
      setAuthorized(true);
      setExpanded(routine(p)[0].id);
    } catch (err) {
      if (run === generation.current) {
        setError(
          err instanceof Error ? err.message : "Could not load your workout.",
        );
        setAuthorized(false);
      }
    } finally {
      if (run === generation.current) setLoading(false);
    }
  }, []);
  useEffect(() => {
    const navigate = () => {
      const [name, tab] = location.hash.slice(1).split("/");
      const p = name === "David" || name === "Mary" ? name : null;
      if (profileRef.current !== p) {
        setAuthorized(false);
        setError("");
        setTimer((t) => ({ ...t, visible: false, running: false }));
        profileRef.current = p;
      }
      setProfile(p);
      setView(tab === "history" || tab === "progress" ? tab : "today");
      setHistorySession(null);
      if (p)
        void fetch("/api/account", { cache: "no-store" })
          .then(async (response) => (response.ok ? response.json() : null))
          .then((account) => {
            if (
              account?.profile === p &&
              !account.needsPassword &&
              profileRef.current === p
            )
              void load(p, false);
          })
          .catch(() => {});
    };
    navigate();
    window.addEventListener("hashchange", navigate);
    return () => window.removeEventListener("hashchange", navigate);
  }, [load]);
  const update = (next: WorkoutData) => {
    if (!profile) return;
    dataRef.current = next;
    setData(next);
    setSave(failed.current ? "error" : "saving");
    const p = profile;
    const storage = store.current;
    const run = generation.current;
    pending.current += 1;
    queue.current = queue.current.then(async () => {
      if (failed.current) {
        pending.current -= 1;
        return;
      }
      try {
        revision.current = await storage.save(p, next, revision.current);
        if (run === generation.current && pending.current === 1)
          setSave("saved");
      } catch (err) {
        failed.current = true;
        setSave("error");
        setError(
          err instanceof Error ? err.message : "Unable to save changes.",
        );
      } finally {
        pending.current -= 1;
      }
    });
  };
  useEffect(() => {
    const guard = (event: BeforeUnloadEvent) => {
      if (pending.current > 0 || failed.current) event.preventDefault();
    };
    window.addEventListener("beforeunload", guard);
    return () => window.removeEventListener("beforeunload", guard);
  }, []);
  const retry = () => {
    failed.current = false;
    update(dataRef.current);
  };
  const editSession = (id: string, fn: (s: Session) => Session) => {
    update({
      ...dataRef.current,
      sessions: dataRef.current.sessions.map((s) => (s.id === id ? fn(s) : s)),
    });
  };
  const session = data.sessions.find((s) => s.date === localDate());
  const completed = data.sessions.filter((s) => s.completedAt);
  const tally = counts(session);
  const week = weekNumber(data);
  const choose = (p: Profile) => {
    setAuthorized(false);
    setDemo(false);
    setError("");
    setTimer((t) => ({ ...t, visible: false, running: false }));
    route(p);
  };
  const backToProfiles = async () => {
    await queue.current;
    if (failed.current) {
      setError("Save or retry your changes before switching profiles.");
      return;
    }
    if (!demo && authorized) {
      try {
        const result = await authClient.signOut();
        if (result.error) {
          setError("Could not sign out yet. Please try again in a moment.");
          return;
        }
      } catch {
        setError("Could not sign out. Check your connection and try again.");
        return;
      }
    }
    setAuthorized(false);
    setDemo(false);
    setProfile(null);
    setError("");
    setTimer((t) => ({ ...t, visible: false, running: false }));
    route(null);
  };
  const start = () => {
    if (
      !profile ||
      dataRef.current.sessions.some((s) => s.date === localDate())
    )
      return;
    const next = makeSession(profile, dataRef.current);
    update({
      ...dataRef.current,
      startedAt: dataRef.current.startedAt ?? next.startedAt,
      sessions: [...dataRef.current.sessions, next],
    });
    setExpanded(routine(profile)[0].id);
  };
  const finish = () => {
    const current = dataRef.current.sessions.find(
      (s) => s.date === localDate(),
    );
    if (
      !current ||
      current.completedAt ||
      !counts(current).done ||
      !current.warmup
    )
      return;
    editSession(current.id, (s) => ({
      ...s,
      completedAt: new Date().toISOString(),
    }));
    setFinishConfirm(false);
    setTimer((t) => ({ ...t, visible: false, running: false }));
    setNotice("Workout saved. A little stronger than yesterday.");
  };
  const weekStart = new Date();
  weekStart.setHours(0, 0, 0, 0);
  weekStart.setDate(weekStart.getDate() - ((weekStart.getDay() + 6) % 7));
  const weekDays = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(weekStart);
    d.setDate(d.getDate() + i);
    return d;
  });
  const thisWeek = completed.filter(
    (s) =>
      s.date >= localDate(weekStart) &&
      s.date <= localDate(new Date(weekStart.getTime() + 6 * 86400000)),
  ).length;
  const totalSets = completed.reduce((sum, s) => sum + counts(s).done, 0);

  if (!profile)
    return (
      <main className="welcome">
        <div className="welcome-top">
          <Brand />
          <span className="private-tag">
            <LockKeyhole size={13} /> JUST THE TWO OF YOU
          </span>
        </div>
        <div className="welcome-content">
          <div className="eyebrow">
            <span className="live-dot" /> YOUR HOME. YOUR PACE.
          </div>
          <h1>
            A little stronger.
            <br />
            <span>Better together.</span>
          </h1>
          <p className="welcome-description">
            Small steps. Stronger habits. A workout space
            <br className="desktop-break" /> made for David and Mary.
          </p>
          <div className="profile-prompt">
            Who’s showing up today?
            <span>
              Choose your own path. We’ll keep your progress separate.
            </span>
          </div>
          <div className="profiles">
            {(["David", "Mary"] as Profile[]).map((p) => (
              <button
                key={p}
                className={`profile-card ${p.toLowerCase()}`}
                onClick={() => choose(p)}
                aria-label={`Choose ${p}`}
              >
                <div className="profile-art">
                  <div className="orb orb-one" />
                  <div className="orb orb-two" />
                  <Dumbbell strokeWidth={1.5} />
                  <span className="profile-initial">{p[0]}</span>
                  <span className="art-spark">
                    <Sparkles size={21} />
                  </span>
                </div>
                <div className="profile-info">
                  <span className="eyebrow">LET’S BUILD YOUR STRENGTH</span>
                  <div>
                    <h2>{p}</h2>
                    <span className="profile-arrow">
                      <ArrowRight size={22} />
                    </span>
                  </div>
                  <p>
                    {p === "David"
                      ? "Chest, arms & a stronger foundation"
                      : "Back, arms & full-body strength"}
                  </p>
                </div>
              </button>
            ))}
          </div>
          <div className="welcome-foot">
            <span>
              <Dumbbell size={15} /> Dumbbells + a little floor space
            </span>
            <span>
              <CalendarDays size={15} /> 3 days a week
            </span>
            <span>
              <Leaf size={15} /> No bench needed
            </span>
          </div>
        </div>
        <footer>
          TOGETHER STRONG <span>PROGRESS OVER PERFECTION.</span>
        </footer>
      </main>
    );

  if (!authorized)
    return (
      <main className={`auth-page theme-${profile.toLowerCase()}`}>
        <div className="auth-top">
          <Brand />
          <button className="text-button" onClick={() => void backToProfiles()}>
            <ArrowLeft size={16} /> Change profile
          </button>
        </div>
        <AuthGate
          profile={profile}
          configured={cloudConfigured}
          emailEnabled={emailConfigured}
          allowDemo={allowDemo}
          onDemo={() => {
            setDemo(true);
            void load(profile, true);
          }}
          onLogin={async () => {
            setDemo(false);
            await load(profile, false);
          }}
        />
        {error && (
          <p className="error-text center" role="alert">
            {error}
          </p>
        )}
      </main>
    );

  return (
    <div className={`app theme-${profile.toLowerCase()}`}>
      <aside className="sidebar">
        <Brand />
        <div className="sidebar-label">YOUR TRAINING SPACE</div>
        <nav aria-label="Main navigation">
          {(
            [
              ["today", House, "My workout"],
              ["history", CalendarDays, "Calendar & history"],
              ["progress", TrendingUp, "My progress"],
            ] as const
          ).map(([v, Icon, label]) => (
            <a
              href={`#${profile}/${v}`}
              key={v}
              className={view === v ? "active" : ""}
              aria-current={view === v ? "page" : undefined}
            >
              <Icon size={19} />
              <span>{label}</span>
              {v === view && <span className="nav-dot" />}
            </a>
          ))}
        </nav>
        <div className="sidebar-bottom">
          <div className="little-note">
            <Leaf size={23} />
            <p>
              Showing up is
              <br />
              where strong begins.
            </p>
            <span>ONE WORKOUT AT A TIME.</span>
          </div>
          <button
            className="switch-profile"
            onClick={() => void backToProfiles()}
          >
            <span className="avatar">{profile[0]}</span>
            <span>
              <strong>{profile}</strong>
              <small>Switch profile</small>
            </span>
            <LogOut size={17} />
          </button>
        </div>
      </aside>
      <div className="app-main">
        <header className="topbar">
          <div className="mobile-brand">
            <Brand compact />
          </div>
          <span className="topbar-date">
            {new Date().toLocaleDateString("en-GB", {
              weekday: "long",
              day: "numeric",
              month: "long",
            })}
          </span>
          <div className="topbar-right">
            <span className={`save-status ${save}`} role="status">
              {save === "saving" ? (
                <LoaderCircle size={13} className="spin" />
              ) : save === "saved" ? (
                <CheckCheck size={14} />
              ) : (
                <CircleHelp size={14} />
              )}{" "}
              {save === "saved"
                ? demo
                  ? "Saved on this device"
                  : "Synced securely"
                : save === "saving"
                  ? "Saving…"
                  : "Not saved"}
            </span>
            <button
              className="avatar"
              aria-label="Switch profile"
              onClick={() => void backToProfiles()}
            >
              {profile[0]}
            </button>
          </div>
        </header>
        <main className="content" id="main-content">
          {demo && (
            <div className="local-banner">
              <ShieldCheck size={15} />
              <span>
                Device-local preview · Separate logs on this browser. Private
                cloud sync is being set up.
              </span>
            </div>
          )}
          {error && (
            <div className="error-banner" role="alert">
              <span>{error}</span>
              {save === "error" && <button onClick={retry}>Retry save</button>}
              <button onClick={() => location.reload()}>Reload latest</button>
            </div>
          )}
          {loading ? (
            <div className="loading">
              <LoaderCircle className="spin" /> Getting your workout ready…
            </div>
          ) : (
            <>
              <div className="page-heading">
                <div>
                  <div className="eyebrow">
                    {view === "today"
                      ? "MAKE TIME FOR YOU"
                      : view === "history"
                        ? "EVERY SESSION COUNTS"
                        : "SMALL STEPS ADD UP"}
                  </div>
                  <h1>
                    {view === "today" ? (
                      <>
                        Let’s get stronger, <span>{profile}.</span>
                      </>
                    ) : view === "history" ? (
                      "Your consistency, in motion."
                    ) : (
                      "Look how far you’re going."
                    )}
                  </h1>
                  <p>
                    {view === "today"
                      ? "Your own pace. Your own progress. One good rep at a time."
                      : view === "history"
                        ? "A little record of all the times you showed up."
                        : "Build the habit first. The numbers will follow."}
                  </p>
                </div>
                <button
                  aria-label="Training guide"
                  className="help-button"
                  onClick={() => setGuide(true)}
                >
                  <CircleHelp size={17} />
                  <span>Training guide</span>
                </button>
              </div>
              {view === "today" && (
                <div className="dashboard-grid">
                  <div className="workout-column">
                    <section className="workout-hero">
                      <div className="hero-content">
                        <span className="hero-label">
                          <span className="live-dot" /> YOUR FULL-BODY SESSION
                        </span>
                        <h2>
                          {profile === "David" ? (
                            <>
                              Build strength.
                              <br />
                              Find your rhythm.
                            </>
                          ) : (
                            <>
                              Strong back.
                              <br />
                              Stronger you.
                            </>
                          )}
                        </h2>
                        <div className="hero-meta">
                          <span>
                            <Clock3 size={15} /> 40–50 min
                          </span>
                          <span>
                            <Dumbbell size={16} /> 7 exercises
                          </span>
                          <span>No bench</span>
                        </div>
                        <button
                          className={`primary-button ${session ? "hero-session" : ""}`}
                          onClick={() => {
                            if (!session) start();
                            else
                              document
                                .getElementById("exercise-list")
                                ?.scrollIntoView({
                                  behavior: "smooth",
                                  block: "start",
                                });
                          }}
                        >
                          {session?.completedAt ? (
                            <>
                              <Check size={18} /> Workout complete
                            </>
                          ) : session ? (
                            <>
                              <Play size={16} /> Continue workout
                            </>
                          ) : (
                            <>
                              Start my workout <ArrowRight size={18} />
                            </>
                          )}
                        </button>
                      </div>
                      <div className="hero-art" aria-hidden="true">
                        <div className="hero-circle" />
                        <Dumbbell strokeWidth={1.2} />
                        <Sparkles className="hero-spark" />
                      </div>
                    </section>
                    <div className="phase-card">
                      <span className="phase-icon">
                        <Sparkles size={21} />
                      </span>
                      <div>
                        <strong>
                          {week <= 2
                            ? "Start easy. Build a lasting habit."
                            : "Your full plan. Your steady progress."}
                        </strong>
                        <p>
                          {week <= 2
                            ? `Week ${week} · Choose 1–2 sets per exercise for your first two weeks.`
                            : "Week 3+ · Full sets are ready. Keep 2–3 good reps in reserve."}
                        </p>
                      </div>
                      {!session && week <= 2 && (
                        <label className="sets-select">
                          <span>Sets</span>
                          <select
                            value={data.rampSets}
                            aria-label="Beginner sets per exercise"
                            onChange={(e) =>
                              update({
                                ...dataRef.current,
                                rampSets: Number(e.target.value) as 1 | 2,
                              })
                            }
                          >
                            <option value="1">1 set</option>
                            <option value="2">2 sets</option>
                          </select>
                        </label>
                      )}
                    </div>
                    <div className="section-heading" id="exercise-list">
                      <div>
                        <h2>
                          Your workout <span>07</span>
                        </h2>
                        <p>
                          {profile === "David"
                            ? "Chest & arms emphasis · full-body foundation"
                            : "Back & arms emphasis · full-body foundation"}
                        </p>
                      </div>
                      {session && (
                        <span className="count-pill">
                          {tally.done}/{tally.total} sets
                        </span>
                      )}
                    </div>
                    {session && (
                      <div
                        className="session-progress"
                        role="progressbar"
                        aria-valuemin={0}
                        aria-valuemax={tally.total}
                        aria-valuenow={tally.done}
                        aria-label={`${tally.done} of ${tally.total} sets completed`}
                      >
                        <span
                          style={{
                            width: `${tally.total ? (tally.done / tally.total) * 100 : 0}%`,
                          }}
                        />
                      </div>
                    )}
                    <button
                      className={`warmup-card ${session?.warmup ? "done" : ""}`}
                      disabled={!session || Boolean(session.completedAt)}
                      onClick={() =>
                        session &&
                        editSession(session.id, (s) => ({
                          ...s,
                          warmup: !s.warmup,
                        }))
                      }
                    >
                      <span className="warmup-icon">
                        {session?.warmup ? (
                          <Check size={20} />
                        ) : (
                          <Flame size={20} />
                        )}
                      </span>
                      <span>
                        <strong>First, a little warm-up</strong>
                        <small>
                          5 min · Easy marching, arm circles & unloaded practice
                          reps
                        </small>
                      </span>
                      <span className="warmup-check">
                        {session?.warmup ? <Check size={16} /> : "5′"}
                      </span>
                    </button>
                    <div className="exercises">
                      {routine(profile).map((exercise, index) => (
                        <ExerciseCard
                          key={exercise.id}
                          exercise={exercise}
                          index={index}
                          expanded={expanded === exercise.id}
                          onExpand={() =>
                            setExpanded(
                              expanded === exercise.id ? null : exercise.id,
                            )
                          }
                          session={session}
                          plannedSets={
                            week <= 2 ? data.rampSets : exercise.sets
                          }
                          onChange={(setIndex, patch) => {
                            if (!session || session.completedAt) return;
                            editSession(session.id, (s) => ({
                              ...s,
                              sets: {
                                ...s.sets,
                                [exercise.id]: s.sets[exercise.id].map(
                                  (set, i) =>
                                    i === setIndex ? { ...set, ...patch } : set,
                                ),
                              },
                            }));
                          }}
                          onRest={() => startTimer(exercise.rest)}
                          onNotice={setNotice}
                        />
                      ))}
                    </div>
                    {session && !session.completedAt && (
                      <div className="finish-section">
                        <p>
                          {tally.done === tally.total && session.warmup
                            ? "You showed up. You put in the work."
                            : !session.warmup
                              ? "Complete your warm-up before finishing."
                              : `${tally.done} sets in. Every controlled rep counts.`}
                        </p>
                        <button
                          className="dark-button"
                          disabled={
                            !tally.done ||
                            !session.warmup ||
                            save === "error" ||
                            save === "saving"
                          }
                          onClick={() =>
                            tally.done === tally.total
                              ? finish()
                              : setFinishConfirm(true)
                          }
                        >
                          {tally.done === tally.total
                            ? "Finish & save workout"
                            : "Finish early & save"}
                          <Check size={18} />
                        </button>
                      </div>
                    )}
                    {session?.completedAt && (
                      <div className="completion-card">
                        <CheckCheck size={28} />
                        <h3>You did something good for yourself.</h3>
                        <p>
                          {tally.done} sets saved · Rest, recover, and come back
                          stronger.
                        </p>
                        <button
                          className="text-button"
                          onClick={() => route(profile, "history")}
                        >
                          See your history <ArrowRight size={16} />
                        </button>
                      </div>
                    )}
                  </div>
                  <aside className="right-column">
                    <section className="week-card">
                      <div className="section-heading">
                        <h3>This week</h3>
                        <span className="mini-icon">
                          <CalendarDays size={17} />
                        </span>
                      </div>
                      <div className="week-score">
                        <strong>
                          {thisWeek}
                          <span>/ 3</span>
                        </strong>
                        <span>
                          workouts
                          <br />
                          completed
                        </span>
                      </div>
                      <div className="week-strip">
                        {weekDays.map((day, i) => {
                          const key = localDate(day);
                          const done = completed.some((s) => s.date === key);
                          return (
                            <div
                              className={`week-day ${key === localDate() ? "today" : ""} ${done ? "completed" : ""}`}
                              key={key}
                            >
                              <span>
                                {["M", "T", "W", "T", "F", "S", "S"][i]}
                              </span>
                              <span className="day-circle">
                                {done ? <Check size={15} /> : day.getDate()}
                              </span>
                              <span
                                className={
                                  i % 2 === 0 && i < 5 ? "schedule-dot" : ""
                                }
                              />
                            </div>
                          );
                        })}
                      </div>
                      <p className="week-caption">
                        <span className="schedule-dot" /> Suggested: Mon · Wed ·
                        Fri
                      </p>
                      <div className="week-note">
                        {thisWeek
                          ? "Keep the momentum. Recovery days count, too."
                          : "A fresh week. A fresh chance to show up."}
                      </div>
                    </section>
                    <section className="habit-card">
                      <span className="eyebrow">YOUR JOURNEY SO FAR</span>
                      <div className="habit-stats">
                        <div>
                          <span className="stat-icon">
                            <Dumbbell size={19} />
                          </span>
                          <strong>{completed.length}</strong>
                          <span>workouts</span>
                        </div>
                        <div>
                          <span className="stat-icon">
                            <CheckCheck size={19} />
                          </span>
                          <strong>{totalSets}</strong>
                          <span>sets done</span>
                        </div>
                      </div>
                      <a href={`#${profile}/progress`}>
                        See your progress <ArrowRight size={16} />
                      </a>
                    </section>
                    <section className="tip-card">
                      <div className="tip-top">
                        <Leaf size={22} />
                        <span>STRONGER, SAFELY</span>
                      </div>
                      <h3>
                        Leave a little
                        <br />
                        in the tank.
                      </h3>
                      <p>
                        Finish each set with 2–3 good reps still in you. Control
                        comes before more weight.
                      </p>
                      <button
                        className="text-button"
                        onClick={() => setGuide(true)}
                      >
                        A few helpful tips <ArrowRight size={15} />
                      </button>
                    </section>
                    <div className="equipment-note">
                      <Dumbbell size={16} />
                      <p>
                        Adjustable dumbbells.
                        <br />
                        Floor space. You’ve got this.
                      </p>
                    </div>
                  </aside>
                </div>
              )}
              {view === "history" && (
                <div className="history-grid">
                  <section className="calendar-card">
                    <div className="section-heading">
                      <h2>
                        {month.toLocaleDateString("en-GB", {
                          month: "long",
                          year: "numeric",
                        })}
                      </h2>
                      <div className="month-controls">
                        <button
                          aria-label="Previous month"
                          onClick={() =>
                            setMonth(
                              new Date(
                                month.getFullYear(),
                                month.getMonth() - 1,
                                1,
                              ),
                            )
                          }
                        >
                          <ChevronLeft size={18} />
                        </button>
                        <button
                          aria-label="Next month"
                          onClick={() =>
                            setMonth(
                              new Date(
                                month.getFullYear(),
                                month.getMonth() + 1,
                                1,
                              ),
                            )
                          }
                        >
                          <ChevronRight size={18} />
                        </button>
                      </div>
                    </div>
                    <div className="calendar-grid">
                      {["M", "T", "W", "T", "F", "S", "S"].map((d, i) => (
                        <span className="calendar-label" key={i}>
                          {d}
                        </span>
                      ))}
                      {Array.from(
                        { length: (month.getDay() + 6) % 7 },
                        (_, i) => (
                          <span key={`empty-${i}`} />
                        ),
                      )}
                      {Array.from(
                        {
                          length: new Date(
                            month.getFullYear(),
                            month.getMonth() + 1,
                            0,
                          ).getDate(),
                        },
                        (_, i) => {
                          const date = localDate(
                            new Date(
                              month.getFullYear(),
                              month.getMonth(),
                              i + 1,
                            ),
                          );
                          const s = data.sessions.find((s) => s.date === date);
                          return (
                            <button
                              key={date}
                              disabled={!s}
                              className={`${s?.completedAt ? "calendar-done" : ""} ${date === localDate() ? "calendar-today" : ""}`}
                              aria-label={`${formatDate(date)}${s?.completedAt ? ", completed workout" : s ? ", in progress" : ", no workout"}`}
                              onClick={() => s && setHistorySession(s)}
                            >
                              {i + 1}
                              {s && <span />}
                            </button>
                          );
                        },
                      )}
                    </div>
                    <p className="calendar-legend">
                      <span /> Completed workout{" "}
                      <span className="outline-dot" /> Today
                    </p>
                  </section>
                  <section className="history-list">
                    <div className="section-heading">
                      <h2>Your sessions</h2>
                      <span className="count-pill">
                        {completed.length} completed
                      </span>
                    </div>
                    {!data.sessions.length ? (
                      <Empty
                        icon={<CalendarDays size={30} />}
                        title="Your story starts with one session."
                        text="Completed workouts will appear here. There’s no rush — just a good place to begin."
                        action={() => route(profile, "today")}
                        label="Go to my workout"
                      />
                    ) : (
                      [...data.sessions].reverse().map((s) => (
                        <button
                          className="history-item"
                          key={s.id}
                          onClick={() => setHistorySession(s)}
                        >
                          <span
                            className={`history-icon ${s.completedAt ? "finished" : ""}`}
                          >
                            {s.completedAt ? (
                              <Check size={19} />
                            ) : (
                              <Dumbbell size={19} />
                            )}
                          </span>
                          <span>
                            <strong>
                              {formatDate(s.date, {
                                weekday: "short",
                                day: "numeric",
                                month: "short",
                              })}
                            </strong>
                            <small>
                              {s.completedAt
                                ? "Full-body session"
                                : "In progress"}{" "}
                              · {counts(s).done}/{counts(s).total} sets
                            </small>
                          </span>
                          <ArrowRight size={18} />
                        </button>
                      ))
                    )}
                  </section>
                </div>
              )}
              {view === "progress" && (
                <>
                  <div className="progress-overview">
                    <Metric
                      icon={<Dumbbell />}
                      value={completed.length}
                      label="Workouts completed"
                    />
                    <Metric
                      icon={<CheckCheck />}
                      value={totalSets}
                      label="Sets with intention"
                    />
                    <Metric
                      icon={<CalendarDays />}
                      value={`${thisWeek}/3`}
                      label="Sessions this week"
                    />
                  </div>
                  <section className="progress-card">
                    <div className="section-heading">
                      <div>
                        <h2>Your exercise progress</h2>
                        <p>
                          Best completed set in each session · total held, in kg
                        </p>
                      </div>
                      <TrendingUp size={24} />
                    </div>
                    {routine(profile).map((e) => {
                      const records = completed
                        .map((s) => {
                          const sets = (s.sets[e.id] ?? []).filter(
                            (x) => x.done,
                          );
                          const best = sets.sort((a, b) =>
                            e.bodyweight
                              ? Number(b.reps) - Number(a.reps)
                              : Number(b.kg) - Number(a.kg) ||
                                Number(b.reps) - Number(a.reps),
                          )[0];
                          return best
                            ? {
                                date: s.date,
                                value: e.bodyweight
                                  ? Number(best.reps)
                                  : Number(best.kg),
                                reps: best.reps,
                              }
                            : null;
                        })
                        .filter((x): x is NonNullable<typeof x> => Boolean(x));
                      const latest = records.at(-1);
                      const max = Math.max(1, ...records.map((r) => r.value));
                      return (
                        <div className="exercise-progress" key={e.id}>
                          <div>
                            <strong>{e.name}</strong>
                            <span>
                              {latest
                                ? `${latest.value} ${e.bodyweight ? "reps per side" : "kg total"} · ${latest.reps} reps${e.side && !e.bodyweight ? " each side" : ""}`
                                : "Your first completed set will start the story."}
                            </span>
                          </div>
                          <div
                            className="spark-bars"
                            aria-label={
                              records.length
                                ? records
                                    .slice(-12)
                                    .map(
                                      (r) =>
                                        `${formatDate(r.date)}: ${r.value} ${e.bodyweight ? "reps" : "kg"}`,
                                    )
                                    .join("; ")
                                : "No progress data yet"
                            }
                          >
                            {records.length ? (
                              records.slice(-12).map((r) => (
                                <span
                                  key={r.date}
                                  title={`${formatDate(r.date)}: ${r.value}`}
                                  style={{
                                    height: `${Math.max(8, (r.value / max) * 46)}px`,
                                  }}
                                />
                              ))
                            ) : (
                              <span className="no-data">—</span>
                            )}
                          </div>
                        </div>
                      );
                    })}
                    <div className="progress-tip">
                      <Sparkles size={18} />
                      <p>
                        Reach the top of the rep range in every set with good
                        form before trying the smallest weight increase. For
                        one-sided moves, both sides count.
                      </p>
                    </div>
                  </section>
                </>
              )}
            </>
          )}
          <footer className="app-footer">
            <span>TOGETHER STRONG</span>
            <span>A LITTLE STRONGER. ONE DAY AT A TIME.</span>
          </footer>
        </main>
      </div>
      <nav className="mobile-nav" aria-label="Mobile navigation">
        {(
          [
            ["today", House, "Workout"],
            ["history", CalendarDays, "History"],
            ["progress", TrendingUp, "Progress"],
          ] as const
        ).map(([v, Icon, label]) => (
          <a
            key={v}
            href={`#${profile}/${v}`}
            className={view === v ? "active" : ""}
            aria-current={view === v ? "page" : undefined}
          >
            <Icon size={21} />
            <span>{label}</span>
          </a>
        ))}
        <button
          aria-label="Switch profile"
          onClick={() => void backToProfiles()}
        >
          <span className="tiny-avatar">{profile[0]}</span>
          <span>Profile</span>
        </button>
      </nav>
      {!timer.visible && view === "today" && (
        <button
          className="timer-launch"
          onClick={() =>
            setTimer({
              remaining: 120,
              running: false,
              duration: 120,
              visible: true,
            })
          }
        >
          <Timer size={19} />
          <span>Rest timer</span>
        </button>
      )}
      {timer.visible && (
        <section className="timer-panel" aria-label="Rest timer">
          <div className="timer-heading">
            <span>
              <Timer size={17} /> TAKE A BREATHER
            </span>
            <button
              className="icon-button"
              aria-label="Close rest timer"
              onClick={() =>
                setTimer((t) => ({ ...t, running: false, visible: false }))
              }
            >
              <X size={17} />
            </button>
          </div>
          <div className="timer-main">
            <span
              className="timer-digits"
              role="timer"
              aria-label="Rest time remaining"
            >
              {timeText(timer.remaining)}
            </span>
            <div className="timer-actions">
              <button
                aria-label="Reset rest timer"
                onClick={() =>
                  setTimer((t) => ({
                    ...t,
                    remaining: t.duration,
                    running: false,
                  }))
                }
              >
                <RotateCcw size={18} />
              </button>
              <button
                className="timer-play"
                aria-label={
                  timer.running ? "Pause rest timer" : "Start rest timer"
                }
                onClick={() => {
                  if (timer.running)
                    setTimer((t) => ({ ...t, running: false }));
                  else {
                    deadline.current =
                      Date.now() + (timer.remaining || timer.duration) * 1000;
                    setTimer((t) => ({
                      ...t,
                      remaining: t.remaining || t.duration,
                      running: true,
                    }));
                  }
                }}
              >
                {timer.running ? <Pause size={19} /> : <Play size={19} />}
              </button>
              <button
                aria-label="Add 30 seconds"
                onClick={() => {
                  if (timer.running) deadline.current += 30000;
                  setTimer((t) => ({ ...t, remaining: t.remaining + 30 }));
                }}
              >
                <Plus size={18} />
              </button>
            </div>
          </div>
          <div className="timer-presets">
            {[60, 90, 120].map((n) => (
              <button
                className={timer.duration === n ? "selected" : ""}
                key={n}
                onClick={() => startTimer(n)}
              >
                {n}s
              </button>
            ))}
            <span>+ adds 30s</span>
          </div>
        </section>
      )}
      {notice && (
        <div className="toast" role="status">
          <Check size={17} />
          {notice}
          <button
            aria-label="Dismiss notification"
            onClick={() => setNotice("")}
          >
            <X size={16} />
          </button>
        </div>
      )}
      {guide && (
        <Modal
          title="Strong starts with good habits."
          onClose={() => setGuide(false)}
        >
          <p className="modal-lead">
            Three nonconsecutive days. A pair of dumbbells. Plenty of patience.
          </p>
          <div className="guide-grid">
            <Guide
              title="Start small"
              text="For the first two weeks, use 1–2 sets for each exercise. Then move to the full plan. Monday, Wednesday and Friday are suggestions — keep a recovery day between sessions."
            />
            <Guide
              title="Make every rep a good one"
              text="Warm up for 5 minutes. Choose a comfortable load and stop with 2–3 good reps in reserve. Move slowly and breathe. Stop if an exercise hurts; don’t train through pain."
            />
            <Guide
              title="Give yourself a breather"
              text="Rest 90–120 seconds for presses, rows, squats and deadlifts. Use 60–90 seconds for arms and core. Rest longer if you need it."
            />
            <Guide
              title="Weight means total held"
              text="Log the combined kg you are holding: two 3 kg dumbbells = 6 kg. For one-arm moves or goblet squats, log the single dumbbell’s kg. Heel slides use bodyweight; no load entry needed. For moves done on both sides, complete both and log reps per side."
            />
            <Guide
              title="Earn the next step"
              text="Only increase by the smallest available weight once every set reaches the top of the rep range with controlled form. We haven’t assumed whether your 20 kg is total or per dumbbell. Start with a load you can control and secure the collars."
            />
            <Guide
              title="Keep a little perspective"
              text="Core exercises build control and strength. They cannot spot-reduce stomach fat. Consistency, recovery and a plan you enjoy matter more than chasing perfect numbers."
            />
          </div>
          <a
            className="source-link"
            href="https://acsm.org/resistance-training-guidelines-update-2026/"
            target="_blank"
            rel="noreferrer"
          >
            General strength-training guidance · ACSM <ArrowRight size={14} />
          </a>
        </Modal>
      )}
      {finishConfirm && (
        <Modal
          title="Call it a good session?"
          onClose={() => setFinishConfirm(false)}
        >
          <p className="modal-lead">
            You completed {tally.done} of {tally.total} sets. We’ll save exactly
            what you did, and leave the remaining sets unfinished.
          </p>
          <button className="dark-button" onClick={finish}>
            Save this session <Check size={18} />
          </button>
        </Modal>
      )}
      {historySession && (
        <Modal
          title={formatDate(historySession.date, {
            weekday: "long",
            day: "numeric",
            month: "long",
          })}
          onClose={() => setHistorySession(null)}
        >
          <p className="modal-lead">
            {historySession.completedAt ? "Completed" : "In progress"} ·{" "}
            {counts(historySession).done} of {counts(historySession).total} sets
            · Weight is total held.
          </p>
          {routine(profile).map((e) => (
            <div className="history-detail" key={e.id}>
              <strong>{e.name}</strong>
              <span>
                {(historySession.sets[e.id] ?? [])
                  .map((s, i) =>
                    s.done
                      ? `Set ${i + 1}: ${s.reps} reps${e.side ? " / side" : ""}${e.bodyweight ? " · bodyweight" : ` × ${s.kg} kg`}`
                      : `Set ${i + 1}: unfinished`,
                  )
                  .join(" · ")}
              </span>
            </div>
          ))}
          {historySession.completedAt &&
            historySession.date === localDate() && (
              <button
                className="text-button reopen"
                onClick={() => {
                  const id = historySession.id;
                  editSession(id, (s) => ({ ...s, completedAt: undefined }));
                  setHistorySession(null);
                  if (historySession.date === localDate())
                    route(profile, "today");
                  setNotice(
                    "Session reopened. You can review it and finish again today.",
                  );
                }}
              >
                Undo session completion <RotateCcw size={15} />
              </button>
            )}
        </Modal>
      )}
    </div>
  );
}

function Brand({ compact = false }: { compact?: boolean }) {
  return (
    <div className={`brand ${compact ? "compact" : ""}`}>
      <span className="brand-icon">
        <Dumbbell size={21} strokeWidth={2.5} />
      </span>
      <span>
        together<span className="brand-strong">strong</span>
        <span className="brand-period">.</span>
      </span>
    </div>
  );
}
function ExerciseCard({
  exercise: e,
  index,
  expanded,
  onExpand,
  session,
  plannedSets,
  onChange,
  onRest,
  onNotice,
}: {
  exercise: Exercise;
  index: number;
  expanded: boolean;
  onExpand: () => void;
  session?: Session;
  plannedSets: number;
  onChange: (index: number, patch: Partial<SetLog>) => void;
  onRest: () => void;
  onNotice: (text: string) => void;
}) {
  const sets = session?.sets[e.id];
  const done = sets?.filter((s) => s.done).length ?? 0;
  const complete = Boolean(sets && done === sets.length);
  return (
    <article
      className={`exercise-card ${expanded ? "expanded" : ""} ${complete ? "complete" : ""}`}
    >
      <button
        className="exercise-head"
        aria-expanded={expanded}
        aria-controls={`details-${e.id}`}
        onClick={onExpand}
      >
        <span className="exercise-number">
          {complete ? <Check size={19} /> : String(index + 1).padStart(2, "0")}
        </span>
        <span className="exercise-title">
          <span className="exercise-group">{e.group}</span>
          <strong>{e.name}</strong>
          <span className="exercise-meta">
            {sets?.length ?? plannedSets} sets <span>×</span> {e.reps} reps
            {e.side ? " / side" : ""}
            <span>·</span>
            {e.rest === 120 ? "90–120" : e.rest === 90 ? "60–90" : "60"}s rest
          </span>
        </span>
        <span className="exercise-chevron">
          {sets && done > 0 && (
            <small>
              {done}/{sets.length}
            </small>
          )}
          <ChevronDown size={19} />
        </span>
      </button>
      {expanded && (
        <div className="exercise-body" id={`details-${e.id}`}>
          <details className="how-to">
            <summary>
              How to do it{" "}
              <span>
                Start & end positions <ChevronDown size={15} />
              </span>
            </summary>
            <ExerciseVisual id={e.id} name={e.name} />
          </details>
          <div className="exercise-instructions">
            <span>
              <Dumbbell size={17} />
            </span>
            <div>
              <strong>{e.cue}</strong>
              <p>{e.instructions}</p>
            </div>
          </div>
          {!sets ? (
            <div className="start-hint">
              <Play size={14} /> Start your workout above to log your sets.
            </div>
          ) : (
            <>
              <div className="weight-note">
                {e.bodyweight
                  ? "Bodyweight · Complete both sides, then log reps per side."
                  : `KG = TOTAL HELD${e.side ? " · Complete both sides; log reps per side." : " · Add both dumbbells together when using two."}`}
              </div>
              <div className="set-header">
                <span>SET</span>
                <span>REPS{e.side ? " / SIDE" : ""}</span>
                <span>{e.bodyweight ? "LOAD" : "KG TOTAL"}</span>
                <span>DONE</span>
              </div>
              {sets.map((set, i) => (
                <div
                  className={`set-row ${set.done ? "set-done" : ""}`}
                  key={i}
                >
                  <span className="set-index">{i + 1}</span>
                  <input
                    aria-label={`${e.name} set ${i + 1} reps`}
                    inputMode="numeric"
                    type="number"
                    min="1"
                    max="100"
                    step="1"
                    placeholder={e.reps}
                    value={set.reps}
                    disabled={Boolean(session?.completedAt)}
                    onChange={(ev) =>
                      onChange(i, { reps: ev.target.value, done: false })
                    }
                  />
                  {e.bodyweight ? (
                    <span className="bodyweight-label">Bodyweight</span>
                  ) : (
                    <input
                      aria-label={`${e.name} set ${i + 1} kg total`}
                      inputMode="decimal"
                      type="number"
                      min="0"
                      max="200"
                      step="any"
                      placeholder="—"
                      value={set.kg}
                      disabled={Boolean(session?.completedAt)}
                      onChange={(ev) =>
                        onChange(i, { kg: ev.target.value, done: false })
                      }
                    />
                  )}
                  <button
                    className="set-checkbox"
                    aria-label={`${set.done ? "Undo" : "Complete"} ${e.name} set ${i + 1}`}
                    aria-pressed={set.done}
                    disabled={Boolean(session?.completedAt)}
                    onClick={() => {
                      if (!set.done && !validSet(set, e.bodyweight)) {
                        onNotice(
                          e.bodyweight
                            ? "Enter your reps before completing this set."
                            : "Enter reps and total kg before completing this set. Use 0 only if you intentionally used no load.",
                        );
                        return;
                      }
                      onChange(i, { done: !set.done });
                    }}
                  >
                    <Check size={18} />
                  </button>
                </div>
              ))}
              <button className="rest-button" onClick={onRest}>
                <Timer size={15} /> Start {e.rest}s rest{" "}
                <ArrowRight size={14} />
              </button>
            </>
          )}
        </div>
      )}
    </article>
  );
}
function Metric({
  icon,
  value,
  label,
}: {
  icon: React.ReactNode;
  value: number | string;
  label: string;
}) {
  return (
    <div className="metric">
      <span>{icon}</span>
      <strong>{value}</strong>
      <p>{label}</p>
    </div>
  );
}
function Empty({
  icon,
  title,
  text,
  action,
  label,
}: {
  icon: React.ReactNode;
  title: string;
  text: string;
  action: () => void;
  label: string;
}) {
  return (
    <div className="empty-state">
      <span>{icon}</span>
      <h3>{title}</h3>
      <p>{text}</p>
      <button className="text-button" onClick={action}>
        {label}
        <ArrowRight size={16} />
      </button>
    </div>
  );
}
function Guide({ title, text }: { title: string; text: string }) {
  return (
    <div className="guide-item">
      <span>
        <Check size={15} />
      </span>
      <div>
        <h3>{title}</h3>
        <p>{text}</p>
      </div>
    </div>
  );
}
function Modal({
  title,
  children,
  onClose,
}: {
  title: string;
  children: React.ReactNode;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const dialog = ref.current;
    dialog?.showModal();
    return () => dialog?.close();
  }, []);
  return (
    <dialog
      ref={ref}
      className="modal"
      onCancel={(e) => {
        e.preventDefault();
        onClose();
      }}
      onClick={(e) => {
        if (e.target === e.currentTarget) onClose();
      }}
    >
      <div className="modal-inner">
        <div className="modal-heading">
          <h2>{title}</h2>
          <button
            className="icon-button"
            aria-label="Close dialog"
            onClick={onClose}
          >
            <X size={20} />
          </button>
        </div>
        {children}
      </div>
    </dialog>
  );
}
