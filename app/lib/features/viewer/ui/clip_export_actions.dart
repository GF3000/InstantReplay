import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/capabilities.dart';
import '../../../l10n/app_localizations.dart';
import '../clips/clip_export.dart';
import '../clips/clip_store.dart';

/// Ways a reviewed clip leaves the app (SPEC §5.4, UX §3.4).
enum ClipExportKind {
  /// The browser downloads the file (web).
  download,

  /// A copy in the phone's gallery (Android).
  gallery,

  /// The system share sheet (Android).
  share;

  String label(AppLocalizations l10n) => switch (this) {
        download => l10n.viewerClipDownload,
        gallery => l10n.viewerClipSaveToGallery,
        share => l10n.viewerClipShare,
      };

  IconData get icon => switch (this) {
        download => Icons.download,
        gallery => Icons.save_alt,
        share => Icons.share,
      };

  /// `review-download`, `review-gallery`, `review-share`.
  ValueKey<String> get key => ValueKey('review-$name');
}

/// The exports [stored] allows here, per [Capabilities]: Download on web, Save to gallery and Share
/// on Android (with the clip on file).
List<ClipExportKind> clipExportKinds(Capabilities caps, StoredClip stored) => [
      if (stored.canDownload) ClipExportKind.download,
      if (stored.filePath != null && caps.canExportToGallery) ClipExportKind.gallery,
      if (stored.filePath != null && caps.canShare) ClipExportKind.share,
    ];

/// Runs exports one at a time (a second tap while the copy or the sheet is up does nothing) and
/// says how they went in a snackbar.
class ClipExporter {
  bool _busy = false;

  bool get busy => _busy;

  Future<void> run(BuildContext context, ClipExportKind kind, StoredClip stored, String fileName) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    _busy = true;
    try {
      final (result, done) = switch (kind) {
        ClipExportKind.download => (await stored.download(fileName).then((_) => ClipExportResult.done), null),
        ClipExportKind.gallery => (await ClipExport.saveToGallery(stored, fileName), l10n.viewerClipSavedToGallery),
        ClipExportKind.share => (await ClipExport.share(stored, fileName), null),
      };
      final message = switch (result) {
        ClipExportResult.done => done,
        ClipExportResult.denied => l10n.viewerClipGalleryDenied,
        ClipExportResult.noSpace => l10n.viewerClipExportNoSpace,
        ClipExportResult.failed => l10n.viewerClipExportFailed,
      };
      if (message != null) messenger?.showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      // A failed download (web) would otherwise be an unhandled error with no word to the user.
      messenger?.showSnackBar(SnackBar(content: Text(l10n.viewerClipExportFailed)));
    } finally {
      _busy = false;
    }
  }
}

/// The review's "Export" button: a menu of [clipExportKinds] (a single way is the button itself).
/// Nothing when the clip cannot leave the app here.
class ClipExportActions extends ConsumerStatefulWidget {
  const ClipExportActions({super.key, required this.stored, required this.fileName});

  final StoredClip stored;
  final String fileName;

  @override
  ConsumerState<ClipExportActions> createState() => _ClipExportActionsState();
}

class _ClipExportActionsState extends ConsumerState<ClipExportActions> {
  final _exporter = ClipExporter();

  Future<void> _run(ClipExportKind kind) async {
    setState(() {});
    await _exporter.run(context, kind, widget.stored, widget.fileName);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final kinds = clipExportKinds(ref.watch(capabilitiesProvider), widget.stored);
    if (kinds.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    const style = ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(48, 44)));
    if (kinds case [final only]) {
      return OutlinedButton.icon(
        key: only.key,
        style: style,
        onPressed: _exporter.busy ? null : () => _run(only),
        icon: Icon(only.icon),
        label: Text(only.label(l10n)),
      );
    }
    return MenuAnchor(
      menuChildren: [
        for (final k in kinds)
          MenuItemButton(
            key: k.key,
            leadingIcon: Icon(k.icon),
            onPressed: () => _run(k),
            child: Text(k.label(l10n)),
          ),
      ],
      builder: (context, menu, _) => OutlinedButton.icon(
        key: const ValueKey('review-export'),
        style: style,
        onPressed: _exporter.busy ? null : () => menu.isOpen ? menu.close() : menu.open(),
        icon: const Icon(Icons.ios_share),
        label: Text(l10n.reviewExport),
      ),
    );
  }
}
