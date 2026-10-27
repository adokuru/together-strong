# Together Strong

A mobile-first home workout companion for two people. Separate profiles, beginner ramp-up, per-set reps and kg, exercise position guides, session history, consistency, progress and a rest timer.

Built with Next.js, React, TypeScript, PostgreSQL and Better Auth. No paid service is required by the source. Hosting and database resources require a separately approved provider setup.

## Run locally

Use Node.js 24 LTS.

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
3. Set the server-only keys listed in `.env.example`. Use separate invited email addresses. Generate a high-entropy Better Auth secret and configure an approved Mailgun sender/API key, only after credential setup is approved. Never put any of these values in source control or `NEXT_PUBLIC_*` variables.
4. Set `BETTER_AUTH_URL` in Production to the exact production origin. Keep it unset in Preview, as Better Auth infers the request origin. Pull Development env values to an ignored `.env.local` file without printing them.
5. Apply the reviewed schema only to the new database:

```sh
MIGRATION_TARGET_CONFIRM=together-strong node --env-file=.env.local scripts/migrate.mjs
```

6. Deploy. Each person chooses a profile and requests a private setup email. The single-use link expires in 15 minutes. Its confirmation page requires an explicit click so mail scanners do not consume it. Only after verifying the invited mailbox can the person choose a password of at least 12 characters. Direct password signup is disabled. Uninvited addresses cannot create accounts, and requesting a setup email does not claim an identity.
7. Verify signup/signin, logout, two independent browser contexts, cross-device persistence, unauthorized requests, cross-profile access denial and concurrent-write conflicts on the actual database and deployment before claiming it is ready.

Passwords are hashed by Better Auth. Sessions use its secure cookie handling. Every workout API request derives the user and allowed profile from the server-verified session; selecting a profile grants no access. A database row belongs to an authenticated user, and a revision check prevents one device silently replacing another device's newer log. Changes remain visibly unsaved after a failed request. Forgot Password returns the same generic response for unknown addresses. Reset links expire in 15 minutes, work once, and revoke existing sessions when successfully used. Password confirmation is checked before submitting. Mailgun link/open tracking is disabled for private auth emails. Mail delivery must be verified against the approved provider before claiming a setup email arrived.

## Workout conventions

- Suggested days: Monday, Wednesday, Friday, with a recovery day between sessions.
- First two weeks: 1–2 sets per exercise. Week three onwards: the full listed plan. The clock begins when the first set is marked complete; opening or saving an empty draft does not advance it.
- **All kg entries are total held.** For two dumbbells, add their weights together. For one-arm rows/kickbacks or goblet squats, enter the single dumbbell's kg. No load is prefilled; whether the equipment's 20 kg is per dumbbell or total is not assumed.
- One-sided exercises are logged as reps per side after completing both sides. Use the lower rep count if the sides differ.
- Original shaded SVG people show exercise-specific start, middle and finish positions and optional joint-based animation. Play/pause, slow speed, a position scrubber and reset are provided. Verified instructor or technique links supplement each guide. Limbs keep constant lengths; the RDL hinges at the hips and the moving heel stays grounded. Reduced-motion users see static positions until they explicitly choose Play. Text instructions explain range and breathing. No copied exercise imagery, tracking scripts or public workout logs are included.
- Repeated start or finish taps do not create duplicate active sessions. Empty saves stay drafts and never count as workouts or consistency. Save progress, Save & pause and Finish workout have separate actions. Older unfinished sessions resume with their original recorded date; completed training counts on its finish date. Empty drafts can be explicitly discarded and recovered without deleting their stored entries. Today’s completed session can be reopened from history.
- Warm-up is recommended and available before starting. Choose Start warm-up, I’ve warmed up or Skip for now; no timer or completion checkbox blocks logging.
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

Run the opt-in real-database authentication checks only against the isolated app database:

```sh
RUN_DB_INTEGRATION=1 CONFIRM_TEST_DB=together-strong npm run test:integration
```

This starts a loopback-only test server on port 3191 with unique synthetic invited identities. Email setup/reset links go to an owner-only local `.private/` test outbox, never to real recipients. The suite verifies mailbox proof before account creation, setup-token replay denial, password confirmation, real database sync and isolation, generic Forgot Password responses, invalid/expired/used reset-token rejection, session revocation, old/new password behavior, save-failure retry and logout. Browser regressions also cover preference-save entry, every warm-up path, empty-draft pause/reload, older draft recovery, repeated taps, recoverable discard and no false completions. It removes only its precisely identified synthetic accounts, records and outbox. Real household accounts are not changed. The local outbox is hard-disabled on Vercel. A passing test outbox does **not** prove real Mailgun delivery. Optional `INTEGRATION_REMOTE_URL`, `INTEGRATION_DAVID_EMAIL` and `INTEGRATION_MARY_EMAIL` run the critical checks against a protected preview of this same app with matching synthetic email overrides. The preview must use the same isolated database. Existing short-lived Vercel OIDC authentication is added only to that preview origin; Deployment Protection stays enabled. The test refuses pre-existing test identities and leaves real accounts alone.

Before pushing public source, inspect `git diff --cached` and run `node scripts/check-public-source.mjs`. `.env*`, `.vercel`, test screenshots, logs, browser state and build artifacts are ignored. The secret scan supplements manual review; it is not a guarantee.

General training reference: [ACSM resistance training guidance](https://acsm.org/resistance-training-guidelines-update-2026/).

## Native iPhone application

The Swift/UIKit project is in `ios/TogetherStrong.xcodeproj`. The native app implements private sign-in, Keychain restoration, full workout logging, draft recovery and revision-protected sync. It includes a persistent rest timer, animated guides for all seven exercises, calendar history with session filters, weekly consistency and interactive exercise progress charts. The existing Next.js backend supports signed bearer sessions for the native client while retaining browser origin checks.

See [the iOS setup and verification guide](ios/README.md) and [the mobile app plan](docs/MOBILE_APP_PLAN.md). API deployment, Apple signing, physical-device validation and TestFlight distribution are separate from local builds and simulator checks.
