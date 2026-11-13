import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/ui/ir_colors.dart';
import '../../core/ui/ir_widgets.dart';
import '../../l10n/app_localizations.dart';
import '../broadcast/broadcast_widgets.dart' show IrQrSheet, irQrCode;
import '../server/server_controller.dart';

/// Setup-mode pairing info (SPEC §3.5, §4): QR with the tokenized URL, the 6-digit code, the URL as
/// text and how many viewers are connected.
class PairingCard extends ConsumerWidget {
  const PairingCard({super.key});

  static const _maxQrSize = 168.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LayoutBuilder(builder: (context, c) => _build(context, ref, c.maxWidth));

  Widget _build(BuildContext context, WidgetRef ref, double width) {
    // Half the panel on a narrow landscape panel, so the code next to it stays large.
    final qrSize = ((width - 36) * 0.55).clamp(96.0, _maxQrSize);
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final server = ref.watch(cameraServerProvider);
    final url = server.url;

    final Widget qr;
    if (server.running && url != null) {
      qr = Container(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
        child: QrImageView(
          key: const Key('camera-pairing-qr'),
          data: url,
          size: qrSize,
          padding: const EdgeInsets.all(8),
          backgroundColor: Colors.white,
          semanticsLabel: url,
        ),
      );
    } else {
      qr = Container(
        width: qrSize,
        height: qrSize,
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
        child: Center(
          // No spinner: the server waits for capture, which may never start (permission denied).
          child: Icon(
            server.error != null ? Icons.error_outline : (server.running ? Icons.wifi_off : Icons.qr_code_2),
            size: 48,
            color: server.error != null ? c.liveText : c.muted,
          ),
        ),
      );
    }

    return IrPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.cameraPairingTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
        const SizedBox(height: 10),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          qr,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l10n.cameraPairingCode, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  spacedPairingCode(server.code),
                  key: const Key('camera-pairing-code'),
                  style: irMono(40, color: c.signal, height: 1.1),
                ),
              ),
              const SizedBox(height: 8),
              _ViewerCount(viewers: server.viewers),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        if (server.error != null)
          Text(l10n.serverStartFailed(server.error!), style: TextStyle(color: c.liveText))
        else if (!server.running)
          Text(l10n.serverStarting, style: TextStyle(fontSize: 13, color: c.muted))
        else if (url == null)
          Text(l10n.cameraPairingNoNetwork, style: TextStyle(color: c.warnText))
        else ...[
          Text(l10n.cameraPairingScanHint, style: TextStyle(fontSize: 13, color: c.muted)),
          SelectableText(url, key: const Key('camera-pairing-url'), style: irMono(13, weight: FontWeight.w500, color: c.text)),
        ],
      ]),
    );
  }
}

/// "123456" → "123 456", easier to read across a field.
String spacedPairingCode(String code) => code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;

class _ViewerCount extends StatelessWidget {
  const _ViewerCount({required this.viewers});

  final int viewers;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Row(children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: viewers > 0 ? c.ok : c.lineStrong, shape: BoxShape.circle),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Text(AppLocalizations.of(context).cameraViewersConnected(viewers),
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
      ),
    ]);
  }
}

/// "Connect a viewer" in broadcast mode: a full-screen sheet with a big QR, the code in amber
/// figures, the address and who is connected.
Future<void> showPairingSheet(BuildContext context) => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (_) => const Dialog.fullscreen(key: Key('camera-pairing-sheet'), child: _PairingSheet()),
    );

class _PairingSheet extends ConsumerWidget {
  const _PairingSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final server = ref.watch(cameraServerProvider);
    final url = server.url;
    return IrQrSheet(
      closeKey: const Key('camera-pairing-sheet-close'),
      title: l10n.cameraConnectViewer,
      subtitle: l10n.camPairSheetSub,
      qr: (side) => server.running && url != null
          ? irQrCode(key: const Key('camera-pairing-sheet-qr'), data: url, side: side)
          : Container(
              width: side,
              height: side,
              decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(8)),
              child: Icon(server.error != null ? Icons.error_outline : Icons.wifi_off, size: 64, color: c.muted),
            ),
      children: [
        Text(l10n.camPairOrCode, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            spacedPairingCode(server.code),
            key: const Key('camera-pairing-sheet-code'),
            style: irMono(46, color: c.signal, height: 1.1),
          ),
        ),
        const SizedBox(height: 4),
        if (url != null)
          SelectableText(url, style: irMono(13, weight: FontWeight.w500, color: c.muted))
        else
          Text(l10n.cameraPairingNoNetwork, style: TextStyle(color: c.warnText)),
        const SizedBox(height: 16),
        Text(l10n.camConnectedNow, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
        const SizedBox(height: 6),
        _ViewerCount(viewers: server.viewers),
      ],
    );
  }
}
