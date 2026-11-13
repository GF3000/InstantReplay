import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/capabilities.dart';
import '../../../core/ui/bucle_logo.dart';
import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
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

/// The three steps from a fresh Viewer to the live screen: pick the Camera, type its code, pick
/// the session. [step] is 0-based; the steps up to it are lit.
class ConnectSteps extends StatelessWidget {
  const ConnectSteps({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final labels = [l10n.connectStepCamera, l10n.connectStepCode, l10n.connectStepSession];
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 6),
        Expanded(
          child: Semantics(
            selected: i == step,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                height: 3,
                decoration: BoxDecoration(color: i <= step ? c.signal : c.line, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 6),
              Text(
                '${i + 1} · ${labels[i]}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: i <= step ? c.text : c.muted),
              ),
            ]),
          ),
        ),
      ],
    ]);
  }
}

class _FormFrame extends StatelessWidget {
  const _FormFrame({required this.step, required this.children});

  final int step;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              ConnectSteps(step: step),
              const SizedBox(height: 22),
              ...children,
            ]),
          ),
        ),
      );
}

/// Android: scan the Camera's QR, pick a Camera found over NSD, or type the address shown under
/// the QR (behind a link, unless it is the only way).
class AddressForm extends ConsumerStatefulWidget {
  const AddressForm({super.key});

  @override
  ConsumerState<AddressForm> createState() => _AddressFormState();
}

class _AddressFormState extends ConsumerState<AddressForm> {
  final _controller = TextEditingController();
  bool _manual = false;

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
      // The message says to type the address: open the field.
      if (mounted) setState(() => _manual = true);
      return;
    }
    final link = await navigator.push<CameraLink>(MaterialPageRoute(builder: (_) => const QrScanPage()));
    if (link != null && mounted) await ref.read(viewerSetupProvider.notifier).connectTo(link);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final error = ref.watch(viewerSetupProvider.select((s) => s.error));
    final canScan = ref.watch(qrScannerAvailableProvider).value ?? false;
    final canBrowse = ref.watch(capabilitiesProvider).canBrowseNsd;
    // With a QR scanner, typing is the fallback behind a link (shown after an error too).
    final showField = _manual || error != null || !canScan;
    return _FormFrame(step: 0, children: [
      Row(children: [
        const BucleLogo(size: 34),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            l10n.viewerConnectTitle,
            style: TextStyle(fontSize: 28, height: 1.1, fontWeight: FontWeight.w700, color: c.text),
          ),
        ),
      ]),
      const SizedBox(height: 18),
      if (canScan) ...[
        IrKey(
          key: const ValueKey('viewer-scan-qr'),
          led: c.signal,
          minHeight: 104,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          onPressed: _scan,
          // 104 less the LED strip and the padding: IrKey top-aligns its child.
          child: SizedBox(
            height: 72,
            child: Row(children: [
              Icon(Icons.qr_code_scanner, size: 44, color: c.signal),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(l10n.viewerScanQr, style: TextStyle(fontSize: 22, height: 1.1, fontWeight: FontWeight.w700, color: c.text)),
                  const SizedBox(height: 4),
                  Text(l10n.connectScanSubtitle, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: c.muted)),
                ]),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 18),
      ],
      if (canBrowse) ...[const _NearbyCameras(), const SizedBox(height: 18)],
      if (showField) ...[
        TextField(
          controller: _controller,
          // The keyboard would hide the nearby list.
          autofocus: !canBrowse,
          keyboardType: TextInputType.url,
          autocorrect: false,
          textInputAction: TextInputAction.go,
          onSubmitted: (_) => _submit(),
          style: irMono(17, weight: FontWeight.w500, color: c.text),
          decoration: InputDecoration(
            labelText: l10n.viewerAddressLabel,
            hintText: 'http://192.168.1.20:$defaultPort',
            errorText: pairErrorText(l10n, error),
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _submit, child: Text(l10n.viewerAddressSubmit)),
      ] else
        TextButton(
          key: const ValueKey('viewer-manual-address'),
          style: TextButton.styleFrom(foregroundColor: c.muted, minimumSize: const Size.fromHeight(48)),
          onPressed: () => setState(() => _manual = true),
          child: Text(
            l10n.connectManual,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, decoration: TextDecoration.underline),
          ),
        ),
    ]);
  }
}

/// Cameras announced on this network (NSD). Tapping one goes on to its code.
class _NearbyCameras extends ConsumerWidget {
  const _NearbyCameras();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final cameras = ref.watch(discoveredCamerasProvider).value ?? const <DiscoveredCamera>[];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        _RadarDot(color: c.ok),
        const SizedBox(width: 10),
        Text(l10n.viewerNearbyTitle, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: c.line)),
      ]),
      const SizedBox(height: 12),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(6)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (cameras.isEmpty)
            Container(
              key: const ValueKey('viewer-nearby-searching'),
              color: c.surface,
              constraints: const BoxConstraints(minHeight: 64),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Icon(Icons.wifi_find, color: c.muted),
                const SizedBox(width: 14),
                Expanded(child: Text(l10n.viewerNearbySearching, style: TextStyle(fontSize: 15, color: c.muted))),
              ]),
            )
          else
            for (final (i, camera) in cameras.indexed) ...[
              if (i > 0) Divider(height: 1, color: c.line),
              _CameraRow(
                key: ValueKey('viewer-nearby-${camera.cameraId}'),
                camera: camera,
                onTap: () => ref.read(viewerSetupProvider.notifier).setAddress(cameraKey(camera.base)),
              ),
            ],
        ]),
      ),
    ]);
  }
}

class _CameraRow extends StatelessWidget {
  const _CameraRow({super.key, required this.camera, required this.onTap});

  final DiscoveredCamera camera;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final enabled = camera.compatible;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: c.surface,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text(
                      camera.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                    ),
                    Text(
                      enabled ? cameraKey(camera.base) : l10n.viewerNearbyIncompatible,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: enabled
                          ? irMono(13, weight: FontWeight.w500, color: c.muted)
                          : TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.warnText),
                    ),
                  ]),
                ),
                const SizedBox(width: 14),
                _Bars(color: enabled ? c.ok : c.lineStrong),
                const SizedBox(width: 14),
                Icon(Icons.chevron_right, color: c.muted),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Found and answering" bars. NSD gives no signal strength, so they only say whether the Camera
/// can be picked (green) or not (grey).
class _Bars extends StatelessWidget {
  const _Bars({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final h in const [6.0, 10.0, 14.0, 18.0]) ...[
            if (h > 6) const SizedBox(width: 2),
            Container(width: 4, height: h, color: color),
          ],
        ]),
      );
}

/// A dot with a ring that grows and fades, like a radar sweep: the Viewer is looking.
class _RadarDot extends StatefulWidget {
  const _RadarDot({required this.color});

  final Color color;

  @override
  State<_RadarDot> createState() => _RadarDotState();
}

class _RadarDotState extends State<_RadarDot> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = IrMotion.of(context);
    if (run && !_c.isAnimating) _c.repeat();
    if (!run && _c.isAnimating) _c.stop();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = !IrMotion.of(context);
    final dot = Container(width: 6, height: 6, decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle));
    return SizedBox.square(
      dimension: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) {
          final t = still ? 0.4 : _c.value;
          return Stack(alignment: Alignment.center, children: [
            Opacity(
              opacity: still ? 0.9 : (0.9 * (1 - t)).clamp(0.0, 1.0),
              child: Transform.scale(
                scale: 0.4 + 1.2 * t,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: widget.color, width: 2)),
                ),
              ),
            ),
            dot,
          ]);
        },
      ),
    );
  }
}

/// Enter the 6-digit code shown on the Camera (POST /pair): six cells over one hidden field, so
/// the keyboard, paste and autofill work as in any text field. Sends itself at the 6th digit.
class PairForm extends ConsumerStatefulWidget {
  const PairForm({super.key});

  static const length = 6;

  @override
  ConsumerState<PairForm> createState() => _PairFormState();
}

class _PairFormState extends ConsumerState<PairForm> {
  final _controller = TextEditingController();
  final _focus = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_controller.text.length != PairForm.length) return;
    final ok = await ref.read(viewerSetupProvider.notifier).pair(_controller.text);
    if (!ok && mounted) {
      _controller.clear();
      _focus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final setup = ref.watch(viewerSetupProvider);
    final error = pairErrorText(l10n, setup.error);
    return _FormFrame(step: 1, children: [
      Text(l10n.viewerCodeTitle, style: TextStyle(fontSize: 26, height: 1.15, fontWeight: FontWeight.w700, color: c.text)),
      const SizedBox(height: 6),
      Text(l10n.connectCodeHint, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: c.muted)),
      if (setup.base case final base?) ...[
        const SizedBox(height: 4),
        Text(l10n.viewerCameraAt(cameraKey(base)), style: TextStyle(fontSize: 13, color: c.muted)),
      ],
      const SizedBox(height: 20),
      Stack(children: [
        ListenableBuilder(
          listenable: Listenable.merge([_controller, _focus]),
          builder: (context, _) => _CodeCells(
            code: _controller.text,
            active: _focus.hasFocus && !setup.busy,
            error: error != null,
          ),
        ),
        // The real input, invisible over the cells: a tap anywhere on them focuses it.
        Positioned.fill(
          child: Semantics(
            label: l10n.viewerCodeLabel,
            child: TextField(
              key: const ValueKey('viewer-code-field'),
              controller: _controller,
              focusNode: _focus,
              autofocus: true,
              enabled: !setup.busy,
              keyboardType: TextInputType.number,
              autofillHints: const [AutofillHints.oneTimeCode],
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(PairForm.length),
              ],
              showCursor: false,
              textInputAction: TextInputAction.done,
              style: const TextStyle(color: Colors.transparent, fontSize: 1),
              decoration: const InputDecoration(
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                disabledBorder: InputBorder.none,
                filled: false,
                counterText: '',
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (v) {
                if (v.length == PairForm.length) _submit();
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
        ),
      ]),
      const SizedBox(height: 10),
      SizedBox(
        height: 4,
        child: setup.busy ? const LinearProgressIndicator() : null,
      ),
      if (error != null) ...[
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, size: 20, color: c.liveText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              error,
              key: const ValueKey('viewer-code-error'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.liveText),
            ),
          ),
        ]),
      ],
      if (!setup.addressFixed) ...[
        const SizedBox(height: 16),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: c.muted, minimumSize: const Size.fromHeight(48)),
          onPressed: setup.busy ? null : () => ref.read(viewerSetupProvider.notifier).changeCamera(),
          child: Text(l10n.connectOtherCamera, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        ),
      ],
    ]);
  }
}

class _CodeCells extends StatelessWidget {
  const _CodeCells({required this.code, required this.active, required this.error});

  final String code;
  final bool active;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return ExcludeSemantics(
      child: Row(children: [
        for (var i = 0; i < PairForm.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Container(
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: active && i == code.length
                      ? c.signal
                      : error && code.isEmpty
                          ? c.live
                          : c.line,
                  width: active && i == code.length ? 2 : 1,
                ),
              ),
              child: Text(i < code.length ? code[i] : '', style: irMono(30, color: c.text)),
            ),
          ),
        ],
      ]),
    );
  }
}
