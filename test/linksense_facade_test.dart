import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:linksense/linksense.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('net.linksense.flutter/method');

  final List<MethodCall> calls = <MethodCall>[];

  Future<Object?> handler(MethodCall call) async {
    calls.add(call);
    switch (call.method) {
      case 'configure':
      case 'start':
        return null;
      case 'getLink':
        return _fakeLinkMap(id: 'link-1');
      case 'createLink':
        return _fakeLinkMap(id: 'link-2', name: (call.arguments as Map)['name'] as String);
      case 'updateLink':
        return _fakeLinkMap(id: (call.arguments as Map)['id'] as String, name: 'renamed');
      case 'deleteLink':
        return null;
      default:
        throw MissingPluginException();
    }
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
  });

  group('configure', () {
    test('passes configuration map through the method channel', () async {
      await LinkSense.instance.configure(const LinkSenseConfiguration(
        sdkKey: 'ls_sdk_12345678_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        enableClipboard: true,
      ));
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map;
      expect(args['sdk_key'], 'ls_sdk_12345678_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(args['enable_clipboard'], true);
      expect(args['enable_install_referrer'], true);
      expect(args['log_level'], 'off');
    });
  });

  group('createLink', () {
    test('sends allowlisted fields and omits null ones', () async {
      await LinkSense.instance.createLink(const CreateLinkOptions(
        name: 'Maria invite',
        slug: 'maria',
        tags: ['launch'],
      ));
      final args = calls.single.arguments as Map;
      expect(args['name'], 'Maria invite');
      expect(args['slug'], 'maria');
      expect(args['tags'], ['launch']);
      expect(args.containsKey('desktop_url'), isFalse);
      expect(args.containsKey('metadata'), isFalse);
    });

    test('decodes the returned link', () async {
      final link = await LinkSense.instance.createLink(const CreateLinkOptions(name: 'Test'));
      expect(link.id, 'link-2');
      expect(link.name, 'Test');
      expect(link.tags, ['launch']);
    });
  });

  group('updateLink', () {
    test('omits absent fields and emits explicit null for clear sentinel', () async {
      await LinkSense.instance.updateLink('link-1', const UpdateLinkOptions(
        name: 'renamed',
        desktopUrl: linkSenseClear,
      ));
      final args = calls.single.arguments as Map;
      final options = args['options'] as Map;
      expect(options['name'], 'renamed');
      expect(options.containsKey('desktop_url'), isTrue);
      expect(options['desktop_url'], isNull);
      expect(options.containsKey('tags'), isFalse);
    });
  });

  group('deleteLink', () {
    test('sends id to deleteLink', () async {
      await LinkSense.instance.deleteLink('link-1');
      expect(calls.single.method, 'deleteLink');
      expect((calls.single.arguments as Map)['id'], 'link-1');
    });
  });

  group('platform-exception translation', () {
    test('FORBIDDEN_CROSS_SCOPE → typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'FORBIDDEN_CROSS_SCOPE', message: 'nope');
      });
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseForbiddenCrossScope>()),
      );
    });

    test('RATE_LIMITED passes retry-after into typed exception', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, (call) async {
        throw PlatformException(code: 'RATE_LIMITED', message: 'slow down', details: <String, Object?>{'retryAfter': 42});
      });
      try {
        await LinkSense.instance.getLink('link-1');
        fail('expected RateLimited exception');
      } on LinkSenseRateLimited catch (e) {
        expect(e.retryAfterSeconds, 42);
      }
    });

    test('MissingPluginException → NotConfigured', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseNotConfigured>()),
      );
    });
  });
}

Map<String, Object?> _fakeLinkMap({required String id, String name = 'Test'}) => <String, Object?>{
      'id': id,
      'project_id': 'project-1',
      'name': name,
      'custom_path': 'slug-$id',
      'full_url': 'https://acme-42.linksense.net/slug-$id',
      'desktop_url': null,
      'ios_fallback_url': null,
      'android_fallback_url': null,
      'og_title': null,
      'og_description': null,
      'og_image_url': null,
      'tags': ['launch'],
      'ios_clipboard_enabled': false,
      'created_at': '2026-04-21T10:00:00Z',
      'updated_at': '2026-04-21T10:00:00Z',
    };
