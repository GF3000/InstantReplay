import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/capabilities.dart';
import '../../core/preferences.dart';
import '../viewer/clips/clip_store.dart';
import '../viewer/clips/clip_transfers.dart';
import '../viewer/tags/tags.dart';
import '../viewer/viewer_providers.dart';
import 'data/library_connection.dart';
import 'data/library_database.dart';
import 'data/library_files.dart';
import 'data/templates.dart';

// region Injection points (overridden in tests)

/// Android only: the web Viewer keeps the current session in memory (D15).
final libraryDatabaseProvider = Provider<LibraryDatabase>((ref) {
  final db = LibraryDatabase(
    openLibraryConnection(),
    legacyTagsJson: ref.read(sharedPreferencesProvider).getString(TagsNotifier.storageKey),
  );
  ref.onDispose(db.close);
  return db;
});

/// `<app files>`: the library keeps clips under `clips/<sessionId>/<clipId>.mp4` there.
final libraryRootProvider = Provider<Future<String> Function()>(
  (_) => () async => (await getApplicationSupportDirectory()).path,
);

/// Removes clip files; tests swap it for a recorder.
final clipFileDeleterProvider = Provider<Future<void> Function(Iterable<String>)>((_) => deleteClipFiles);

// endregion

/// Whether this Viewer keeps a library: native Android.
final libraryEnabledProvider = Provider<bool>((ref) => ref.watch(capabilitiesProvider).hasPersistentLibrary);

// region Active session

/// The library session clips are saved into, with its template's tags in order.
@immutable
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.name,
    required this.type,
    required this.templateId,
    this.tags = const [],
  });

  final String id;
  final String name;
  final SessionType type;
  final String? templateId;
  final List<ViewerTag> tags;

  ActiveSession copyWith({List<ViewerTag>? tags}) =>
      ActiveSession(id: id, name: name, type: type, templateId: templateId, tags: tags ?? this.tags);
}

/// The session picked in the session picker (SPEC §5.1.3); null until one is picked. Not kept
/// across restarts: the picker offers to continue the latest one instead.
class ActiveSessionNotifier extends Notifier<ActiveSession?> {
  @override
  ActiveSession? build() => null;

  LibraryDatabase get _db => ref.read(libraryDatabaseProvider);

  Future<void> start({required String name, required SessionType type, required String? templateId}) async {
    final row = await _db.createSession(name: name, type: type, templateId: templateId);
    await resume(row);
  }

  Future<void> resume(SessionRow row) async {
    final content = row.templateId == null ? null : await _db.templateContent(row.templateId!);
    if (!ref.mounted) return;
    state = ActiveSession(
      id: row.id,
      name: row.name,
      type: row.type,
      templateId: content?.template.id,
      tags: [for (final t in content?.tags ?? const <TagRow>[]) tagLabel(t)],
    );
  }

  /// The active session, or a new one named after the date when a clip arrives without one.
  Future<ActiveSession> ensure() async {
    if (state case final s?) return s;
    await start(
      name: DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now()),
      type: SessionType.other,
      templateId: BuiltInTemplates.generic,
    );
    return state!;
  }

  /// Back to the session picker.
  void close() => state = null;

  /// The tag editor changed the template's tags.
  void setTags(List<ViewerTag> tags) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(tags: tags);
    final templateId = s.templateId;
    if (templateId == null) return; // Its template was deleted: edits last for this run only.
    unawaited(() async {
      try {
        await _db.replaceTags(templateId, [for (final t in tags) LabelSpec(id: t.id, name: t.name, color: t.color)]);
      } catch (e) {
        debugPrint('Could not save template tags: $e');
      }
    }());
  }
}

final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, ActiveSession?>(ActiveSessionNotifier.new);

ViewerTag tagLabel(TagRow t) => ViewerTag(id: t.id, name: t.name, color: t.color);

// endregion

// region Saving clips into the library

/// Records the clips the Android store writes (SPEC §5.2: "move into library").
class LibraryCatalog implements ClipCatalog {
  LibraryCatalog(this._ref);

  final Ref _ref;
  final _sessionOf = <String, String>{};

  @override
  Future<String> pathFor(String clipId) async {
    final session = await _ref.read(activeSessionProvider.notifier).ensure();
    _sessionOf[clipId] = session.id;
    final root = await _ref.read(libraryRootProvider)();
    return '$root/clips/${session.id}/$clipId.mp4';
  }

  @override
  Future<void> added(String clipId, String path, Uint8List bytes) async {
    final db = _ref.read(libraryDatabaseProvider);
    final sessionId = _sessionOf.remove(clipId) ?? (await _ref.read(activeSessionProvider.notifier).ensure()).id;
    final now = DateTime.now();
    await db.addClip(ClipsCompanion.insert(
      id: clipId,
      sessionId: sessionId,
      requestedAt: now,
      filePath: path,
      sizeBytes: bytes.length,
      createdAt: now,
      updatedAt: now,
    ));
    // The transfer already checked the hash; this records it without holding up the ack.
    unawaited(() async {
      try {
        await db.updateClip(clipId, ClipsCompanion(sha256: Value(await compute(_sha256, bytes))));
      } catch (e) {
        debugPrint('Could not hash clip $clipId: $e');
      }
    }());
  }

  static String _sha256(Uint8List bytes) => sha256.convert(bytes).toString();
}

/// While the live screen is open: writes what the Viewer knows of each saved clip (request,
/// times, duration) and its tag into the library as soon as the clip is stored.
/// Tagging stays in memory first, so it never waits for the database or blocks a save.
///
/// A resumed session brings back the tags of its earlier clips: once per session, the stored
/// tags fill the in-memory map (keys not set yet only), without being written back.
final liveLibrarySyncProvider = Provider.autoDispose<void>((ref) {
  if (!ref.watch(libraryEnabledProvider)) return;
  final inLibrary = ref.watch(_libraryClipTagsProvider);
  final seeded = <String>{};
  ref.listen<String?>(activeSessionProvider.select((s) => s?.id), (_, sessionId) {
    if (sessionId == null || !seeded.add(sessionId)) return;
    unawaited(() async {
      try {
        final entries = await ref.read(libraryDatabaseProvider).watchSessionClips(sessionId).first;
        if (!ref.mounted) return;
        final tags = {for (final e in entries) e.clip.requestId ?? e.clip.id: ?e.tagIds.firstOrNull};
        inLibrary.addAll(tags);
        ref.read(clipTagsProvider.notifier).seed(tags);
      } catch (e) {
        debugPrint('Could not read the tags of session $sessionId: $e');
      }
    }());
  }, fireImmediately: true);
  final written = <String>{};
  ref.listen<List<SessionClip>>(viewerClipsProvider, (_, clips) {
    final db = ref.read(libraryDatabaseProvider);
    for (final c in clips) {
      final clipId = c.clipId;
      if (c.phase != SessionClipPhase.ready || clipId == null || !written.add(clipId)) continue;
      unawaited(() async {
        try {
          await db.updateClip(clipId, ClipsCompanion(
            requestId: Value(c.requestId),
            requestedAt: Value(c.requestedAt),
            durationMs: Value(c.durationMs),
          ));
          if (await writeClipTag(ref, c.requestId, clipId: clipId)) {
            inLibrary[c.requestId] = ref.read(clipTagsProvider)[c.requestId];
          }
        } catch (e) {
          debugPrint('Could not update clip $clipId: $e');
        }
      }());
    }
  }, fireImmediately: true);
  ref.watch(clipLabelWriterProvider);
});

/// Writes tag changes to clips already in the library (live or reviewed from the library), by
/// request id.
final clipLabelWriterProvider = Provider.autoDispose<void>((ref) {
  if (!ref.watch(libraryEnabledProvider)) return;
  final inLibrary = ref.watch(_libraryClipTagsProvider);
  ref.listen<Map<String, String>>(clipTagsProvider, (before, after) {
    for (final requestId in {...after.keys, ...?before?.keys}) {
      final tagId = after[requestId];
      if (before?[requestId] == tagId) continue;
      // Tags just read from the library (a resumed session) are not written back.
      if (inLibrary.containsKey(requestId) && inLibrary[requestId] == tagId) continue;
      unawaited(() async {
        if (await writeClipTag(ref, requestId)) inLibrary[requestId] = tagId;
      }());
    }
  });
});

/// The tag each clip has in the library as far as this screen knows (read from it or written to
/// it), by request id; lets [clipLabelWriterProvider] skip writes that change nothing.
final _libraryClipTagsProvider = Provider.autoDispose<Map<String, String?>>((_) => {});

/// Copies the in-memory tag of request [requestId] to its library clip, if stored. True when
/// written.
Future<bool> writeClipTag(Ref ref, String requestId, {String? clipId}) async {
  final db = ref.read(libraryDatabaseProvider);
  final tagId = ref.read(clipTagsProvider)[requestId];
  try {
    final id = clipId ?? await db.clipIdForRequest(requestId);
    if (id == null) return false;
    await db.setClipTags(id, [?tagId]);
    return true;
  } catch (e) {
    debugPrint('Could not save the tag of $requestId: $e');
    return false;
  }
}

// endregion

// region Earlier clips of the active session

/// A library clip as the clip list and the review show it. Keyed by its save request when known,
/// like the clips of this run, so its tag lives under the same key.
SessionClip sessionClipFromEntry(ClipEntry e, {StoredClip? stored}) {
  final c = e.clip;
  return SessionClip(
    requestId: c.requestId ?? c.id,
    seconds: (c.durationMs ?? 0) / 1000,
    requestedAt: c.requestedAt,
    phase: SessionClipPhase.ready,
    clipId: c.id,
    durationMs: c.durationMs,
    received: c.sizeBytes,
    total: c.sizeBytes,
    stored: stored ?? ClipStore.openFile(c.id, c.filePath, c.sizeBytes),
    acked: true,
  );
}

/// The clips of the active library session already in the database, newest first: after
/// resuming a session, the ones saved before (Android). Empty on web (D15) or without a session.
final activeSessionStoredClipsProvider = StreamProvider.autoDispose<List<SessionClip>>((ref) {
  if (!ref.watch(libraryEnabledProvider)) return Stream.value(const []);
  // The id only: editing the tags replaces the session state and must not restart the stream.
  final sessionId = ref.watch(activeSessionProvider.select((s) => s?.id));
  if (sessionId == null) return Stream.value(const []);
  // One StoredClip per clip, so the thumbnail family keeps its key across updates.
  final opened = <String, StoredClip>{};
  return ref.watch(libraryDatabaseProvider).watchSessionClips(sessionId).map((entries) {
    final ids = {for (final e in entries) e.clip.id};
    opened.removeWhere((id, _) => !ids.contains(id));
    return [
      for (final e in entries)
        sessionClipFromEntry(
          e,
          stored: opened.putIfAbsent(e.clip.id, () => ClipStore.openFile(e.clip.id, e.clip.filePath, e.clip.sizeBytes)),
        ),
    ];
  });
});

/// The live screen's clip list: this run's clips and the session's earlier ones from the library,
/// newest first. A clip of this run shows once even when it is in the library too (matched by
/// clip id, which the library has before the request id); the in-memory entry wins.
final liveClipsProvider = Provider.autoDispose<List<SessionClip>>((ref) {
  final live = ref.watch(viewerClipsProvider);
  final stored = ref.watch(activeSessionStoredClipsProvider).value ?? const <SessionClip>[];
  final pending = ref.watch(pendingClipDeletesProvider);
  if (stored.isEmpty) return live;
  final known = {...pending, for (final c in live) ...[c.requestId, ?c.clipId]};
  final earlier = [
    for (final c in stored)
      if (!known.contains(c.requestId) && !known.contains(c.clipId)) c,
  ];
  if (earlier.isEmpty) return live;
  // Both are newest first: merge, this run's clip first on a tie.
  final merged = <SessionClip>[];
  var i = 0;
  var j = 0;
  while (i < live.length || j < earlier.length) {
    final takeLive = j >= earlier.length || (i < live.length && !earlier[j].requestedAt.isAfter(live[i].requestedAt));
    merged.add(takeLive ? live[i++] : earlier[j++]);
  }
  return merged;
});

// endregion

// region Library screens

final librarySessionsProvider = StreamProvider.autoDispose<List<SessionSummary>>(
  (ref) => ref.watch(libraryDatabaseProvider).watchSessions(),
);

final sessionClipsProvider = StreamProvider.autoDispose.family<List<ClipEntry>, String>(
  (ref, sessionId) => ref.watch(libraryDatabaseProvider).watchSessionClips(sessionId),
);

final libraryTemplatesProvider = StreamProvider.autoDispose<List<TemplateRow>>(
  (ref) => ref.watch(libraryDatabaseProvider).watchTemplates(),
);

/// Every tag by id, to label clips of any session.
final libraryLabelsProvider = FutureProvider.autoDispose<Map<String, ViewerTag>>((ref) async {
  // Re-read whenever the template list or the active session's tags change.
  ref.watch(libraryTemplatesProvider);
  ref.watch(activeSessionProvider);
  final tags = await ref.watch(libraryDatabaseProvider).allTags();
  return {for (final t in tags) t.id: tagLabel(t)};
});

/// `ref.read` of a widget or a container.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// What a clip of session [sessionId] can be tagged with from the library: null for the active
/// session (the picker follows its live tags, editable), else the tags of the
/// session's own template — not the active session's, nor the web tag set when none is active.
/// Empty when the session's template was deleted.
Future<ClipLabelChoices?> libraryLabelChoices(Reader read, String sessionId) async {
  final active = read(activeSessionProvider);
  if (active?.id == sessionId) return null;
  final db = read(libraryDatabaseProvider);
  // Read the session again: its template may have been deleted since the screen got the row.
  final templateId = (await db.session(sessionId))?.templateId;
  if (templateId == null) return const ClipLabelChoices();
  // Same template as the live session: its tags may carry edits not yet written.
  if (active != null && active.templateId == templateId) return ClipLabelChoices(tags: active.tags);
  final content = await db.templateContent(templateId);
  return ClipLabelChoices(tags: [for (final t in content?.tags ?? const <TagRow>[]) tagLabel(t)]);
}

/// Deletes clips and their files.
Future<void> deleteLibraryClips(Reader read, Iterable<String> clipIds) async {
  final files = await read(libraryDatabaseProvider).deleteClips(clipIds);
  await read(clipFileDeleterProvider)(files);
}

/// Deletes a session, its clips and their files.
Future<void> deleteLibrarySession(Reader read, String sessionId) async {
  if (read(activeSessionProvider)?.id == sessionId) read(activeSessionProvider.notifier).close();
  final files = await read(libraryDatabaseProvider).deleteSession(sessionId);
  await read(clipFileDeleterProvider)(files);
}

// endregion
