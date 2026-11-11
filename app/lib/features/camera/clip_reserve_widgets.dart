import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// `Replay reserve  −  3  +`: how many acknowledged clips the Camera keeps so they can go on air
/// (SPEC §3.4, §12.6). Shared by the Camera's Advanced section and the viewer's dialog.
class ClipReserveStepper extends StatelessWidget {
  const ClipReserveStepper({
    super.key,
    required this.size,
    required this.enabled,
    required this.onChanged,
    this.max = 10,
    this.keyPrefix = 'clip-reserve',
    this.vertical = false,
  });

  /// For a dialog: − N + centred on top, the explanation below; no title (the dialog has one).
  final bool vertical;

  final int size;
  final bool enabled;
  final ValueChanged<int> onChanged;
  final int max;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final hint = Text(
      size == 0 ? l10n.clipReserveOff : l10n.clipReserveHint(size),
      textAlign: vertical ? TextAlign.center : null,
      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
    if (vertical) {
      return Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton.outlined(
            key: ValueKey('$keyPrefix-minus'),
            tooltip: l10n.clipReserveLess,
            onPressed: enabled && size > 0 ? () => onChanged(size - 1) : null,
            icon: const Icon(Icons.remove),
          ),
          SizedBox(
            width: 72,
            child: Text(
              '$size',
              key: ValueKey('$keyPrefix-size'),
              textAlign: TextAlign.center,
              style: theme.textTheme.displaySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          IconButton.outlined(
            key: ValueKey('$keyPrefix-plus'),
            tooltip: l10n.clipReserveMore,
            onPressed: enabled && size < max ? () => onChanged(size + 1) : null,
            icon: const Icon(Icons.add),
          ),
        ]),
        const SizedBox(height: 12),
        hint,
      ]);
    }
    return Row(children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.clipReserveTitle, style: theme.textTheme.titleSmall),
          Text(
            size == 0 ? l10n.clipReserveOff : l10n.clipReserveHint(size),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ]),
      ),
      IconButton.outlined(
        key: ValueKey('$keyPrefix-minus'),
        tooltip: l10n.clipReserveLess,
        onPressed: enabled && size > 0 ? () => onChanged(size - 1) : null,
        icon: const Icon(Icons.remove),
      ),
      SizedBox(
        width: 40,
        child: Text(
          '$size',
          key: ValueKey('$keyPrefix-size'),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
      ),
      IconButton.outlined(
        key: ValueKey('$keyPrefix-plus'),
        tooltip: l10n.clipReserveMore,
        onPressed: enabled && size < max ? () => onChanged(size + 1) : null,
        icon: const Icon(Icons.add),
      ),
    ]);
  }
}
