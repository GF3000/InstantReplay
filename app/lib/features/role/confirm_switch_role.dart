import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// True to go ahead with a role switch that would cut something off: a stream on air, connected
/// viewers, or this viewer's connection to the Camera. [body] says what will stop.
Future<bool> confirmSwitchRole(BuildContext context, String body) async {
  final l10n = AppLocalizations.of(context);
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.switchRoleTitle),
      content: Text(body),
      actions: [
        TextButton(
          key: const ValueKey('switch-role-cancel'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('switch-role-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.switchRole),
        ),
      ],
    ),
  );
  return ok ?? false;
}
