# Together Strong for iPhone

Native Swift and UIKit app, with no third-party iOS dependencies. It supports private sign-in, Keychain session restoration, all seven exercises in each personal routine, warm-up choices, per-set logging, save/pause/finish, recoverable drafts, a persistent rest timer, animated guides, calendar history and interactive progress charts.

## Open and run

Open `TogetherStrong.xcodeproj` in Xcode. The project targets iPhone with iOS 17 or later, provisionally, until both users' device versions are confirmed. It uses Swift 6 language mode and was developed with Xcode 26.6 / Swift 6.3.3.

The checked-in Debug configuration points to the loopback integration server on port 3191. It contains no account credentials. A simulator can reach that server on this Mac. A physical iPhone needs a separately approved, HTTPS-accessible backend with the native authentication changes deployed.

To use another approved server, copy `Configuration/Local.xcconfig.example` to the ignored `Configuration/Local.xcconfig` and set its HTTPS origin. Xcode configuration files require the `https:/$()/host` spelling to preserve the double slash. The app accepts an origin only, with no path, user information, query or fragment.

Release uses a separate, ignored `Configuration/Release.local.xcconfig`. Its API origin must be HTTPS and cannot be a loopback address. An unconfigured build shows a connection-configuration message. Set the bundle identifier and signing team before installing on a physical iPhone. No signing identity, production origin or Apple account is checked into this milestone.

Account setup and password reset open the existing website in a system browser view. Complete the email verification/reset there, then return and sign in normally. A browser session is not imported into the app.

## Build and test

The Xcode project is committed. If Swift source files are added or removed, regenerate its deterministic file references from the repository root:

```sh
python3 scripts/generate-ios-project.py
```

Compile for the simulator:

```sh
xcodebuild -project ios/TogetherStrong.xcodeproj -scheme TogetherStrong \
  -configuration Debug -sdk iphonesimulator \
  -derivedDataPath .private/ios/build CODE_SIGNING_ALLOWED=NO build
```

Run native unit and UI checks on an installed iPhone simulator:

```sh
xcodebuild -project ios/TogetherStrong.xcodeproj -scheme TogetherStrong \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath .private/ios/build -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY=- test
```

Simulator tests use local ad hoc code signing, which needs no Apple account and allows the Keychain entitlement to work. Unsigned compilation is useful for a build check, but is insufficient to verify secure session storage.

The live backend tests are disabled unless an owner-only, temporary test configuration is supplied. The following command runs the existing real-database web integration suite, native bearer-security checks, Swift URLSession/Keychain checks and UIKit automation. Use only the dedicated Together Strong database in `.env.local`. No migrations run. Do not run another Xcode test process against the same simulator or build directory concurrently.

```sh
npm run build
RUN_DB_INTEGRATION=1 CONFIRM_TEST_DB=together-strong RUN_IOS_INTEGRATION=1 \
  npm run test:integration
```

Set `IOS_TEST_DESTINATION` if the named simulator is unavailable. The runner creates synthetic invited accounts, delivers setup/reset mail to an owner-only local outbox, writes a temporary native test configuration, tests both profiles, and removes its accounts/configuration afterward. No email is sent to real recipients. Native test logs and Xcode results stay in ignored `.private/ios/`; they must not be published because UI diagnostics may include temporary test inputs. Do not place real credentials in test configuration.

The default integration port is 3191. If another local server uses it, set `INTEGRATION_PORT=3193` or another free loopback port. The runner refuses occupied ports and leaves existing servers running. Its live UI tests temporarily load calendar/progress fixtures into the synthetic David account, restore that account's original test document afterward, and then remove the run's synthetic accounts. Fixture writes require synthetic identity validation.

## Workout logging

Open Start workout or Resume workout from the signed-in home screen. Warm-up is optional and has Start warm-up, I've warmed up and Skip for now paths. Expand an exercise to enter reps and total kg, then complete its set. Bodyweight exercises require reps only. Existing form instructions are available from each exercise.

Every accepted edit saves to Core Data immediately. The app attempts cloud sync after 1.5 seconds without another edit. Save progress explicitly syncs, Save & pause preserves the session and returns home, and Finish workout asks for confirmation before marking the session complete. Failed cloud requests leave the local copy available. Pending completions remain visibly pending sync.

Empty drafts never count as completed workouts. The programme clock starts with the first completed set. Editing a completed set clears its tick; a completed workout must be reopened before its entries can change. Finishing a partial workout leaves all remaining sets unfinished. Today's completion can be undone. Older drafts keep their original date when resumed.

History & calendar contains completed workouts, unfinished sessions and recoverable discarded drafts. Discarding an empty draft preserves its entered values. Restoration refuses to create two live sessions for the same date. Previously completed set values appear as reference and do not prefill new loads.

Swift exercise content is generated from the web source. To update it and the common parity fixtures, run from the repository root:

```sh
node --experimental-strip-types scripts/generate-workout-fixtures.mjs
python3 scripts/generate-ios-project.py
```

The Swift and TypeScript tests both check these fixtures. Native tests additionally cover session transitions, date/timezone handling, edits during upload, save failure and conflict recovery.

## Rest timer and exercise guides

Expand an exercise and choose Start rest to use its suggested duration. The Rest button in the workout navigation bar reopens the current timer. Pause/resume, add 30 seconds, reset, and 60/90/120-second presets are available. Reset and presets leave the timer paused. Close keeps it running; End rest clears it. Starting another exercise's rest replaces the current timer.

The account-scoped Core Data snapshot stores an absolute deadline or paused remaining time. Backgrounding or terminating the app does not restart the countdown. Returning after the deadline displays Rest complete. The timer does not modify workout entries, completion counts or cloud JSON. Pausing, finishing or discarding its workout cancels it. Logout and revoked authentication cancel its alert. Relaunch still requires online account verification before the timer screen is available.

Rest alerts are optional and off initially. Enable rest alerts requests iOS notification permission explicitly. When allowed, the app schedules one generic, local completion notification for the deadline. Pause/reset/end and workout cancellation remove it; resume or added time replaces it. No remote push or continuous background task is required. Denied permission leaves the countdown usable. Focus, sound settings and OS delivery can silence or delay alerts. See [Apple's notification guidance](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app). Lock-screen delivery remains a physical-device acceptance check.

Movement guide opens a Swift/Core Graphics illustration for any of the seven exercises. It starts still, with Start/Middle/Finish positions, a position slider, Play/Pause, Slow/Normal and Reset. Normal playback takes six seconds per full cycle; Slow takes twelve. Closing the guide, backgrounding or changing the system Reduce Motion setting pauses playback. It never resumes automatically. With Reduce Motion enabled, static positions remain available and Play is an explicit choice. Technique cues and reference links reuse the web content; illustrations are drawn locally and require no downloaded video.

Motion geometry is checked against 147 reference poses generated from the web implementation. Update guide metadata and fixtures together:

```sh
node --experimental-strip-types scripts/generate-motion-fixtures.mjs
python3 scripts/generate-ios-project.py
```

## History, calendar and progress

Open History & calendar from home. The native calendar marks completed days with a check and unfinished days with an orange dot. Select any day to see all its sessions, including multiple workouts finished on the same day. Today and Latest jump to a date; All dates clears the date selection. All, Completed and Unfinished filter the list. Recoverable discarded drafts appear under All dates with the All filter. Pull down to refresh.

Completed sessions appear on their completion day in the phone's time zone. A session finished later than it started also shows its original start date in the list. Unfinished sessions keep their original day. Tap an unfinished session to resume it; tap a completed workout to review its sets. Undo completion remains available for workouts completed today. Calendar browsing and filtering do not edit workout records.

Your progress shows completed workouts, completed sets from those workouts, and this week's sessions against the existing three-session target. Weeks run Monday to Sunday. The weekly chart shows eight weeks; tap a bar for its count. Exercise charts show the last twelve recorded workouts in chronological order by their original workout date. Swipe horizontally and tap a bar for the exact date, load and reps, then open the selected workout for review. Weighted exercises use the highest completed load, breaking ties by reps; bodyweight uses the highest completed reps per side. Zero-load sets remain valid records. Unfinished sets and sessions never enter the charts.

Both screens derive from the authenticated account's current local snapshot. Pending sync and conflicts remain visible, and totals can include completed workouts waiting to upload. Separate recovery copies are excluded. Charts have labelled scales, accessible bar buttons and text readouts. Calendar data and weekly totals refresh after foregrounding, significant clock changes and time-zone changes. All stored history remains available even though exercise charts show only twelve points.

Shared progress fixtures cover empty and unordered histories, best-set ties, paused/discarded/empty sessions, completion after midnight, daylight-saving changes and multiple local time zones. Regenerate after changing the metric rules in `lib/workout.ts`:

```sh
node --experimental-strip-types scripts/generate-progress-fixtures.mjs
python3 scripts/generate-ios-project.py
```

## Sync behavior and limits

- Native API calls use a signed Better Auth session credential from Keychain. Cookies are disabled in the URLSession, and authenticated redirects are refused. Server routes reject mixed cookie/bearer credentials and retain origin checks for browser writes.
- The complete version-1 JSON workout document is retained, including fields this milestone does not edit. Changing the beginner-set preference does not regenerate sessions or alter existing sets.
- Local edits and the pending-send marker are saved together in a Core Data snapshot scoped by API origin and authenticated user ID. Session credentials use device-only Keychain storage; workout files use complete file protection and are excluded from device backups.
- Sync first checks the current cloud revision. A failed or uncertain response leaves the pending copy intact. Refetching can recognize a successful previous write without sending it twice. Edits made during an upload stay local and pending after that older upload is acknowledged; the next write uses the updated revision.
- A conflict stops cloud writes while local logging remains available. Choosing the cloud version retains the pending local document as an account-scoped recovery copy. It can be reviewed read-only from home and only removed with explicit confirmation. A prior recovery copy must be reviewed and removed before another can replace it. Automatic per-session/field merging belongs to a later milestone.
- Sign-out removes the account's local snapshot and Keychain credential. Unsynced workouts and recovery copies require explicit removal confirmation. Failed server logout stays signed in unless the user explicitly chooses local-only sign-out.
- Without connectivity at launch, the app requires online account verification before showing cached history. Working fully offline after relaunch and continuous retry scheduling are later milestones. Current-session logging can continue through a network failure after authentication; reopening the app still needs online account verification.

This milestone does not create cloud resources, deploy the API, register Apple devices, configure signing or submit to TestFlight. Simulator verification does not establish real-device readiness.

## Verification snapshot

Verified locally on 27 October 2026 using an iPhone 17 Pro simulator with iOS 26.5. The native suite contains 37 tests; all passed, with live authentication verified through the synthetic-account integration run. All four UIKit UI tests and all 54 web regression tests passed. Type checking, lint and the production web build passed. Debug simulator and unsigned Release hardware builds compiled.

The live flow used real URLSession requests, Keychain storage and the dedicated app database with synthetic accounts. It covered draft recovery, set validation, app termination/relaunch, completion/undo, pause/resume, partial finish, timer controls and persistence, guide position/playback controls, background interruption and sign-out. Native tests also cover denied notification permission, stale permission responses, cancellation on workout/account changes, timer edits during sync, notification deadline construction, all 147 motion reference poses, rigid limb lengths and Reduce Motion event handling. The API independently verified the completed workout contained exactly one completed set. Tests removed their synthetic accounts afterward. Physical-device notification delivery, deployment, signing and TestFlight remain pending.
