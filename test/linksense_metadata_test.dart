// Verifies that arbitrary metadata round-trips through the
// CreateLinkOptions serializer untouched — the Dart side hands raw
// Maps to the native bridge, which converts to its typed
// LinkMetadataValue tree (Kotlin) or Codable enum (Swift). The
// Flutter plugin contract is: anything JSON-shaped goes through.

import 'package:flutter_test/flutter_test.dart';
import 'package:linksense/linksense.dart';

void main() {
  group('metadata round-trip via toMap', () {
    test('preserves string values', () {
      final map = const CreateLinkOptions(
        name: 'x',
        metadata: {'campaign': 'spring-2026'},
      ).toMap();
      expect(map['metadata'], {'campaign': 'spring-2026'});
    });

    test('preserves nested map and list values', () {
      final metadata = <String, Object?>{
        'segments': <String>['us', 'eu'],
        'attributes': <String, Object?>{
          'tier': 'gold',
          'priority': 3,
          'flags': <String, Object?>{'beta': true},
        },
      };
      final map = CreateLinkOptions(name: 'x', metadata: metadata).toMap();
      expect(map['metadata'], metadata);
    });

    test('preserves numeric and boolean primitives', () {
      final map = const CreateLinkOptions(
        name: 'x',
        metadata: {'count': 42, 'ratio': 0.75, 'active': true},
      ).toMap();
      expect(map['metadata'], {'count': 42, 'ratio': 0.75, 'active': true});
    });

    test('preserves explicit null inside metadata', () {
      final map = const CreateLinkOptions(
        name: 'x',
        metadata: {'optional': null, 'present': 'yes'},
      ).toMap();
      final returned = map['metadata'] as Map;
      expect(returned['optional'], isNull);
      expect(returned.containsKey('optional'), isTrue);
      expect(returned['present'], 'yes');
    });
  });
}
