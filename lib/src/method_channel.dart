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

/// Event channel for deferred deep links. Emits a single URL string
/// (or `null`) per install resolution. Subscribers that attach after
/// the resolution fires receive the buffered value on their next event.
const EventChannel kLinkSenseDeepLinkChannel =
    EventChannel('net.linksense.flutter/deep-links');

/// Thin helper that converts a [PlatformException] into the right typed
/// [LinkSenseException] subclass. Keeps the facade free of repetitive
/// try/catch branching.
Future<T> invokeAndTranslate<T>(
  String method, [
  Object? arguments,
]) async {
  try {
    final result = await kLinkSenseMethodChannel.invokeMethod<T>(method, arguments);
    if (result == null && null is! T) {
      throw LinkSenseNetworkException('Unexpected null response from $method');
    }
    return result as T;
  } on PlatformException catch (e) {
    final details = e.details;
    int? status;
    int? retryAfter;
    if (details is Map) {
      final statusRaw = details['status'];
      final retryRaw = details['retryAfter'];
      if (statusRaw is int) status = statusRaw;
      if (retryRaw is int) retryAfter = retryRaw;
    }
    throw linkSenseExceptionFromPlatform(
      code: e.code,
      message: e.message ?? e.code,
      status: status,
      retryAfter: retryAfter,
    );
  } on MissingPluginException catch (_) {
    // We still want a typed exception when the plugin isn't wired up
    // (e.g. integrator forgot to pod install).
    throw const LinkSenseNotConfigured();
  }
}
