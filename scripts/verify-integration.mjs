import { chromium, expect } from "@playwright/test";
import { Pool } from "pg";
import { randomBytes } from "node:crypto";
import { spawn } from "node:child_process";
import { createServer } from "node:net";
import {
  readFileSync,
  writeFileSync,
  mkdirSync,
  existsSync,
  unlinkSync,
} from "node:fs";
import path from "node:path";
import { verifyNativeHTTP, verifyIOS } from "./native-integration.mjs";
if (
  process.env.RUN_DB_INTEGRATION !== "1" ||
  process.env.CONFIRM_TEST_DB !== "together-strong" ||
  !process.env.DATABASE_URL
)
  throw Error(
    "Opt in with RUN_DB_INTEGRATION=1 and CONFIRM_TEST_DB=together-strong, using only the isolated app database.",
  );
const port = Number(process.env.INTEGRATION_PORT ?? 3191);
if (!Number.isInteger(port) || port < 1024 || port > 65535)
  throw Error("Use a local integration port from 1024 to 65535.");
await new Promise((resolve, reject) => {
  const probe = createServer();
  probe.once("error", () =>
    reject(
      Error(
        "Integration port is occupied. Choose another INTEGRATION_PORT; existing servers must remain untouched.",
      ),
    ),
  );
  probe.listen(port, "127.0.0.1", () =>
    probe.close((error) => (error ? reject(error) : resolve())),
  );
});
const run = randomBytes(6).toString("hex"),
  base = `http://127.0.0.1:${port}`,
  outbox = path.join(process.cwd(), ".private", `auth-outbox-${run}.jsonl`);
const emails = [
    process.env.INTEGRATION_DAVID_EMAIL ?? `qa-david-${run}@example.invalid`,
    process.env.INTEGRATION_MARY_EMAIL ?? `qa-mary-${run}@example.invalid`,
  ],
  password = randomBytes(24).toString("base64url"),
  newPassword = randomBytes(24).toString("base64url");
const pool = new Pool({ connectionString: process.env.DATABASE_URL, max: 1 });
if (
  !/^qa-david-[a-f0-9]+@example.invalid$/.test(emails[0]) ||
  !/^qa-mary-[a-f0-9]+@example.invalid$/.test(emails[1])
)
  throw Error("Only synthetic integration identities are allowed");
if (
  (
    await pool.query('SELECT id FROM "user" WHERE email=ANY($1::text[])', [
      emails,
    ])
  ).rows.length
) {
  await pool.end();
  throw Error(
    "Test identities already exist; refusing to touch accounts not created by this run",
  );
}
mkdirSync(".private", { recursive: true, mode: 0o700 });
const server = spawn(
  process.execPath,
  [
    "node_modules/next/dist/bin/next",
    "start",
    "--hostname",
    "127.0.0.1",
    "--port",
    String(port),
  ],
  {
    stdio: "ignore",
    env: {
      ...process.env,
      VERCEL: "",
      DAVID_EMAIL: emails[0],
      MARY_EMAIL: emails[1],
      BETTER_AUTH_URL: base,
      EMAIL_TEST_OUTBOX: outbox,
    },
  },
);
let browser,
  nativeToken,
  step = "server start";
const passed = [];
const ok = (label) => {
  passed.push(label);
  console.log(`PASS ${label}`);
};
const mail = (email, kind) =>
  readFileSync(outbox, "utf8")
    .trim()
    .split("\n")
    .map((line) => JSON.parse(line))
    .filter((item) => item.to === email && item.kind === kind)
    .at(-1);
async function signup(profile, email) {
  step = `verified ${profile} setup`;
  const context = await browser.newContext(),
    page = await context.newPage();
  await page.goto(base);
  await page.getByRole("button", { name: `Choose ${profile}` }).click();
  await page
    .getByRole("button", { name: "First time? Email me a setup link" })
    .click();
  await page.getByRole("textbox", { name: "Email address" }).fill(email);
  await page.getByRole("button", { name: "Email my setup link" }).click();
  await expect(
    page.getByRole("heading", { name: "Check your inbox." }),
  ).toBeVisible();
  expect(
    (await pool.query('SELECT id FROM "user" WHERE email=$1', [email])).rows,
  ).toHaveLength(0);
  ok(`${profile}: email request alone cannot claim an account`);
  const link = mail(email, "setup").url;
  await page.goto(link);
  expect(
    (await pool.query('SELECT id FROM "user" WHERE email=$1', [email])).rows,
  ).toHaveLength(0);
  await page.getByRole("link", { name: "Verify email & continue" }).click();
  await expect(
    page.getByLabel("Choose password", { exact: true }),
  ).toBeVisible();
  await page.getByLabel("Choose password", { exact: true }).fill(password);
  await page
    .getByLabel("Confirm password", { exact: true })
    .fill(password + "x");
  await page.getByRole("button", { name: "Save password & start" }).click();
  await expect(page.locator(".error-text")).toContainText("don’t match");
  await page.getByLabel("Confirm password", { exact: true }).fill(password);
  await page.getByRole("button", { name: "Save password & start" }).click();
  await expect(
    page.getByRole("heading", { name: "Today’s workout" }),
  ).toBeVisible({ timeout: 15000 });
  ok(
    `${profile}: single-use email verification and user-chosen password setup`,
  );
  return { context, page, link };
}
async function signin(profile, email, pwd) {
  const context = await browser.newContext(),
    page = await context.newPage();
  await page.goto(base);
  await page.getByRole("button", { name: `Choose ${profile}` }).click();
  await page.getByRole("textbox", { name: "Email address" }).fill(email);
  await page.getByLabel("Password", { exact: true }).fill(pwd);
  await page.getByRole("button", { name: "Sign in & get stronger" }).click();
  await expect(
    page.getByRole("heading", { name: "Today’s workout" }),
  ).toBeVisible({ timeout: 15000 });
  return { context, page };
}
try {
  for (let attempt = 0; attempt < 100; attempt++) {
    if (server.exitCode !== null)
      throw Error("The isolated integration server could not start.");
    try {
      if ((await fetch(base)).ok) break;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  browser = await chromium.launch({
    executablePath: process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE,
  });
  const anon = await browser.newContext();
  expect(
    (await anon.request.get(base + "/api/workouts?profile=David")).status(),
  ).toBe(401);
  expect(
    (
      await anon.request.post(base + "/api/account/password", {
        headers: { Origin: base },
        data: { newPassword: password },
      })
    ).status(),
  ).toBe(401);
  ok("Unauthenticated logs and password creation denied");
  const david = await signup("David", emails[0]),
    mary = await signup("Mary", emails[1]);
  step = "mail-token replay";
  const replay = await browser.newContext(),
    rp = await replay.newPage();
  await rp.goto(david.link);
  await rp.getByRole("link", { name: "Verify email & continue" }).click();
  expect(
    (await replay.request.get(base + "/api/workouts?profile=David")).status(),
  ).toBe(401);
  ok("Used setup link cannot mint a second session");
  step = "independent sessions";
  const second = await signin("David", emails[0], password);
  ok("Independent browser password login");
  const page = david.page;
  await page.getByRole("button", { name: "Start workout" }).click();
  await page
    .getByRole("button", { name: /A 5-minute warm-up is recommended/ })
    .click();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("10");
  await expect(
    page.getByText("Synced securely", { exact: true }),
  ).toBeVisible();
  await page.route(
    "**/api/workouts",
    (route) =>
      route.fulfill({
        status: 503,
        contentType: "application/json",
        body: JSON.stringify({ error: "Temporary test failure" }),
      }),
    { times: 1 },
  );
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("11");
  await expect(page.locator(".error-banner")).toBeVisible();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toHaveValue("11");
  await page.getByRole("button", { name: "Retry save", exact: true }).click();
  await expect(
    page.getByText("Synced securely", { exact: true }),
  ).toBeVisible();
  await expect(page.locator(".error-banner")).toHaveCount(0);
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("10");
  ok(
    "Network-save failure preserves entries and explicit retry recovers cleanly",
  );
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 kg total",
      exact: true,
    })
    .fill("6");
  await page
    .getByRole("button", {
      name: "Complete Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  await expect(page.getByText("Synced securely", { exact: true })).toBeVisible({
    timeout: 15000,
  });
  const payload = await (
    await second.context.request.get(base + "/api/workouts?profile=David")
  ).json();
  expect(payload.data.sessions[0].sets.press[0].done).toBe(true);
  ok("Completed set persists to real database and independent session");
  await second.page.reload();
  await second.page
    .getByRole("button", { name: "Resume workout", exact: true })
    .click();
  await expect(
    second.page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toHaveValue("10");
  ok("Reload resumes verified session and cloud data");
  expect(
    (
      await mary.context.request.get(base + "/api/workouts?profile=David")
    ).status(),
  ).toBe(403);
  expect(
    (
      await david.context.request.get(base + "/api/workouts?profile=Mary")
    ).status(),
  ).toBe(403);
  expect(
    (
      await (
        await mary.context.request.get(base + "/api/workouts?profile=Mary")
      ).json()
    ).data.sessions,
  ).toHaveLength(0);
  ok("Personal profiles remain isolated");
  expect(
    (
      await david.context.request.put(base + "/api/workouts", {
        headers: { Origin: base },
        data: { profile: "Mary", data: payload.data, revision: 0 },
      })
    ).status(),
  ).toBe(403);
  expect(
    (
      await second.context.request.put(base + "/api/workouts", {
        headers: { Origin: base },
        data: { profile: "David", data: payload.data, revision: 0 },
      })
    ).status(),
  ).toBe(409);
  expect(
    (
      await david.context.request.put(base + "/api/workouts", {
        headers: { Origin: "https://invalid.example" },
        data: {
          profile: "David",
          data: payload.data,
          revision: payload.revision,
        },
      })
    ).status(),
  ).toBe(403);
  ok("Cross-profile, stale-revision and cross-origin writes denied");
  step = "native bearer security and workout sync";
  nativeToken = await verifyNativeHTTP({
    onStep: (label) => {
      step = label;
    },
    base,
    email: emails[0],
    password,
    cookie: (await david.context.cookies(base))
      .map((item) => `${item.name}=${item.value}`)
      .join("; "),
  });
  ok(
    "Native signed bearer login, originless sync, conflict protection, isolation and logout; mixed/unsigned credentials denied",
  );
  if (process.env.RUN_IOS_INTEGRATION === "1") {
    step = "Swift and UIKit simulator integration";
    await verifyIOS({ base, emails, password, run });
    ok(
      "Swift URLSession/Keychain and UIKit workout logging, recovery, persistent rest timer, interactive guides, sync, relaunch and sign-out on iPhone simulator",
    );
  }
  step = "forgot password request";
  const resetContext = await browser.newContext(),
    resetPage = await resetContext.newPage();
  await resetPage.goto(base);
  await resetPage.getByRole("button", { name: "Choose David" }).click();
  await resetPage
    .getByRole("button", { name: "Forgot password?", exact: true })
    .click();
  await resetPage
    .getByRole("textbox", { name: "Email address" })
    .fill(emails[0]);
  const resetResponse = resetPage.waitForResponse((response) =>
    response.url().endsWith("/api/auth/request-password-reset"),
  );
  await resetPage
    .getByRole("button", { name: "Send password reset link" })
    .click();
  const known = await (await resetResponse).json();
  await expect(
    resetPage.getByRole("heading", { name: "Check your inbox." }),
  ).toBeVisible();
  const unknown = await resetContext.request.post(
    base + "/api/auth/request-password-reset",
    {
      headers: { Origin: base },
      data: {
        email: "uninvited@example.invalid",
        redirectTo: base + "/reset-password",
      },
    },
  );
  expect(unknown.status()).toBe(200);
  expect(await unknown.json()).toEqual(known);
  ok("Forgot Password uses the same generic response for unknown addresses");
  step = "password reset";
  const resetUrl = mail(emails[0], "reset").url;
  await resetPage.goto(resetUrl);
  const token = new URL(resetPage.url()).searchParams.get("token");
  await resetPage.getByLabel("New password", { exact: true }).fill(newPassword);
  await resetPage
    .getByLabel("Confirm password", { exact: true })
    .fill(newPassword + "x");
  await resetPage.getByRole("button", { name: "Reset my password" }).click();
  await expect(resetPage.locator(".error-text")).toContainText("don’t match");
  await resetPage
    .getByLabel("Confirm password", { exact: true })
    .fill(newPassword);
  await resetPage.getByRole("button", { name: "Reset my password" }).click();
  await expect(
    resetPage.getByRole("heading", { name: "A fresh start, saved." }),
  ).toBeVisible();
  ok(
    "Reset rejects mismatched confirmation and accepts the verified single-use link",
  );
  expect(
    (
      await second.context.request.get(base + "/api/workouts?profile=David")
    ).status(),
  ).toBe(401);
  ok("Successful password reset revokes an existing independent session");
  expect(
    (
      await fetch(base + "/api/account", {
        headers: { Authorization: `Bearer ${nativeToken}` },
      })
    ).status,
  ).toBe(401);
  ok("Password reset revokes native bearer sessions too");
  expect(
    (
      await resetContext.request.post(base + "/api/auth/sign-in/email", {
        headers: { Origin: base },
        data: { email: emails[0], password },
      })
    ).status(),
  ).toBe(401);
  const current = await signin("David", emails[0], newPassword);
  ok("Old password denied; new password signs in without losing workout data");
  expect(
    (
      await resetContext.request.post(base + "/api/auth/reset-password", {
        headers: { Origin: base },
        data: { token, newPassword: password },
      })
    ).status(),
  ).toBe(400);
  expect(
    (
      await resetContext.request.post(base + "/api/auth/reset-password", {
        headers: { Origin: base },
        data: { token: "invalid-token", newPassword: password },
      })
    ).status(),
  ).toBe(400);
  ok("Used and invalid reset tokens rejected");
  step = "expired reset token";
  await resetContext.request.post(base + "/api/auth/request-password-reset", {
    headers: { Origin: base },
    data: { email: emails[0], redirectTo: base + "/reset-password" },
  });
  const expiredToken = new URL(mail(emails[0], "reset").url).pathname
      .split("/")
      .at(-1),
    user = (
      await pool.query('SELECT id FROM "user" WHERE email=$1', [emails[0]])
    ).rows[0];
  await pool.query(
    'UPDATE verification SET "expiresAt"=$1 WHERE value=$2 AND identifier LIKE $3',
    [new Date(Date.now() - 60000), user.id, "reset-password:%"],
  );
  expect(
    (
      await resetContext.request.post(base + "/api/auth/reset-password", {
        headers: { Origin: base },
        data: { token: expiredToken, newPassword: password },
      })
    ).status(),
  ).toBe(400);
  ok("Expired reset token rejected");
  step = "logout";
  await current.page.route(
    "**/api/auth/sign-out",
    (route) =>
      route.fulfill({
        status: 429,
        contentType: "application/json",
        body: JSON.stringify({
          code: "TOO_MANY_REQUESTS",
          message: "Please retry shortly",
        }),
      }),
    { times: 1 },
  );
  await current.page
    .getByRole("button", { name: "Switch profile", exact: true })
    .filter({ visible: true })
    .first()
    .click();
  await expect(current.page.locator(".error-banner")).toContainText(
    "Could not sign out yet",
  );
  expect(
    (
      await current.context.request.get(base + "/api/workouts?profile=David")
    ).status(),
  ).toBe(200);
  ok("Failed logout stays visibly signed in instead of claiming success");
  await current.page
    .getByRole("button", { name: "Switch profile", exact: true })
    .filter({ visible: true })
    .first()
    .click();
  await expect(
    current.page.getByRole("button", { name: "Choose David" }),
  ).toBeVisible();
  expect(
    (
      await current.context.request.get(base + "/api/workouts?profile=David")
    ).status(),
  ).toBe(401);
  ok("Logout clears the server session");
  if (process.env.INTEGRATION_REMOTE_URL) {
    step = "protected deployed preview verification";
    const remote = new URL(process.env.INTEGRATION_REMOTE_URL).origin;
    if (
      !/^https:\/\/together-strong-[a-z0-9]+-david-adokurus-projects\.vercel\.app$/.test(
        remote,
      ) ||
      !process.env.VERCEL_OIDC_TOKEN
    )
      throw Error(
        "Expected this app's protected preview and short-lived OIDC authentication",
      );
    const remoteContext = async (mobile = false) => {
      const context = await browser.newContext(
        mobile
          ? {
              viewport: { width: 390, height: 844 },
              isMobile: true,
              hasTouch: true,
            }
          : {},
      );
      await context.route(remote + "/**", (route) =>
        route.continue({
          headers: {
            ...route.request().headers(),
            "x-vercel-trusted-oidc-idp-token": process.env.VERCEL_OIDC_TOKEN,
          },
        }),
      );
      for (const method of ["get", "post", "put"]) {
        const original = context.request[method].bind(context.request);
        context.request[method] = (url, options = {}) => {
          if (new URL(url).origin !== remote)
            throw Error("Unexpected request origin");
          return original(url, {
            ...options,
            maxRedirects: 0,
            headers: {
              ...options.headers,
              "x-vercel-trusted-oidc-idp-token": process.env.VERCEL_OIDC_TOKEN,
            },
          });
        };
      }
      return context;
    };
    const remoteSignin = async (profile, email, pwd) => {
      const context = await remoteContext(profile === "Mary"),
        page = await context.newPage();
      await page.goto(remote);
      await page.getByRole("button", { name: `Choose ${profile}` }).click();
      await page.getByRole("textbox", { name: "Email address" }).fill(email);
      await page.getByLabel("Password", { exact: true }).fill(pwd);
      await page
        .getByRole("button", { name: "Sign in & get stronger" })
        .click();
      await expect(
        page.getByRole("heading", { name: "Today’s workout" }),
      ).toBeVisible({ timeout: 20000 });
      return { context, page };
    };
    const remoteAnon = await remoteContext();
    expect(
      (
        await remoteAnon.request.get(remote + "/api/workouts?profile=David")
      ).status(),
    ).toBe(401);
    ok(
      "Deployed preview denies app data after Vercel protection authentication",
    );
    const remoteDavid = await remoteSignin("David", emails[0], newPassword),
      remoteMary = await remoteSignin("Mary", emails[1], password);
    ok(
      "Deployed desktop and mobile profiles sign in with verified test identities",
    );
    const remotePage = remoteDavid.page;
    await remotePage
      .getByRole("button", { name: "Resume workout", exact: true })
      .click();
    await remotePage
      .getByRole("spinbutton", {
        name: "Dumbbell floor press set 2 reps",
        exact: true,
      })
      .fill("11");
    await remotePage
      .getByRole("spinbutton", {
        name: "Dumbbell floor press set 2 kg total",
        exact: true,
      })
      .fill("6");
    await remotePage
      .getByRole("button", {
        name: "Complete Dumbbell floor press set 2",
        exact: true,
      })
      .click();
    await expect(
      remotePage.getByText("Synced securely", { exact: true }),
    ).toBeVisible({ timeout: 20000 });
    expect(
      (
        await (
          await mary.context.request.get(base + "/api/workouts?profile=Mary")
        ).json()
      ).data.sessions,
    ).toHaveLength(0);
    const fromLocal = await (
      await (
        await signin("David", emails[0], newPassword)
      ).context.request.get(base + "/api/workouts?profile=David")
    ).json();
    expect(fromLocal.data.sessions[0].sets.press[1].done).toBe(true);
    ok(
      "Deployed set update is visible from an independent local database-backed session",
    );
    expect(
      (
        await remoteMary.context.request.get(
          remote + "/api/workouts?profile=David",
        )
      ).status(),
    ).toBe(403);
    expect(
      (
        await remoteDavid.context.request.put(remote + "/api/workouts", {
          headers: { Origin: remote },
          data: { profile: "David", data: fromLocal.data, revision: 0 },
        })
      ).status(),
    ).toBe(409);
    ok("Deployed profile isolation and stale-write protection hold");
    const maryPage = remoteMary.page;
    await maryPage
      .getByRole("combobox", { name: "Beginner sets per exercise" })
      .selectOption("1");
    await expect(
      maryPage.getByText("Synced securely", { exact: true }),
    ).toBeVisible();
    await maryPage
      .getByRole("button", { name: "Start warm-up", exact: true })
      .click();
    await maryPage
      .getByRole("button", { name: "Start workout now", exact: true })
      .click();
    await expect(
      maryPage.getByRole("heading", { name: "Log your sets" }),
    ).toBeFocused();
    await expect(
      maryPage.getByRole("button", { name: "Finish workout", exact: true }),
    ).toBeDisabled();
    await maryPage
      .getByRole("button", { name: "Save progress", exact: true })
      .click();
    await expect(
      maryPage.getByText(
        "Draft saved. No workout or streak has been recorded.",
      ),
    ).toBeVisible();
    await maryPage
      .getByRole("button", { name: "Save & pause", exact: true })
      .click();
    await maryPage.reload();
    await maryPage
      .getByRole("button", { name: "Open saved draft", exact: true })
      .click();
    await expect(
      maryPage.getByRole("spinbutton", {
        name: "One-arm dumbbell row set 1 reps",
        exact: true,
      }),
    ).toBeEnabled();
    const maryDraft = await (
      await remoteMary.context.request.get(
        remote + "/api/workouts?profile=Mary",
      )
    ).json();
    expect(maryDraft.data.sessions).toHaveLength(1);
    expect(maryDraft.data.sessions[0].completedAt).toBeUndefined();
    expect(
      Object.values(maryDraft.data.sessions[0].sets)
        .flat()
        .filter((set) => set.done),
    ).toHaveLength(0);
    expect(Object.values(maryDraft.data.sessions[0].sets).flat()).toHaveLength(
      7,
    );
    ok(
      "Deployed phone preference-save, optional warm-up and empty-draft save/reload/resume preserve zero workout count",
    );
    await remotePage
      .locator(".exercise-card")
      .first()
      .locator(".how-to > summary")
      .click();
    await remotePage
      .getByRole("button", { name: "Play Dumbbell floor press demonstration" })
      .click();
    await expect(remotePage.locator('[data-animated="true"]')).toBeVisible();
    await remotePage
      .getByRole("button", { name: "Pause Dumbbell floor press demonstration" })
      .click();
    ok("Deployed animation play and pause controls work");
    await remotePage
      .getByRole("button", { name: "Switch profile", exact: true })
      .filter({ visible: true })
      .first()
      .click();
    await expect(
      remotePage.getByRole("button", { name: "Choose David" }),
    ).toBeVisible();
    expect(
      (
        await remoteDavid.context.request.get(
          remote + "/api/workouts?profile=David",
        )
      ).status(),
    ).toBe(401);
    ok("Deployed logout clears authenticated API access");
    expect(
      await remoteMary.page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    ).toBe(true);
    ok("Deployed phone layout stays within viewport");
  }
  writeFileSync(
    ".private/integration-report.json",
    JSON.stringify(
      {
        passed: passed.length,
        checks: passed,
        emailTransport: "local private test outbox; no real messages sent",
      },
      null,
      2,
    ),
    { mode: 0o600 },
  );
} catch (error) {
  const diagnostic = String(error)
    .split("Call log:")[0]
    .slice(0, 1600)
    .replaceAll(password, "[private test input]")
    .replaceAll(newPassword, "[private test input]")
    .replaceAll(emails[0], "[synthetic David]")
    .replaceAll(emails[1], "[synthetic Mary]")
    .replace(/https?:\/\/[^\s\"']+/g, "[private URL]");
  writeFileSync(
    path.join(".private", `integration-error-${run}.txt`),
    `${step}\n${diagnostic}\n`,
    { mode: 0o600 },
  );
  console.error(
    `Integration verification failed during: ${step}. Private input and token diagnostics are deliberately omitted.`,
  );
  process.exitCode = 1;
} finally {
  const users = await pool.query(
    'SELECT id,email FROM "user" WHERE email=ANY($1::text[])',
    [emails],
  );
  for (const user of users.rows) {
    await pool.query("DELETE FROM workout_data WHERE user_id=$1", [user.id]);
    await pool.query('DELETE FROM session WHERE "userId"=$1', [user.id]);
    await pool.query('DELETE FROM account WHERE "userId"=$1', [user.id]);
    await pool.query(
      "DELETE FROM verification WHERE value=$1 OR value LIKE $2",
      [user.id, "%" + user.email + "%"],
    );
    await pool.query('DELETE FROM "user" WHERE id=$1 AND email=$2', [
      user.id,
      user.email,
    ]);
  }
  console.log(
    `Cleaned ${users.rows.length} precisely identified synthetic test accounts; no real accounts changed.`,
  );
  if (existsSync(outbox)) unlinkSync(outbox);
  await pool.end();
  if (browser) await browser.close();
  server.kill("SIGTERM");
}
