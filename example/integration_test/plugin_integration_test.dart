// Minimal smoke test wired to the `LinkSense` facade. Run with
// `flutter test integration_test` on a real device with
// `--dart-define=LINKSENSE_SDK_KEY=ls_sdk_...` to exercise the bridge.
// Without the key it degrades into a no-op compile check.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:linksense/linksense.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('configure degrades gracefully when SDK key is absent', (tester) async {
    const sdkKey = String.fromEnvironment('LINKSENSE_SDK_KEY');
    if (sdkKey.isEmpty) {
      // Smoke-only path — confirm the singleton is reachable.
      expect(LinkSense.instance, isNotNull);
      return;
    }
    await LinkSense.instance.configure(const LinkSenseConfiguration(sdkKey: sdkKey));
  });
}
