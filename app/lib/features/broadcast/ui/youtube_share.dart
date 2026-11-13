import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../youtube/youtube_account.dart';
import '../youtube/youtube_api.dart';

/// A full-screen sheet with a big QR code on one side and the words on the other (a column on a
/// portrait screen). Shared by "Connect a viewer" and "Share the live".
class IrQrSheet extends StatelessWidget {
  const IrQrSheet({
    super.key,
    required this.qr,
    required this.title,
    required this.subtitle,
    required this.children,
    this.closeKey,
  });

  /// Builds the code at the given side.
  final Widget Function(double side) qr;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Key? closeKey;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final close = SizedBox.square(
      dimension: 48,
      child: IconButton.outlined(
        key: closeKey,
        tooltip: l10n.camClose,
        style: IconButton.styleFrom(side: BorderSide(color: c.line)),
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.close),
      ),
    );
    final heading = Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.1, color: c.text)),
          const SizedBox(height: 4),
          Text(subtitle, style: TextStyle(fontSize: 15, color: c.muted)),
        ]),
      ),
      const SizedBox(width: 8),
      close,
    ]);
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: LayoutBuilder(builder: (context, box) {
          if (box.maxWidth > box.maxHeight) {
            // On its side: the code as tall as the screen allows, the words beside it.
            final side = (box.maxHeight - 40).clamp(160.0, 520.0);
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                qr(side),
                const SizedBox(width: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      heading,
                      const SizedBox(height: 12),
                      ...children,
                    ]),
                  ),
                ),
              ]),
            );
          }
          final side = (box.maxWidth - 48).clamp(160.0, 420.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              heading,
              const SizedBox(height: 16),
              Center(child: qr(side)),
              const SizedBox(height: 16),
              ...children,
            ]),
          );
        }),
      ),
    );
  }
}

/// A QR code on white, at [side].
Widget irQrCode({required String data, required double side, Key? key}) => Container(
      width: side,
      height: side,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
      padding: EdgeInsets.all(side * 0.05),
      child: QrImageView(key: key, data: data, padding: EdgeInsets.zero, backgroundColor: Colors.white, semanticsLabel: data),
    );

/// The live's link as a big QR code, with copy and share, for people to open it on their phones.
Future<void> showYouTubeLinkQr(BuildContext context, YouTubeBroadcast live) => showDialog<void>(
      context: context,
      useSafeArea: false,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final c = context.ir;
        final title = live.title.isEmpty ? l10n.youtubeQrTitle : live.title;
        return Dialog.fullscreen(
          key: const ValueKey('youtube-qr-dialog'),
          child: IrQrSheet(
            closeKey: const ValueKey('youtube-qr-close'),
            title: title,
            subtitle: l10n.camShareSheetSub,
            qr: (side) => irQrCode(key: const ValueKey('youtube-qr-code'), data: live.url, side: side),
            children: [
              Container(
                constraints: const BoxConstraints(minHeight: 52),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                alignment: Alignment.centerLeft,
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border.all(color: c.lineStrong),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: SelectableText(live.url, style: irMono(16, weight: FontWeight.w600, color: c.text)),
              ),
              const SizedBox(height: 8),
              // Copy and share the link: for the team chat, without scanning anything.
              Row(children: [
                Expanded(child: _CopyLinkButton(url: live.url)),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const ValueKey('youtube-qr-share'),
                    style: FilledButton.styleFrom(minimumSize: const Size(64, 56)),
                    onPressed: () => SharePlus.instance.share(ShareParams(text: '$title\n${live.url}', subject: title)),
                    icon: const Icon(Icons.share),
                    label: Text(l10n.camShareAction),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              Text(l10n.camShareHint, style: TextStyle(fontSize: 13, color: c.muted)),
              const SizedBox(height: 12),
              Container(
                key: const ValueKey('youtube-qr-privacy'),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${youtubePrivacyLabel(l10n, live.privacy).toUpperCase()}  ',
                    style: irMono(12, color: c.signal),
                  ),
                  TextSpan(text: '${youtubePrivacySub(l10n, live.privacy)}. ${l10n.camPrivacyChangeHint}'),
                ]), style: TextStyle(fontSize: 14, color: c.text)),
              ),
            ],
          ),
        );
      },
    );

/// Copies the link and says so on the button for a moment (a snack bar would hide behind the
/// sheet).
class _CopyLinkButton extends StatefulWidget {
  const _CopyLinkButton({required this.url});

  final String url;

  @override
  State<_CopyLinkButton> createState() => _CopyLinkButtonState();
}

class _CopyLinkButtonState extends State<_CopyLinkButton> {
  bool _copied = false;
  Timer? _reset;

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final fg = _copied ? c.ok : c.text;
    return IrKey(
      key: const ValueKey('youtube-qr-copy'),
      borderColor: _copied ? c.ok : null,
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.url));
        if (!mounted) return;
        setState(() => _copied = true);
        _reset?.cancel();
        _reset = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_copied ? Icons.check : Icons.content_copy, size: 20, color: fg),
        const SizedBox(width: 8),
        Flexible(
          child: Text(_copied ? l10n.youtubeLinkCopied : l10n.youtubeCopyLink,
              overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: fg)),
        ),
      ]),
    );
  }
}

/// Before going live with a YouTube account: a live must be there to receive the stream (the
/// last one ended with its stream). Returns the target, or null after telling the user why not.
Future<YouTubeTarget?> prepareYouTubeLive(BuildContext context, YouTubeAccount youtube) async {
  final l10n = AppLocalizations.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    return await youtube.ensureLive(defaultTitle: youtubeDefaultTitle(l10n, DateTime.now()));
  } on YouTubeAccountException catch (e) {
    messenger?.showSnackBar(SnackBar(content: Text(youtubeErrorMessage(l10n, e))));
  } catch (e) {
    messenger?.showSnackBar(
        SnackBar(content: Text(youtubeErrorMessage(l10n, YouTubeAccountException('api', '$e')))));
  }
  return null;
}

/// The share button: prepares the live if needed (so its link exists before going on air), then
/// shows its link as a QR code.
Future<void> shareYouTubeLive(BuildContext context, YouTubeAccount youtube) async {
  final target = await prepareYouTubeLive(context, youtube);
  if (target != null && context.mounted) await showYouTubeLinkQr(context, target.broadcast);
}

String youtubeDefaultTitle(AppLocalizations l10n, DateTime now) => l10n.youtubeDefaultTitle(
    '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}');

String youtubePrivacyLabel(AppLocalizations l10n, YouTubePrivacy p) => switch (p) {
      YouTubePrivacy.public => l10n.youtubePrivacyPublic,
      YouTubePrivacy.unlisted => l10n.youtubePrivacyUnlisted,
      YouTubePrivacy.private => l10n.youtubePrivacyPrivate,
    };

/// Who can see a live with privacy [p], in a few words.
String youtubePrivacySub(AppLocalizations l10n, YouTubePrivacy p) => switch (p) {
      YouTubePrivacy.public => l10n.camPrivacyPublicSub,
      YouTubePrivacy.unlisted => l10n.camPrivacyUnlistedSub,
      YouTubePrivacy.private => l10n.camPrivacyPrivateSub,
    };

String youtubeLifeCycleLabel(AppLocalizations l10n, YouTubeLifeCycle c) => switch (c) {
      YouTubeLifeCycle.ready => l10n.youtubeLifeReady,
      YouTubeLifeCycle.starting => l10n.youtubeLifeStarting,
      YouTubeLifeCycle.live => l10n.youtubeLifeLive,
      YouTubeLifeCycle.complete || YouTubeLifeCycle.other => l10n.youtubeLifeComplete,
    };

String youtubeErrorMessage(AppLocalizations l10n, YouTubeAccountException e) => switch (e.code) {
      'live_not_enabled' => l10n.youtubeErrorLiveNotEnabled,
      'quota' => l10n.youtubeErrorQuota,
      'forbidden' || 'not_signed_in' => l10n.youtubeErrorForbidden,
      'network' => l10n.youtubeErrorNetwork,
      'sign_in_failed' => l10n.youtubeErrorSignIn(e.message ?? e.code),
      _ => l10n.youtubeErrorApi(e.message ?? e.code),
    };
