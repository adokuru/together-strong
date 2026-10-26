import { getAuth } from "@/lib/auth";
export const runtime = "nodejs";
export async function GET(request: Request) {
  if (!process.env.DATABASE_URL || !process.env.BETTER_AUTH_SECRET)
    return Response.json(
      { error: "Private access setup pending" },
      { status: 503 },
    );
  return getAuth().handler(request);
}
export const POST = GET;
