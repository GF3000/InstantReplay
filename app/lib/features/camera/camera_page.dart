import 'package:flutter/material.dart';

import '../../core/orientation_lock.dart';
import '../../l10n/app_localizations.dart';
import '../role/role_placeholder_page.dart';

class CameraPage extends StatelessWidget {
  const CameraPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return OrientationLock(
      child: RolePlaceholderPage(title: l10n.roleCamera, message: l10n.cameraComingSoon),
    );
  }
}
