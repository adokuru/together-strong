import { getAuth, profileForEmail } from "@/lib/auth";
import { db } from "@/lib/db";
export const dynamic = "force-dynamic";
export async function GET(request: Request) {
  if (!process.env.DATABASE_URL || !process.env.BETTER_AUTH_SECRET)
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  const session = await getAuth().api.getSession({ headers: request.headers });
  const profile = session && profileForEmail(session.user.email);
  if (!session || !profile || !session.user.emailVerified)
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  const result = await db().query(
    `SELECT id FROM account WHERE "userId"=$1 AND "providerId"='credential' AND password IS NOT NULL`,
    [session.user.id],
  );
  return Response.json(
    { profile, needsPassword: result.rows.length === 0 },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
