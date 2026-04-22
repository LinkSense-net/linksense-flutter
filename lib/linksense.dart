import 'dart:async';

import 'src/method_channel.dart';
import 'src/models.dart';

export 'src/exceptions.dart';
export 'src/models.dart';

/// Public entry point for the LinkSense Flutter plugin.
///
/// Use as a singleton:
///
/// ```dart
/// await LinkSense.instance.configure(LinkSenseConfiguration(sdkKey: '...'));
/// await LinkSense.instance.start();
///
/// LinkSense.instance.deferredDeepLinks.listen((uri) {
///   if (uri != null) router.handle(uri);
/// });
/// ```
///
/// All methods are thin bridges to the native SDK — no attribution
/// logic lives here. Deferred deep links are surfaced as a broadcast
/// [Stream] so multiple listeners can subscribe independently.
class LinkSense {
  LinkSense._();

  static final LinkSense instance = LinkSense._();

  Stream<Uri?>? _deepLinks;

  /// Store configuration on the native side. Must be called exactly once.
  /// Subsequent calls are no-ops (the native layer logs a warning).
  Future<void> configure(LinkSenseConfiguration configuration) {
    return invokeAndTranslate<void>('configure', configuration.toMap());
  }

  /// Trigger the first-launch `/install` call. Idempotent — safe to call
  /// on every launch. The deferred deep link (if any) is emitted on
  /// [deferredDeepLinks].
  Future<void> start() {
    return invokeAndTranslate<void>('start');
  }

  /// Broadcast stream of deferred deep links. Emits exactly one value
  /// per install resolution (possibly `null` when attribution found
  /// nothing). Multiple subscribers are allowed; late subscribers
  /// receive the buffered value on their next event.
  Stream<Uri?> get deferredDeepLinks {
    _deepLinks ??= kLinkSenseDeepLinkChannel
        .receiveBroadcastStream()
        .map((raw) => raw is String && raw.isNotEmpty ? Uri.tryParse(raw) : null)
        .asBroadcastStream();
    return _deepLinks!;
  }

  // MARK: - Link CRUD passthroughs

  Future<LinkSenseLink> createLink(CreateLinkOptions options) async {
    final raw = await invokeAndTranslate<Map<Object?, Object?>>('createLink', options.toMap());
    return LinkSenseLink.fromMap(raw);
  }

  Future<LinkSenseLink> getLink(String id) async {
    final raw = await invokeAndTranslate<Map<Object?, Object?>>('getLink', <String, Object?>{'id': id});
    return LinkSenseLink.fromMap(raw);
  }

  Future<LinkSenseLink> updateLink(String id, UpdateLinkOptions options) async {
    final args = <String, Object?>{'id': id, 'options': options.toMap()};
    final raw = await invokeAndTranslate<Map<Object?, Object?>>('updateLink', args);
    return LinkSenseLink.fromMap(raw);
  }

  Future<void> deleteLink(String id) {
    return invokeAndTranslate<void>('deleteLink', <String, Object?>{'id': id});
  }
}
