# Building and testing without a Mac

## CI

`.github/workflows/ci.yml` runs on every push and on pull requests from forks:

| Job | Runner | Steps |
|---|---|---|
| C64Core (Linux) | `ubuntu-latest`, `swift:6.3.3-noble` container | `swift format lint`, build, tests |
| App (iOS) | `macos-26`, Xcode 26.6 | generate the project with XcodeGen, run the tests in the iOS Simulator (iPhone 17), build an unsigned archive for devices |

If the app tests fail, the job keeps the `.xcresult` bundle as a download on the run page.

When changing the Swift version, update it in three places: the container image in `ci.yml`, `SWIFT_VERSION` in `.claude/hooks/session-start.sh`, and the Xcode version (`DEVELOPER_DIR`) in `ci.yml`.

## Claude Code on the web

`.claude/hooks/session-start.sh` runs when a web session starts. It installs Swift 6.3.3 from swift.org into `/opt/swift`, after checking its signature. The download is about 1 GB and takes under a minute. The session can then build, lint and test `C64Core`; the iOS app itself is built by CI.

## TestFlight

`.github/workflows/testflight.yml` uploads a build to TestFlight. It runs in two cases:
- when started by hand, from the Actions tab (TestFlight → Run workflow)
- when a pushed commit's message starts with `[testflight]`, e.g. `[testflight] Tweak the palette`. The marker anywhere else in a message, such as a commit body or a squash merge's list of commits, does not count.

It can upload to two App Store Connect records:

| Record | Bundle ID | Name on the home screen | Used for |
|---|---|---|---|
| Dev app | `com.camerac64.dev` | C64 Dev | Everyday TestFlight builds. The default, and the only target of `[testflight]` pushes. |
| Release app | `com.camerac64` | Camera C64 | Builds meant for App Review. Chosen with `app: release` in a manual run. |

The dev app exists because the release record has been "removed from sale" since the legacy app, and TestFlight cannot install builds of an app in that state. It fails with "The requested app is not available or does not exist".

Each run:

1. It checks that the signing settings exist, and names any that are missing.
2. It builds an **unsigned** archive. The version comes from `MARKETING_VERSION` in `project.yml`. The build number is the UTC date followed by the workflow's run number (e.g. `20260926003`). App Store Connect requires each build number to be higher than every earlier upload to a record, and the release record's last one, from 2018, was `20180325001`.
3. It exports the archive with the App Store Connect API key. Apple's cloud-managed signing supplies the distribution certificate and the App Store provisioning profile, and `xcodebuild` uploads the result.

The archive is left unsigned on purpose. Signing it on CI makes Xcode create a new development certificate through the API key on every run, until Apple's certificate limit stops the job.

After an upload, App Store Connect takes a few minutes to process the build. It then appears under TestFlight, where internal testers can install it with the TestFlight app. The app icon is a placeholder for now.

### Setting up the dev app

1. On developer.apple.com → Certificates, Identifiers & Profiles → Identifiers, register an App ID with the explicit bundle ID `com.camerac64.dev`. It needs no capabilities.
2. In App Store Connect → Apps → + → New App, create an iOS app with that bundle ID. The name must be unique on the App Store, for example "Camera C64 Dev".
3. After the first upload, add the build to an internal testing group in the app's TestFlight tab.

### Settings it needs

Under the repository's Settings → Secrets and variables → Actions:

- **Secrets**:
  - `ASC_KEY_ID` and `ASC_ISSUER_ID`: from App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys.
  - `ASC_KEY_P8`: the contents of the key's `.p8` file, which can only be downloaded once.
  - The key must have the **Admin** role; cloud signing fails with other roles.
- **`DEVELOPMENT_TEAM`**, as a variable or a secret: the Team ID from developer.apple.com → Membership.

The `DIST_CERT_P12_BASE64` and `DIST_CERT_PASSWORD` secrets are not used: cloud signing replaced them. They can stay as a fallback in case cloud signing ever stops working, or be deleted, with the certificate revoked on developer.apple.com.
