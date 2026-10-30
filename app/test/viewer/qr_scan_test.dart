import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/scan/qr_scan_page.dart';
import 'package:instant_replay/features/viewer/scan/qr_scanner.dart';
import 'package:instant_replay/features/viewer/ui/connect_view.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Stands in for the camera: the test feeds it the codes "seen" by the preview.
class _FakeScanner implements QrScanner {
  _FakeScanner({this.available = true, this.granted = true});

  final bool available;
  final bool granted;
  ValueChanged<String>? onCode;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> requestPermission() async => granted;

  @override
  Widget preview({required ValueChanged<String> onCode}) {
    this.onCode = onCode;
    return const ColoredBox(key: ValueKey('fake-preview'), color: Colors.black);
  }
}

void main() {
  late ProviderContainer container;

  Future<void> pump(WidgetTester tester, _FakeScanner scanner) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pageUriProvider.overrideWithValue(null),
        qrScannerProvider.overrideWithValue(scanner),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: Consumer(builder: (context, ref, _) {
          container = ProviderScope.containerOf(context);
          ref.watch(viewerSetupProvider);
          return const AddressForm();
        })),
      ),
    ));
    await tester.pumpAndSettle();
  }

  final scanButton = find.byKey(const ValueKey('viewer-scan-qr'));

  testWidgets('no scan button without a camera (web, or a device without one)', (tester) async {
    await pump(tester, _FakeScanner(available: false));
    expect(scanButton, findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('scan button shows when a camera is available', (tester) async {
    await pump(tester, _FakeScanner());
    expect(scanButton, findsOneWidget);
    expect(find.text('Scan QR'), findsOneWidget);
  });

  testWidgets('permission denied: a message, and the address field stays', (tester) async {
    await pump(tester, _FakeScanner(granted: false));
    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    expect(find.textContaining('No camera permission'), findsOneWidget);
    expect(find.byType(QrScanPage), findsNothing);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a foreign QR shows an error and keeps scanning; the camera QR connects', (tester) async {
    final scanner = _FakeScanner();
    await pump(tester, scanner);
    await tester.tap(scanButton);
    await tester.pumpAndSettle();
    expect(find.byType(QrScanPage), findsOneWidget);
    expect(find.text('Point at the QR shown on the camera'), findsOneWidget);

    scanner.onCode!('https://example.com/menu');
    await tester.pump();
    expect(find.textContaining('not from an InstantReplay camera'), findsOneWidget);
    expect(find.byType(QrScanPage), findsOneWidget);

    scanner.onCode!('http://192.168.43.1:8080/?k=qrtoken');
    scanner.onCode!('http://192.168.43.1:8080/?k=qrtoken'); // the same frame again: ignored
    await tester.pumpAndSettle();
    expect(find.byType(QrScanPage), findsNothing);
    final setup = container.read(viewerSetupProvider);
    expect(setup.base, Uri.parse('http://192.168.43.1:8080'));
    expect(setup.token, 'qrtoken');
  });
}
