import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capabilities.dart';
import '../../../l10n/app_localizations.dart';
import '../clips/clip_export.dart';
import '../clips/clip_store.dart';

/// Save to gallery and Share buttons for the review app bar (SPEC §5.4, UX §3.4), per [Capabilities].
/// Empty on web, which downloads instead.
class ClipExportActions extends ConsumerStatefulWidget {
  const ClipExportActions({super.key, required this.stored, required this.fileName});

  final StoredClip stored;
  final String fileName;

  @override
  ConsumerState<ClipExportActions> createState() => _ClipExportActionsState();
}

class _ClipExportActionsState extends ConsumerState<ClipExportActions> {
  /// One export at a time: a second tap while the copy or the sheet is up does nothing.
  bool _busy = false;

  Future<void> _run(Future<ClipExportResult> Function() export, {String? doneMessage}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final result = await export();
    if (!mounted) return;
    setState(() => _busy = false);
    final l10n = AppLocalizations.of(context);
    final message = switch (result) {
      ClipExportResult.done => doneMessage,
      ClipExportResult.denied => l10n.viewerClipGalleryDenied,
      ClipExportResult.noSpace => l10n.viewerClipExportNoSpace,
      ClipExportResult.failed => l10n.viewerClipExportFailed,
    };
    if (message != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final caps = ref.watch(capabilitiesProvider);
    if (widget.stored.filePath == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (caps.canExportToGallery)
        IconButton(
          key: const ValueKey('review-gallery'),
          tooltip: l10n.viewerClipSaveToGallery,
          icon: const Icon(Icons.save_alt),
          onPressed: _busy
              ? null
              : () => _run(
                    () => ClipExport.saveToGallery(widget.stored, widget.fileName),
                    doneMessage: l10n.viewerClipSavedToGallery,
                  ),
        ),
      if (caps.canShare)
        IconButton(
          key: const ValueKey('review-share'),
          tooltip: l10n.viewerClipShare,
          icon: const Icon(Icons.share),
          onPressed: _busy ? null : () => _run(() => ClipExport.share(widget.stored, widget.fileName)),
        ),
    ]);
  }
}
