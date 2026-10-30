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

/// The library session clips are saved into, with its template's labels in order.
@immutable
class ActiveSession {
  const ActiveSession({
    required this.id,
    required this.name,
    required this.type,
    required this.templateId,
    this.categories = const [],
    this.tags = const [],
  });

  final String id;
  final String name;
  final SessionType type;
  final String? templateId;
  final List<ViewerTag> categories;
  final List<ViewerTag> tags;

  ActiveSession copyWith({List<ViewerTag>? categories, List<ViewerTag>? tags}) => ActiveSession(
        id: id,
        name: name,
        type: type,
        templateId: templateId,
        categories: categories ?? this.categories,
        tags: tags ?? this.tags,
      );
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
      categories: [for (final c in content?.categories ?? const <CategoryRow>[]) categoryLabel(c)],
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
  void setTags(List<ViewerTag> tags) => _setLabels(tags: tags);

  void setCategories(List<ViewerTag> categories) => _setLabels(categories: categories);

  void _setLabels({List<ViewerTag>? tags, List<ViewerTag>? categories}) {
    final s = state;
    if (s == null) return;
    state = s.copyWith(tags: tags, categories: categories);
    final templateId = s.templateId;
    if (templateId == null) return; // Its template was deleted: edits last for this run only.
    List<LabelSpec> specs(List<ViewerTag> l) => [for (final t in l) LabelSpec(id: t.id, name: t.name, color: t.color)];
    unawaited(() async {
      try {
        if (tags != null) await _db.replaceTags(templateId, specs(tags));
        if (categories != null) await _db.replaceCategories(templateId, specs(categories));
      } catch (e) {
        debugPrint('Could not save template labels: $e');
      }
    }());
  }
}

final activeSessionProvider = NotifierProvider<ActiveSessionNotifier, ActiveSession?>(ActiveSessionNotifier.new);

ViewerTag categoryLabel(CategoryRow c) => ViewerTag(id: c.id, name: c.name, color: c.color);

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
/// times, duration) and its tag and category into the library as soon as the clip is stored.
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
          await writeClipLabels(ref, c.requestId, clipId: clipId);
        } catch (e) {
          debugPrint('Could not update clip $clipId: $e');
        }
      }());
    }
  }, fireImmediately: true);
  ref.watch(clipLabelWriterProvider);
});

/// Writes tag and category changes to clips already in the library (live or reviewed from the
/// library), by request id.
final clipLabelWriterProvider = Provider.autoDispose<void>((ref) {
  if (!ref.watch(libraryEnabledProvider)) return;
  void changed(Map<String, String>? before, Map<String, String> after) {
    for (final requestId in {...after.keys, ...?before?.keys}) {
      if (before?[requestId] != after[requestId]) unawaited(writeClipLabels(ref, requestId));
    }
  }

  ref.listen<Map<String, String>>(clipTagsProvider, changed);
  ref.listen<Map<String, String>>(clipCategoriesProvider, changed);
});

/// Copies the in-memory tag and category of request [requestId] to its library clip, if stored.
Future<void> writeClipLabels(Ref ref, String requestId, {String? clipId}) async {
  final db = ref.read(libraryDatabaseProvider);
  final tagId = ref.read(clipTagsProvider)[requestId];
  final categoryId = ref.read(clipCategoriesProvider)[requestId];
  try {
    final id = clipId ?? await db.clipIdForRequest(requestId);
    if (id == null) return;
    await db.setClipTags(id, [?tagId]);
    await db.setClipCategory(id, categoryId);
  } catch (e) {
    debugPrint('Could not save labels of $requestId: $e');
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

/// Every category and tag by id, to label clips of any session.
final libraryLabelsProvider = FutureProvider.autoDispose<Map<String, ViewerTag>>((ref) async {
  // Re-read whenever the template list or the active session's labels change.
  ref.watch(libraryTemplatesProvider);
  ref.watch(activeSessionProvider);
  final (cats, tags) = await ref.watch(libraryDatabaseProvider).allLabels();
  return {
    for (final c in cats) c.id: categoryLabel(c),
    for (final t in tags) t.id: tagLabel(t),
  };
});

/// `ref.read` of a widget or a container.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

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
