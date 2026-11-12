import 'dart:io';
import 'dart:ui' as ui;

import 'package:device_frame/device_frame.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/app/theme.dart';
import 'package:instant_replay/l10n/app_localizations.dart';

import 'pitch_painter.dart';

/// Where the PNGs go (from `app/`).
const outputDir = '../docs/screenshots';

/// Optional real photos (16:9 JPG or PNG): `live`, then `clip1`, `clip2`... for the thumbnails.
/// Missing ones are drawn ([PitchPainter]).
const framesDir = 'marketing/frames';

final _shot = GlobalKey();

/// Real text and icons in test renders: Roboto from `app/fonts`, Material Icons from the SDK.
Future<void> loadFonts() async {
  Future<ByteData> bytes(String path) async => ByteData.sublistView(File(path).readAsBytesSync());
  final roboto = FontLoader('Roboto');
  for (final f in ['Regular', 'Italic', 'Medium', 'Bold']) {
    roboto.addFont(bytes('fonts/Roboto/Roboto-$f.ttf'));
  }
  await roboto.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(bytes('${_flutterRoot()}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'));
  await icons.load();
}

String _flutterRoot() {
  if (Platform.environment['FLUTTER_ROOT'] case final root? when root.isNotEmpty) return root;
  // flutter_tester lives in <root>/bin/cache/artifacts/engine/<platform>/.
  var dir = File(Platform.resolvedExecutable).parent;
  for (var i = 0; i < 5; i++) {
    dir = dir.parent;
  }
  return dir.path;
}

/// The frame shown as live video, video in review, and thumbnail [index] (0 = live).
Future<Uint8List> frame(int index) async {
  final name = index == 0 ? 'live' : 'clip$index';
  for (final ext in ['jpg', 'jpeg', 'png']) {
    final f = File('$framesDir/$name.$ext');
    if (f.existsSync()) return f.readAsBytesSync();
  }
  if (index > 0) {
    // Without its own photo a thumbnail reuses the live photo, if there is one.
    for (final ext in ['jpg', 'jpeg', 'png']) {
      final f = File('$framesDir/live.$ext');
      if (f.existsSync()) return f.readAsBytesSync();
    }
  }
  return Uint8List.fromList(await renderPitchPng(index == 0 ? 11 : 11 + index * 17));
}

/// A laptop whose browser fills the screen (device_frame's own laptops show a small window on
/// a wallpaper).
final laptop = DeviceInfo.genericLaptop(
  platform: TargetPlatform.windows,
  name: 'Laptop',
  id: 'laptop-full',
  screenSize: const Size(1440, 900),
  windowPosition: Rect.fromLTWH(0, 0, 1440, 900),
);

/// Where the telestrator shot draws, as fractions of the review frame (0,0 top left).
class Marks {
  const Marks({required this.arrowFrom, required this.arrowTo, required this.circleFrom, required this.circleTo});

  final Offset arrowFrom;
  final Offset arrowTo;

  /// Opposite corners of the box the circle fits.
  final Offset circleFrom;
  final Offset circleTo;
}

/// For `marketing/frames/review.jpg`: the pass from #24 to the teammate below, and the goalkeeper.
/// Move these when you change that photo.
const photoMarks = Marks(
  arrowFrom: Offset(0.63, 0.64),
  arrowTo: Offset(0.36, 0.80),
  circleFrom: Offset(0.23, 0.46),
  circleTo: Offset(0.32, 0.70),
);

/// For the drawn pitch ([PitchPainter]).
final pitchMarks = Marks(
  arrowFrom: keyPlayer + const Offset(0.03, -0.12),
  arrowTo: runTarget,
  circleFrom: markedPlayer + const Offset(-0.05, -0.20),
  circleTo: markedPlayer + const Offset(0.05, 0.03),
);

typedef ReviewFrame = ({Uint8List image, Marks marks});

/// The paused frame of the review shot: `review.jpg`, else the live frame (with [pitchMarks]).
Future<ReviewFrame> reviewFrame() async {
  for (final ext in ['jpg', 'jpeg', 'png']) {
    final f = File('$framesDir/review.$ext');
    if (f.existsSync()) return (image: f.readAsBytesSync(), marks: photoMarks);
  }
  return (image: await frame(0), marks: pitchMarks);
}

/// The app as the store and the website show it: dark theme, no debug banner.
Widget app(Locale locale, Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

/// [screen] inside [device]'s frame, with a status bar on phones and tablets.
Widget framed(DeviceInfo device, Orientation orientation, Widget screen) {
  final mobile = device.identifier.platform == TargetPlatform.android || device.identifier.platform == TargetPlatform.iOS;
  return RepaintBoundary(
    key: _shot,
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: DeviceFrame(
        device: device,
        orientation: orientation,
        screen: mobile ? _StatusBar(child: screen) : screen,
      ),
    ),
  );
}

/// Sizes the test view to the frame, pumps [widget] and waits for its images to decode.
Future<void> pumpFramed(WidgetTester tester, DeviceInfo device, Orientation orientation, Widget widget) async {
  final size = device.frameSize;
  // Phone and tablet frames are drawn upright; a landscape shot turns them. Laptops already are.
  final landscape = device.isLandscape(orientation) && size.height > size.width;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = landscape ? size.flipped : size;
  addTearDown(tester.view.reset);
  // Tests paint without shadows by default; the shots want them. [capture] turns them back off.
  debugDisableShadows = false;
  await tester.pumpWidget(MediaQuery(data: MediaQueryData.fromView(tester.view), child: widget));
  await settleImages(tester);
}

/// Decodes every Image on screen (real async work, outside the fake clock), then repaints.
Future<void> settleImages(WidgetTester tester) async {
  // Twice: thumbnails only appear once their futures resolve, after the first round.
  for (var round = 0; round < 2; round++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
      for (final e in find.byType(Image).evaluate()) {
        await precacheImage((e.widget as Image).image, e);
      }
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }
}

/// Writes the framed shot to `docs/screenshots/<name>.png`, [width] pixels wide.
Future<void> capture(WidgetTester tester, String name, {double width = 2000}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_shot));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: width / boundary.size.width);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  debugDisableShadows = true;
  final file = File('$outputDir/$name.png');
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes!);
}

/// A plain Android status bar in the device's top inset: time on the left, signal, Wi-Fi and
/// battery on the right.
class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    const style = TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500, fontFamily: 'Roboto');
    return Stack(children: [
      Positioned.fill(child: child),
      if (top > 0)
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: top,
          child: ColoredBox(
            color: Colors.black,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              child: Row(children: const [
                Text('18:42', style: style),
                Spacer(),
                Icon(Icons.signal_cellular_alt, color: Colors.white, size: 15),
                SizedBox(width: 4),
                Icon(Icons.wifi, color: Colors.white, size: 15),
                SizedBox(width: 4),
                Icon(Icons.battery_5_bar, color: Colors.white, size: 15),
              ]),
            ),
          ),
        ),
    ]);
  }
}
