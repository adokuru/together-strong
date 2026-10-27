import { test, expect } from "@playwright/test";
import { validCredentials, validWriteOrigin } from "../lib/request-identity";
import { parseData } from "../lib/workout";
import { readFileSync } from "node:fs";

test("native credential policy rejects mixed and malformed credentials", () => {
  for (const authorization of [
    "",
    "Basic abc",
    "Bearer",
    "Bearer a b",
    "Bearer  abc",
  ])
    expect(
      validCredentials(
        new Request("https://app.example/api/workouts", {
          headers: { authorization },
        }),
      ),
    ).toBe(false);
  expect(
    validCredentials(
      new Request("https://app.example/api/workouts", {
        headers: {
          authorization: "Bearer signed.token",
          cookie: "session=browser",
        },
      }),
    ),
  ).toBe(false);
  expect(
    validCredentials(
      new Request("https://app.example/api/workouts", {
        headers: { authorization: "Bearer signed.token" },
      }),
    ),
  ).toBe(true);
});

test("browser origin protection remains required while bearer identity is verified separately", () => {
  const request = (headers: Record<string, string>) =>
    new Request("https://app.example/api/workouts", { method: "PUT", headers });
  expect(validWriteOrigin(request({}))).toBe(false);
  expect(validWriteOrigin(request({ cookie: "session=browser" }))).toBe(false);
  expect(validWriteOrigin(request({ origin: "https://app.example" }))).toBe(
    true,
  );
  expect(validWriteOrigin(request({ origin: "http://app.example" }))).toBe(
    false,
  );
  expect(
    validWriteOrigin(
      request({
        origin: "https://other.example",
        authorization: "Bearer signed.token",
      }),
    ),
  ).toBe(false);
  expect(
    validWriteOrigin(request({ authorization: "Bearer signed.token" })),
  ).toBe(true);
  expect(
    validWriteOrigin(
      request({
        authorization: "Bearer signed.token",
        cookie: "session=browser",
      }),
    ),
  ).toBe(false);
});

test("the native transport fixture remains valid and preserves unknown JSON fields", () => {
  const fixture = JSON.parse(
    readFileSync("contracts/fixtures/workout-v1.json", "utf8"),
  );
  expect(parseData(fixture.data)).toEqual(fixture.data);
});

test("origin checks use the listener host and forwarded HTTPS protocol", () => {
  expect(
    validWriteOrigin(
      new Request("http://localhost:3187/api/workouts", {
        headers: { host: "127.0.0.1:3187", origin: "http://127.0.0.1:3187" },
      }),
    ),
  ).toBe(true);
  expect(
    validWriteOrigin(
      new Request("http://localhost/api/workouts", {
        headers: {
          host: "app.example",
          "x-forwarded-proto": "https",
          origin: "https://app.example",
        },
      }),
    ),
  ).toBe(true);
});
