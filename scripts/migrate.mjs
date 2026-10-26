import { Pool } from "pg";
import { getMigrations } from "better-auth/db/migration";
if (process.env.MIGRATION_TARGET_CONFIRM !== "together-strong")
  throw Error(
    "Set MIGRATION_TARGET_CONFIRM=together-strong only after checking the new database target.",
  );
const keys = [
  "DATABASE_URL",
  "BETTER_AUTH_SECRET",
  "DAVID_EMAIL",
  "MARY_EMAIL",
  "DAVID_INVITE_CODE",
  "MARY_INVITE_CODE",
];
const missing = keys.filter((key) => !process.env[key]);
if (missing.length)
  throw Error(`Missing configuration keys: ${missing.join(", ")}`);
if (
  process.env.DAVID_EMAIL.toLowerCase() === process.env.MARY_EMAIL.toLowerCase()
)
  throw Error("The two profiles need distinct invited email addresses.");
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
try {
  const existing = await pool.query(
    "SELECT tablename FROM pg_tables WHERE schemaname='public'",
  );
  const allowed = new Set([
    "user",
    "session",
    "account",
    "verification",
    "rateLimit",
    "workout_data",
  ]);
  if (existing.rows.some((row) => !allowed.has(row.tablename)))
    throw Error(
      "This database contains unrelated tables. Stopping to protect an existing project.",
    );
  const plan = await getMigrations({
    database: pool,
    emailAndPassword: { enabled: true },
    rateLimit: { enabled: true, storage: "database" },
  });
  await plan.runMigrations();
  await pool.query(
    `CREATE TABLE IF NOT EXISTS workout_data (user_id text PRIMARY KEY REFERENCES "user"(id) ON DELETE CASCADE, data jsonb NOT NULL, revision integer NOT NULL CHECK (revision > 0))`,
  );
  console.log(
    "Authentication and workout schema ready. No personal workout data was seeded.",
  );
} finally {
  await pool.end();
}
