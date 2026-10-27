export type Profile = "David" | "Mary";
export type SetLog = { reps: string; kg: string; done: boolean };
export type Session = {
  id: string;
  date: string;
  startedAt: string;
  completedAt?: string;
  warmup: boolean;
  warmupState?: "pending" | "underway" | "done" | "skipped";
  status?: "draft" | "active" | "paused";
  pausedAt?: string;
  discardedAt?: string;
  trainingStartedAt?: string;
  sets: Record<string, SetLog[]>;
};
export type WorkoutData = {
  version: 1;
  startedAt?: string;
  rampSets: 1 | 2;
  activeSessionId?: string;
  sessions: Session[];
};
export type Exercise = {
  id: string;
  name: string;
  group: string;
  reps: string;
  maxReps: number;
  sets: number;
  rest: number;
  side?: boolean;
  bodyweight?: boolean;
  instructions: string;
  cue: string;
};
const exercises: Record<string, Exercise> = {
  press: {
    id: "press",
    name: "Dumbbell floor press",
    group: "CHEST · TRICEPS",
    reps: "8–12",
    maxReps: 12,
    sets: 2,
    rest: 120,
    instructions:
      "Lie on the floor with knees bent. Hold dumbbells over your chest, palms forward or slightly inward. Lower slowly until upper arms gently touch the floor, then press up. Keep wrists stacked and avoid bouncing.",
    cue: "Slow lower. Smooth press.",
  },
  row: {
    id: "row",
    name: "One-arm dumbbell row",
    group: "BACK · BICEPS",
    reps: "8–12",
    maxReps: 12,
    sets: 2,
    rest: 120,
    side: true,
    instructions:
      "Hinge forward with a flat, comfortable back and a staggered stance. Rest your free hand on your front thigh. Pull one dumbbell toward your hip without twisting, then lower slowly. Complete both sides; log the lower rep count.",
    cue: "Pull toward your hip.",
  },
  squat: {
    id: "squat",
    name: "Goblet squat",
    group: "LEGS · CORE",
    reps: "8–12",
    maxReps: 12,
    sets: 2,
    rest: 120,
    instructions:
      "Hold one dumbbell close to your chest. Stand with feet in a comfortable stance. Sit down between your hips to a comfortable depth, keeping heels grounded and knees tracking with toes. Stand tall without locking your knees.",
    cue: "Stay tall. Keep heels down.",
  },
  rdl: {
    id: "rdl",
    name: "Dumbbell Romanian deadlift",
    group: "GLUTES · HAMSTRINGS",
    reps: "8–12",
    maxReps: 12,
    sets: 2,
    rest: 120,
    instructions:
      "Stand with soft knees and dumbbells near your thighs. Push your hips back, keeping the weights close and your back comfortable. Stop when you feel a hamstring stretch and can maintain form, then stand by bringing your hips forward.",
    cue: "Hips back, weights close.",
  },
  curl: {
    id: "curl",
    name: "Dumbbell curls",
    group: "BICEPS",
    reps: "10–15",
    maxReps: 15,
    sets: 2,
    rest: 90,
    instructions:
      "Stand tall with a dumbbell in each hand. Keep elbows close to your sides. Curl without swinging or leaning, then lower under control. Log the lower rep count if the arms differ.",
    cue: "Quiet elbows. No swinging.",
  },
  kickback: {
    id: "kickback",
    name: "Light triceps kickback",
    group: "TRICEPS",
    reps: "10–15",
    maxReps: 15,
    sets: 2,
    rest: 90,
    side: true,
    instructions:
      "Use a light dumbbell. Hinge slightly and support your free hand on your thigh. Hold your upper arm close to your body. Straighten the elbow without moving the shoulder, then return slowly. Repeat both sides; log the lower rep count.",
    cue: "Light load. Upper arm still.",
  },
  heel: {
    id: "heel",
    name: "Bodyweight heel slides",
    group: "CORE · CONTROL",
    reps: "6–10",
    maxReps: 10,
    sets: 2,
    rest: 60,
    side: true,
    bodyweight: true,
    instructions:
      "Lie on your back with knees bent and heels on the floor. Gently brace while breathing normally. Slide one heel away only as far as you can without arching your back, then return. Alternate sides and log reps per side.",
    cue: "Breathe. Move with control.",
  },
};
export function routine(profile: Profile): Exercise[] {
  const order =
    profile === "David"
      ? ["press", "row", "squat", "rdl", "curl", "kickback", "heel"]
      : ["row", "squat", "press", "rdl", "curl", "kickback", "heel"];
  return order.map((id) => ({
    ...exercises[id],
    sets:
      (profile === "David" && id === "press") ||
      (profile === "Mary" && id === "row")
        ? 3
        : 2,
  }));
}
export const emptyData = (): WorkoutData => ({
  version: 1,
  rampSets: 2,
  sessions: [],
});
export function localDate(d = new Date()) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
}
export function weekNumber(data: WorkoutData, now = new Date()) {
  if (!data.sessions.some((s) => counts(s).done > 0)) return 1;
  if (!data.startedAt) return 1;
  const first = new Date(data.startedAt);
  return Math.max(
    1,
    Math.floor((now.getTime() - first.getTime()) / 604800000) + 1,
  );
}
export function makeSession(profile: Profile, data: WorkoutData): Session {
  return {
    id: crypto.randomUUID(),
    date: localDate(),
    startedAt: new Date().toISOString(),
    warmup: false,
    warmupState: "pending",
    status: "draft",
    sets: Object.fromEntries(
      routine(profile).map((e) => [
        e.id,
        Array.from(
          { length: weekNumber(data) <= 2 ? data.rampSets : e.sets },
          () => ({ reps: "", kg: "", done: false }),
        ),
      ]),
    ),
  };
}
export function counts(session?: Session) {
  const sets = session ? Object.values(session.sets).flat() : [];
  return { total: sets.length, done: sets.filter((s) => s.done).length };
}
export function isCompleted(session?: Session) {
  return Boolean(session?.completedAt) && counts(session).done > 0;
}
export function sessionStage(session?: Session) {
  if (!session) return "new";
  if (isCompleted(session)) return "complete";
  if (counts(session).done === 0) return "draft";
  return session.status === "paused" ? "paused" : "active";
}
export function activeSession(data: WorkoutData) {
  const available = data.sessions.filter((s) => !s.discardedAt);
  return (
    available.find(
      (s) =>
        s.id === data.activeSessionId &&
        (!isCompleted(s) ||
          localDate(new Date(s.completedAt!)) === localDate()),
    ) ??
    [...available].reverse().find((s) => !isCompleted(s)) ??
    available.find((s) => s.date === localDate())
  );
}
export function validSet(set: SetLog, bodyweight = false) {
  return (
    /^\d+$/.test(set.reps) &&
    Number(set.reps) >= 1 &&
    Number(set.reps) <= 100 &&
    (bodyweight || (/^\d+(\.\d{1,2})?$/.test(set.kg) && Number(set.kg) <= 200))
  );
}
export function parseData(value: unknown): WorkoutData | null {
  if (!value || typeof value !== "object") return null;
  const d = value as WorkoutData;
  if (
    d.version !== 1 ||
    ![1, 2].includes(d.rampSets) ||
    !Array.isArray(d.sessions) ||
    d.sessions.length > 1000
  )
    return null;
  if (d.startedAt && isNaN(Date.parse(d.startedAt))) return null;
  const ids = new Set<string>();
  const days = new Set<string>();
  for (const s of d.sessions) {
    if (
      !s ||
      typeof s.id !== "string" ||
      s.id.length > 80 ||
      ids.has(s.id) ||
      !/^\d{4}-\d{2}-\d{2}$/.test(s.date) ||
      (!s.discardedAt && days.has(s.date)) ||
      isNaN(Date.parse(s.startedAt)) ||
      typeof s.warmup !== "boolean" ||
      !s.sets ||
      typeof s.sets !== "object"
    )
      return null;
    ids.add(s.id);
    if (!s.discardedAt) days.add(s.date);
    if (s.status && !["draft", "active", "paused"].includes(s.status))
      return null;
    if (
      s.warmupState &&
      !["pending", "underway", "done", "skipped"].includes(s.warmupState)
    )
      return null;
    for (const value of [s.pausedAt, s.discardedAt, s.trainingStartedAt])
      if (value && isNaN(Date.parse(value))) return null;
    if (s.completedAt && isNaN(Date.parse(s.completedAt))) return null;
    for (const [id, sets] of Object.entries(s.sets)) {
      if (
        !exercises[id] ||
        !Array.isArray(sets) ||
        sets.length < 1 ||
        sets.length > 3
      )
        return null;
      for (const set of sets) {
        if (
          !set ||
          typeof set.reps !== "string" ||
          typeof set.kg !== "string" ||
          typeof set.done !== "boolean" ||
          set.reps.length > 3 ||
          set.kg.length > 6 ||
          (set.done && !validSet(set, exercises[id].bodyweight))
        )
          return null;
      }
    }
    if (s.discardedAt && counts(s).done > 0) return null;
  }
  return JSON.parse(JSON.stringify(d));
}

export function sessionDay(s: Session) {
  return isCompleted(s) ? localDate(new Date(s.completedAt!)) : s.date;
}

export function completedWorkouts(data: WorkoutData) {
  return data.sessions.filter((s) => !s.discardedAt && isCompleted(s));
}

export function weeklyProgress(data: WorkoutData, now = new Date()) {
  const monday = new Date(now);
  monday.setHours(0, 0, 0, 0);
  monday.setDate(monday.getDate() - ((monday.getDay() + 6) % 7));
  const completed = completedWorkouts(data);
  return Array.from({ length: 8 }, (_, index) => {
    const start = new Date(monday);
    start.setDate(start.getDate() + (index - 7) * 7);
    const end = new Date(start);
    end.setDate(end.getDate() + 7);
    const first = localDate(start),
      last = localDate(end);
    return {
      date: first,
      count: completed.filter(
        (s) => sessionDay(s) >= first && sessionDay(s) < last,
      ).length,
    };
  });
}

export function progressSummary(data: WorkoutData, now = new Date()) {
  const completed = completedWorkouts(data);
  return {
    workouts: completed.length,
    sets: completed.reduce((sum, s) => sum + counts(s).done, 0),
    thisWeek: weeklyProgress(data, now).at(-1)!.count,
  };
}

export function exerciseRecords(data: WorkoutData, exercise: Exercise) {
  return completedWorkouts(data)
    .flatMap((s) => {
      const best = (s.sets[exercise.id] ?? [])
        .filter((x) => x.done)
        .sort((a, b) =>
          exercise.bodyweight
            ? Number(b.reps) - Number(a.reps)
            : Number(b.kg) - Number(a.kg) || Number(b.reps) - Number(a.reps),
        )[0];
      return best
        ? [
            {
              sessionID: s.id,
              date: s.date,
              value: exercise.bodyweight ? Number(best.reps) : Number(best.kg),
              reps: Number(best.reps),
            },
          ]
        : [];
    })
    .sort(
      (a, b) =>
        a.date.localeCompare(b.date) || a.sessionID.localeCompare(b.sessionID),
    );
}
