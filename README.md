# linksense

Flutter plugin for the [LinkSense](https://linksense.net) dynamic-link and
deferred-deep-link platform. Thin MethodChannel bridge over the native
LinkSense iOS and Android SDKs — all attribution work lives in the
native layer, the Dart facade is a typed protocol adapter.

## Install

```bash
flutter pub add linksense
```

Platform requirements: **iOS 16+** and **Android API 24+**.

## Setup

### iOS

Works with both Swift Package Manager and CocoaPods; the native SDK is
built into the plugin, so there is nothing else to add. Minimum iOS 16.

Add the Associated Domains capability with
`applinks:<your-project>.linksense.net`. That's all: the plugin observes
Universal Links itself (no `AppDelegate` code). It only observes, so keep
routing links with your own router (`go_router`, `app_links`, …).

### Android

Declare your App Link intent filter on the host activity in
`AndroidManifest.xml`:

```xml
<intent-filter android:autoVerify="true">
  <action android:name="android.intent.action.VIEW" />
  <category android:name="android.intent.category.DEFAULT" />
  <category android:name="android.intent.category.BROWSABLE" />
  <data android:scheme="https"
        android:host="<your-project>.linksense.net" />
</intent-filter>
```

No `MainActivity` code changes are required. The plugin's `ActivityAware`
integration auto-forwards intents to LinkSense.

## Quick start

```dart
import 'package:linksense/linksense.dart';

Future<void> bootstrap() async {
  await LinkSense.instance.configure(const LinkSenseConfiguration(
    sdkKey: 'ls_sdk_<project>_<random>',
    enableClipboard: false, // iOS only
  ));

  LinkSense.instance.deferredDeepLinks.listen((uri) {
    if (uri != null) appRouter.handle(uri);
  });

  await LinkSense.instance.start();
}
```

### Universal Links / App Links

The plugin reports every link that opens the app to LinkSense, so opens
show in your analytics, and emits the URL LinkSense resolved on
`deferredDeepLinks` (the same stream as the deferred link). No platform
code is needed on either OS.

### Paste-to-attribute (iOS)

```dart
// From your own "paste your invite link" field. No iOS paste prompt.
final deepLink = await LinkSense.instance.submitPastedLink(text);
```

### Link CRUD

```dart
final link = await LinkSense.instance.createLink(const CreateLinkOptions(
  name: 'Spring promo',
  slug: 'spring-promo',
  tags: ['campaign:spring-2026'],
  metadata: {'campaign_id': 42, 'channel': 'email'},
));

await LinkSense.instance.updateLink(link.id, UpdateLinkOptions(
  name: 'Spring promo (v2)',
  ogTitle: linkSenseClear, // explicitly clear the og:title
));

await LinkSense.instance.deleteLink(link.id);
```

`UpdateLinkOptions` has two null semantics: a Dart `null` **omits** the
key from the request (server leaves it unchanged); the `linkSenseClear`
sentinel sends explicit JSON `null` (clears the field server-side).

## Error handling

All errors derive from `LinkSenseException`. Catch the parent broadly
or narrow with typed subclasses:

```dart
try {
  await LinkSense.instance.createLink(options);
} on LinkSenseRateLimited catch (e) {
  await Future.delayed(Duration(seconds: e.retryAfterSeconds ?? 1));
} on LinkSenseInvalidInput catch (e) {
  for (final entry in e.fieldErrors.entries) {
    print('${entry.key}: ${entry.value}');
  }
} on LinkSenseForbiddenCrossScope {
  // SDK key isn't allowed to mutate that link.
} on LinkSenseException catch (e) {
  print('linksense failed: ${e.code} — ${e.message}');
}
```

Modelled error codes:

| Class | Code | When |
|---|---|---|
| `LinkSenseNotConfigured` | `NOT_CONFIGURED` | `configure()` not called |
| `LinkSenseInvalidSdkKey` | `INVALID_SDK_KEY` | SDK key format invalid |
| `LinkSenseNetworkException` | `NETWORK` | Transport-level failure |
| `LinkSenseDecodeFailure` | `DECODE_FAILURE` | 2xx body didn't match schema |
| `LinkSenseUnauthorized` | `UNAUTHORIZED` | 401 — bad key |
| `LinkSenseForbiddenCrossScope` | `FORBIDDEN_CROSS_SCOPE` | 403 — cross-scope mutation |
| `LinkSenseForbiddenField` | `FORBIDDEN_FIELD` | 400 — disallowed body field |
| `LinkSenseInvalidInput` | `INVALID_INPUT` | 400 — validation; carries `fieldErrors` |
| `LinkSenseNotFound` | `NOT_FOUND` | 404 |
| `LinkSenseCustomPathExists` | `CUSTOM_PATH_EXISTS` | 409 — slug taken |
| `LinkSenseRateLimited` | `RATE_LIMITED` | 429 — carries `retryAfterSeconds` |
| `LinkSenseServerException` | _(any other server code)_ | Catch-all with `code` + `status` |

## Platform support

| Platform | Status |
|---|---|
| iOS 16+ | Native SDK built into the plugin (SwiftPM or CocoaPods) |
| Android API 24+ | Supported via `linksense-android` (Maven Central) |
| macOS / Web / Desktop | Not supported |

## License

Proprietary. See [LICENSE](LICENSE).
