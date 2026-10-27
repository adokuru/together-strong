import { requestIdentity, validWriteOrigin } from "@/lib/request-identity";
import { db } from "@/lib/db";
import { emptyData, parseData } from "@/lib/workout";
export const runtime = "nodejs";
export const dynamic = "force-dynamic";
const response = (body: unknown, status = 200) =>
  Response.json(body, {
    status,
    headers: { "Cache-Control": "private, no-store" },
  });
export async function GET(request: Request) {
  const user = await requestIdentity(request);
  if (!user) return response({ error: "Unauthorized" }, 401);
  if (new URL(request.url).searchParams.get("profile") !== user.profile)
    return response({ error: "Forbidden" }, 403);
  const { rows } = await db().query(
    "SELECT data, revision FROM workout_data WHERE user_id = $1",
    [user.userId],
  );
  return response(rows[0] ?? { data: emptyData(), revision: 0 });
}
export async function PUT(request: Request) {
  if (!validWriteOrigin(request))
    return response({ error: "Invalid origin" }, 403);
  const user = await requestIdentity(request);
  if (!user) return response({ error: "Unauthorized" }, 401);
  const raw = await request.text();
  if (raw.length > 300000) return response({ error: "Too large" }, 413);
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return response({ error: "Invalid JSON" }, 400);
  }
  const data = parseData(body.data);
  if (!data || !Number.isInteger(body.revision) || body.revision < 0)
    return response({ error: "Invalid workout" }, 400);
  if (body.profile !== user.profile)
    return response({ error: "Forbidden" }, 403);
  const { rows } =
    body.revision === 0
      ? await db().query(
          `INSERT INTO workout_data (user_id, data, revision) VALUES ($1, $2::jsonb, 1) ON CONFLICT (user_id) DO NOTHING RETURNING revision`,
          [user.userId, JSON.stringify(data)],
        )
      : await db().query(
          `UPDATE workout_data SET data = $2::jsonb, revision = revision + 1 WHERE user_id = $1 AND revision = $3 RETURNING revision`,
          [user.userId, JSON.stringify(data), body.revision],
        );
  return rows[0]
    ? response(rows[0])
    : response({ error: "Changed on another device" }, 409);
}
