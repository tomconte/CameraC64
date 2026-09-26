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

## TestFlight (not wired up yet)

Uploading builds to TestFlight from CI needs a few things that only the account holder can create. All of them can be created in a browser plus any computer with `openssl`:

1. **App Store Connect API key.**
   1. In App Store Connect, go to Users and Access → Integrations → App Store Connect API → Team Keys and create a key with the **Admin** role. Cloud signing fails with other roles.
   2. Download the `.p8` file (possible only once) and note the Key ID and the Issuer ID.
2. **Apple Distribution certificate.** Creating one certificate up front stops CI from creating a new one on every run, which would eventually hit Apple's certificate limit.
   1. Create a key and a signing request:
      ```sh
      openssl req -new -newkey rsa:2048 -nodes -keyout dist.key -out dist.csr -subj "/emailAddress=you@example.com/CN=Your Name"
      ```
   2. On developer.apple.com, go to Certificates → + → Apple Distribution, upload `dist.csr` and download `distribution.cer`.
   3. Convert it into a `.p12` file:
      ```sh
      openssl x509 -inform DER -in distribution.cer -out dist.pem
      openssl pkcs12 -export -legacy -inkey dist.key -in dist.pem -out dist.p12 -passout pass:CHOOSE_A_PASSWORD
      base64 -i dist.p12 | tr -d '\n' > dist.p12.b64
      ```
3. **GitHub settings.** Under the repository's Settings → Secrets and variables → Actions:
   - Secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the `.p8` file's contents), `DIST_CERT_P12_BASE64` (the contents of `dist.p12.b64`), `DIST_CERT_PASSWORD`.
   - Variable: `DEVELOPMENT_TEAM`, your Team ID from developer.apple.com → Membership.

Once these exist, a manually triggered `testflight.yml` workflow will archive, sign and upload a build, with the build number taken from the run number. The app will also need a real 1024×1024 icon before its first upload.
