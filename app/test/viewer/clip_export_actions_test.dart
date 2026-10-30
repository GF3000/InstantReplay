import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/features/viewer/clips/clip_store.dart';
import 'package:instant_replay/features/viewer/ui/clip_export_actions.dart';
import 'package:instant_replay/l10n/app_localizations.dart';

import 'fakes.dart';

class _FileClip extends MemoryClip {
  _FileClip() : super('c1', 10);

  @override
  String? get filePath => '/data/clips/c1.mp4';
}

void main() {
  Future<void> pump(WidgetTester tester, Capabilities caps, StoredClip clip) => tester.pumpWidget(
        ProviderScope(
          overrides: [capabilitiesProvider.overrideWithValue(caps)],
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              appBar: AppBar(actions: [ClipExportActions(stored: clip, fileName: 'clip.mp4')]),
            ),
          ),
        ),
      );

  testWidgets('Android shows Save to gallery and Share', (tester) async {
    await pump(tester, Capabilities.nativeAndroid, _FileClip());
    expect(find.byKey(const ValueKey('review-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-share')), findsOneWidget);
  });

  testWidgets('web shows neither', (tester) async {
    await pump(tester, Capabilities.web, _FileClip());
    expect(find.byKey(const ValueKey('review-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('review-share')), findsNothing);
  });

  testWidgets('a clip without a file shows neither', (tester) async {
    await pump(tester, Capabilities.nativeAndroid, MemoryClip('c1', 10));
    expect(find.byKey(const ValueKey('review-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('review-share')), findsNothing);
  });
}
