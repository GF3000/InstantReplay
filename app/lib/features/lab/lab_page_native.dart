import 'package:flutter/widgets.dart';

import '../../core/orientation_lock.dart';
import 'spike_page.dart';

class LabPage extends StatelessWidget {
  const LabPage({super.key});

  @override
  Widget build(BuildContext context) => const OrientationLock(child: SpikePage());
}
