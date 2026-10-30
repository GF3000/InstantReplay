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
final liveLibrarySyncProvider = Provider.autoDispose<void>((ref) {
  if (!ref.watch(libraryEnabledProvider)) return;
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
          await writeClipTag(ref, c.requestId, clipId: clipId);
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
  ref.listen<Map<String, String>>(clipTagsProvider, (before, after) {
    for (final requestId in {...after.keys, ...?before?.keys}) {
      if (before?[requestId] != after[requestId]) unawaited(writeClipTag(ref, requestId));
    }
  });
});

/// Copies the in-memory tag of request [requestId] to its library clip, if stored.
Future<void> writeClipTag(Ref ref, String requestId, {String? clipId}) async {
  final db = ref.read(libraryDatabaseProvider);
  final tagId = ref.read(clipTagsProvider)[requestId];
  try {
    final id = clipId ?? await db.clipIdForRequest(requestId);
    if (id == null) return;
    await db.setClipTags(id, [?tagId]);
  } catch (e) {
    debugPrint('Could not save the tag of $requestId: $e');
  }
}

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
