import { emptyData, parseData, Profile, WorkoutData } from "./workout";
export interface WorkoutStorage {
  load(profile: Profile): Promise<{ data: WorkoutData; revision: number }>;
  save(profile: Profile, data: WorkoutData, revision: number): Promise<number>;
}
export class LocalWorkoutStorage implements WorkoutStorage {
  async load(profile: Profile) {
    const raw = localStorage.getItem(`together-strong:demo:${profile}`);
    if (!raw) return { data: emptyData(), revision: 0 };
    try {
      const parsed = JSON.parse(raw);
      const data = parseData(parsed.data);
      if (!data) throw Error();
      return { data, revision: parsed.revision ?? 0 };
    } catch {
      throw Error(
        "Your saved data could not be read. Your browser copy has been preserved.",
      );
    }
  }
  async save(profile: Profile, data: WorkoutData, revision: number) {
    const current = await this.load(profile);
    if (current.revision !== revision)
      throw Error(
        "This workout changed in another tab. Reload to get the latest copy.",
      );
    localStorage.setItem(
      `together-strong:demo:${profile}`,
      JSON.stringify({ data, revision: revision + 1 }),
    );
    return revision + 1;
  }
}
export class CloudWorkoutStorage implements WorkoutStorage {
  async load(profile: Profile) {
    const r = await fetch(`/api/workouts?profile=${profile}`, {
      cache: "no-store",
    });
    if (!r.ok)
      throw Error(
        r.status === 401
          ? "Please sign in to your profile again."
          : "Could not load your workout. Please retry.",
      );
    return r.json();
  }
  async save(profile: Profile, data: WorkoutData, revision: number) {
    const r = await fetch("/api/workouts", {
      method: "PUT",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ profile, data, revision }),
    });
    if (!r.ok)
      throw Error(
        r.status === 409
          ? "This workout changed on another device. Reload to get the latest copy."
          : "Your change could not be saved. Please retry before leaving.",
      );
    return (await r.json()).revision;
  }
}
