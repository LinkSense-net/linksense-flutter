// Pure Dart serialization tests for the channel-bound models. No
// platform binding required — these exercise the contract the native
// bridges key off of.

import 'package:flutter_test/flutter_test.dart';
import 'package:linksense/linksense.dart';

void main() {
  group('LinkSenseConfiguration.toMap', () {
    test('emits required + default fields', () {
      final map = const LinkSenseConfiguration(sdkKey: 'ls_sdk_x_y').toMap();
      expect(map['sdk_key'], 'ls_sdk_x_y');
      expect(map['enable_clipboard'], false);
      expect(map['enable_install_referrer'], true);
      expect(map['enable_fingerprint'], true);
      expect(map['log_level'], 'off');
      // The native 0.2.0 SDKs fix the backend at build time.
      expect(map.containsKey('base_url'), isFalse);
    });

    test('serialises every log level', () {
      for (final level in LinkSenseLogLevel.values) {
        final map =
            LinkSenseConfiguration(sdkKey: 'ls_sdk_x_y', logLevel: level)
                .toMap();
        expect(map['log_level'], level.name);
      }
    });
  });

  group('CreateLinkOptions.toMap', () {
    test('omits null fields, includes provided ones', () {
      final map = const CreateLinkOptions(
        name: 'Maria',
        slug: 'maria',
        tags: ['campaign:spring'],
      ).toMap();
      expect(map['name'], 'Maria');
      expect(map['slug'], 'maria');
      expect(map['tags'], ['campaign:spring']);
      for (final k in const [
        'desktop_url',
        'metadata',
        'ios_clipboard_enabled',
        'ios_fallback_url',
        'android_fallback_url',
        'og_title',
        'og_description',
        'og_image_url'
      ]) {
        expect(map.containsKey(k), isFalse,
            reason: '$k should be omitted when null');
      }
    });

    test('preserves every supplied field', () {
      final map = CreateLinkOptions(
        name: 'X',
        desktopUrl: 'https://example.com',
        slug: 'x',
        tags: const ['t'],
        metadata: const {'k': 1},
        iosClipboardEnabled: true,
        iosFallbackUrl: 'https://ios.example',
        androidFallbackUrl: 'https://android.example',
        ogTitle: 'title',
        ogDescription: 'desc',
        ogImageUrl: 'https://img.example',
      ).toMap();
      expect(map, {
        'name': 'X',
        'desktop_url': 'https://example.com',
        'slug': 'x',
        'tags': ['t'],
        'metadata': {'k': 1},
        'ios_clipboard_enabled': true,
        'ios_fallback_url': 'https://ios.example',
        'android_fallback_url': 'https://android.example',
        'og_title': 'title',
        'og_description': 'desc',
        'og_image_url': 'https://img.example',
      });
    });
  });

  group('UpdateLinkOptions.toMap absent vs clear vs value', () {
    test('all-absent emits empty map', () {
      expect(const UpdateLinkOptions().toMap(), <String, Object?>{});
    });

    test('linkSenseClear emits explicit JSON null for every clearable field',
        () {
      final map = const UpdateLinkOptions(
        desktopUrl: linkSenseClear,
        metadata: linkSenseClear,
        iosFallbackUrl: linkSenseClear,
        androidFallbackUrl: linkSenseClear,
        ogTitle: linkSenseClear,
        ogDescription: linkSenseClear,
        ogImageUrl: linkSenseClear,
      ).toMap();
      for (final k in const [
        'desktop_url',
        'metadata',
        'ios_fallback_url',
        'android_fallback_url',
        'og_title',
        'og_description',
        'og_image_url'
      ]) {
        expect(map.containsKey(k), isTrue, reason: '$k key should be present');
        expect(map[k], isNull, reason: '$k should be JSON null');
      }
    });

    test('non-null values pass through unchanged', () {
      final map = UpdateLinkOptions(
        name: 'renamed',
        desktopUrl: 'https://new.example',
        tags: const ['x'],
        metadata: const {'k': 'v'},
        iosClipboardEnabled: true,
        iosFallbackUrl: 'https://ios',
        androidFallbackUrl: 'https://android',
        ogTitle: 'new title',
        ogDescription: 'new desc',
        ogImageUrl: 'https://img',
      ).toMap();
      expect(map, {
        'name': 'renamed',
        'desktop_url': 'https://new.example',
        'tags': ['x'],
        'metadata': {'k': 'v'},
        'ios_clipboard_enabled': true,
        'ios_fallback_url': 'https://ios',
        'android_fallback_url': 'https://android',
        'og_title': 'new title',
        'og_description': 'new desc',
        'og_image_url': 'https://img',
      });
    });
  });

  group('LinkSenseLink.fromMap', () {
    Map<String, Object?> base() => <String, Object?>{
          'id': 'link-1',
          'project_id': 'proj-1',
          'name': 'Test',
          'full_url': 'https://acme.linksense.net/test',
          'tags': const <String>[],
          'created_at': '2026-04-21T10:00:00.000Z',
          'updated_at': '2026-04-21T11:00:00.000Z',
        };

    test('accepts custom_path key (canonical)', () {
      final link = LinkSenseLink.fromMap({...base(), 'custom_path': 'test'});
      expect(link.slug, 'test');
    });

    test('accepts slug key (alias)', () {
      final link = LinkSenseLink.fromMap({...base(), 'slug': 'test'});
      expect(link.slug, 'test');
    });

    test('accepts both og_* and social_* aliases', () {
      final canonical = LinkSenseLink.fromMap({
        ...base(),
        'custom_path': 'x',
        'og_title': 'A',
        'og_description': 'B',
        'og_image_url': 'https://img/og',
      });
      expect(canonical.ogTitle, 'A');
      expect(canonical.ogDescription, 'B');
      expect(canonical.ogImageUrl, 'https://img/og');

      final aliased = LinkSenseLink.fromMap({
        ...base(),
        'custom_path': 'x',
        'social_title': 'C',
        'social_description': 'D',
        'social_image_url': 'https://img/social',
      });
      expect(aliased.ogTitle, 'C');
      expect(aliased.ogDescription, 'D');
      expect(aliased.ogImageUrl, 'https://img/social');
    });

    test('parses ISO 8601 timestamps', () {
      final link = LinkSenseLink.fromMap({...base(), 'custom_path': 'x'});
      expect(link.createdAt.toUtc(), DateTime.utc(2026, 4, 21, 10));
      expect(link.updatedAt.toUtc(), DateTime.utc(2026, 4, 21, 11));
    });

    test('defaults missing optional fields safely', () {
      final link = LinkSenseLink.fromMap({...base(), 'custom_path': 'x'});
      expect(link.desktopUrl, isNull);
      expect(link.iosFallbackUrl, isNull);
      expect(link.androidFallbackUrl, isNull);
      expect(link.ogTitle, isNull);
      expect(link.iosClipboardEnabled, isFalse);
      expect(link.tags, isEmpty);
    });
  });
}
