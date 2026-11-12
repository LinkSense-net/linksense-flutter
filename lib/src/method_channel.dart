import 'dart:async';
import 'package:flutter/services.dart';

import 'exceptions.dart';

/// Single method channel all Flutter→Native calls flow through.
///
/// Named `net.linksense.flutter/method` so logs and debug captures make
/// the origin obvious. The native side registers handlers under the
/// same name in `SwiftLinksensePlugin` / `LinksensePlugin.kt`.
const MethodChannel kLinkSenseMethodChannel =
    MethodChannel('net.linksense.flutter/method');

/// Event channel for link opens (iOS Universal Links, Android App Link
/// intents). Emits one URL string (`''` when unresolved) per open. The
/// native side buffers opens in FIFO order until a listener attaches.
const EventChannel kLinkSenseDeepLinkChannel =
    EventChannel('net.linksense.flutter/deep-links');

/// Event channel for the deferred deep link resolved by `start()`. Emits
/// one URL string (`''` when attribution found nothing) per resolution,
/// buffered natively until a listener attaches.
const EventChannel kLinkSenseDeferredDeepLinkChannel =
    EventChannel('net.linksense.flutter/deferred-deep-links');

/// Thin helper that converts a [PlatformException] into the right typed
/// [LinkSenseException] subclass. Keeps the facade free of repetitive
/// try/catch branching.
Future<T> invokeAndTranslate<T>(
  String method, [
  Object? arguments,
]) async {
  try {
    final result =
        await kLinkSenseMethodChannel.invokeMethod<T>(method, arguments);
    if (result == null && null is! T) {
      throw LinkSenseNetworkException('Unexpected null response from $method');
    }
    return result as T;
  } on PlatformException catch (e) {
    final details = e.details;
    int? status;
    int? retryAfterSeconds;
    Map<String, String>? fieldErrors;
    if (details is Map) {
      final statusRaw = details['status'];
      final retryRaw = details['retryAfterSeconds'];
      final fieldsRaw = details['fieldErrors'];
      if (statusRaw is int) status = statusRaw;
      if (retryRaw is int) retryAfterSeconds = retryRaw;
      if (fieldsRaw is Map) {
        fieldErrors =
            fieldsRaw.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    }
    throw linkSenseExceptionFromPlatform(
      code: e.code,
      message: e.message ?? e.code,
      status: status,
      retryAfterSeconds: retryAfterSeconds,
      fieldErrors: fieldErrors,
      details: details is Map ? details : null,
    );
  } on MissingPluginException catch (_) {
    // We still want a typed exception when the plugin isn't wired up
    // (e.g. integrator forgot to pod install).
    throw const LinkSenseNotConfiguredException();
  }
}
