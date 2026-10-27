# Together Strong for iPhone

Native Swift and UIKit app, with no third-party iOS dependencies. The first milestone connects the existing private accounts to workout sync. It includes sign-in, Keychain session restoration, workout loading, a locally persisted beginner-set preference, revision-protected writes, conflict detection and sign-out. Full exercise logging, history screens, illustrations and timer are subsequent milestones.

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

## Sync behavior and limits

- Native API calls use a signed Better Auth session credential from Keychain. Cookies are disabled in the URLSession, and authenticated redirects are refused. Server routes reject mixed cookie/bearer credentials and retain origin checks for browser writes.
- The complete version-1 JSON workout document is retained, including fields this milestone does not edit. Changing the beginner-set preference does not regenerate sessions or alter existing sets.
- Local edits and the pending-send marker are saved together in a Core Data snapshot scoped by API origin and authenticated user ID. Session credentials use device-only Keychain storage; workout files use complete file protection and are excluded from device backups.
- Sync first checks the current cloud revision. A failed or uncertain response leaves the pending copy intact. Refetching can recognize a successful previous write without sending it twice. Pending-send edits remain locked until reconciliation.
- A conflict stops writes. The milestone lets the user retain their pending preference or explicitly discard it in favor of the cloud copy. A broader per-session/field merge interface belongs to a later milestone.
- Sign-out removes the account's local snapshot and Keychain credential. Pending preferences require explicit discard confirmation. Failed server logout stays signed in unless the user explicitly chooses local-only sign-out.
- Without connectivity at launch, the app requires online account verification before showing cached history. Working fully offline after relaunch, automatic retry scheduling and the complete workout editor are later milestones.

This milestone does not create cloud resources, deploy the API, register Apple devices, configure signing or submit to TestFlight. Simulator verification does not establish real-device readiness.

## Verification snapshot

Verified locally on 27 October 2026 using an iPhone 17 Pro simulator with iOS 26.5. All 13 native tests, both UIKit UI tests and all 50 web regression tests passed. The live native flow used real URLSession requests, Keychain storage and the dedicated app database with synthetic accounts. It covered a pending preference surviving app termination, cloud sync, session restoration and sign-out. Debug simulator and unsigned Release hardware builds compiled. Physical-device validation and deployment remain pending.
