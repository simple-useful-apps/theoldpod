# Shipping to TestFlight

Everything on the build side is staged (`scripts/testflight.sh`, export plists, versions, privacy policy). What remains splits into a one-time account setup (you, in a browser) and the per-build upload (`scripts/testflight.sh`).

## One-time — you, in App Store Connect (no code)

1. **Accept agreements** — appstoreconnect.apple.com → Business/Agreements. A free app needs only the free-apps agreement; no banking or tax forms. *This silently blocks the first upload if skipped.*
2. **Create the app record** — App Store Connect → Apps → **+ New App**. Platform iOS (do iOS first), name "theoldpod", primary language, bundle ID **com.mattreed.theoldpod**, SKU anything (e.g. `theoldpod-ios`). The Mac app is a separate record with **com.mattreed.theoldpod.mac** when you're ready for it.
3. **Upload auth** — one time, so `scripts/testflight.sh` can upload headlessly. Easiest: App Store Connect → Users and Access → Integrations → **App Store Connect API** → generate a key, then `xcrun notarytool store-credentials` (or set the key in Xcode's Accounts). Alternatively an app-specific password from appleid.apple.com.

## Per build

1. Bump `CFBundleVersion` in `project.yml` (App Store Connect rejects a duplicate build number). Marketing version `CFBundleShortVersionString` ("1.0") only changes for a real release.
2. `scripts/testflight.sh ios` (or `mac`) — archives with real distribution signing and uploads. Automatic signing mints the distribution certificate and App Store profile on first run.
3. Wait ~5–15 min for processing, then in App Store Connect → your app → **TestFlight**:
   - **Internal testers** (your team, ≤100): add yourself, install from the TestFlight app on your device. **No review.**
   - **External testers** (≤10,000): needs a one-time **Beta App Review** — fill "What to Test" + beta contact email, and a privacy policy URL (host `docs/privacy.html`; see below).

## Notes

- **Export compliance** is pre-answered: `ITSAppUsesNonExemptEncryption: false` is set, so no per-build encryption prompt.
- **Privacy policy** — `docs/privacy.html` ("collects nothing"). Host it via GitHub Pages (needs the repo public or a paid plan) or any static host, and paste the URL into App Store Connect's App Privacy + the external-testing form. App Privacy answers: **Data Not Collected** across the board.
- **Deployment target is iOS 26 / macOS 26** — only devices on those OSes can install. Lower it in `project.yml` (`options.deploymentTarget`) to widen the pool.
- **iOS icon** is the single 1024 App Store icon (present). Mac icon set is present.
- First distribution cert occasionally needs one approval in Xcode → Settings → Accounts → Manage Certificates → **+ Apple Distribution**, if CLI signing balks.
