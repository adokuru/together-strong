import { expect } from "@playwright/test";
import { spawn } from "node:child_process";
import {
  mkdirSync,
  writeFileSync,
  unlinkSync,
  createWriteStream,
  readFileSync,
} from "node:fs";
import path from "node:path";
import http from "node:http";

// Node fetch adds Sec-Fetch-Mode, unlike URLSession. Use actual native-style HTTP.
function nativeFetch(url, options = {}) {
  const target = new URL(url);
  if (target.protocol !== "http:" || target.hostname !== "127.0.0.1")
    throw Error(
      "Native integration requests must stay on the loopback server.",
    );
  return new Promise((resolve, reject) => {
    const request = http.request(target, options, (incoming) => {
      const chunks = [];
      incoming.on("data", (chunk) => chunks.push(chunk));
      incoming.on("error", reject);
      incoming.on("end", () => {
        const headers = new Headers();
        for (const [key, value] of Object.entries(incoming.headers)) {
          if (Array.isArray(value))
            value.forEach((item) => headers.append(key, item));
          else if (value !== undefined) headers.set(key, value);
        }
        resolve(
          new Response(Buffer.concat(chunks), {
            status: incoming.statusCode,
            headers,
          }),
        );
      });
    });
    request.on("error", reject);
    request.setTimeout(30000, () =>
      request.destroy(Error("Native test request timed out")),
    );
    request.end(options.body);
  });
}

export async function verifyNativeHTTP({
  base,
  email,
  password,
  cookie,
  onStep = () => {},
}) {
  const login = async () => {
    const response = await nativeFetch(base + "/api/auth/sign-in/email", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password }),
    });
    expect(response.status).toBe(200);
    const signed = response.headers.get("set-auth-token");
    expect(typeof signed).toBe("string");
    expect(signed).toContain(".");
    return { signed, raw: (await response.json()).token };
  };
  onStep("native sign-in and signed credential header");
  const { signed, raw } = await login();
  const headers = { Authorization: `Bearer ${signed}` };
  onStep("native account lookup");
  const account = await nativeFetch(base + "/api/account", { headers });
  expect(account.status).toBe(200);
  const identity = await account.json();
  expect(identity.profile).toBe("David");
  expect(typeof identity.userId).toBe("string");
  onStep("native workout load");
  const response = await nativeFetch(base + "/api/workouts?profile=David", {
    headers,
  });
  expect(response.status).toBe(200);
  const payload = await response.json();
  const save = async (credentialHeaders, profile = "David", origin) =>
    nativeFetch(base + "/api/workouts", {
      method: "PUT",
      headers: {
        "Content-Type": "application/json",
        ...credentialHeaders,
        ...(origin ? { Origin: origin } : {}),
      },
      body: JSON.stringify({
        profile,
        data: payload.data,
        revision: payload.revision,
      }),
    });
  onStep("native profile and browser origin restrictions");
  expect((await save(headers, "Mary")).status).toBe(403);
  expect((await save(headers, "David", "https://invalid.example")).status).toBe(
    403,
  );
  expect((await save({ Cookie: cookie })).status).toBe(403);
  onStep("unsigned and invalid native credentials");
  for (const authorization of [
    `Bearer ${raw}`,
    "Bearer invalid.signature",
    "Basic invalid",
  ]) {
    expect(
      (
        await nativeFetch(base + "/api/account", {
          headers: { Authorization: authorization },
        })
      ).status,
    ).toBe(401);
  }
  onStep("mixed browser and native credentials");
  for (const endpoint of ["/api/account", "/api/workouts?profile=David"]) {
    expect(
      (
        await nativeFetch(base + endpoint, {
          headers: { ...headers, Cookie: cookie },
        })
      ).status,
    ).toBe(401);
  }
  expect(
    (
      await nativeFetch(base + "/api/auth/sign-out", {
        method: "POST",
        headers: {
          ...headers,
          Cookie: cookie,
          "Content-Type": "application/json",
        },
        body: "{}",
      })
    ).status,
  ).toBe(401);
  onStep("native originless workout save and stale revision");
  const saved = await save(headers);
  expect(saved.status).toBe(200);
  expect((await saved.json()).revision).toBe(payload.revision + 1);
  expect((await save(headers)).status).toBe(409);
  onStep("native logout and revocation");
  expect(
    (
      await nativeFetch(base + "/api/auth/sign-out", {
        method: "POST",
        headers: { ...headers, "Content-Type": "application/json" },
        body: "{}",
      })
    ).status,
  ).toBe(200);
  expect((await nativeFetch(base + "/api/account", { headers })).status).toBe(
    401,
  );
  return (await login()).signed;
}

export async function verifyIOS({ base, emails, password, run }) {
  const folder = path.resolve(".private/ios");
  mkdirSync(folder, { recursive: true, mode: 0o700 });
  const config = path.join(folder, `live-${run}.json`);
  writeFileSync(config, JSON.stringify({ origin: base, emails, password }), {
    mode: 0o600,
  });
  const logPath = path.join(folder, `live-${run}.log`);
  const log = createWriteStream(logPath, {
    mode: 0o600,
  });
  try {
    const args = [
      "-project",
      "ios/TogetherStrong.xcodeproj",
      "-scheme",
      "TogetherStrong",
      "-configuration",
      "Debug",
      "-destination",
      process.env.IOS_TEST_DESTINATION ??
        "platform=iOS Simulator,name=iPhone 17 Pro",
      "-derivedDataPath",
      ".private/ios/build",
      "-parallel-testing-enabled",
      "NO",
      "CODE_SIGNING_ALLOWED=YES",
      "CODE_SIGN_IDENTITY=-",
      "test",
    ];
    const exit = await new Promise((resolve, reject) => {
      const child = spawn("xcodebuild", args, {
        stdio: ["ignore", "pipe", "pipe"],
        env: { ...process.env, TEST_RUNNER_TS_LIVE_CONFIG: config },
      });
      child.stdout.pipe(log, { end: false });
      child.stderr.pipe(log, { end: false });
      child.on("error", reject);
      child.on("close", resolve);
    });
    await new Promise((resolve, reject) => {
      log.on("error", reject);
      log.end(resolve);
    });
    if (exit !== 0)
      throw Error("Native checks failed. Inspect the owner-only iOS test log.");
    const output = readFileSync(logPath, "utf8");
    if (
      !/Test realBackendAuthenticationAndWorkoutRoundTrip\(\) passed/.test(
        output,
      ) ||
      !/Test Case .*testLiveSignInSyncRestoreAndSignOut.* passed/.test(output)
    )
      throw Error(
        "Required live native checks did not run successfully; skipped tests cannot satisfy this milestone.",
      );
  } finally {
    unlinkSync(config);
    if (!log.writableEnded) log.end();
  }
}
