## 0.3.0

Native SDKs 0.3.0: iOS SDK v0.3.0 (vendored into the plugin) and
`net.linksense:sdk:0.3.0`. The four LinkSense SDKs now share one API
vocabulary (see the cross-SDK table in the README).

**Breaking**

* Link opens moved to the new `deepLinks` stream. `deferredDeepLinks` (now
  on its own EventChannel `net.linksense.flutter/deferred-deep-links`)
  emits only the `start()` result. Listen to both if you handled opens on
  `deferredDeepLinks`.
* Every exception class ends in `Exception`: `LinkSenseNotConfiguredException`,
  `LinkSenseInvalidSdkKeyException`, `LinkSenseForbiddenCrossScopeException`,
  `LinkSenseForbiddenFieldException`, `LinkSenseRateLimitedException`,
  `LinkSenseDecodeFailureException`, `LinkSenseUnauthorizedException`,
  `LinkSenseNotFoundException`, `LinkSenseSlugExistsException`,
  `LinkSenseInvalidInputException`.
* `LinkSenseCustomPathExists` / `CUSTOM_PATH_EXISTS` is now
  `LinkSenseSlugExistsException` / `SLUG_EXISTS` (native `slugExists` /
  `SlugExists`).
* `UpdateLinkOptions` clearable fields are typed `FieldUpdate<T>?`:
  `null` = unchanged, `FieldUpdate.set(v)`, `FieldUpdate.clear()`. The
  `Object?` fields, `linkSenseClear` and `LinkSenseFieldClear` are removed.
* The `RATE_LIMITED` platform-error detail key is `retryAfterSeconds`
  (was `retryAfter`). Only matters if you read `PlatformException.details`.
* `configure` now rejects a malformed SDK key on both platforms by throwing
  `LinkSenseInvalidSdkKeyException`. The SDK stays unconfigured, and
  `configure` can be called again with a valid key.

**Added**

* `LinkSense.instance.deepLinks`: a stream of every Universal Link / App
  Link open. Opens that arrive before a listener are buffered in order.
* `LinkSenseAccessDeniedException` (`ACCESS_DENIED`) with `upgradeRequired`,
  `plan`, `currentUsage` and `limit`.
* `LinkSenseLink.metadata` (`Map<String, Object?>?`).
* Android `submitPastedLink` calls the native SDK (a documented no-op that
  returns `null`).

## 0.2.0

* Native SDKs 0.2.0: iOS SDK v0.2.0 (vendored into the plugin) and
  `net.linksense:sdk:0.2.0`. Fixes from 0.1.0: `/install` once per install
  (not every launch), working clipboard attribution on iOS, late-match
  polling, daylight-saving and screen-size fingerprint fixes on Android.
* **App opens are reported.** Every Universal Link / App Link that opens the
  app is sent to LinkSense (`/open`), so opens show in analytics.
* **iOS Universal Links need no AppDelegate code.** The plugin observes them
  itself; a link that cold-launches the app is held until `configure`.
  `handleUniversalLink` is removed.
* Android: links are observed, not consumed (`onNewIntent` returns false),
  so the app's own link handling still runs; a re-created activity no longer
  reports the same open twice; the launch link is held until `configure`.
* New `submitPastedLink(text)` (iOS paste-to-attribute, no paste prompt).
* `LinkSenseConfiguration.baseUrl` removed (fixed at SDK build time).
* iOS packaging fixed: CocoaPods hosts now get the native SDK (0.1.0 silently
  returned NOT_CONFIGURED), the SwiftPM product is named `linksense`, the
  package depends on `FlutterFramework`, and the stray `sharedDarwinSource`
  flag is gone. Minimum iOS is 16.

## 0.1.0

* Initial release. Bridges the native LinkSense iOS and Android SDKs
  via MethodChannel + EventChannel.
* `configure` / `start` lifecycle and `deferredDeepLinks` broadcast
  stream.
* Link CRUD: `createLink`, `getLink`, `updateLink`, `deleteLink`.
* Typed exception hierarchy mirroring native SDK error codes
  (`LinkSenseUnauthorized`, `LinkSenseNotFound`, `LinkSenseInvalidInput`
  with `fieldErrors`, `LinkSenseCustomPathExists`,
  `LinkSenseDecodeFailure`, plus the original six).
* iOS Universal Link forwarding via `handleUniversalLink(Uri)`. Android
  App Links auto-forwarded by the plugin's `ActivityAware` integration.
* Swift Package Manager support for iOS (Flutter 3.24+). CocoaPods
  podspec retained as a fallback for older Flutter versions.
* Wires native LinkSense iOS SDK 0.1.0 via Swift Package Manager
  (`https://github.com/LinkSense-net/linksense-ios-sdk`).
* Depends on `net.linksense:sdk:0.1.0` from Maven Central.
