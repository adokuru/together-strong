import { betterAuth, APIError } from "better-auth";
import { nextCookies } from "better-auth/next-js";
import { createAuthMiddleware } from "better-auth/api";
import { createHash, timingSafeEqual } from "node:crypto";
import { db } from "./db";
export function profileForEmail(email: string) {
  const normalized = email.toLowerCase();
  if (process.env.DAVID_EMAIL?.toLowerCase() === normalized) return "David";
  if (process.env.MARY_EMAIL?.toLowerCase() === normalized) return "Mary";
  return null;
}
const createAuth = () =>
  betterAuth({
    database: db(),
    secret: process.env.BETTER_AUTH_SECRET,
    baseURL: process.env.BETTER_AUTH_URL,
    emailAndPassword: {
      enabled: true,
      minPasswordLength: 12,
      maxPasswordLength: 128,
    },
    rateLimit: { enabled: true, storage: "database", window: 60, max: 20 },
    hooks: {
      before: createAuthMiddleware(async (ctx) => {
        if (ctx.path !== "/sign-up/email") return;
        const profile = profileForEmail(String(ctx.body?.email ?? ""));
        const expected =
          profile === "David"
            ? process.env.DAVID_INVITE_CODE
            : profile === "Mary"
              ? process.env.MARY_INVITE_CODE
              : undefined;
        const actual = ctx.headers?.get("x-invite-code");
        if (
          !expected ||
          !actual ||
          !timingSafeEqual(
            createHash("sha256").update(expected).digest(),
            createHash("sha256").update(actual).digest(),
          )
        )
          throw new APIError("FORBIDDEN", {
            message:
              "Use the private invitation code supplied for your profile.",
          });
      }),
    },
    databaseHooks: {
      user: {
        create: {
          before: async (user) => {
            if (!profileForEmail(user.email))
              throw new APIError("FORBIDDEN", {
                message:
                  "This is a private app. Use your invited email address.",
              });
            return { data: user };
          },
        },
      },
    },
    plugins: [nextCookies()],
  });
let instance: ReturnType<typeof createAuth> | undefined;
export function getAuth() {
  return (instance ??= createAuth());
}
