import { betterAuth, APIError } from "better-auth";
import { nextCookies } from "better-auth/next-js";
import { createAuthMiddleware } from "better-auth/api";
import { magicLink } from "better-auth/plugins/magic-link";
import { db } from "./db";
import { sendAuthMail } from "./mail";
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
      disableSignUp: true,
      requireEmailVerification: true,
      resetPasswordTokenExpiresIn: 900,
      revokeSessionsOnPasswordReset: true,
      sendResetPassword: async ({ user, url }) => {
        await sendAuthMail({ to: user.email, url, kind: "reset" });
      },
    },
    rateLimit: { enabled: true, storage: "database", window: 60, max: 20 },
    hooks: {
      before: createAuthMiddleware(async (ctx) => {
        if (ctx.path === "/sign-up/email")
          throw new APIError("FORBIDDEN", {
            message:
              "Verify your private email setup link before choosing a password.",
          });
        if (
          ctx.path === "/sign-in/magic-link" &&
          !profileForEmail(String(ctx.body?.email ?? ""))
        )
          return ctx.json({ status: true });
      }),
    },
    databaseHooks: {
      user: {
        create: {
          before: async (user) => {
            if (!profileForEmail(user.email))
              throw new APIError("FORBIDDEN", {
                message: "This is a private app.",
              });
            return { data: user };
          },
        },
      },
    },
    plugins: [
      magicLink({
        expiresIn: 900,
        storeToken: "hashed",
        sendMagicLink: async ({ email, url }) => {
          const confirmation = new URL("/email-link", url);
          confirmation.hash = new URLSearchParams({ verify: url }).toString();
          await sendAuthMail({
            to: email,
            url: confirmation.toString(),
            kind: "setup",
          });
        },
      }),
      nextCookies(),
    ],
  });
let instance: ReturnType<typeof createAuth> | undefined;
export function getAuth() {
  return (instance ??= createAuth());
}
