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

class _WebClip extends MemoryClip {
  _WebClip() : super('c1', 10);

  final downloads = <String>[];

  @override
  bool get canDownload => true;

  @override
  Future<void> download(String fileName) async => downloads.add(fileName);
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

  test('the ways out per platform', () {
    expect(clipExportKinds(Capabilities.nativeAndroid, _FileClip()), [ClipExportKind.gallery, ClipExportKind.share]);
    expect(clipExportKinds(Capabilities.web, _WebClip()), [ClipExportKind.download]);
    expect(clipExportKinds(Capabilities.nativeAndroid, MemoryClip('c1', 10)), isEmpty);
  });

  testWidgets('Android: Export opens Save to gallery and Share', (tester) async {
    await pump(tester, Capabilities.nativeAndroid, _FileClip());
    expect(find.byKey(const ValueKey('review-gallery')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-export')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('review-gallery')), findsOneWidget);
    expect(find.byKey(const ValueKey('review-share')), findsOneWidget);
  });

  testWidgets('web: a single Download button', (tester) async {
    final clip = _WebClip();
    await pump(tester, Capabilities.web, clip);
    expect(find.byKey(const ValueKey('review-export')), findsNothing);
    expect(find.byKey(const ValueKey('review-gallery')), findsNothing);
    expect(find.byKey(const ValueKey('review-share')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('review-download')));
    await tester.pumpAndSettle();
    expect(clip.downloads, ['clip.mp4']);
  });

  testWidgets('a clip without a file shows nothing', (tester) async {
    await pump(tester, Capabilities.nativeAndroid, MemoryClip('c1', 10));
    expect(find.byKey(const ValueKey('review-export')), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
