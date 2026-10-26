import { Pool } from "pg";
const globalForDb = globalThis as unknown as { workoutPool?: Pool };
export function db() {
  if (!process.env.DATABASE_URL) throw Error("Database is not configured");
  return (globalForDb.workoutPool ??= new Pool({
    connectionString: process.env.DATABASE_URL,
    max: 4,
    connectionTimeoutMillis: 10000,
    idleTimeoutMillis: 20000,
  }));
}
