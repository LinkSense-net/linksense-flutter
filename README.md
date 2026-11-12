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

  // The deferred deep link resolved on first launch after install.
  LinkSense.instance.deferredDeepLinks.listen((uri) {
    if (uri != null) appRouter.handle(uri);
  });
  // Every Universal Link / App Link that opens the app.
  LinkSense.instance.deepLinks.listen((uri) {
    if (uri != null) appRouter.handle(uri);
  });

  await LinkSense.instance.start();
}
```

### Universal Links / App Links

The plugin reports every link that opens the app to LinkSense, so opens
show in your analytics, and emits the URL LinkSense resolved on
`deepLinks`. `deferredDeepLinks` carries only the `start()` result. Opens
that arrive before you listen (such as the link that cold-launched the app)
are buffered and delivered in order on subscribe. No platform code is
needed on either OS.

### Paste-to-attribute (iOS)

```dart
// From your own "paste your invite link" field. No iOS paste prompt.
final deepLink = await LinkSense.instance.submitPastedLink(text);
```

On Android this calls the native `submitPastedLink`, a no-op that returns
`null`: the Play Install Referrer already covers this case.

### Link CRUD

```dart
final link = await LinkSense.instance.createLink(const CreateLinkOptions(
  name: 'Spring promo',
  slug: 'spring-promo',
  tags: ['campaign:spring-2026'],
  metadata: {'campaign_id': 42, 'channel': 'email'},
));

print(link.metadata); // {campaign_id: 42, channel: email}

await LinkSense.instance.updateLink(link.id, const UpdateLinkOptions(
  name: 'Spring promo (v2)',
  ogDescription: FieldUpdate.set('Now with 20% off'),
  ogTitle: FieldUpdate.clear(), // explicitly clear the og:title
));

await LinkSense.instance.deleteLink(link.id);
```

Each `UpdateLinkOptions` field has three states: `null` leaves the field
unchanged (the key is omitted), `FieldUpdate.set(v)` sets it, and
`FieldUpdate.clear()` sends JSON `null` to clear it server-side. `name`,
`tags` and `iosClipboardEnabled` can't be cleared, so they take a plain
value (`null` = unchanged).

## Error handling

All errors derive from `LinkSenseException`. Catch the parent broadly
or narrow with typed subclasses:

```dart
try {
  await LinkSense.instance.createLink(options);
} on LinkSenseRateLimitedException catch (e) {
  await Future.delayed(Duration(seconds: e.retryAfterSeconds ?? 1));
} on LinkSenseInvalidInputException catch (e) {
  for (final entry in e.fieldErrors.entries) {
    print('${entry.key}: ${entry.value}');
  }
} on LinkSenseAccessDeniedException catch (e) {
  if (e.upgradeRequired) showUpgrade(e.plan, e.currentUsage, e.limit);
} on LinkSenseForbiddenCrossScopeException {
  // SDK key isn't allowed to mutate that link.
} on LinkSenseException catch (e) {
  print('linksense failed: ${e.code} — ${e.message}');
}
```

Modelled error codes:

| Class | Code | When |
|---|---|---|
| `LinkSenseNotConfiguredException` | `NOT_CONFIGURED` | `configure()` not called, or it threw |
| `LinkSenseInvalidSdkKeyException` | `INVALID_SDK_KEY` | Thrown by `configure()` for a malformed key |
| `LinkSenseNetworkException` | `NETWORK` | Transport-level failure |
| `LinkSenseDecodeFailureException` | `DECODE_FAILURE` | 2xx body didn't match schema |
| `LinkSenseUnauthorizedException` | `UNAUTHORIZED` | 401 — bad key |
| `LinkSenseAccessDeniedException` | `ACCESS_DENIED` | 403 — plan limit or platform not allowed; carries `upgradeRequired`, `plan`, `currentUsage`, `limit` |
| `LinkSenseForbiddenCrossScopeException` | `FORBIDDEN_CROSS_SCOPE` | 403 — cross-scope mutation |
| `LinkSenseForbiddenFieldException` | `FORBIDDEN_FIELD` | 400 — disallowed body field |
| `LinkSenseInvalidInputException` | `INVALID_INPUT` | 400 — validation; carries `fieldErrors` |
| `LinkSenseNotFoundException` | `NOT_FOUND` | 404 |
| `LinkSenseSlugExistsException` | `SLUG_EXISTS` | 409 — slug taken |
| `LinkSenseRateLimitedException` | `RATE_LIMITED` | 429 — carries `retryAfterSeconds` |
| `LinkSenseServerException` | _(any other server code)_ | Catch-all with `code` + `status` |

## Platform support

| Platform | Status |
|---|---|
| iOS 16+ | Native SDK built into the plugin (SwiftPM or CocoaPods) |
| Android API 24+ | Supported via `linksense-android` (Maven Central) |
| macOS / Web / Desktop | Not supported |

## Cross-SDK API (0.3.0)

The same surface in every LinkSense SDK. Names differ only where the platform idiom does.

| Concept | iOS (Swift) | Android (Kotlin) | Flutter (Dart) | React Native (TS) |
|---|---|---|---|---|
| Configure (throws on a malformed key) | `try LinkSense.configure(_:)` | `LinkSense.configure(context, config)` | `await LinkSense.configure(config)` | `LinkSense.configure(config)` |
| Start / deferred link | `start()` + `onDeferredDeepLink { }` | `start()` + `onDeferredDeepLink { }` | `start()` + `deferredDeepLinks` stream | `await start()` |
| Link opens | `continueUserActivity(_:handler:)` | `handleIntent(intent) { }` | `deepLinks` stream | `onDeepLink(listener)` |
| Pasted link | `submitPastedLink(_:completion:)` | `submitPastedLink(text)` (no-op, returns null) | `submitPastedLink(text)` | `submitPastedLink(text)` |
| Create / get / update / delete | `createLink` / `getLink` / `updateLink` / `deleteLink` | same, `suspend` | same, `Future` | same, `Promise` |
| Update: leave field / set / clear | `.unchanged` / `.set(v)` / `.clear` | `FieldUpdate.Unchanged` / `Set(v)` / `Clear` | `null` / `FieldUpdate.set(v)` / `FieldUpdate.clear()` | `undefined` / `v` / `CLEAR` |
| Link metadata | `link.metadata` | `link.metadata` | `link.metadata` | `link.metadata` |

| Error | iOS `LinkSenseError` | Android `LinkSenseError` | Flutter | RN `error.code` |
|---|---|---|---|---|
| Not configured | `.notConfigured` | `NotConfigured` | `LinkSenseNotConfiguredException` | `NOT_CONFIGURED` |
| Malformed SDK key | `.invalidSdkKey` | `InvalidSdkKey` | `LinkSenseInvalidSdkKeyException` | `INVALID_SDK_KEY` |
| Bad / revoked key | `.unauthorized` | `Unauthorized` | `LinkSenseUnauthorizedException` | `UNAUTHORIZED` |
| Plan limit / platform not allowed | `.accessDenied(details)` | `AccessDenied(...)` | `LinkSenseAccessDeniedException` | `ACCESS_DENIED` + `error.accessDenied` |
| Rate limited | `.rateLimited(retryAfterSeconds:)` | `RateLimited(retryAfterSeconds)` | `LinkSenseRateLimitedException.retryAfterSeconds` | `RATE_LIMITED` + `error.retryAfterSeconds` |
| Slug taken | `.slugExists` | `SlugExists` | `LinkSenseSlugExistsException` | `SLUG_EXISTS` |
| Validation | `.invalidInput(fieldErrors:)` | `InvalidInput(fieldErrors)` | `LinkSenseInvalidInputException` | `INVALID_INPUT` + `error.fieldErrors` |
| Not found | `.notFound` | `NotFound` | `LinkSenseNotFoundException` | `NOT_FOUND` |

Access-denied details carry the same fields everywhere: `serverMessage`, `upgradeRequired` (false when absent), `plan`, `currentUsage`, `limit` (each optional).

## License

Proprietary. See [LICENSE](LICENSE).
