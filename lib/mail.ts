import { appendFile, mkdir } from "node:fs/promises";
import path from "node:path";
export function emailConfigured() {
  return (
    Boolean(
      process.env.MAILGUN_API_KEY &&
      process.env.MAILGUN_DOMAIN &&
      process.env.MAILGUN_FROM_EMAIL,
    ) || Boolean(!process.env.VERCEL && process.env.EMAIL_TEST_OUTBOX)
  );
}
const escape = (s: string) =>
  s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
export async function sendAuthMail({
  to,
  url,
  kind,
}: {
  to: string;
  url: string;
  kind: "setup" | "reset";
}) {
  if (
    ![process.env.DAVID_EMAIL, process.env.MARY_EMAIL].some(
      (email) => email?.toLowerCase() === to.toLowerCase(),
    )
  )
    throw Error("Recipient is not invited");
  const subject =
    kind === "setup"
      ? "Set up your Together Strong account"
      : "Reset your Together Strong password";
  const text =
    kind === "setup"
      ? `Open this private link to verify your email and choose your password. It expires in 15 minutes and works once.\n\n${url}\n\nIf you did not request this, ignore it. Never share this link.`
      : `Open this private link to choose a new password. It expires in 15 minutes and works once. Existing sessions are signed out after a successful reset.\n\n${url}\n\nIf you did not request this, ignore it. Never share this link.`;
  // Test delivery is available only on the local computer, never on Vercel.
  if (!process.env.VERCEL && process.env.EMAIL_TEST_OUTBOX) {
    const filename = path.resolve(process.env.EMAIL_TEST_OUTBOX),
      privateRoot = path.join(process.cwd(), ".private") + path.sep;
    if (!filename.startsWith(privateRoot))
      throw Error("Test outbox must stay in the private local directory");
    await mkdir(path.dirname(filename), { recursive: true, mode: 0o700 });
    await appendFile(filename, JSON.stringify({ to, url, kind }) + "\n", {
      mode: 0o600,
    });
    return;
  }
  const key = process.env.MAILGUN_API_KEY,
    domain = process.env.MAILGUN_DOMAIN,
    from = process.env.MAILGUN_FROM_EMAIL;
  if (!key || !domain || !from)
    throw Error("Private email delivery is not configured");
  const host =
    process.env.MAILGUN_REGION === "eu"
      ? "https://api.eu.mailgun.net"
      : "https://api.mailgun.net";
  const body = new FormData();
  body.set("from", from);
  body.set("to", to);
  body.set("subject", subject);
  body.set("text", text);
  body.set(
    "html",
    `<div style="font-family:Arial,sans-serif;color:#263728;max-width:520px;margin:auto;padding:32px"><p style="font-size:12px;letter-spacing:2px">TOGETHER STRONG</p><h1 style="font-family:Georgia,serif;font-weight:400">${kind === "setup" ? "A little stronger. Together." : "A fresh start for your password."}</h1><p style="font-size:14px;line-height:1.8">${kind === "setup" ? "Verify your email, then choose a private password for your workout space." : "Choose a new private password. Your existing sessions will be signed out."}</p><a href="${escape(url)}" style="display:inline-block;background:#d7e9c7;color:#263728;padding:15px 23px;border-radius:8px;text-decoration:none;font-size:14px">${kind === "setup" ? "Set up my account" : "Reset my password"}</a><p style="font-size:12px;color:#68785a;line-height:1.8">Expires in 15 minutes. Works once. Never share this link. If you didn’t request it, ignore this email.</p></div>`,
  );
  body.set("o:tracking", "no");
  body.set("o:tracking-clicks", "no");
  body.set("o:tracking-opens", "no");
  const response = await fetch(
    `${host}/v3/${encodeURIComponent(domain)}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${Buffer.from(`api:${key}`).toString("base64")}`,
      },
      body,
      signal: AbortSignal.timeout(20000),
    },
  );
  if (!response.ok)
    throw Error("Private email delivery failed. Please try again later.");
}
