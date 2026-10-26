# Together Strong

A mobile-first home workout companion for two people. Separate profiles, beginner ramp-up, per-set reps and kg, exercise position guides, session history, consistency, progress and a rest timer.

Built with Next.js, React, TypeScript, PostgreSQL and Better Auth. No paid service is required by the source. Hosting and database resources require a separately approved provider setup.

## Run locally

Use Node.js 24 LTS or later.

```sh
npm ci
npm run build
npm run start -- --port 3187
```

Open http://127.0.0.1:3187. Without cloud configuration, the local preview offers browser-local storage after choosing a profile. This preview is disabled on Vercel. Browser storage is not authentication and does not sync. Real cloud mode never falls back to local storage when a cloud request fails.

For development, use `npm run dev`. The isolated local preview can run without cloud resources. Do not run migrations until the new database target and required credentials have been approved and verified.

## Private cross-device setup

1. Create a **new** Vercel project in the approved personal workspace. Never reuse an existing project or its database.
2. Provision a **new** Neon Free resource from Vercel Marketplace, plan `free_v3`, with Neon Auth disabled. Better Auth runs in this app and stores users, sessions and shared rate limits in the same Postgres database.
3. Set the server-only keys listed in `.env.example`. Use separate invited email addresses. Generate a high-entropy Better Auth secret and separate private invitation codes using a secure process, only after credential setup is approved. Never put any of these values in source control or `NEXT_PUBLIC_*` variables.
4. Set `BETTER_AUTH_URL` in Production to the exact production origin. Keep it unset in Preview, as Better Auth infers the request origin. Pull Development env values to an ignored `.env.local` file without printing them.
5. Apply the reviewed schema only to the new database:

```sh
MIGRATION_TARGET_CONFIRM=together-strong node --env-file=.env.local scripts/migrate.mjs
```

6. Deploy. Each person chooses their profile, selects first-time setup, and enters their invited email, private invitation code and a password of at least 12 characters. Deliver invitation codes privately. Open registration is denied, and uninvited emails cannot register. A code alone does not select another person's data. Existing-account creation is prevented by Better Auth's unique email constraint.
7. Verify signup/signin, logout, two independent browser contexts, cross-device persistence, unauthorized requests, cross-profile access denial and concurrent-write conflicts on the actual database and deployment before claiming it is ready.

Passwords are hashed by Better Auth. Sessions use its secure cookie handling. Every workout API request derives the user and allowed profile from the server-verified session; selecting a profile grants no access. A database row belongs to an authenticated user, and a revision check prevents one device silently replacing another device's newer log. Changes remain visibly unsaved after a failed request. The current app supports password sign-in; password reset email delivery is not configured. Keep credentials in a password manager, and arrange account recovery privately with the app owner if needed.

## Workout conventions

- Suggested days: Monday, Wednesday, Friday, with a recovery day between sessions.
- First two weeks: 1–2 sets per exercise. Week three onwards: the full listed plan. The clock begins at the first session.
- **All kg entries are total held.** For two dumbbells, add their weights together. For one-arm rows/kickbacks or goblet squats, enter the single dumbbell's kg. No load is prefilled; whether the equipment's 20 kg is per dumbbell or total is not assumed.
- One-sided exercises are logged as reps per side after completing both sides. Use the lower rep count if the sides differ.
- Original SVG guides show simplified start/end positions. Text instructions explain range and breathing. No copied exercise imagery, tracking scripts or public workout logs are included.
- Sessions are limited to one per local calendar day; repeated start or finish taps do not create duplicates. Today’s completed session can be reopened from history. Previous days remain a record of what was done.
- Warm up, secure collars, leave 2–3 good reps in reserve, and stop with pain. Core exercises do not spot-reduce fat.

## Checks

```sh
npm run typecheck
npm run lint
npm run build
npx playwright install chromium
npm run test
```

Tests expect the app running on port 3187. Set `TEST_BASE_URL` for another target. Set `PLAYWRIGHT_CHROMIUM_EXECUTABLE` to reuse an existing Chromium binary. Browser tests use isolated contexts and generic local sample entries. They do not pretend to verify an unprovisioned cloud database. No traces or login state are published.

Before pushing public source, inspect `git diff --cached` and run `node scripts/check-public-source.mjs`. `.env*`, `.vercel`, test screenshots, logs, browser state and build artifacts are ignored. The secret scan supplements manual review; it is not a guarantee.

General training reference: [ACSM resistance training guidance](https://acsm.org/resistance-training-guidelines-update-2026/).
