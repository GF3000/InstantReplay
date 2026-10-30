import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../l10n/app_localizations.dart';
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

/// Android without NSD yet: type the Camera address shown under its QR.
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
    return _FormFrame(children: [
      Text(l10n.viewerConnectTitle, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 24),
      TextField(
        controller: _controller,
        autofocus: true,
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
