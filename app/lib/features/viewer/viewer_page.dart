import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../role/role_placeholder_page.dart';

class ViewerPage extends StatelessWidget {
  const ViewerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RolePlaceholderPage(title: l10n.roleViewer, message: l10n.viewerComingSoon);
  }
}
