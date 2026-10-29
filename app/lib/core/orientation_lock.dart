import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Locks orientation while [child] is mounted and restores the default afterwards.
class OrientationLock extends StatefulWidget {
  const OrientationLock({
    super.key,
    this.orientations = const [DeviceOrientation.landscapeLeft],
    required this.child,
  });

  final List<DeviceOrientation> orientations;
  final Widget child;

  @override
  State<OrientationLock> createState() => _OrientationLockState();
}

class _OrientationLockState extends State<OrientationLock> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(widget.orientations);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(const []);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
