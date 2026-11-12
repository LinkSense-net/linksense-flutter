// Tests for the deferredDeepLinks broadcast stream. Mocks the
// EventChannel by intercepting binary messenger traffic — Flutter
// has no first-class EventChannel mock, so we route via codec
// envelopes directly.

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linksense/linksense.dart';

const _eventChannelName = 'net.linksense.flutter/deep-links';
const _codec = StandardMethodCodec();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;

  void emit(Object? event) {
    messenger.handlePlatformMessage(
      _eventChannelName,
      _codec.encodeSuccessEnvelope(event),
      (_) {},
    );
  }

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // Acknowledge listen/cancel calls so EventChannel's subscribe completes.
    messenger.setMockMessageHandler(_eventChannelName, (message) async {
      return _codec.encodeSuccessEnvelope(null);
    });
  });

  tearDown(() {
    messenger.setMockMessageHandler(_eventChannelName, null);
  });

  test('decodes a URL string into a Uri', () async {
    final received = Completer<Uri?>();
    final sub = LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!received.isCompleted) received.complete(uri);
    });
    await Future<void>.delayed(Duration.zero);

    emit('https://acme.linksense.net/welcome');

    expect(
        await received.future, Uri.parse('https://acme.linksense.net/welcome'));
    await sub.cancel();
  });

  test('empty string maps to null', () async {
    final received = Completer<Uri?>();
    final sub = LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!received.isCompleted) received.complete(uri);
    });
    await Future<void>.delayed(Duration.zero);

    emit('');

    expect(await received.future, isNull);
    await sub.cancel();
  });

  test('stream is broadcast — multiple subscribers receive events', () async {
    final completer1 = Completer<Uri?>();
    final completer2 = Completer<Uri?>();
    final sub1 = LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!completer1.isCompleted) completer1.complete(uri);
    });
    final sub2 = LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!completer2.isCompleted) completer2.complete(uri);
    });
    await Future<void>.delayed(Duration.zero);

    emit('https://acme.linksense.net/a');

    final results = await Future.wait([completer1.future, completer2.future]);
    expect(results[0]?.path, '/a');
    expect(results[1]?.path, '/a');
    await sub1.cancel();
    await sub2.cancel();
  });
}
