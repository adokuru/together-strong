import { counts, isCompleted, localDate, sessionDay, type Exercise, type WorkoutData } from "./workout";

export function completedWorkouts(data: WorkoutData) {
  return data.sessions.filter(s => !s.discardedAt && isCompleted(s));
}

export function weeklyProgress(data: WorkoutData, now = new Date()) {
  const monday = new Date(now); monday.setHours(0,0,0,0);
  monday.setDate(monday.getDate() - ((monday.getDay()+6)%7));
  return Array.from({length:8}, (_, index) => {
    const start = new Date(monday); start.setDate(start.getDate()+(index-7)*7);
    const end = new Date(start); end.setDate(end.getDate()+7);
    const first = localDate(start), last = localDate(end);
    return {date:first,count:completedWorkouts(data).filter(s => sessionDay(s)>=first && sessionDay(s)<last).length};
  });
}

export function progressSummary(data: WorkoutData, now = new Date()) {
  const completed = completedWorkouts(data);
  return {workouts:completed.length, sets:completed.reduce((sum,s)=>sum+counts(s).done,0), thisWeek:weeklyProgress(data,now).at(-1)!.count};
}

export function exerciseRecords(data: WorkoutData, exercise: Exercise) {
  return completedWorkouts(data).flatMap(s => {
    const best = (s.sets[exercise.id]??[]).filter(x=>x.done).sort((a,b)=>exercise.bodyweight ? Number(b.reps)-Number(a.reps) : Number(b.kg)-Number(a.kg)||Number(b.reps)-Number(a.reps))[0];
    return best ? [{sessionID:s.id,date:s.date,value:exercise.bodyweight ? Number(best.reps):Number(best.kg),reps:Number(best.reps)}] : [];
  }).sort((a,b)=>a.date.localeCompare(b.date)||a.sessionID.localeCompare(b.sessionID));
}
