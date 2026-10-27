import { writeFileSync } from "node:fs";
import { emptyData, makeSession, routine, progressSummary, weeklyProgress, exerciseRecords, sessionDay, parseData } from "../lib/workout.ts";

const session = (id, date, values = {}) => ({...makeSession("David", emptyData()), id, date, startedAt:date+"T12:00:00.000Z", ...values});
const data = emptyData();
for (let index=0; index<19; index++) {
 const date = new Date(Date.UTC(2026,8,1+index*3)).toISOString().slice(0,10);
 const item = session(`completed-${index}`,date,{completedAt:date+"T14:00:00.000Z"});
 item.sets.press = [{reps:"8",kg:String(index%6*2),done:true},{reps:"12",kg:String(index%6*2),done:true},{reps:"15",kg:"200",done:false}];
 item.sets.heel = [{reps:String(6+index%5),kg:"",done:true},{reps:"6",kg:"",done:true}];
 data.sessions.push(item);
}
const late = session("late-finish","2026-10-20",{completedAt:"2026-10-26T23:30:00.000Z"});
late.sets.row[0] = {reps:"10",kg:"7.50",done:true};
data.sessions.push(late);
const paused = session("paused","2026-10-27",{status:"paused",pausedAt:"2026-10-27T13:00:00.000Z"});
paused.sets.press[0] = {reps:"10",kg:"100",done:true};
data.sessions.push(paused,session("draft","2026-10-28"),session("discarded","2026-10-29",{discardedAt:"2026-10-29T12:01:00.000Z"}),session("empty-finish","2026-10-30",{completedAt:"2026-10-30T12:01:00.000Z"}));
const edge = session("dst-week","2026-10-31",{completedAt:"2026-11-02T00:30:00.000Z"});
edge.sets.press[0] = {reps:"10",kg:"0",done:true}; data.sessions.push(edge);
data.startedAt = data.sessions[0].startedAt;
// Deliberately unordered history must still produce a chronological exercise chart.
data.sessions.reverse();
if (!parseData(data)) throw Error("Progress fixtures must satisfy the live document contract.");
const cases = [
 ["UTC","2026-10-27T12:00:00.000Z",data],
 ["Africa/Lagos","2026-10-27T12:00:00.000Z",data],
 ["America/New_York","2026-11-02T12:00:00.000Z",data],
 ["Pacific/Kiritimati","2026-11-02T12:00:00.000Z",data],
 ["UTC","2026-10-27T12:00:00.000Z",emptyData()],
].map(([zone,now,data])=> {
 process.env.TZ=zone;
 return {zone,now,data,summary:progressSummary(data,new Date(now)),weekly:weeklyProgress(data,new Date(now)),records:Object.fromEntries(routine("David").map(e=>[e.id,exerciseRecords(data,e)])),days:Object.fromEntries(data.sessions.filter(s=>!s.discardedAt).map(s=>[s.id,sessionDay(s)]))};
});
writeFileSync("contracts/fixtures/workout-progress.json",JSON.stringify(cases,null,2)+"\n");
console.log("Generated shared progress, calendar and time-zone fixtures.");
