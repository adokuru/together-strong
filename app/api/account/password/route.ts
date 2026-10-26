import { getAuth, profileForEmail } from "@/lib/auth";
export async function POST(request: Request) {
  const origin = request.headers.get("origin");
  try {
    if (!origin || new URL(origin).host !== request.headers.get("host"))
      return Response.json({ error: "Invalid origin" }, { status: 403 });
  } catch {
    return Response.json({ error: "Invalid origin" }, { status: 403 });
  }
  if (!process.env.DATABASE_URL || !process.env.BETTER_AUTH_SECRET)
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  const session = await getAuth().api.getSession({ headers: request.headers });
  if (!session?.user.emailVerified || !profileForEmail(session.user.email))
    return Response.json({ error: "Unauthorized" }, { status: 401 });
  let body;
  try {
    body = await request.json();
  } catch {
    return Response.json({ error: "Invalid request" }, { status: 400 });
  }
  if (
    typeof body.newPassword !== "string" ||
    body.newPassword.length < 12 ||
    body.newPassword.length > 128
  )
    return Response.json(
      { error: "Choose a password with 12–128 characters." },
      { status: 400 },
    );
  try {
    await getAuth().api.setPassword({
      headers: request.headers,
      body: { newPassword: body.newPassword },
    });
    return Response.json(
      { status: true },
      { headers: { "Cache-Control": "private, no-store" } },
    );
  } catch {
    return Response.json(
      {
        error:
          "A password is already set or your setup session expired. Request a reset link if you need a new password.",
      },
      { status: 400 },
    );
  }
}
