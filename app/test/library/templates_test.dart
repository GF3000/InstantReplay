import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instant_replay/features/library/data/templates.dart';
import 'package:instant_replay/features/library/labels.dart';
import 'package:instant_replay/l10n/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final es = lookupAppLocalizations(const Locale('es'));

  group('built-in templates', () {
    test('Football, Basketball, Handball, Hockey and Generic: one tag list, the phases first', () {
      expect([for (final t in BuiltInTemplates.all) t.id], [
        BuiltInTemplates.football,
        BuiltInTemplates.basketball,
        BuiltInTemplates.handball,
        BuiltInTemplates.hockey,
        BuiltInTemplates.generic,
      ]);
      for (final t in BuiltInTemplates.all) {
        expect([for (final c in t.tags.take(4)) builtInLabel(en, c.id!)], ['Attack', 'Defence', 'Transition', 'Set piece']);
        // The phases keep their old category ids, so clips labelled with one keep it.
        expect(t.tags.first.id, '${t.sport}.cat.attack');
        expect(t.tags.length, greaterThan(4));
        expect({for (final l in t.tags) builtInLabel(en, l.id!)}, hasLength(t.tags.length), reason: 'no repeated names');
      }
    });

    test('every built-in label and template has a name in English and Spanish', () {
      final ids = {
        for (final t in BuiltInTemplates.all) ...[for (final l in t.tags) l.id!],
      };
      expect(ids, hasLength(BuiltInTemplates.all.fold<int>(0, (n, t) => n + t.tags.length)));
      for (final id in ids) {
        expect(builtInLabel(en, id), isNotNull, reason: id);
        expect(builtInLabel(es, id), isNotNull, reason: id);
      }
      expect(templateIdLabel(es, BuiltInTemplates.football), 'Fútbol');
      expect(builtInLabel(es, 'handball.tag.sevenMeters'), '7 metros');
      expect(builtInLabel(en, 'some-uuid'), isNull);
    });
  });

  group('template JSON', () {
    test('export resolves names and colours; import reads them back without ids', () {
      final football = BuiltInTemplates.all.first;
      final file = resolveTemplateNames(es, football).encode();
      final json = jsonDecode(file) as Map<String, dynamic>;
      expect(json['format'], TemplateSpec.format);
      expect(json['schemaVersion'], TemplateSpec.schemaVersion);
      expect(json['name'], 'Fútbol');
      expect(json.containsKey('categories'), isFalse);
      expect((json['tags'] as List).first, {'name': 'Ataque', 'color': '#E53935'});

      final back = TemplateSpec.decode(file);
      expect(back.id, isNull);
      expect(back.name, 'Fútbol');
      expect(back.sport, 'football');
      expect([for (final c in back.tags.take(4)) c.name], ['Ataque', 'Defensa', 'Transición', 'Balón parado']);
      expect([for (final c in back.tags) c.color], [for (final c in football.tags) c.color]);
      expect(back.tags.every((t) => t.id == null), isTrue);
    });

    test('colours may be #RRGGBB, #AARRGGBB or ints; bad ones fall back to grey', () {
      final t = TemplateSpec.fromJson({
        'format': TemplateSpec.format,
        'schemaVersion': 1,
        'name': ' Waterpolo ',
        'tags': [
          {'name': 'A', 'color': '#00ff00'},
          {'name': 'B', 'color': '80FF0000'},
          {'name': 'C', 'color': 0x123456},
          {'name': 'D', 'color': 'red'},
          {'name': 'E'},
        ],
      });
      expect(t.name, 'Waterpolo');
      expect(t.sport, 'generic');
      expect([for (final l in t.tags) l.color], [0xFF00FF00, 0x80FF0000, 0xFF123456, 0xFF9E9E9E, 0xFF9E9E9E]);
    });

    test('a file from before the merge: its categories become the first tags, without repeats', () {
      final t = TemplateSpec.fromJson({
        'format': TemplateSpec.format,
        'schemaVersion': 1,
        'name': 'Old',
        'categories': [
          {'name': 'Attack', 'color': '#FF0000'},
          {'name': 'Defence', 'color': '#0000FF'},
        ],
        'tags': [
          {'name': 'Goal', 'color': '#00FF00'},
          {'name': 'attack', 'color': '#FFFFFF'},
        ],
      });
      expect([for (final l in t.tags) (l.name, l.color)], [
        ('Attack', 0xFFFF0000),
        ('Defence', 0xFF0000FF),
        ('Goal', 0xFF00FF00),
      ]);
    });

    test('rejects what is not a template, with a reason', () {
      Matcher fails(String reason) => throwsA(isA<FormatException>().having((e) => e.message, 'message', contains(reason)));
      expect(() => TemplateSpec.decode('{nope'), fails('not valid JSON'));
      expect(() => TemplateSpec.decode('[]'), fails('not a JSON object'));
      expect(() => TemplateSpec.decode('{"name": "x"}'), fails('not an InstantReplay template'));
      final base = {'format': TemplateSpec.format, 'schemaVersion': 1, 'name': 'X'};
      expect(() => TemplateSpec.fromJson({...base, 'schemaVersion': 99}), fails('newer version'));
      expect(() => TemplateSpec.fromJson({...base, 'name': '  '}), fails('missing name'));
      expect(() => TemplateSpec.fromJson({...base, 'tags': 'Goal'}), fails('tags is not a list'));
      expect(
        () => TemplateSpec.fromJson({
          ...base,
          'categories': [
            {'color': '#FFFFFF'},
          ],
        }),
        fails('bad entry in categories'),
      );
    });
  });
}
