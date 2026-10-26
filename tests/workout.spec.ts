import { test, expect, Page } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";
import {
  counts,
  emptyData,
  makeSession,
  parseData,
  routine,
  weekNumber,
} from "../lib/workout";
async function enter(page: Page, profile = "David") {
  await page.getByRole("button", { name: `Choose ${profile}` }).click();
  await page.getByRole("button", { name: "Try on this device" }).click();
  await expect(
    page.getByRole("heading", { name: "Today’s workout" }),
  ).toBeVisible();
}
test("routine keeps personal emphasis and ramps up after two weeks", () => {
  for (const profile of ["David", "Mary"] as const) {
    expect(routine(profile)[0].id).toBe(profile === "David" ? "press" : "row");
    expect(routine(profile)[0].sets).toBe(3);
    const first = emptyData();
    expect(counts(makeSession(profile, first)).total).toBe(14);
    first.rampSets = 1;
    expect(counts(makeSession(profile, first)).total).toBe(7);
    first.startedAt = new Date(Date.now() - 15 * 86400000).toISOString();
    const trained = makeSession(profile, first);
    trained.sets[routine(profile)[0].id][0] = {
      reps: "10",
      kg: "0",
      done: true,
    };
    first.sessions = [trained];
    expect(weekNumber(first)).toBe(3);
    expect(counts(makeSession(profile, first)).total).toBe(15);
  }
});
test("saved data validation rejects duplicate sessions and invalid completed sets", () => {
  const data = emptyData();
  const session = makeSession("David", data);
  data.sessions = [session];
  expect(parseData(data)).not.toBeNull();
  data.sessions.push(session);
  expect(parseData(data)).toBeNull();
  data.sessions = [session];
  session.sets.press[0] = { reps: "-1", kg: "5", done: true };
  expect(parseData(data)).toBeNull();
  const malformed = {
    ...emptyData(),
    sessions: [
      {
        ...session,
        discardedAt: new Date().toISOString(),
        sets: { press: null },
      },
    ],
  };
  expect(() => parseData(malformed)).not.toThrow();
  expect(parseData(malformed)).toBeNull();
});
test("profile choice, empty history and narrow-screen layout", async ({
  page,
}) => {
  await page.goto("/");
  await expect(
    page.getByRole("button", { name: "Choose David" }),
  ).toBeVisible();
  await expect(page.getByRole("button", { name: "Choose Mary" })).toBeVisible();
  await page.screenshot({
    path: `test-results/welcome-${test.info().project.name}.png`,
    fullPage: true,
  });
  await enter(page, "Mary");
  await expect(page.locator(".routine-preview strong").first()).toHaveText(
    "One-arm dumbbell row",
  );
  await page
    .getByRole("link", { name: /History|Calendar & history/ })
    .filter({ visible: true })
    .first()
    .click();
  await expect(
    page.getByRole("heading", { name: "Your story starts with one session." }),
  ).toBeVisible();
  await expect
    .poll(() =>
      page.evaluate(
        () => document.documentElement.scrollWidth <= window.innerWidth,
      ),
    )
    .toBe(true);
  await page.screenshot({
    path: `test-results/history-${test.info().project.name}.png`,
    fullPage: true,
  });
});
test("sets save, undo, edit, reload and stay separate between profiles", async ({
  page,
}) => {
  await page.goto("/");
  await enter(page);
  await page
    .getByRole("combobox", { name: "Beginner sets per exercise" })
    .selectOption("1");
  await page.getByRole("button", { name: "Start workout" }).click();
  await expect(page.getByText("0/7 sets", { exact: true })).toBeVisible();
  await page
    .getByRole("button", { name: /A 5-minute warm-up is recommended/ })
    .click();
  await page
    .getByRole("button", {
      name: "Complete Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  await expect(page.locator(".toast")).toContainText("Enter reps and total kg");
  await page.getByRole("button", { name: "Dismiss notification" }).click();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("10");
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
  await expect(page.getByText("1/7 sets", { exact: true })).toBeVisible();
  await page
    .getByRole("button", {
      name: "Undo Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  await expect(page.getByText("0/7 sets", { exact: true })).toBeVisible();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("12");
  await page
    .getByRole("button", {
      name: "Complete Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "Try on this device" }).click();
  await page
    .getByRole("button", { name: /^(Open saved draft|Resume workout)$/ })
    .click();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toHaveValue("12");
  await expect(page.getByText("1/7 sets", { exact: true })).toBeVisible();
  await page
    .getByRole("button", { name: "Switch profile", exact: true })
    .filter({ visible: true })
    .first()
    .click();
  await enter(page, "Mary");
  await expect(
    page.getByRole("button", { name: "Start workout" }),
  ).toBeVisible();
  await expect(page.getByText("0/7 sets", { exact: true })).not.toBeVisible();
  await page.getByRole("button", { name: "Start workout" }).click();
  await expect(page.getByText("0/14 sets", { exact: true })).toBeVisible();
});
test("finish is idempotent, history and undo completion work", async ({
  page,
}) => {
  await page.goto("/");
  await enter(page);
  await page.getByRole("button", { name: "Start workout" }).dblclick();
  await page
    .getByRole("button", { name: /A 5-minute warm-up is recommended/ })
    .click();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("10");
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
  await page.getByRole("button", { name: "Finish workout" }).click();
  await page
    .getByRole("button", { name: "Save this session", exact: true })
    .dblclick();
  await expect(
    page.getByRole("heading", { name: "Good work. Make room for recovery." }),
  ).toBeVisible();
  const raw = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("together-strong:demo:David") ?? "{}"),
  );
  expect(raw.data.sessions).toHaveLength(1);
  await page.getByRole("button", { name: "View completed session" }).click();
  await expect(page.getByText("1 completed", { exact: true })).toBeVisible();
  await page.locator(".history-item").click();
  await page.getByRole("button", { name: "Undo session completion" }).click();
  await expect(
    page.getByRole("button", { name: "Finish workout" }),
  ).toBeVisible();
});
test("timer pause, resume, add time, reset and close", async ({ page }) => {
  await page.goto("/");
  await enter(page);
  await page.getByRole("button", { name: "Rest timer", exact: true }).click();
  await expect(page.getByRole("timer")).toHaveText("2:00");
  await page.getByRole("button", { name: "Start rest timer" }).click();
  await expect(page.getByRole("timer")).not.toHaveText("2:00", {
    timeout: 4000,
  });
  await page.getByRole("button", { name: "Pause rest timer" }).click();
  const paused = await page.getByRole("timer").textContent();
  await page.waitForTimeout(1100);
  await expect(page.getByRole("timer")).toHaveText(paused!);
  await page.getByRole("button", { name: "Add 30 seconds" }).click();
  await expect(page.getByRole("timer")).not.toHaveText(paused!);
  await page.getByRole("button", { name: "Reset rest timer" }).click();
  await expect(page.getByRole("timer")).toHaveText("2:00");
  await page.getByRole("button", { name: "Start rest timer" }).click();
  await page.getByRole("button", { name: "Close rest timer" }).click();
  await expect(page.getByRole("timer")).not.toBeVisible();
});
test("every exercise has labelled original visual guidance and browser back works", async ({
  page,
}) => {
  await page.goto("/");
  await enter(page);
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .click();
  for (const exercise of routine("David")) {
    const card = page
      .locator(".exercise-card")
      .filter({ has: page.getByText(exercise.name, { exact: true }) });
    if (
      (await card.locator(".exercise-head").getAttribute("aria-expanded")) !==
      "true"
    )
      await card.locator(".exercise-head").click();
    await card.locator(".how-to > summary").click();
    await expect(card.getByRole("img")).toHaveCount(1);
    await expect(
      card.getByText("Original movement illustration."),
    ).toBeVisible();
  }
  await page
    .getByRole("link", { name: /Progress|My progress/ })
    .filter({ visible: true })
    .first()
    .click();
  await expect(
    page.getByRole("heading", { name: "Look how far you’re going." }),
  ).toBeVisible();
  await page.goBack();
  await expect(
    page.getByRole("heading", { name: "Log your sets" }),
  ).toBeVisible();
  await page.screenshot({
    path: `test-results/workout-${test.info().project.name}.png`,
    fullPage: true,
  });
});
test("private endpoints deny unauthenticated reads and writes", async ({
  request,
}) => {
  expect((await request.get("/api/workouts?profile=David")).status()).toBe(401);
  expect((await request.get("/api/workouts?profile=Mary")).status()).toBe(401);
  expect(
    (
      await request.put("/api/workouts", {
        headers: { Origin: "http://127.0.0.1:3187" },
        data: { profile: "David", data: emptyData(), revision: 0 },
      })
    ).status(),
  ).toBe(401);
  expect([403, 503]).toContain(
    (
      await request.post("/api/auth/sign-up/email", {
        data: {
          email: "test@example.com",
          password: "example-only-password",
          name: "Test",
        },
      })
    ).status(),
  );
});
test("accessible profile choices, workout controls and exercise panels", async ({
  page,
}) => {
  await page.goto("/");
  expect(
    (
      await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze()
    ).violations.map((v) => ({
      id: v.id,
      nodes: v.nodes.map((n) => ({
        target: n.target,
        summary: n.failureSummary,
      })),
    })),
  ).toEqual([]);
  await enter(page);
  await page.getByRole("button", { name: "Start workout" }).click();
  await page
    .locator(".exercise-card")
    .first()
    .locator(".how-to > summary")
    .click();
  expect(
    (
      await new AxeBuilder({ page })
        .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
        .analyze()
    ).violations.map((v) => ({
      id: v.id,
      nodes: v.nodes.map((n) => ({
        target: n.target,
        summary: n.failureSummary,
      })),
    })),
  ).toEqual([]);
  await page.screenshot({
    path: `test-results/active-${test.info().project.name}.png`,
    fullPage: true,
  });
});
test("another tab cannot silently replace a newer workout", async ({
  page,
  context,
}) => {
  await page.goto("/");
  await enter(page);
  await page.getByRole("button", { name: "Start workout" }).click();
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  const second = await context.newPage();
  await second.goto("/");
  await enter(second);
  await second
    .getByRole("button", { name: "Open saved draft", exact: true })
    .click();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("11");
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  await second
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("8");
  await expect(second.locator(".error-banner")).toContainText(
    "changed in another tab",
  );
  await expect(second.getByText("Not saved", { exact: true })).toBeVisible();
  const raw = await page.evaluate(() =>
    JSON.parse(localStorage.getItem("together-strong:demo:David") ?? "{}"),
  );
  expect(raw.data.sessions[0].sets.press[0].reps).toBe("11");
  await second
    .getByRole("button", { name: "Reload latest", exact: true })
    .click();
  await second.getByRole("button", { name: "Try on this device" }).click();
  await second
    .getByRole("button", { name: "Open saved draft", exact: true })
    .click();
  await expect(
    second.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toHaveValue("11");
  await expect(second.locator(".error-banner")).toHaveCount(0);
});
