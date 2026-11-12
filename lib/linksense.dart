import 'dart:async';

import 'package:flutter/services.dart';

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
///   if (uri != null) router.handle(uri); // first launch after install
/// });
/// LinkSense.instance.deepLinks.listen((uri) {
///   if (uri != null) router.handle(uri); // every link open
/// });
/// ```
///
/// All methods are thin bridges to the native SDK — no attribution
/// logic lives here. Both link streams are broadcast [Stream]s so
/// multiple listeners can subscribe independently.
class LinkSense {
  LinkSense._();

  static final LinkSense instance = LinkSense._();

  Stream<Uri?>? _deepLinks;
  Stream<Uri?>? _deferredDeepLinks;

  /// Store configuration on the native side. Must be called exactly once.
  /// Subsequent calls are no-ops (the native layer logs a warning).
  /// Throws [LinkSenseInvalidSdkKeyException] when the key isn't an
  /// `ls_sdk_<project>_<random>` key; the SDK then stays unconfigured.
  Future<void> configure(LinkSenseConfiguration configuration) {
    return invokeAndTranslate<void>('configure', configuration.toMap());
  }

  /// Trigger the first-launch `/install` call. Idempotent — safe to call
  /// on every launch. The deferred deep link (if any) is emitted on
  /// [deferredDeepLinks].
  Future<void> start() {
    return invokeAndTranslate<void>('start');
  }

  /// Broadcast stream of the deferred deep link resolved by [start].
  /// Emits one value per install resolution (`null` when attribution
  /// found nothing). Link opens are on [deepLinks], not here. A value
  /// resolved before the first listener attaches is buffered natively
  /// and delivered on subscribe.
  Stream<Uri?> get deferredDeepLinks =>
      _deferredDeepLinks ??= _uriStream(kLinkSenseDeferredDeepLinkChannel);

  /// Broadcast stream of link opens: iOS Universal Links and Android App
  /// Link intents, observed automatically. Emits the resolved deep link
  /// for each open (`null` when it couldn't be resolved). Opens that
  /// arrive before the first listener (e.g. the cold-launch link) are
  /// buffered natively in order and delivered on subscribe.
  Stream<Uri?> get deepLinks =>
      _deepLinks ??= _uriStream(kLinkSenseDeepLinkChannel);

  static Stream<Uri?> _uriStream(EventChannel channel) => channel
      .receiveBroadcastStream()
      .map((raw) => raw is String && raw.isNotEmpty ? Uri.tryParse(raw) : null)
      .asBroadcastStream();

  // MARK: - Link CRUD passthroughs

  Future<LinkSenseLink> createLink(CreateLinkOptions options) async {
    final raw = await invokeAndTranslate<Map<Object?, Object?>>(
        'createLink', options.toMap());
    return LinkSenseLink.fromMap(raw);
  }

  Future<LinkSenseLink> getLink(String id) async {
    final raw = await invokeAndTranslate<Map<Object?, Object?>>(
        'getLink', <String, Object?>{'id': id});
    return LinkSenseLink.fromMap(raw);
  }

  Future<LinkSenseLink> updateLink(String id, UpdateLinkOptions options) async {
    final args = <String, Object?>{'id': id, 'options': options.toMap()};
    final raw =
        await invokeAndTranslate<Map<Object?, Object?>>('updateLink', args);
    return LinkSenseLink.fromMap(raw);
  }

  Future<void> deleteLink(String id) {
    return invokeAndTranslate<void>('deleteLink', <String, Object?>{'id': id});
  }

  // MARK: - Paste-to-attribute (iOS)

  /// iOS 16+: attribute the install from a link the user pasted into your
  /// own UI (e.g. a "paste your invite link" field). The user's paste
  /// gesture grants access, so iOS shows no paste prompt. Returns the
  /// matched deep link, or `null`. Always `null` on Android, where the
  /// native `submitPastedLink` is a no-op because the Play Install
  /// Referrer covers this.
  Future<Uri?> submitPastedLink(String text) async {
    final raw = await invokeAndTranslate<String?>(
      'submitPastedLink',
      <String, Object?>{'text': text},
    );
    return raw == null || raw.isEmpty ? null : Uri.tryParse(raw);
  }
}
