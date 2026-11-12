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
      case 'submitPastedLink':
        return 'https://acme.linksense.net/welcome';
      case 'getLink':
        return _fakeLinkMap(id: 'link-1');
      case 'createLink':
        return _fakeLinkMap(
            id: 'link-2', name: (call.arguments as Map)['name'] as String);
      case 'updateLink':
        return _fakeLinkMap(
            id: (call.arguments as Map)['id'] as String, name: 'renamed');
      case 'deleteLink':
        return null;
      default:
        throw MissingPluginException();
    }
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, handler);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null);
  });

  group('configure', () {
    test('passes configuration map through the method channel', () async {
      await LinkSense.instance.configure(const LinkSenseConfiguration(
        sdkKey: 'ls_sdk_12345678_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
        enableClipboard: true,
      ));
      expect(calls, hasLength(1));
      final args = calls.single.arguments as Map;
      expect(
          args['sdk_key'], 'ls_sdk_12345678_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
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
      final link = await LinkSense.instance
          .createLink(const CreateLinkOptions(name: 'Test'));
      expect(link.id, 'link-2');
      expect(link.name, 'Test');
      expect(link.tags, ['launch']);
    });
  });

  group('updateLink', () {
    test('omits absent fields and emits explicit null for clear sentinel',
        () async {
      await LinkSense.instance.updateLink(
          'link-1',
          const UpdateLinkOptions(
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

  group('submitPastedLink', () {
    test('sends the pasted text and parses the matched link', () async {
      final uri = await LinkSense.instance.submitPastedLink('see https://x');
      expect(calls.single.method, 'submitPastedLink');
      expect((calls.single.arguments as Map)['text'], 'see https://x');
      expect(uri, Uri.parse('https://acme.linksense.net/welcome'));
    });
  });

  group('platform-exception translation', () {
    void mockThrow(PlatformException ex) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async => throw ex);
    }

    test('FORBIDDEN_CROSS_SCOPE → typed exception', () async {
      mockThrow(
          PlatformException(code: 'FORBIDDEN_CROSS_SCOPE', message: 'nope'));
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseForbiddenCrossScope>()),
      );
    });

    test('RATE_LIMITED passes retry-after into typed exception', () async {
      mockThrow(PlatformException(
        code: 'RATE_LIMITED',
        message: 'slow down',
        details: <String, Object?>{'retryAfter': 42},
      ));
      try {
        await LinkSense.instance.getLink('link-1');
        fail('expected RateLimited exception');
      } on LinkSenseRateLimited catch (e) {
        expect(e.retryAfterSeconds, 42);
      }
    });

    test('DECODE_FAILURE → typed exception with reason', () async {
      mockThrow(
          PlatformException(code: 'DECODE_FAILURE', message: 'missing field'));
      try {
        await LinkSense.instance.getLink('link-1');
        fail('expected DecodeFailure');
      } on LinkSenseDecodeFailure catch (e) {
        expect(e.message, 'missing field');
        expect(e.code, 'DECODE_FAILURE');
      }
    });

    test('UNAUTHORIZED → typed exception', () async {
      mockThrow(PlatformException(code: 'UNAUTHORIZED', message: 'bad key'));
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseUnauthorized>()),
      );
    });

    test('NOT_FOUND → typed exception', () async {
      mockThrow(PlatformException(code: 'NOT_FOUND', message: 'gone'));
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseNotFound>()),
      );
    });

    test('CUSTOM_PATH_EXISTS → typed exception', () async {
      mockThrow(
          PlatformException(code: 'CUSTOM_PATH_EXISTS', message: 'taken'));
      expect(
        LinkSense.instance
            .createLink(const CreateLinkOptions(name: 'x', slug: 'taken')),
        throwsA(isA<LinkSenseCustomPathExists>()),
      );
    });

    test('INVALID_INPUT carries fieldErrors map', () async {
      mockThrow(PlatformException(
        code: 'INVALID_INPUT',
        message: 'validation',
        details: <String, Object?>{
          'fieldErrors': {
            'name': 'too short',
            'metadata.tag': 'must be string'
          },
        },
      ));
      try {
        await LinkSense.instance.createLink(const CreateLinkOptions(name: ''));
        fail('expected InvalidInput');
      } on LinkSenseInvalidInput catch (e) {
        expect(e.fieldErrors,
            {'name': 'too short', 'metadata.tag': 'must be string'});
      }
    });

    test('INVALID_INPUT with no details still produces typed exception',
        () async {
      mockThrow(
          PlatformException(code: 'INVALID_INPUT', message: 'validation'));
      try {
        await LinkSense.instance.createLink(const CreateLinkOptions(name: ''));
        fail('expected InvalidInput');
      } on LinkSenseInvalidInput catch (e) {
        expect(e.fieldErrors, isEmpty);
      }
    });

    test('Unknown code falls through to LinkSenseServerException with status',
        () async {
      mockThrow(PlatformException(
        code: 'BUNDLE_ID_EXISTS',
        message: 'collision',
        details: <String, Object?>{'status': 409},
      ));
      try {
        await LinkSense.instance.getLink('link-1');
        fail('expected ServerException');
      } on LinkSenseServerException catch (e) {
        expect(e.code, 'BUNDLE_ID_EXISTS');
        expect(e.status, 409);
      }
    });

    test('MissingPluginException → NotConfigured', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      expect(
        LinkSense.instance.getLink('link-1'),
        throwsA(isA<LinkSenseNotConfigured>()),
      );
    });
  });
}

Map<String, Object?> _fakeLinkMap({required String id, String name = 'Test'}) =>
    <String, Object?>{
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
