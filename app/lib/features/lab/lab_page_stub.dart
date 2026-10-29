import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class LabPage extends StatelessWidget {
  const LabPage({super.key});

  @override
  Widget build(BuildContext context) =>
      Scaffold(appBar: AppBar(), body: Center(child: Text(AppLocalizations.of(context).labUnavailable)));
}
