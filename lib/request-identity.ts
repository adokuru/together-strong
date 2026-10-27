import { getAuth, profileForEmail } from "./auth";

// Never fall back to a browser cookie when a native credential is supplied.
export function validCredentials(request: Request) {
  const authorization = request.headers.get("authorization");
  return (
    authorization === null ||
    (/^Bearer [^\s]+$/i.test(authorization) && !request.headers.has("cookie"))
  );
}

export function validWriteOrigin(request: Request) {
  const origin = request.headers.get("origin");
  if (!origin)
    return request.headers.has("authorization") && validCredentials(request);
  try {
    const parsed = new URL(origin);
    const requestURL = new URL(request.url);
    // Next.js may normalize the internal URL to localhost behind its listener.
    const host = request.headers.get("host") ?? requestURL.host;
    const protocol = request.headers.get("x-forwarded-proto")
      ? `${request.headers.get("x-forwarded-proto")}:`
      : requestURL.protocol;
    return (
      parsed.origin === origin &&
      parsed.host === host &&
      parsed.protocol === protocol
    );
  } catch {
    return false;
  }
}

export async function requestIdentity(request: Request) {
  if (
    !process.env.DATABASE_URL ||
    !process.env.BETTER_AUTH_SECRET ||
    !validCredentials(request)
  )
    return null;
  const session = await getAuth().api.getSession({
    headers: request.headers,
    query: { disableCookieCache: true },
  });
  if (!session?.user.emailVerified) return null;
  const profile = profileForEmail(session.user.email);
  return profile ? { userId: session.user.id, profile } : null;
}
