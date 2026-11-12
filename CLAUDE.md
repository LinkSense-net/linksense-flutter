# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`linksense` is a Flutter plugin that bridges the native LinkSense iOS and Android SDKs over MethodChannel + EventChannel. It does **no** attribution logic itself — every public method is a thin passthrough that (a) serializes args to the server's SDK allowlist shape, (b) invokes a native method, (c) translates `PlatformException` into a typed `LinkSenseException`. Treat the Dart side as a protocol adapter, not a library with its own behavior.

## Related repositories

- `../linksense` — Backend (Next.js + Postgres). Source of truth for the `/api/sdk/v1/*` routes, error envelopes (see `src/features/api/types.ts`), and rate-limiter behavior. 25 error codes total; this plugin types 11 of them (the others ride through `LinkSenseServerException`).
- `../linksense-android` — Native Android SDK. Published as `net.linksense:sdk:0.1.0` on Maven Central. Plugin imports `net.linksense.sdk.*` in `android/.../LinksensePlugin.kt` and resolves the artifact via `implementation("net.linksense:sdk:0.1.0")` in `android/build.gradle`.
- `../linksense-ios` — Native iOS SDK at `LinkSense-net/linksense-ios-sdk`. Ships **only** via Swift Package Manager — there is no podspec. Plugin imports `LinkSense` via `#if canImport(LinkSense)` in the Swift bridge and declares an SPM dependency in `ios/linksense/Package.swift` pointing at `https://github.com/LinkSense-net/linksense-ios-sdk.git`.
- `../linksense-react-native` — Sister Turbo Module for React Native (RN 0.76+ New Architecture). Same wire contract as this plugin, different transport. Error-code strings and field names must stay aligned across both — they ultimately delegate to the same native SDKs.
- `../research` — Competitive research and partner-documentation workspace (not source). Useful when reasoning about competitor SDK behavior; out of scope for code edits.

## Architecture (three layers)

1. **Dart facade** — `lib/linksense.dart` exposes the `LinkSense` singleton (`configure`, `start`, `deferredDeepLinks`, `deepLinks`, `submitPastedLink`, link CRUD). All public types live under `lib/src/`: models (`models.dart`), method/event channel constants + `invokeAndTranslate<T>` helper (`method_channel.dart`), and the sealed `LinkSenseException` hierarchy (`exceptions.dart`).
2. **Platform channels** — `net.linksense.flutter/method` (invocations), `net.linksense.flutter/deep-links` (link opens → `deepLinks`) and `net.linksense.flutter/deferred-deep-links` (the `start()` result → `deferredDeepLinks`). Each event is a URL string, `""` for an unresolved link (Dart maps it to `null`). Each native bridge has one `BufferedStream` per event channel: a sink plus a FIFO buffer flushed when that stream's listener attaches. Dart method names, arg keys, and error `code`s are part of the contract — the native sides (`SwiftLinksensePlugin.swift`, `LinksensePlugin.kt`) key off them directly.
3. **Native bridges**
   - **iOS** — `ios/linksense/Sources/linksense/SwiftLinksensePlugin.swift`. Routes calls to `LinkSense.shared`. `start` feeds `onDeferredDeepLink` into the deferred stream; the app-delegate `continue userActivity` hook forwards Universal Links (held until `configure` succeeds) and feeds the link-open stream. `configure` catches the native throw and returns `INVALID_SDK_KEY`; `isConfigured` is set only on success.
   - **Android** — `android/src/main/kotlin/net/linksense/flutter/LinksensePlugin.kt`. Forwards to `LinkSense` singleton, emits `result.error(...)` with the SDK's error codes. Implements `ActivityAware` + `NewIntentListener` to auto-forward App-Link intents to the link-open stream — integrators don't touch `MainActivity`. Intents that arrive before `configure` are replayed only after it succeeds. `submitPastedLink` calls the native no-op (returns `null`).

When changing a method signature or arg shape, you must update **all four** sites: Dart facade, Dart model `toMap`, Swift `handle*`, Kotlin `handle*`. The channel contract has no compile-time checker.

## Error-code contract

`lib/src/exceptions.dart` maps native error codes → Dart subclasses in `linkSenseExceptionFromPlatform`. When adding a new native error, update all three: Swift `flutterError(from:)`, Kotlin `surfaceError`, and the Dart switch.

13 typed exceptions (every class name ends in `Exception`). Both bridges emit the same codes and detail keys:

| Class | Code | `details` keys |
|---|---|---|
| `LinkSenseNotConfiguredException` | `NOT_CONFIGURED` | — |
| `LinkSenseInvalidSdkKeyException` | `INVALID_SDK_KEY` (from `configure`) | — |
| `LinkSenseNetworkException` | `NETWORK` | — |
| `LinkSenseDecodeFailureException` | `DECODE_FAILURE` | — |
| `LinkSenseUnauthorizedException` | `UNAUTHORIZED` | — |
| `LinkSenseAccessDeniedException` | `ACCESS_DENIED` (message = server message) | `upgradeRequired`, `plan`, `currentUsage`, `limit` |
| `LinkSenseForbiddenCrossScopeException` | `FORBIDDEN_CROSS_SCOPE` | — |
| `LinkSenseForbiddenFieldException` | `FORBIDDEN_FIELD` | — |
| `LinkSenseInvalidInputException` | `INVALID_INPUT` | `fieldErrors` |
| `LinkSenseNotFoundException` | `NOT_FOUND` | — |
| `LinkSenseSlugExistsException` | `SLUG_EXISTS` (Dart also accepts legacy `CUSTOM_PATH_EXISTS`) | — |
| `LinkSenseRateLimitedException` | `RATE_LIMITED` | `retryAfterSeconds` |
| `LinkSenseServerException` (catch-all) | _any other server code_ | `status` |

Backend codes not explicitly typed (e.g. `INVALID_FORMAT`, `BUNDLE_ID_EXISTS`, `SUBDOMAIN_TAKEN`, `LINKED_REFERENCES`, all the 5xx codes) fall into `LinkSenseServerException` — integrators inspect `.code` for narrower handling. `MissingPluginException` (e.g. integrator forgot SPM enable) becomes `LinkSenseNotConfiguredException`.

`INVALID_INPUT.fieldErrors` is the **Android-flattened** shape (`Map<String, String>`) — backend emits a raw Zod issues array; the Android SDK flattens path-joined-by-`.` → first message. iOS bridge currently lets `INVALID_INPUT` through as a generic server case; the Dart switch keys off `code` regardless.

## UpdateLinkOptions tri-state

Clearable `UpdateLinkOptions` fields are `FieldUpdate<T>?`: `null` = unchanged (key omitted from the wire map), `FieldUpdate.set(v)` = key with value, `FieldUpdate.clear()` = key with explicit `null` (clears server-side). `name`, `tags`, `iosClipboardEnabled` are plain `T?` (the server can't clear them). The bridges key off key-presence: Kotlin maps absent → `FieldUpdate.Unchanged`, null → `FieldUpdate.Clear`; Swift → `.unchanged` / `.clear`. Don't collapse absent and null — it is load-bearing.

`LinkSenseLink.metadata` arrives as plain codec values (String, int, double, bool, List, Map, null) — both bridges' `encodeLink` convert the native `LinkMetadataValue` tree.

## Commands

```bash
# Static analysis (uses flutter_lints 6.0 via analysis_options.yaml)
flutter analyze

# Unit tests (Dart only — mocks the method channel, no native required)
flutter test
flutter test test/linksense_facade_test.dart          # single file
flutter test --name 'INVALID_INPUT'                   # single test by name

# Format
dart format lib test example

# Android-side Kotlin bridge tests (JUnit 5 + Mockito), via the example's Gradle build
cd example && flutter pub get && cd android && ./gradlew :linksense:testDebugUnitTest
# (before net.linksense:sdk is on Maven Central, add a throwaway --init-script that adds mavenLocal()
#  to the root build only; never commit mavenLocal())

# Host-machine one-time: enable SPM (Flutter 3.24+ default-off, 3.27+ default-on)
flutter config --enable-swift-package-manager

# Example app (requires SDK key + native SDKs wired up locally)
cd example
flutter run --dart-define=LINKSENSE_SDK_KEY=ls_sdk_<project>_<random>

# Integration test (on a connected device/emulator)
cd example && flutter test integration_test/plugin_integration_test.dart

# Pub package validation before publish
flutter pub publish --dry-run

# pana score check (target: ≥130 pub points)
dart pub global activate pana
pana --no-warning .
```

## Platform constraints (from build files, not derivable elsewhere)

- **Android**: `minSdk` 24, `compileSdk`/`targetSdk` 35, Kotlin 2.0.20, AGP 8.5.2, JVM 11. Namespace `net.linksense.flutter`. Test deps: JUnit 4.13.2 + Mockito-Kotlin 5.4.0.
- **iOS**: deployment target 14.0, Swift 5.0. SPM manifest at `ios/linksense/Package.swift` (Flutter 3.24+); CocoaPods podspec at `ios/linksense.podspec` for legacy hosts. `sharedDarwinSource: true` in pubspec anticipates a macOS target but there is no macOS plugin class yet.
- **Source paths**: Swift sources live under `ios/linksense/Sources/linksense/` (NOT `ios/Classes/`). The privacy manifest is at `ios/linksense/Sources/linksense/Resources/PrivacyInfo.xcprivacy` and is bundled by both the SPM target (`resources: [.process("Resources")]`) and the podspec (`s.resource_bundles`).

## What not to do

- Don't put attribution/link-resolution logic in Dart — it belongs in the native SDKs. The Dart facade is a protocol adapter.
- Don't change the method/event channel names or error code strings without coordinated edits to Swift + Kotlin + Dart.
- Don't reintroduce `ios/Classes/`. Swift sources live under `ios/linksense/Sources/linksense/` for SPM compatibility. The podspec's `s.source_files` and `s.resource_bundles` reference that path; moving them back breaks both CocoaPods and SPM consumers.
- Don't commit `build/`, `.dart_tool/`, or `pubspec.lock` (gitignored — libraries don't ship lockfiles).
