import { test, expect, Page } from "@playwright/test";
import { emptyData, makeSession, weekNumber } from "../lib/workout";
async function enter(page: Page) {
  await page.goto("/");
  await page.getByRole("button", { name: "Choose David" }).click();
  await page.getByRole("button", { name: "Try on this device" }).click();
}
const stored = (page: Page) =>
  page.evaluate(
    () =>
      JSON.parse(localStorage.getItem("together-strong:demo:David") ?? "{}")
        .data,
  );
test("preference save leaves warm-up and entry usable without claiming activity", async ({
  page,
}) => {
  await enter(page);
  await page
    .getByRole("combobox", { name: "Beginner sets per exercise" })
    .selectOption("1");
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  expect((await stored(page)).sessions).toHaveLength(0);
  await expect(
    page.getByRole("button", { name: "Start warm-up", exact: true }),
  ).toBeEnabled();
  await expect(
    page.getByRole("button", { name: "Start workout", exact: true }),
  ).toBeEnabled();
  await page
    .getByRole("button", { name: "Start warm-up", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Start workout now", exact: true }),
  ).toBeEnabled();
  await page
    .getByRole("button", { name: "Start workout now", exact: true })
    .click();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toBeEnabled();
  await expect(
    page.getByRole("heading", { name: "Log your sets" }),
  ).toBeFocused();
  await expect(
    page.getByRole("button", { name: "Start workout now", exact: true }),
  ).toHaveCount(0);
  expect((await stored(page)).sessions[0].warmupState).toBe("underway");
  expect((await stored(page)).sessions[0].completedAt).toBeUndefined();
});
for (const choice of ["I’ve warmed up", "Skip for now"])
  test(`warm-up entry via ${choice} creates a usable zero-activity draft`, async ({
    page,
  }) => {
    await enter(page);
    await page.getByRole("button", { name: choice, exact: true }).click();
    await expect(
      page.getByRole("spinbutton", {
        name: "Dumbbell floor press set 1 reps",
        exact: true,
      }),
    ).toBeEnabled();
    await expect(
      page.getByRole("button", { name: "Finish workout", exact: true }),
    ).toBeDisabled();
    const data = await stored(page);
    expect(data.sessions).toHaveLength(1);
    expect(data.sessions[0].warmupState).toBe(
      choice === "I’ve warmed up" ? "done" : "skipped",
    );
    expect(data.sessions[0].completedAt).toBeUndefined();
    expect(weekNumber(data)).toBe(1);
  });
test("save without exercise pauses as draft and resumes after reload and back navigation", async ({
  page,
}) => {
  await enter(page);
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .dblclick();
  await page
    .getByRole("button", { name: "Save progress", exact: true })
    .click();
  await expect(
    page.getByText("Draft saved. No workout or streak has been recorded."),
  ).toBeVisible();
  await page.getByRole("button", { name: "Save & pause", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Open saved draft", exact: true }),
  ).toBeVisible();
  await page.reload();
  await page.getByRole("button", { name: "Try on this device" }).click();
  await page
    .getByRole("button", { name: "Open saved draft", exact: true })
    .click();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toBeEnabled();
  expect((await stored(page)).sessions).toHaveLength(1);
  await page
    .getByRole("link", { name: /History|Calendar & history/ })
    .filter({ visible: true })
    .first()
    .click();
  await page.goBack();
  await expect(
    page.getByRole("heading", { name: "Log your sets" }),
  ).toBeVisible();
  expect((await stored(page)).sessions[0].completedAt).toBeUndefined();
});
test("older and legacy completed-empty drafts recover without redating or progressing program", async ({
  page,
}) => {
  await page.goto("/");
  const data = emptyData(),
    s = makeSession("David", data);
  s.date = "2026-09-20";
  s.startedAt = "2026-09-20T12:00:00.000Z";
  s.completedAt = "2026-09-20T12:05:00.000Z";
  data.startedAt = s.startedAt;
  data.sessions = [s];
  await page.evaluate(
    (value) =>
      localStorage.setItem(
        "together-strong:demo:David",
        JSON.stringify({ data: value, revision: 1 }),
      ),
    data,
  );
  await enter(page);
  await expect(
    page.getByRole("button", { name: "Open saved draft", exact: true }),
  ).toBeVisible();
  await expect(
    page.getByText("Full-body strength · Week 1 · No bench needed"),
  ).toBeVisible();
  await page
    .getByRole("button", { name: "Open saved draft", exact: true })
    .click();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toBeEnabled();
  await page.getByRole("button", { name: "Save & pause", exact: true }).click();
  const saved = await stored(page);
  expect(saved.sessions[0].date).toBe("2026-09-20");
  expect(saved.sessions[0].sets).toEqual(s.sets);
  expect(saved.sessions[0].completedAt).toBeUndefined();
  await page
    .getByRole("button", { name: "Open saved draft", exact: true })
    .click();
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("8");
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 kg total",
      exact: true,
    })
    .fill("0");
  await page
    .getByRole("button", {
      name: "Complete Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  const trained = await stored(page);
  expect(weekNumber(trained)).toBe(1);
  expect(trained.sessions[0].date).toBe("2026-09-20");
});
test("empty draft discard is explicit and recoverable; no false workout count", async ({
  page,
}) => {
  await enter(page);
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Discard empty draft", exact: true })
    .click();
  await expect(
    page.getByRole("alertdialog", { name: "Discard empty draft" }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Keep draft", exact: true }).click();
  expect((await stored(page)).sessions[0].discardedAt).toBeUndefined();
  await page
    .getByRole("button", { name: "Discard empty draft", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Discard draft", exact: true })
    .click();
  await expect(
    page.getByRole("button", { name: "Start workout", exact: true }),
  ).toBeVisible();
  await page.getByRole("button", { name: "Undo discard", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Open saved draft", exact: true }),
  ).toBeVisible();
  const data = await stored(page);
  expect(data.sessions).toHaveLength(1);
  expect(data.sessions[0].discardedAt).toBeUndefined();
  expect(data.sessions[0].completedAt).toBeUndefined();
});
test("skipping warm-up permits a real finish but saving zero sets never does", async ({
  page,
}) => {
  await enter(page);
  await page.getByRole("button", { name: "Skip for now", exact: true }).click();
  await expect(
    page.getByRole("button", { name: "Finish workout", exact: true }),
  ).toBeDisabled();
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
    .fill("0");
  await page
    .getByRole("button", {
      name: "Complete Dumbbell floor press set 1",
      exact: true,
    })
    .click();
  await page.getByRole("button", { name: "Save & pause", exact: true }).click();
  await expect(page.getByText("PAUSED SESSION", { exact: true })).toBeVisible();
  await page
    .getByRole("button", { name: "Resume workout", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Finish workout", exact: true })
    .click();
  await page
    .getByRole("button", { name: "Save this session", exact: true })
    .dblclick();
  const data = await stored(page);
  expect(data.sessions).toHaveLength(1);
  expect(data.sessions[0].completedAt).toBeTruthy();
  expect(data.sessions[0].warmup).toBe(false);
  expect(data.sessions[0].warmupState).toBe("skipped");
});
test("failed save retains entries and retry recovers without completion", async ({
  page,
}) => {
  await enter(page);
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .click();
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  await page.evaluate(() => {
    const original = Storage.prototype.setItem;
    Storage.prototype.setItem = function (k, v) {
      if (k === "together-strong:demo:David") {
        Storage.prototype.setItem = original;
        throw new Error("Temporary storage failure");
      }
      return original.call(this, k, v);
    };
  });
  await page
    .getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    })
    .fill("9");
  await expect(page.locator(".error-banner")).toBeVisible();
  await expect(
    page.getByRole("spinbutton", {
      name: "Dumbbell floor press set 1 reps",
      exact: true,
    }),
  ).toHaveValue("9");
  await page.getByRole("button", { name: "Retry save", exact: true }).click();
  await expect(
    page.getByText("Saved on this device", { exact: true }),
  ).toBeVisible();
  const data = await stored(page);
  expect(data.sessions[0].sets.press[0].reps).toBe("9");
  await expect(page.locator(".error-banner")).toHaveCount(0);
  expect(data.sessions[0].completedAt).toBeUndefined();
});
