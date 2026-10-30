import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../core/preferences.dart';
import '../../../l10n/app_localizations.dart';

/// A label the coach puts on a clip (UX §3.5). Viewer-local: the Camera never sees tags.
@immutable
class ViewerTag {
  const ViewerTag({required this.id, this.name, required this.color});

  factory ViewerTag.fromJson(Map<String, dynamic> j) =>
      ViewerTag(id: j['id'] as String, name: j['name'] as String?, color: j['color'] as int);

  final String id;

  /// What the user typed; null for an untouched default tag, which shows its localized name.
  final String? name;

  /// ARGB.
  final int color;

  Color get colour => Color(color);

  String label(AppLocalizations l10n) =>
      name ??
      switch (id) {
        TagsNotifier.good => l10n.viewerTagDefaultGood,
        TagsNotifier.bad => l10n.viewerTagDefaultBad,
        TagsNotifier.other => l10n.viewerTagDefaultOther,
        _ => id,
      };

  ViewerTag copyWith({String? name, int? color}) =>
      ViewerTag(id: id, name: name ?? this.name, color: color ?? this.color);

  Map<String, dynamic> toJson() => {'id': id, if (name != null) 'name': name, 'color': color};

  @override
  bool operator ==(Object other) => other is ViewerTag && other.id == id && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}

/// Colours offered by the tag editor; readable on the dark theme.
const tagPalette = <int>[
  0xFF43A047, // green
  0xFFE53935, // red
  0xFF1E88E5, // blue
  0xFFFFB300, // amber
  0xFF8E24AA, // purple
  0xFF00ACC1, // cyan
  0xFFF4511E, // orange
  0xFFD81B60, // pink
  0xFF9E9E9E, // grey
];

/// The tag set, in display order, persisted in shared_preferences (localStorage on web).
class TagsNotifier extends Notifier<List<ViewerTag>> {
  static const storageKey = 'viewer.tags';
  static const good = 'good';
  static const bad = 'bad';
  static const other = 'other';
  static const defaults = [
    ViewerTag(id: good, color: 0xFF43A047),
    ViewerTag(id: bad, color: 0xFFE53935),
    ViewerTag(id: other, color: 0xFF1E88E5),
  ];

  @override
  List<ViewerTag> build() {
    final raw = ref.watch(sharedPreferencesProvider).getString(storageKey);
    if (raw == null) return defaults;
    try {
      return [for (final j in jsonDecode(raw) as List<dynamic>) ViewerTag.fromJson(j as Map<String, dynamic>)];
    } catch (_) {
      return defaults;
    }
  }

  ViewerTag? byId(String? id) => id == null ? null : state.where((t) => t.id == id).firstOrNull;

  /// Adds a tag at the end and returns it.
  ViewerTag add(String name, int color) {
    final tag = ViewerTag(id: const Uuid().v4(), name: name.trim(), color: color);
    _set([...state, tag]);
    return tag;
  }

  void update(String id, {String? name, int? color}) =>
      _set([for (final t in state) t.id == id ? t.copyWith(name: name?.trim(), color: color) : t]);

  void remove(String id) => _set([
        for (final t in state)
          if (t.id != id) t,
      ]);

  /// Undo of [remove]: clips keep the tag id, so they get their tag back.
  void restore(ViewerTag tag, int index) {
    if (state.any((t) => t.id == tag.id)) return;
    _set([...state]..insert(index.clamp(0, state.length), tag));
  }

  /// Moves the tag at [oldIndex] so it ends up at [newIndex].
  void reorder(int oldIndex, int newIndex) {
    final list = [...state];
    list.insert(newIndex, list.removeAt(oldIndex));
    _set(list);
  }

  void _set(List<ViewerTag> tags) {
    state = tags;
    // On web this is localStorage, which can be full or unavailable (private mode): keep working
    // with the in-memory tags rather than failing.
    unawaited(
      ref
          .read(sharedPreferencesProvider)
          .setString(storageKey, jsonEncode([for (final t in tags) t.toJson()]))
          .catchError((Object e) {
        debugPrint('Could not save tags: $e');
        return false;
      }),
    );
  }
}

final tagsProvider = NotifierProvider<TagsNotifier, List<ViewerTag>>(TagsNotifier.new);

/// Tag of each clip of this session, keyed by requestId so a clip can be tagged while it is still
/// recording or downloading. Session-only, like the clips themselves (D15).
class ClipTagsNotifier extends Notifier<Map<String, String>> {
  @override
  Map<String, String> build() => const {};

  void set(String requestId, String? tagId) => state = {
        for (final e in state.entries)
          if (e.key != requestId) e.key: e.value,
        requestId: ?tagId,
      };
}

final clipTagsProvider = NotifierProvider<ClipTagsNotifier, Map<String, String>>(ClipTagsNotifier.new);

/// The tag of clip [requestId], or null if untagged or its tag was deleted.
final clipTagProvider = Provider.family<ViewerTag?, String>((ref, requestId) {
  final id = ref.watch(clipTagsProvider.select((m) => m[requestId]));
  return id == null ? null : ref.watch(tagsProvider).where((t) => t.id == id).firstOrNull;
});

/// The post-save tag bar (UX §3.2): offers the tags for the newest save for [visibleFor], then fades.
/// State is the requestId being offered, or null when the bar is hidden.
class PostSaveTagBarNotifier extends Notifier<String?> {
  static const visibleFor = Duration(seconds: 6);

  Timer? _timer;

  @override
  String? build() {
    ref.onDispose(() => _timer?.cancel());
    return null;
  }

  /// A new save replaces the bar for the newest clip.
  void show(String requestId) {
    _timer?.cancel();
    state = requestId;
    _timer = Timer(visibleFor, dismiss);
  }

  void dismiss() {
    _timer?.cancel();
    _timer = null;
    state = null;
  }

  void pick(String tagId) {
    final requestId = state;
    if (requestId == null) return;
    ref.read(clipTagsProvider.notifier).set(requestId, tagId);
    dismiss();
  }
}

final postSaveTagBarProvider = NotifierProvider<PostSaveTagBarNotifier, String?>(PostSaveTagBarNotifier.new);
