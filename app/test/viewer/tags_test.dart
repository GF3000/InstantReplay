import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/core/preferences.dart';
import 'package:instant_replay/features/viewer/clips/clip_transfers.dart';
import 'package:instant_replay/features/viewer/tags/tags.dart';
import 'package:instant_replay/features/viewer/ui/clip_list.dart';
import 'package:instant_replay/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ProviderContainer> _container([Map<String, Object> prefs = const {}]) async {
  SharedPreferences.setMockInitialValues(prefs);
  final p = await SharedPreferences.getInstance();
  final c = ProviderContainer(overrides: [sharedPreferencesProvider.overrideWithValue(p)]);
  addTearDown(c.dispose);
  return c;
}

SessionClip _clip(String id, {DateTime? at, SessionClipPhase phase = SessionClipPhase.ready}) => SessionClip(
      requestId: id,
      seconds: 20,
      requestedAt: at ?? DateTime(2026, 10, 29, 12, 41),
      phase: phase,
    );

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final es = lookupAppLocalizations(const Locale('es'));

  group('tag store', () {
    test('defaults are Good/Bad/Other in English and Bien/Mal/Otros in Spanish, each coloured', () async {
      final c = await _container();
      final tags = c.read(tagsProvider);
      expect([for (final t in tags) t.label(en)], ['Good', 'Bad', 'Other']);
      expect([for (final t in tags) t.label(es)], ['Bien', 'Mal', 'Otros']);
      expect({for (final t in tags) t.color}, hasLength(3));
    });

    test('add, rename, recolour, delete and reorder persist across restarts', () async {
      final c = await _container();
      final n = c.read(tagsProvider.notifier);
      final serve = n.add(' Serve ', tagPalette[4]);
      n.update(TagsNotifier.good, name: 'Great');
      n.update(TagsNotifier.bad, color: tagPalette[2]);
      n.remove(TagsNotifier.other);
      n.reorder(2, 0); // Serve to the front
      expect([for (final t in c.read(tagsProvider)) t.label(en)], ['Serve', 'Great', 'Bad']);
      expect(c.read(tagsProvider)[2].color, tagPalette[2]);
      expect(serve.name, 'Serve');

      // A fresh app start reads the same set back from storage.
      final raw = c.read(sharedPreferencesProvider).getString(TagsNotifier.storageKey)!;
      final again = await _container({TagsNotifier.storageKey: raw});
      expect(again.read(tagsProvider), c.read(tagsProvider));
    });

    test('no limit on the number of tags; an empty set stays empty', () async {
      final c = await _container();
      final n = c.read(tagsProvider.notifier);
      for (var i = 0; i < 20; i++) {
        n.add('T$i', tagPalette[i % tagPalette.length]);
      }
      expect(c.read(tagsProvider), hasLength(23));
      for (final t in [...c.read(tagsProvider)]) {
        n.remove(t.id);
      }
      final raw = c.read(sharedPreferencesProvider).getString(TagsNotifier.storageKey)!;
      expect((await _container({TagsNotifier.storageKey: raw})).read(tagsProvider), isEmpty);
    });

    test('deleting a tag untags its clips', () async {
      final c = await _container();
      c.read(clipTagsProvider.notifier).set('r1', TagsNotifier.bad);
      expect(c.read(clipTagProvider('r1'))?.id, TagsNotifier.bad);
      c.read(tagsProvider.notifier).remove(TagsNotifier.bad);
      expect(c.read(clipTagProvider('r1')), isNull);
    });
  });

  group('post-save tag bar', () {
    test('tags the clip of the newest save by requestId, then hides', () async {
      final c = await _container();
      final bar = c.read(postSaveTagBarProvider.notifier);
      bar.show('r1');
      bar.show('r2'); // a new save replaces the bar
      expect(c.read(postSaveTagBarProvider), 'r2');
      bar.pick(TagsNotifier.good);
      expect(c.read(clipTagsProvider), {'r2': TagsNotifier.good});
      expect(c.read(postSaveTagBarProvider), isNull);
    });

    testWidgets('expires after ~6 s when untouched', (tester) async {
      final c = await _container();
      c.read(postSaveTagBarProvider.notifier).show('r1');
      await tester.pump(PostSaveTagBarNotifier.visibleFor - const Duration(milliseconds: 100));
      expect(c.read(postSaveTagBarProvider), 'r1');
      await tester.pump(const Duration(milliseconds: 200));
      expect(c.read(postSaveTagBarProvider), isNull);
      expect(c.read(clipTagsProvider), isEmpty);
    });
  });

  group('clip list', () {
    test('name is tag + HH:mm, or "Clip · HH:mm" when untagged', () {
      final at = DateTime(2026, 10, 29, 9, 5);
      const good = ViewerTag(id: TagsNotifier.good, color: 0xFF43A047);
      expect(clipName(en, null, at), 'Clip · 09:05');
      expect(clipName(en, good, at), 'Good · 09:05');
      expect(clipName(es, good, at), 'Bien · 09:05');
      expect(
        clipName(en, const ViewerTag(id: 'x', name: 'Serve', color: 0), DateTime(2026, 1, 1, 17, 30)),
        'Serve · 17:30',
      );
    });

    test('filter by tag; chips list only tags in use, in tag-set order', () {
      final clips = [_clip('a'), _clip('b'), _clip('c'), _clip('d')];
      final clipTags = {'a': TagsNotifier.other, 'b': TagsNotifier.good, 'c': TagsNotifier.other};
      expect(
        [for (final t in tagsInUse(clips, clipTags, TagsNotifier.defaults)) t.id],
        [TagsNotifier.good, TagsNotifier.other],
      );
      expect([for (final c in filterClips(clips, clipTags, TagsNotifier.other)) c.requestId], ['a', 'c']);
      expect(filterClips(clips, clipTags, null), clips);
    });

    test('a save made while filtering stays visible until it is ready', () {
      final clips = [
        _clip('new', phase: SessionClipPhase.downloading),
        _clip('a'),
        _clip('b'),
      ];
      final clipTags = {'a': TagsNotifier.good, 'b': TagsNotifier.bad};
      expect([for (final c in filterClips(clips, clipTags, TagsNotifier.good)) c.requestId], ['new', 'a']);
    });
  });

  group('tag delete undo', () {
    test('restoring a deleted tag gives its clips their tag back, at the same place', () async {
      final c = await _container();
      final n = c.read(tagsProvider.notifier);
      c.read(clipTagsProvider.notifier).set('r1', TagsNotifier.bad);
      final bad = n.byId(TagsNotifier.bad)!;
      n.remove(TagsNotifier.bad);
      expect(c.read(clipTagProvider('r1')), isNull);
      n.restore(bad, 1);
      expect(c.read(clipTagProvider('r1'))?.id, TagsNotifier.bad);
      expect([for (final t in c.read(tagsProvider)) t.id], [TagsNotifier.good, TagsNotifier.bad, TagsNotifier.other]);
      n.restore(bad, 0); // already there: no duplicate
      expect(c.read(tagsProvider), hasLength(3));
    });
  });
}
