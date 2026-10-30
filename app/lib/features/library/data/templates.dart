import 'dart:convert';

import 'package:meta/meta.dart';

/// A tag inside a template: what the JSON file and the built-in list carry.
@immutable
class LabelSpec {
  const LabelSpec({this.id, this.name, required this.color});

  /// Stable id of a built-in label; null for imported ones (a new id is made on import).
  final String? id;

  /// Null for an untouched built-in label, which shows its localized name.
  final String? name;

  /// ARGB.
  final int color;

  @override
  bool operator ==(Object other) => other is LabelSpec && other.id == id && other.name == name && other.color == color;

  @override
  int get hashCode => Object.hash(id, name, color);
}

/// A tag template (SPEC §5.3, D18): the tags a clip can be given, one per clip.
@immutable
class TemplateSpec {
  const TemplateSpec({
    this.id,
    this.name,
    required this.sport,
    this.tags = const [],
  });

  /// JSON file marker and version. Bump [schemaVersion] when the layout changes; keep reading old ones.
  static const format = 'instantreplay.template';
  static const schemaVersion = 1;

  final String? id;

  /// Null for a built-in template, which shows its localized name.
  final String? name;

  /// `football`, `basketball`, `handball`, `hockey`, `generic`, or anything a user typed.
  final String sport;
  final List<LabelSpec> tags;

  /// The export file. Names must be resolved first ([name] and every label name non-null), so the
  /// file reads the same on any device.
  Map<String, dynamic> toJson() => {
        'format': format,
        'schemaVersion': schemaVersion,
        'name': name,
        'sport': sport,
        'tags': [for (final t in tags) _labelJson(t)],
      };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Parses an export file. Throws [FormatException] with a short reason when it is not one.
  /// Files from before tags and categories were merged list `categories` too: they become tags,
  /// first, skipping a tag with the same name.
  factory TemplateSpec.fromJson(Object? json) {
    if (json is! Map<String, dynamic>) throw const FormatException('not a JSON object');
    if (json['format'] != format) throw const FormatException('not an InstantReplay template');
    final version = json['schemaVersion'];
    if (version is! int || version < 1) throw const FormatException('missing schemaVersion');
    if (version > schemaVersion) throw FormatException('made by a newer version ($version)');
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) throw const FormatException('missing name');
    final sport = json['sport'];
    return TemplateSpec(
      name: name.trim(),
      sport: sport is String && sport.trim().isNotEmpty ? sport.trim() : 'generic',
      tags: mergeLabels(_labels(json['categories'], 'categories'), _labels(json['tags'], 'tags')),
    );
  }

  static TemplateSpec decode(String source) {
    final Object? json;
    try {
      json = jsonDecode(source);
    } on FormatException {
      throw const FormatException('not valid JSON');
    }
    return TemplateSpec.fromJson(json);
  }

  /// [first] then [second], leaving out a label of [second] whose name (or, for a built-in one,
  /// whose kind: `football.tag.goal` → `goal`) one of [first] already has.
  static List<LabelSpec> mergeLabels(List<LabelSpec> first, List<LabelSpec> second) {
    String key(LabelSpec l) => (l.name ?? l.id?.split('.').last ?? '').trim().toLowerCase();
    final seen = {for (final l in first) key(l)};
    return [...first, for (final l in second) if (seen.add(key(l))) l];
  }

  static Map<String, dynamic> _labelJson(LabelSpec l) => {'name': l.name, 'color': _hex(l.color)};

  static List<LabelSpec> _labels(Object? raw, String field) {
    if (raw == null) return const [];
    if (raw is! List) throw FormatException('$field is not a list');
    return [
      for (final item in raw)
        if (item is Map<String, dynamic> && item['name'] is String && (item['name'] as String).trim().isNotEmpty)
          LabelSpec(name: (item['name'] as String).trim(), color: _color(item['color']))
        else
          throw FormatException('bad entry in $field'),
    ];
  }

  /// `#RRGGBB` / `#AARRGGBB` or an ARGB int; a missing or bad colour falls back to grey.
  static int _color(Object? raw) {
    if (raw is int) return raw | 0xFF000000;
    if (raw is String) {
      final hex = raw.startsWith('#') ? raw.substring(1) : raw;
      final v = int.tryParse(hex, radix: 16);
      if (v != null && hex.length == 6) return 0xFF000000 | v;
      if (v != null && hex.length == 8) return v;
    }
    return 0xFF9E9E9E;
  }

  static String _hex(int argb) => '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

// region Built-in templates (SPEC §5.3)

/// Ids of the built-in templates; their names and tags are localized by id. Each starts with the
/// four phases (attack, defence, transition, set piece; once categories, which kept their ids so
/// labelled clips keep their tag), then the sport's own tags.
abstract final class BuiltInTemplates {
  static const football = 'builtin.football';
  static const basketball = 'builtin.basketball';
  static const handball = 'builtin.handball';
  static const hockey = 'builtin.hockey';
  static const generic = 'builtin.generic';

  /// The tag set the Viewer kept in shared_preferences before the library, moved into the DB.
  static const migrated = 'migrated.tags';

  static const _attack = 0xFFE53935;
  static const _defense = 0xFF1E88E5;
  static const _transition = 0xFFFFB300;
  static const _setPiece = 0xFF8E24AA;

  static List<LabelSpec> _phases(String sport) => [
        LabelSpec(id: '$sport.cat.attack', color: _attack),
        LabelSpec(id: '$sport.cat.defense', color: _defense),
        LabelSpec(id: '$sport.cat.transition', color: _transition),
        LabelSpec(id: '$sport.cat.setPiece', color: _setPiece),
      ];

  static const _tagColors = [0xFF43A047, 0xFF00ACC1, 0xFFF4511E, 0xFFD81B60, 0xFFFFB300, 0xFF9E9E9E];

  static List<LabelSpec> _tags(String sport, List<String> kinds) => TemplateSpec.mergeLabels(_phases(sport), [
        for (final (i, k) in kinds.indexed) LabelSpec(id: '$sport.tag.$k', color: _tagColors[i % _tagColors.length]),
      ]);

  static final all = <TemplateSpec>[
    TemplateSpec(
      id: football,
      sport: 'football',
      tags: _tags('football', ['goal', 'shot', 'foul', 'corner', 'freeKick', 'turnover']),
    ),
    TemplateSpec(
      id: basketball,
      sport: 'basketball',
      tags: _tags('basketball', ['basket', 'threePointer', 'rebound', 'steal', 'turnover', 'foul']),
    ),
    TemplateSpec(
      id: handball,
      sport: 'handball',
      tags: _tags('handball', ['goal', 'shot', 'save', 'sevenMeters', 'turnover', 'foul']),
    ),
    TemplateSpec(
      id: hockey,
      sport: 'hockey',
      tags: _tags('hockey', ['goal', 'shot', 'save', 'penalty', 'turnover', 'foul']),
    ),
    TemplateSpec(
      id: generic,
      sport: 'generic',
      tags: TemplateSpec.mergeLabels(_phases('generic'), const [
        LabelSpec(id: 'generic.tag.good', color: 0xFF43A047),
        LabelSpec(id: 'generic.tag.bad', color: 0xFFE53935),
        LabelSpec(id: 'generic.tag.other', color: 0xFF1E88E5),
      ]),
    ),
  ];
}

// endregion
