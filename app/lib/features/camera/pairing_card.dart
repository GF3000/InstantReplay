import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../l10n/app_localizations.dart';
import '../server/server_controller.dart';

/// Setup-mode pairing info (SPEC §3.5, §4): QR with the tokenized URL, the 6-digit code, the URL as
/// text and how many viewers are connected.
class PairingCard extends ConsumerWidget {
  const PairingCard({super.key});

  static const _maxQrSize = 160.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      LayoutBuilder(builder: (context, c) => _build(context, ref, c.maxWidth));

  Widget _build(BuildContext context, WidgetRef ref, double width) {
    // Half the card on a narrow landscape panel, so the code next to it stays large.
    final qrSize = ((width - 36) * 0.55).clamp(96.0, _maxQrSize);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final server = ref.watch(cameraServerProvider);
    final url = server.url;

    final Widget qr;
    if (server.running && url != null) {
      qr = QrImageView(
        key: const Key('camera-pairing-qr'),
        data: url,
        size: qrSize,
        padding: const EdgeInsets.all(8),
        backgroundColor: Colors.white,
        semanticsLabel: url,
      );
    } else {
      qr = SizedBox.square(
        dimension: qrSize,
        child: Center(
          // No spinner: the server waits for capture, which may never start (permission denied).
          child: Icon(
            server.error != null ? Icons.error_outline : (server.running ? Icons.wifi_off : Icons.qr_code_2),
            size: 48,
            color: server.error != null ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(l10n.cameraPairingTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            qr,
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(l10n.cameraPairingCode, style: theme.textTheme.labelLarge),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _spaced(server.code),
                    key: const Key('camera-pairing-code'),
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(children: [
                  Icon(Icons.people, size: 20, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(child: Text(l10n.cameraViewersConnected(server.viewers))),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          if (server.error != null)
            Text(l10n.serverStartFailed(server.error!), style: TextStyle(color: theme.colorScheme.error))
          else if (!server.running)
            Text(l10n.serverStarting, style: theme.textTheme.bodySmall)
          else if (url == null)
            Text(l10n.cameraPairingNoNetwork, style: TextStyle(color: theme.colorScheme.tertiary))
          else ...[
            Text(l10n.cameraPairingScanHint, style: theme.textTheme.bodySmall),
            SelectableText(url, key: const Key('camera-pairing-url'), style: theme.textTheme.bodyMedium),
          ],
        ]),
      ),
    );
  }

  /// "123456" → "123 456", easier to read across a field.
  static String _spaced(String code) =>
      code.length == 6 ? '${code.substring(0, 3)} ${code.substring(3)}' : code;
}
