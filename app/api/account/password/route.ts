import { getAuth } from "@/lib/auth";
import { requestIdentity, validWriteOrigin } from "@/lib/request-identity";
export async function POST(request: Request) {
  if (!validWriteOrigin(request))
    return Response.json({ error: "Invalid origin" }, { status: 403 });
  if (!(await requestIdentity(request)))
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
