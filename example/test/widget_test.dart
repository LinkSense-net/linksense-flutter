import 'package:flutter_test/flutter_test.dart';

import 'package:linksense_example/main.dart';

void main() {
  testWidgets('Playground builds and renders the app bar title',
      (WidgetTester tester) async {
    await tester.pumpWidget(const LinkSensePlaygroundApp());
    expect(find.text('LinkSense playground'), findsOneWidget);
    expect(find.text('1. Configure & start'), findsOneWidget);
  });
}
