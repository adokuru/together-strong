import { requestIdentity } from "@/lib/request-identity";
import { db } from "@/lib/db";
export const dynamic = "force-dynamic";
export async function GET(request: Request) {
  const user = await requestIdentity(request);
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const result = await db().query(
    `SELECT id FROM account WHERE "userId"=$1 AND "providerId"='credential' AND password IS NOT NULL`,
    [user.userId],
  );
  return Response.json(
    {
      userId: user.userId,
      profile: user.profile,
      needsPassword: result.rows.length === 0,
    },
    { headers: { "Cache-Control": "private, no-store" } },
  );
}
