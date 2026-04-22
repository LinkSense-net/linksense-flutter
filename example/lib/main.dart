import 'dart:async';

import 'package:flutter/material.dart';
import 'package:linksense/linksense.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  Uri? _deferredLink;
  StreamSubscription<Uri?>? _subscription;

  @override
  void initState() {
    super.initState();
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    const sdkKey = String.fromEnvironment('LINKSENSE_SDK_KEY');
    if (sdkKey.isEmpty) {
      debugPrint('Set --dart-define=LINKSENSE_SDK_KEY=... to run the example against a real project.');
      return;
    }
    await LinkSense.instance.configure(const LinkSenseConfiguration(
      sdkKey: sdkKey,
      enableClipboard: false,
    ));
    _subscription = LinkSense.instance.deferredDeepLinks.listen((uri) {
      if (!mounted) return;
      setState(() => _deferredLink = uri);
    });
    await LinkSense.instance.start();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('LinkSense example')),
        body: Center(
          child: Text(
            _deferredLink == null
                ? 'No deferred deep link yet'
                : 'Resolved: $_deferredLink',
          ),
        ),
      ),
    );
  }
}
