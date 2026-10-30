import '../../l10n/app_localizations.dart';
import 'data/library_database.dart';
import 'data/templates.dart';

/// The localized name of a built-in tag (`football.tag.goal`, `hockey.cat.attack`)
/// or of the Viewer's original default tags (`good`, `bad`, `other`); null for any other id.
String? builtInLabel(AppLocalizations l10n, String id) {
  final kind = id.split('.').last;
  return switch (kind) {
    'good' => l10n.viewerTagDefaultGood,
    'bad' => l10n.viewerTagDefaultBad,
    'other' => l10n.viewerTagDefaultOther,
    'attack' => l10n.libraryTagAttack,
    'defense' => l10n.libraryTagDefense,
    'transition' => l10n.libraryTagTransition,
    'setPiece' => l10n.libraryTagSetPiece,
    'goal' => l10n.libraryTagGoal,
    'shot' => l10n.libraryTagShot,
    'foul' => l10n.libraryTagFoul,
    'corner' => l10n.libraryTagCorner,
    'freeKick' => l10n.libraryTagFreeKick,
    'turnover' => l10n.libraryTagTurnover,
    'basket' => l10n.libraryTagBasket,
    'threePointer' => l10n.libraryTagThreePointer,
    'rebound' => l10n.libraryTagRebound,
    'steal' => l10n.libraryTagSteal,
    'save' => l10n.libraryTagSave,
    'sevenMeters' => l10n.libraryTagSevenMeters,
    'penalty' => l10n.libraryTagPenalty,
    _ => null,
  };
}

String templateLabel(AppLocalizations l10n, TemplateRow t) => t.name ?? templateIdLabel(l10n, t.id);

String templateIdLabel(AppLocalizations l10n, String id) => switch (id) {
      BuiltInTemplates.football => l10n.libraryTemplateFootball,
      BuiltInTemplates.basketball => l10n.libraryTemplateBasketball,
      BuiltInTemplates.handball => l10n.libraryTemplateHandball,
      BuiltInTemplates.hockey => l10n.libraryTemplateHockey,
      BuiltInTemplates.generic => l10n.libraryTemplateGeneric,
      BuiltInTemplates.migrated => l10n.libraryTemplateMigrated,
      _ => id,
    };

String sessionTypeLabel(AppLocalizations l10n, SessionType type) => switch (type) {
      SessionType.match => l10n.librarySessionTypeMatch,
      SessionType.training => l10n.librarySessionTypeTraining,
      SessionType.other => l10n.librarySessionTypeOther,
    };

/// [spec] with every name filled in, for an export file that reads the same on any device.
TemplateSpec resolveTemplateNames(AppLocalizations l10n, TemplateSpec spec) {
  LabelSpec resolve(LabelSpec l) =>
      LabelSpec(name: l.name ?? builtInLabel(l10n, l.id ?? '') ?? l.id ?? '?', color: l.color);
  return TemplateSpec(
    name: spec.name ?? templateIdLabel(l10n, spec.id ?? ''),
    sport: spec.sport,
    tags: [for (final t in spec.tags) resolve(t)],
  );
}
