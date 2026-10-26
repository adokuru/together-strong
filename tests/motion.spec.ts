import { test, expect } from "@playwright/test";
import { exercisePose } from "../lib/exercise-motion";
import { routine } from "../lib/workout";
const segments = (polyline: string) => {
  const pts = polyline.split(" ").map((s) => s.split(",").map(Number));
  return pts
    .slice(1)
    .map((p, i) => Math.hypot(p[0] - pts[i][0], p[1] - pts[i][1]));
};
test("joint motion preserves limb lengths and grounded contacts", () => {
  for (const e of routine("David")) {
    const start = exercisePose(e.id, 0);
    for (const t of [0.2, 0.4, 0.6, 0.8, 1]) {
      const pose = exercisePose(e.id, t);
      const first = [start.body, ...start.arms, ...start.legs].flatMap(
          segments,
        ),
        next = [pose.body, ...pose.arms, ...pose.legs].flatMap(segments);
      next.forEach((length, i) =>
        expect(Math.abs(length - first[i])).toBeLessThan(0.01),
      );
      if (["press", "row", "kickback", "curl", "heel"].includes(e.id)) {
        expect(pose.head).toEqual(start.head);
        expect(pose.body).toEqual(start.body);
      }
      if (e.id === "heel")
        expect(pose.legs[1].split(" ").at(-1)!.split(",")[1]).toBe("122.000");
      if (e.id === "rdl") {
        const hipHeight = Number(pose.body.split(" ")[1].split(",")[1]);
        expect(hipHeight).toBeGreaterThanOrEqual(71);
        expect(hipHeight).toBeLessThanOrEqual(73);
      }
    }
  }
});
test("exercise demo play, pause, slow speed and reset controls", async ({
  page,
}) => {
  await page.goto("/");
  await page.getByRole("button", { name: "Choose David" }).click();
  await page.getByRole("button", { name: "Try on this device" }).click();
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .click();
  await page
    .locator(".exercise-card")
    .first()
    .locator(".how-to > summary")
    .click();
  await expect(
    page.getByRole("button", { name: /^Play .* demonstration$/ }),
  ).toHaveAttribute("aria-pressed", "false");
  await page
    .getByRole("button", { name: "Play Dumbbell floor press demonstration" })
    .click();
  const limbs = page.locator('[data-animated="true"]');
  const initial = await limbs.getAttribute("data-progress");
  await expect
    .poll(() => limbs.getAttribute("data-progress"))
    .not.toBe(initial);
  await page
    .getByRole("button", { name: "Pause Dumbbell floor press demonstration" })
    .click();
  const paused = await limbs.getAttribute("data-progress");
  await page.waitForTimeout(200);
  await expect(limbs).toHaveAttribute("data-progress", paused!);
  await page
    .getByRole("combobox", { name: "Dumbbell floor press demonstration speed" })
    .selectOption("1");
  await page
    .getByRole("button", { name: "Reset Dumbbell floor press demonstration" })
    .click();
  await expect(limbs).toHaveAttribute("data-progress", "0.000");
  await page
    .getByRole("slider", { name: "Dumbbell floor press movement position" })
    .press("End");
  await expect(limbs).toHaveAttribute("data-progress", "1.000");
  await page
    .getByRole("button", { name: "Start position", exact: true })
    .click();
  await expect(limbs).toHaveAttribute("data-progress", "0.000");
});
test("reduced motion keeps demonstrations static until requested", async ({
  page,
}) => {
  await page.emulateMedia({ reducedMotion: "reduce" });
  await page.goto("/");
  await page.getByRole("button", { name: "Choose Mary" }).click();
  await page.getByRole("button", { name: "Try on this device" }).click();
  await page
    .getByRole("button", { name: "Start workout", exact: true })
    .click();
  await page
    .locator(".exercise-card")
    .first()
    .locator(".how-to > summary")
    .click();
  await expect(
    page.getByText(
      "Reduced motion is on. Use the slider or choose Play when you’re ready.",
    ),
  ).toBeVisible();
  await expect(
    page.getByRole("button", { name: /^Play .* demonstration$/ }),
  ).toHaveAttribute("aria-pressed", "false");
});
