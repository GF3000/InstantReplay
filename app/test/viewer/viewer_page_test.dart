import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/capabilities.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/data/session_link.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/clip_list.dart';
import 'package:instant_replay/features/viewer/ui/live_control_view.dart';
import 'package:instant_replay/features/viewer/viewer_page.dart';
import 'package:instant_replay/features/viewer/viewer_providers.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:replay_protocol/replay_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ConnectedLink extends LinkStateNotifier {
  @override
  LinkState? build() => const LinkState(
    phase: LinkPhase.connected,
    camera: CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
    status: CameraStatus(recording: true, fps: 30, bufferMs: 60000, outboxClips: 0, thermalStatus: 0),
  );
}

/// A Camera with full-session recording in [rec].
class _RecLink extends LinkStateNotifier {
  _RecLink(this.rec, {this.phase = LinkPhase.connected});

  final SessionRecording rec;
  final LinkPhase phase;

  @override
  LinkState? build() => LinkState(
    phase: phase,
    camera: const CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch'),
    status: CameraStatus(
      recording: true,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 0,
      thermalStatus: 0,
      sessionRecording: rec,
    ),
  );
}

SessionRecording _rec(
  SessionRecordingState state, {
  int elapsedMs = 0,
  int parts = 1,
  bool lowSpace = false,
  int? remainingMs = 4 * 3600000,
}) => SessionRecording(
  state: state,
  elapsedMs: elapsedMs,
  parts: parts,
  freeBytes: 20000000000,
  lowSpace: lowSpace,
  remainingMs: remainingMs,
);

/// Records what the controls ask the Camera for; [push] plays the Camera's answers.
class _FakeRecording extends ViewerRecordingNotifier {
  _FakeRecording(this.sent);

  final List<String> sent;

  @override
  RecordingNotice? build() => null;

  @override
  bool record({int includeSeconds = 0}) {
    sent.add('record:$includeSeconds');
    return true;
  }

  @override
  bool pause() {
    sent.add('pause');
    return true;
  }

  @override
  bool finish() {
    sent.add('finish');
    return true;
  }

  void push(RecordingNotice notice) => state = notice;
}

Finder _vrec(String name) => find.byKey(ValueKey('viewer-rec-$name'));

class _RecordingClips extends ViewerClipsNotifier {
  _RecordingClips(this.saved, [this.clips = const []]);

  final List<int?> saved;
  final List<SessionClip> clips;

  @override
  List<SessionClip> build() => clips;

  @override
  String? save({int? seconds}) {
    saved.add(seconds);
    return 'r${saved.length}';
  }
}

/// Clips whose delete/undo/commit only hide and restore entries, recording each call.
class _DeletableClips extends ViewerClipsNotifier {
  _DeletableClips(this.all);

  final List<SessionClip> all;
  final hidden = <String>{};
  final calls = <String>[];

  @override
  List<SessionClip> build() => all;

  @override
  bool delete(String requestId) {
    calls.add('delete:$requestId');
    hidden.add(requestId);
    state = [
      for (final c in all)
        if (!hidden.contains(c.requestId)) c,
    ];
    return true;
  }

  @override
  void undoDelete(String requestId) {
    calls.add('undo:$requestId');
    hidden.remove(requestId);
    state = [
      for (final c in all)
        if (!hidden.contains(c.requestId)) c,
    ];
  }

  @override
  Future<void> commitDelete(String requestId) async => calls.add('commit:$requestId');
}

class _PlayingLive extends LiveViewNotifier {
  @override
  LiveViewState build() => const LiveViewState(phase: LivePhase.playing);
}

Future<SharedPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

Widget _app(Widget child, List<dynamic> overrides) => ProviderScope(
  overrides: overrides.cast(),
  child: MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  ),
);

/// Lets AnimatedSwitcher start and finish its 300 ms fade.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  _viewerPageTests();

  testWidgets('big button saves the default preset; chips save their own duration', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(
      _app(const SaveControls(), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        linkStateProvider.overrideWith(_ConnectedLink.new),
        viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
      ]),
    );
    expect(find.text('Save play'), findsOneWidget);
    expect(find.text('the last 20 s and 2 s more'), findsOneWidget);
    expect(find.text('10 s'), findsOneWidget);
    expect(find.text('30 s'), findsOneWidget);
    expect(find.text('60 s'), findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('viewer-save'))).height, greaterThanOrEqualTo(56));

    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await tester.tap(find.text('30 s'));
    await tester.tap(find.text('10 s'));
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, [null, 30, 10, null]);
    // The choice just used lights up, then goes back to normal.
    await tester.tap(find.text('30 s'));
    await tester.pump();
    bool selected(String key) => tester
        .widget<Semantics>(find.descendant(of: find.byKey(ValueKey(key)), matching: find.byType(Semantics)).first)
        .properties
        .selected!;
    expect(selected('viewer-save-30'), isTrue);
    expect(selected('viewer-save-10'), isFalse);
    await tester.pump(RecentSaveNotifier.highlightFor);
    expect(selected('viewer-save-30'), isFalse);
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
  });

  testWidgets('after a save the left panel tags that clip, a new save replaces it, Save stays free', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final saved = <int?>[];
    late WidgetRef ref;
    await tester.pumpWidget(
      _app(
        Consumer(
          builder: (context, r, _) {
            ref = r;
            return const LiveControlView();
          },
        ),
        [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          linkStateProvider.overrideWith(_ConnectedLink.new),
          liveViewProvider.overrideWith(_PlayingLive.new),
          viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
        ],
      ),
    );
    final bar = find.byKey(const ValueKey('viewer-tag-bar'));
    expect(bar, findsNothing);

    await tester.tap(find.byKey(const ValueKey('viewer-save'))); // r1
    await _settle(tester);
    expect(bar, findsOneWidget);
    // Over the bottom-left of the live view, clear of the Save button.
    final panel = tester.getRect(find.byKey(const ValueKey('viewer-tag-panel')));
    final live = tester.getRect(find.byType(LivePanel));
    expect(live.contains(panel.topLeft) && live.contains(panel.bottomRight - const Offset(1, 1)), isTrue);
    expect(panel.left - live.left, lessThan(20));
    expect(live.bottom - panel.bottom, lessThan(20));
    // The live view flashes amber.
    expect(find.byKey(const ValueKey('viewer-save-flash')), findsOneWidget);
    expect(panel.overlaps(tester.getRect(find.byKey(const ValueKey('viewer-save')))), isFalse);
    // The chips stay usable while the bar is up.
    await tester.tap(find.text('30 s')); // r2
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('tag-${TagsNotifier.bad}')));
    await _settle(tester);
    expect(ref.read(clipTagsProvider), {'r2': TagsNotifier.bad});
    expect(bar, findsNothing);

    // Untouched, the bar fades after ~6 s.
    await tester.tap(find.byKey(const ValueKey('viewer-save'))); // r3
    await _settle(tester);
    expect(bar, findsOneWidget);
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
    await _settle(tester);
    expect(bar, findsNothing);
    expect(ref.read(clipTagsProvider), {'r2': TagsNotifier.bad});

    // The close button hides it without tagging.
    await tester.tap(find.byKey(const ValueKey('viewer-save'))); // r4
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('viewer-tag-panel-close')));
    await _settle(tester);
    expect(bar, findsNothing);
    expect(ref.read(clipTagsProvider), {'r2': TagsNotifier.bad});
    // The save highlight fades on its own.
    await tester.pump(RecentSaveNotifier.highlightFor);
    expect(find.byKey(const ValueKey('viewer-save-flash')), findsNothing);
  });

  for (final size in const [Size(360, 640), Size(640, 360), Size(768, 1024), Size(1280, 800), Size(800, 416)]) {
    testWidgets('live screen fits ${size.width.toInt()}x${size.height.toInt()} without overflow', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final clips = [
        for (var i = 0; i < 12; i++)
          SessionClip(
            requestId: 'r$i',
            seconds: 20,
            requestedAt: DateTime(2026, 10, 29, 12, i),
            phase: SessionClipPhase.values[i % SessionClipPhase.values.length],
          ),
      ];
      // Leave room for the 48 px app bar of the paired Viewer. The recording row in its widest
      // state: paused (Resume, ▾, Finish), a second part and the low-space warning.
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              SizedBox(height: 48),
              Expanded(child: LiveControlView()),
            ],
          ),
          [
            sharedPreferencesProvider.overrideWithValue(await _prefs()),
            linkStateProvider.overrideWith(
              () => _RecLink(
                _rec(
                  SessionRecordingState.paused,
                  elapsedMs: 5025000,
                  parts: 2,
                  lowSpace: true,
                  remainingMs: 8 * 60000,
                ),
              ),
            ),
            liveViewProvider.overrideWith(_PlayingLive.new),
            viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
          ],
        ),
      );
      await tester.tap(find.byKey(const ValueKey('viewer-save')));
      await _settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('viewer-tag-bar')), findsOneWidget);
      final save = tester.getRect(find.byKey(const ValueKey('viewer-save')));
      expect(save.height, greaterThanOrEqualTo(56));
      expect(save.bottom, lessThanOrEqualTo(size.height));
      expect(find.byKey(const ValueKey('clip-row-r0')), findsOneWidget);
      // On a phone the tag panel drops over the live view, inside it.
      final live = tester.getRect(find.byType(LivePanel));
      final panel = tester.getRect(find.byKey(const ValueKey('viewer-tag-panel')));
      expect(panel.top, greaterThanOrEqualTo(live.top));
      expect(panel.bottom, lessThanOrEqualTo(live.bottom + 0.5));
      // The full-session recording moved to the app bar (ViewerRecordingButton).
      expect(_vrec('button'), findsNothing);
      // Quick-save labels stay on one line, however narrow the panel.
      for (final chip
          in find
              .byWidgetPredicate(
                (w) =>
                    w.key is ValueKey<String> &&
                    RegExp(r'^viewer-save-\d+$').hasMatch((w.key! as ValueKey<String>).value),
              )
              .evaluate()) {
        final label = find.descendant(of: find.byWidget(chip.widget), matching: find.byType(Text));
        expect(tester.getSize(label).height, lessThan(26), reason: 'one line');
      }
      await tester.pump(PostSaveTagBarNotifier.visibleFor);
      await _settle(tester);
    });
  }

  testWidgets('phone landscape keeps clip rows visible with filter chips and the tag bar', (tester) async {
    tester.view.physicalSize = const Size(640, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clips = [
      for (var i = 0; i < 6; i++)
        SessionClip(
          requestId: 'r$i',
          seconds: 20,
          requestedAt: DateTime(2026, 10, 29, 12, i),
          phase: SessionClipPhase.ready,
        ),
    ];
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            SizedBox(height: 48),
            Expanded(child: LiveControlView()),
          ],
        ),
        [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          linkStateProvider.overrideWith(_ConnectedLink.new),
          liveViewProvider.overrideWith(_PlayingLive.new),
          viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
        ],
      ),
    );
    final ref = ProviderScope.containerOf(tester.element(find.byType(LiveControlView)));
    ref.read(clipTagsProvider.notifier)
      ..set('r0', TagsNotifier.good)
      ..set('r1', TagsNotifier.bad);
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('filter-all')), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer-tag-bar')), findsOneWidget);
    // At least one full clip row and part of the next stay on screen.
    final rows = find.byType(ClipTile);
    expect(rows, findsAtLeast(2));
    expect(tester.getRect(rows.first).bottom, lessThanOrEqualTo(360));
    await tester.pump(PostSaveTagBarNotifier.visibleFor);
    await _settle(tester);
    // With the tag bar gone, the quick chips are back in its place.
    expect(find.byKey(const ValueKey('viewer-save-30')), findsOneWidget);
  });

  group('full-session recording', () {
    Future<_FakeRecording> pump(WidgetTester tester, LinkStateNotifier Function() link) async {
      final remote = _FakeRecording([]);
      // The app bar's button over the live view, which shows the recording's notices.
      await tester.pumpWidget(
        _app(
          const Column(
            children: [
              Row(children: [Spacer(), ViewerRecordingButton()]),
              Expanded(child: LiveControlView()),
            ],
          ),
          [
            sharedPreferencesProvider.overrideWithValue(await _prefs()),
            linkStateProvider.overrideWith(link),
            liveViewProvider.overrideWith(_PlayingLive.new),
            viewerClipsProvider.overrideWith(() => _RecordingClips([])),
            viewerRecordingProvider.overrideWith(() => remote),
          ],
        ),
      );
      // Not pumpAndSettle: a reconnecting link keeps a spinner going.
      await tester.pump();
      return remote;
    }

    testWidgets('hidden when the Camera does not send it (an older Camera)', (tester) async {
      await pump(tester, _ConnectedLink.new);
      expect(find.byKey(const ValueKey('viewer-recording')), findsNothing);
      expect(_vrec('button'), findsNothing);
    });

    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(_vrec('button'));
      await tester.pumpAndSettle();
    }

    testWidgets('idle: an icon; its dialog shows the space and records from now or with the last 30 s', (tester) async {
      final remote = await pump(tester, () => _RecLink(_rec(SessionRecordingState.idle, parts: 0)));
      expect(find.byTooltip('Full recording'), findsOneWidget);
      expect(remote.sent, isEmpty, reason: 'the button alone never records');

      await openDialog(tester);
      expect(find.text('4 h left'), findsOneWidget);
      expect(_vrec('pause'), findsNothing);
      expect(_vrec('finish'), findsNothing);
      await tester.tap(_vrec('record'));
      await tester.pumpAndSettle();
      expect(_vrec('dialog'), findsNothing);

      await openDialog(tester);
      expect(find.text('Record including the last 30 s'), findsOneWidget);
      await tester.tap(_vrec('record-include'));
      await tester.pumpAndSettle();
      expect(remote.sent, ['record:0', 'record:30']);
    });

    testWidgets('recording: elapsed time and part; Pause; Finish only after confirming', (tester) async {
      final remote = await pump(
        tester,
        () => _RecLink(_rec(SessionRecordingState.recording, elapsedMs: 3723000, parts: 2)),
      );
      // The button shows the time; the dialog the part too.
      expect(find.text('1:02:03'), findsOneWidget);
      await openDialog(tester);
      expect(find.text('1:02:03 · part 2'), findsOneWidget);
      expect(_vrec('record'), findsNothing);

      await tester.tap(_vrec('pause'));
      await tester.pumpAndSettle();
      expect(remote.sent, ['pause']);

      await openDialog(tester);
      await tester.tap(_vrec('finish'));
      await tester.pumpAndSettle();
      expect(find.text('Finish the recording?'), findsOneWidget);
      expect(find.textContaining('1:02:03'), findsWidgets);
      await tester.tap(find.byKey(const ValueKey('rec-finish-keep')));
      await tester.pumpAndSettle();
      expect(remote.sent, ['pause']);

      await openDialog(tester);
      await tester.tap(_vrec('finish'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('rec-finish-confirm')));
      await tester.pumpAndSettle();
      expect(remote.sent, ['pause', 'finish']);
    });

    testWidgets('paused: Resume, or resume with the last 30 s', (tester) async {
      final remote = await pump(tester, () => _RecLink(_rec(SessionRecordingState.paused, elapsedMs: 600000)));
      expect(find.text('10:00'), findsOneWidget);
      await openDialog(tester);
      expect(find.text('Paused · 10:00'), findsOneWidget);
      await tester.tap(_vrec('record'));
      await tester.pumpAndSettle();
      await openDialog(tester);
      expect(find.text('Resume including the last 30 s'), findsOneWidget);
      await tester.tap(_vrec('record-include'));
      await tester.pumpAndSettle();
      expect(remote.sent, ['record:0', 'record:30']);
    });

    testWidgets('warns on low space', (tester) async {
      await pump(
        tester,
        () => _RecLink(_rec(SessionRecordingState.recording, elapsedMs: 60000, lowSpace: true, remainingMs: 9 * 60000)),
      );
      await openDialog(tester);
      expect(find.text('Low space: 9 min left'), findsOneWidget);
      expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    });

    testWidgets('disabled while reconnecting', (tester) async {
      final remote = await pump(
        tester,
        () => _RecLink(_rec(SessionRecordingState.recording), phase: LinkPhase.reconnecting),
      );
      // The button is disabled: no dialog, nothing sent.
      await tester.tap(_vrec('button'), warnIfMissed: false);
      await tester.pump();
      expect(_vrec('dialog'), findsNothing);
      expect(remote.sent, isEmpty);
    });

    testWidgets('tells when a recording is saved, stopped for space, or refused', (tester) async {
      // Snackbars queue: let the current one show its 4 s and leave.
      Future<void> nextSnackBar() async {
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
      }

      final remote = await pump(tester, () => _RecLink(_rec(SessionRecordingState.recording)));
      remote.push(
        const RecordingEnded(
          RecordingFinished(name: 'a.mp4', parts: 1, durationMs: 47 * 60000, reason: RecordingEndReason.user),
        ),
      );
      await tester.pump();
      expect(find.text("Recording saved to the camera's gallery (47 min)"), findsOneWidget);

      remote.push(
        const RecordingEnded(
          RecordingFinished(name: 'a.mp4', parts: 2, durationMs: 2 * 3600000, reason: RecordingEndReason.lowSpace),
        ),
      );
      await nextSnackBar();
      expect(find.text('The camera ran out of space: the recording stopped and was saved (2 h)'), findsOneWidget);

      remote.push(const RecordingRefused('no_space', null));
      await nextSnackBar();
      expect(find.text('Not enough space on the camera to record (it needs 1 GB free)'), findsOneWidget);
    });
  });

  testWidgets('save is disabled while not connected', (tester) async {
    final saved = <int?>[];
    await tester.pumpWidget(
      _app(const SaveControls(), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        linkStateProvider.overrideWith(() => _NullLink()),
        viewerClipsProvider.overrideWith(() => _RecordingClips(saved)),
      ]),
    );
    await tester.tap(find.byKey(const ValueKey('viewer-save')));
    expect(saved, isEmpty);
  });

  testWidgets('Android without a camera asks for the address, then the code', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      _app(const ViewerPage(), [
        sharedPreferencesProvider.overrideWithValue(prefs),
        pageUriProvider.overrideWithValue(null),
      ]),
    );
    expect(find.text('Connect to the camera'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '192.168.1.20');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code shown on the camera'), findsOneWidget);
    expect(find.text('Camera at http://192.168.1.20:8080'), findsOneWidget);
  });

  testWidgets('swipe deletes a finished clip with Undo; clips in progress cannot be swiped', (tester) async {
    final clips = _DeletableClips([
      SessionClip(
        requestId: 'busy',
        seconds: 20,
        requestedAt: DateTime(2026, 10, 30, 12, 2),
        phase: SessionClipPhase.downloading,
      ),
      SessionClip(
        requestId: 'b',
        seconds: 20,
        requestedAt: DateTime(2026, 10, 30, 12, 1),
        phase: SessionClipPhase.ready,
      ),
      SessionClip(
        requestId: 'a',
        seconds: 20,
        requestedAt: DateTime(2026, 10, 30, 12, 0),
        phase: SessionClipPhase.failed,
      ),
    ]);
    await tester.pumpWidget(
      _app(const ClipList(), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        viewerClipsProvider.overrideWith(() => clips),
      ]),
    );

    // The downloading clip's spinner never settles, so the test steps through the swipe animations.
    Future<void> step() async {
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
    }

    await tester.drag(find.byKey(const ValueKey('clip-row-busy')), const Offset(-600, 0));
    await step();
    expect(find.byKey(const ValueKey('clip-row-busy')), findsOneWidget, reason: 'still downloading');
    expect(clips.calls, isEmpty);

    await tester.drag(find.byKey(const ValueKey('clip-row-b')), const Offset(-600, 0));
    await step();
    expect(find.byKey(const ValueKey('clip-row-b')), findsNothing);
    expect(find.text('Clip · 12:01 deleted'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await step();
    expect(find.byKey(const ValueKey('clip-row-b')), findsOneWidget);
    expect(clips.calls, ['delete:b', 'undo:b']);

    // A failed clip too; without Undo the deletion stands once the SnackBar goes.
    await tester.drag(find.byKey(const ValueKey('clip-row-a')), const Offset(-600, 0));
    await step();
    await tester.pump(const Duration(seconds: 10));
    await step();
    expect(find.byKey(const ValueKey('clip-row-a')), findsNothing);
    expect(clips.calls.skip(2), ['delete:a', 'commit:a']);
  });
}

class _NullLink extends LinkStateNotifier {
  @override
  LinkState? build() => null;
}

class _Paired extends ViewerSetupNotifier {
  @override
  ViewerSetup build() => ViewerSetup(base: Uri.parse('http://cam:8080'), token: 't');
}

/// A Camera in broadcast mode, streaming with the mic closed, and recording the full session.
class _StreamingLink extends LinkStateNotifier {
  @override
  LinkState? build() => const LinkState(
    phase: LinkPhase.connected,
    camera: CameraInfo(protocolVersion: 1, cameraId: 'c', name: 'Pitch with a rather long name'),
    status: CameraStatus(
      recording: true,
      fps: 30,
      bufferMs: 60000,
      outboxClips: 0,
      thermalStatus: 0,
      scoreboard: ScoreboardState(
        home: TeamState(name: 'LIONS', score: 2, color: 0xFF1E88E5),
        away: TeamState(name: 'HAWKS', score: 1, color: 0xFFFAFAFA),
        period: 1,
        clockMs: 0,
      ),
      broadcast: BroadcastInfo(
        state: BroadcastStreamState.live,
        configured: true,
        server: BroadcastInfo.defaultServer,
        targetKbps: 4500,
        audio: false,
      ),
      sessionRecording: SessionRecording(
        state: SessionRecordingState.recording,
        elapsedMs: 3723000,
        parts: 1,
        freeBytes: 1,
        lowSpace: false,
      ),
    ),
  );
}

class _FixedMicLevel extends ViewerMicLevelNotifier {
  _FixedMicLevel(this.db);

  final double db;

  @override
  double? build() => db;
}

class _MicRemote extends ViewerBroadcastNotifier {
  final audio = <bool>[];

  @override
  BroadcastNotice? build() => null;

  @override
  bool configure({
    required String server,
    String? key,
    required int targetKbps,
    required bool audio,
    bool? replayScoreboard,
  }) {
    this.audio.add(audio);
    return true;
  }
}

void _viewerPageTests() {
  Future<_MicRemote> pumpPage(WidgetTester tester, Size size, LinkStateNotifier Function() link,
      {double? micDb}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final remote = _MicRemote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          capabilitiesProvider.overrideWithValue(Capabilities.web),
          viewerSetupProvider.overrideWith(_Paired.new),
          linkStateProvider.overrideWith(link),
          liveViewProvider.overrideWith(_PlayingLive.new),
          viewerClipsProvider.overrideWith(() => _RecordingClips([])),
          viewerBroadcastNoticeProvider.overrideWith(() => remote),
          if (micDb != null) viewerMicLevelProvider.overrideWith(() => _FixedMicLevel(micDb)),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const ViewerPage(),
        ),
      ),
    );
    await tester.pump();
    return remote;
  }

  testWidgets('top bar fits 360 dp: name, teams, status pill with the recording clock, mic and menu', (tester) async {
    final remote = await pumpPage(tester, const Size(360, 640), _StreamingLink.new);
    expect(tester.takeException(), isNull);
    expect(find.text('LIONS vs HAWKS'), findsOneWidget);
    expect(find.text('REC'), findsOneWidget);
    expect(find.text('1:02:03'), findsOneWidget);
    for (final k in ['viewer-status', 'viewer-broadcast-mic', 'viewer-menu']) {
      final r = tester.getRect(find.byKey(ValueKey(k)));
      expect(r.right, lessThanOrEqualTo(360), reason: k);
      expect(r.height, greaterThanOrEqualTo(44), reason: k);
    }
    // Mic closed while streaming: the live view says YouTube hears nothing; one tap opens it.
    expect(find.byKey(const ValueKey('viewer-no-sound-badge')), findsOneWidget);
    expect(find.text('STREAM WITHOUT SOUND'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-broadcast-mic')));
    expect(remote.audio, [true]);
  });

  testWidgets("the mic shows the Camera's real level, and no bars without one", (tester) async {
    await pumpPage(tester, const Size(360, 640), _StreamingLink.new);
    expect(find.byKey(const ValueKey('ir-mic-level')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester, const Size(360, 640), _StreamingLink.new, micDb: -20);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('viewer-broadcast-mic')),
        matching: find.byKey(const ValueKey('ir-mic-level')),
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('ir-mic-bar-2-on')), findsOneWidget);
    expect(find.byKey(const ValueKey('ir-mic-bar-3-off')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no mic and no sound badge outside broadcast mode', (tester) async {
    await pumpPage(tester, const Size(360, 640), _ConnectedLink.new);
    expect(find.byKey(const ValueKey('viewer-broadcast-mic')), findsNothing);
    expect(find.byKey(const ValueKey('viewer-no-sound-badge')), findsNothing);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('the menu sheet holds every action; panel switches act in place', (tester) async {
    await pumpPage(tester, const Size(360, 640), _StreamingLink.new);
    await tester.tap(find.byKey(const ValueKey('viewer-menu')));
    await tester.pumpAndSettle();
    for (final text in [
      'Edit tags',
      'Full recording',
      'PANELS',
      'Live view',
      'Scoreboard',
      'Replays',
      'Settings',
      'Switch role',
    ]) {
      expect(find.text(text), findsWidgets, reason: text);
    }
    expect(find.text('Change camera'), findsOneWidget);
    expect(find.byType(LivePanel), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('viewer-panel-viewerLive')));
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsOneWidget, reason: 'the sheet stays open');
    expect(find.byType(LivePanel), findsNothing);

    // An action closes the sheet and runs: the full recording's dialog.
    await tester.tap(find.byKey(const ValueKey('viewer-menu-recording')));
    await tester.pumpAndSettle();
    expect(_vrec('dialog'), findsOneWidget);
  });

  testWidgets('tablet: the match at a glance shows a mark per clip, coloured by tag', (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final clips = [
      for (var i = 0; i < 4; i++)
        SessionClip(
          requestId: 'r$i',
          seconds: 20,
          requestedAt: DateTime(2026, 10, 29, 12, i * 5),
          phase: SessionClipPhase.ready,
        ),
    ];
    await tester.pumpWidget(
      _app(
        const Column(
          children: [
            SizedBox(height: 56),
            Expanded(child: LiveControlView()),
          ],
        ),
        [
          sharedPreferencesProvider.overrideWithValue(await _prefs()),
          linkStateProvider.overrideWith(_ConnectedLink.new),
          liveViewProvider.overrideWith(_PlayingLive.new),
          viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
        ],
      ),
    );
    final ref = ProviderScope.containerOf(tester.element(find.byType(LiveControlView)));
    ref.read(clipTagsProvider.notifier).set('r2', TagsNotifier.good);
    await tester.pump();
    expect(find.byType(MatchGlance), findsOneWidget);
    expect(find.text('Match at a glance'), findsOneWidget);
    // Oldest on the left.
    final x = [for (var i = 0; i < 4; i++) tester.getCenter(find.byKey(ValueKey('glance-r$i'))).dx];
    expect(x, orderedEquals([...x]..sort()));
    final mark = tester.widget<Container>(
      find.descendant(of: find.byKey(const ValueKey('glance-r2')), matching: find.byType(Container)),
    );
    expect((mark.decoration! as BoxDecoration).color, TagsNotifier.defaults.first.colour);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty cue list: one line and a hint', (tester) async {
    await tester.pumpWidget(
      _app(const ClipList(), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        viewerClipsProvider.overrideWith(() => _RecordingClips([])),
      ]),
    );
    expect(find.text('Saved clips appear here.'), findsOneWidget);
    expect(find.text('Tap Save play right after a good moment.'), findsOneWidget);
  });

  testWidgets('a clip row shows the tag as title, time and state in mono, and a visible tag button', (tester) async {
    final clips = [
      SessionClip(
        requestId: 'a',
        seconds: 20,
        requestedAt: DateTime(2026, 10, 29, 18, 40),
        phase: SessionClipPhase.ready,
      ),
    ];
    await tester.pumpWidget(
      _app(const ClipList(), [
        sharedPreferencesProvider.overrideWithValue(await _prefs()),
        viewerClipsProvider.overrideWith(() => _RecordingClips([], clips)),
      ]),
    );
    final ref = ProviderScope.containerOf(tester.element(find.byType(ClipList)));
    expect(find.text('No tag'), findsOneWidget);
    ref.read(clipTagsProvider.notifier).set('a', TagsNotifier.good);
    await tester.pump();
    expect(find.descendant(of: find.byKey(const ValueKey('clip-row-a')), matching: find.text('Good')), findsOneWidget);
    expect(find.text('18:40 · Ready'), findsOneWidget);
    expect(find.text('20 s'), findsOneWidget);
    // The filter chips count the clips.
    expect(find.descendant(of: find.byKey(const ValueKey('filter-all')), matching: find.text('1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('clip-tag-a')));
    await tester.pumpAndSettle();
    expect(find.text('Tag'), findsOneWidget, reason: 'the tag sheet opens');
  });
}
