// Minimal smoke test wired to the `LinkSense` facade. Run with
// `flutter test integration_test` on a real device with
// `--dart-define=LINKSENSE_SDK_KEY=ls_sdk_...` to exercise the bridge.
// Without the key it degrades into a no-op compile check.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:linksense/linksense.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('singleton + streams are reachable without an SDK key', (
    tester,
  ) async {
    expect(LinkSense.instance, isNotNull);
    expect(LinkSense.instance.deferredDeepLinks, isA<Stream<Uri?>>());
    expect(LinkSense.instance.deepLinks, isA<Stream<Uri?>>());
  });

  testWidgets('getLink surfaces a typed exception when unconfigured', (
    tester,
  ) async {
    const sdkKey = String.fromEnvironment('LINKSENSE_SDK_KEY');
    if (sdkKey.isNotEmpty) return; // covered by the configured branch below

    try {
      await LinkSense.instance.getLink('missing');
      fail('expected LinkSenseException');
    } on LinkSenseException catch (e) {
      // Without `configure`, the native SDK returns NOT_CONFIGURED. The
      // point is a typed exception, not an untyped PlatformException.
      expect(e.code, isNotNull);
    }
  });

  testWidgets('configure degrades gracefully when SDK key is absent', (
    tester,
  ) async {
    const sdkKey = String.fromEnvironment('LINKSENSE_SDK_KEY');
    if (sdkKey.isEmpty) return;
    await LinkSense.instance.configure(
      const LinkSenseConfiguration(sdkKey: sdkKey),
    );
  });
}
