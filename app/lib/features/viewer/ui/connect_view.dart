import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/capabilities.dart';
import '../../../l10n/app_localizations.dart';
import '../../discovery/discovered_camera.dart';
import '../../discovery/nsd.dart';
import '../data/viewer_api.dart';
import '../scan/qr_scan_page.dart';
import '../viewer_providers.dart';

String? pairErrorText(AppLocalizations l10n, PairError? error) => switch (error) {
      null => null,
      PairError.invalidAddress => l10n.viewerAddressInvalid,
      PairError.wrongCode => l10n.viewerCodeWrong,
      PairError.tooManyAttempts => l10n.viewerCodeTooManyAttempts,
      PairError.unreachable => l10n.viewerCameraUnreachable,
      PairError.sessionExpired => l10n.viewerSessionExpired,
    };

class _FormFrame extends StatelessWidget {
  const _FormFrame({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      );
}

/// Android: pick a Camera found over NSD, scan its QR, or type the address shown under it.
class AddressForm extends ConsumerStatefulWidget {
  const AddressForm({super.key});

  @override
  ConsumerState<AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<AddressForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => ref.read(viewerSetupProvider.notifier).setAddress(_controller.text);

  Future<void> _scan() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final denied = AppLocalizations.of(context).viewerScanPermissionDenied;
    if (!await ref.read(qrScannerProvider).requestPermission()) {
      messenger.showSnackBar(SnackBar(content: Text(denied)));
      return;
    }
    final link = await navigator.push<CameraLink>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (link != null && mounted) await ref.read(viewerSetupProvider.notifier).connectTo(link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final error = ref.watch(viewerSetupProvider.select((s) => s.error));
    final canScan = ref.watch(qrScannerAvailableProvider).value ?? false;
    final canBrowse = ref.watch(capabilitiesProvider).canBrowseNsd;
    return _FormFrame(children: [
      Text(l10n.viewerConnectTitle, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 24),
      if (canBrowse) ...[
        const _NearbyCameras(),
        const SizedBox(height: 16),
        Text(l10n.viewerNearbyOther, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 12),
      ],
      TextField(
        controller: _controller,
        // The keyboard would hide the nearby list.
        autofocus: !canBrowse,
        keyboardType: TextInputType.url,
        autocorrect: false,
        textInputAction: TextInputAction.go,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.viewerAddressLabel,
          hintText: 'http://192.168.1.20:$defaultPort',
          errorText: pairErrorText(l10n, error),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(onPressed: _submit, child: Text(l10n.viewerAddressSubmit)),
      if (canScan) ...[
        const SizedBox(height: 8),
        OutlinedButton.icon(
          key: const ValueKey('viewer-scan-qr'),
          onPressed: _scan,
          icon: const Icon(Icons.qr_code_scanner),
          label: Text(l10n.viewerScanQr),
        ),
      ],
    ]);
  }
}

/// Cameras announced on this network (NSD). Tapping one goes on to its code.
class _NearbyCameras extends ConsumerWidget {
  const _NearbyCameras();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final cameras = ref.watch(discoveredCamerasProvider).value ?? const <DiscoveredCamera>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(l10n.viewerNearbyTitle, style: theme.textTheme.titleSmall),
      const SizedBox(height: 8),
      if (cameras.isEmpty)
        ListTile(
          key: const ValueKey('viewer-nearby-searching'),
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.wifi_find),
          title: Text(l10n.viewerNearbySearching, style: theme.textTheme.bodyMedium),
        )
      else
        for (final camera in cameras)
          Card(
            key: ValueKey('viewer-nearby-${camera.cameraId}'),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              enabled: camera.compatible,
              leading: const Icon(Icons.videocam),
              title: Text(camera.name),
              subtitle: Text(camera.compatible ? cameraKey(camera.base) : l10n.viewerNearbyIncompatible),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => ref.read(viewerSetupProvider.notifier).setAddress(cameraKey(camera.base)),
            ),
          ),
    ]);
  }
}

/// Enter the 6-digit code shown on the Camera (POST /pair).
class PairForm extends ConsumerStatefulWidget {
  const PairForm({super.key});

  @override
  ConsumerState<PairForm> createState() => _PairFormState();
}

class _PairFormState extends ConsumerState<PairForm> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.length != 6) return;
    final ok = await ref.read(viewerSetupProvider.notifier).pair(_controller.text);
    if (!ok && mounted) _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final setup = ref.watch(viewerSetupProvider);
    return _FormFrame(children: [
      Text(l10n.viewerCodeTitle, style: Theme.of(context).textTheme.headlineSmall),
      if (setup.base case final base?) ...[
        const SizedBox(height: 8),
        Text(l10n.viewerCameraAt(cameraKey(base)), style: Theme.of(context).textTheme.bodyMedium),
      ],
      const SizedBox(height: 24),
      TextField(
        controller: _controller,
        autofocus: true,
        enabled: !setup.busy,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium?.copyWith(letterSpacing: 8),
        textInputAction: TextInputAction.done,
        onChanged: (v) {
          if (v.length == 6) _submit();
        },
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: l10n.viewerCodeLabel,
          counterText: '',
          errorText: pairErrorText(l10n, setup.error),
          errorMaxLines: 3,
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 16),
      FilledButton(
        onPressed: setup.busy ? null : _submit,
        child: setup.busy
            ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 3))
            : Text(l10n.viewerCodeSubmit),
      ),
      if (!setup.addressFixed) ...[
        const SizedBox(height: 8),
        TextButton(
          onPressed: setup.busy ? null : () => ref.read(viewerSetupProvider.notifier).changeCamera(),
          child: Text(l10n.viewerChangeCamera),
        ),
      ],
    ]);
  }
}
