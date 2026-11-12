# linksense example

A single-page playground for exercising every public API on the `linksense`
Flutter plugin against a real native SDK + backend. Useful as both a smoke
test for integrators and a copy-pasteable reference for each call site.

## Run

```bash
cd example
flutter run --dart-define=LINKSENSE_SDK_KEY=ls_sdk_<project>_<random>
```

The SDK key text field is prefilled from `--dart-define`, but every config
field is editable in-app so you can flip flags, change log level, or point at
a non-default `baseUrl` without rebuilding.

## Testing against a local server

Point the SDK at your local instance via the **Base URL** field on the
Configure card. Use the right loopback for each platform:

| Where you're running | baseUrl |
|---|---|
| iOS simulator | `http://localhost:3000` |
| Android emulator | `http://10.0.2.2:3000` (the emulator's host alias) |
| Physical device on Wi-Fi | `http://<host-LAN-IP>:3000` |

The example ships a **scoped** cleartext-HTTP exemption — `localhost` on
iOS (via `NSAllowsLocalNetworking` in `Info.plist`) and `localhost` +
`10.0.2.2` on Android (via `network_security_config.xml`). Everything else
still requires HTTPS, so this isn't a pattern to copy into production apps.

If your local server binds to `127.0.0.1` only, the Android emulator can't
reach it via `10.0.2.2`. Bind to `0.0.0.0:3000` instead.

## What the playground covers

| Card | Plugin surface exercised |
|---|---|
| **Status banner** | `LinkSense.instance.deferredDeepLinks` and `deepLinks` streams — shows the last emission with timestamp |
| **1. Configure & start** | Every field on `LinkSenseConfiguration` (`sdkKey`, `baseUrl`, `enableClipboard`, `enableInstallReferrer`, `enableFingerprint`, `logLevel`) → `configure()` → `start()` |
| **2. Forward Universal Link** | `handleUniversalLink(Uri)` — paste a URL to simulate the iOS warm path. No-op on Android |
| **3. Create link** | Every field on `CreateLinkOptions` (incl. multi-line JSON `metadata` and comma-separated `tags`) → `createLink()` |
| **4. Get / update / delete** | `getLink()`, `updateLink()`, `deleteLink()`. The update sub-form has a **"Clear"** checkbox per clearable field — flip it to send `FieldUpdate.clear()` (explicit JSON `null`) instead of omitting the key |
| **5. Activity log** | Every call's outcome (last 50). Typed exceptions surface with their `code` and extras: `LinkSenseInvalidInputException.fieldErrors`, `LinkSenseRateLimitedException.retryAfterSeconds`, `LinkSenseAccessDeniedException.upgradeRequired`, etc. |

## Forcing errors

The playground is also the easiest way to see each typed exception fire:

- Configure with a bogus key like `ls_sdk_bad_xyz` → `LinkSenseInvalidSdkKeyException` from `configure()`
- Create a link with an empty `name` → `LinkSenseInvalidInputException` with `fieldErrors` shown inline
- Create the same `slug` twice → `LinkSenseSlugExistsException`
- Get a link by an unknown id → `LinkSenseNotFoundException`
- Update a link your SDK key doesn't own → `LinkSenseForbiddenCrossScopeException`

## Not wired up (intentionally)

- **iOS Universal Link entitlements** — requires a real domain + bundle ID +
  CDN-served `apple-app-site-association`. Use the "Forward Universal Link"
  card to drive the API surface manually instead.
- **Android App Link intent filter** — same domain-verification requirement.
  The plugin auto-forwards intents via `ActivityAware`, so once you add an
  `intent-filter` in your own app's manifest it will Just Work.
- **State persistence** — the last created link ID lives in memory only;
  relaunch starts fresh.
