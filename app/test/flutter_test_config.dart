import 'dart:async';

import 'package:instant_replay/core/ui/ir_widgets.dart';

/// Runs before every test file: looping decorative animations would keep `pumpAndSettle` busy.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  IrMotion.loops = false;
  await testMain();
}
