import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../clips/clip_transfers.dart';
import '../data/session_link.dart';
import '../viewer_providers.dart';
import 'review_page.dart';

/// Main Viewer screen (SPEC §5.1.4): live video large, save controls beside it on wide screens and
/// below it on narrow/portrait ones.
class LiveControlView extends StatelessWidget {
  const LiveControlView({super.key});

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight && c.maxWidth >= 640;
        if (wide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Expanded(child: _LivePanel()),
            SizedBox(width: c.maxWidth >= 1000 ? 380 : 320, child: const _ControlPanel()),
          ]);
        }
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(height: (c.maxWidth * 9 / 16).clamp(120, c.maxHeight * 0.45), child: const _LivePanel()),
          const Expanded(child: _ControlPanel()),
        ]);
      });
}

class _LivePanel extends ConsumerWidget {
  const _LivePanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(liveViewProvider);
    final link = ref.watch(linkStateProvider.select((s) => s?.phase));
    final overlay = switch ((link, live.phase)) {
      (LinkPhase.connecting || null, _) => l10n.viewerLinkConnecting,
      (LinkPhase.reconnecting, _) => l10n.viewerLinkReconnecting,
      (_, LivePhase.waiting || LivePhase.negotiating) => l10n.viewerLiveStarting,
      (_, LivePhase.interrupted) => l10n.viewerLiveInterrupted,
      _ => null,
    };
    return ColoredBox(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (live.peer case final peer?) peer.buildView(),
        if (overlay != null)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              Text(overlay, style: const TextStyle(color: Colors.white)),
            ]),
          ),
        if (link == LinkPhase.connected && live.phase != LivePhase.negotiating)
          Positioned(
            right: 4,
            bottom: 4,
            child: IconButton(
              color: Colors.white70,
              tooltip: l10n.viewerLiveRestart,
              icon: const Icon(Icons.refresh),
              onPressed: () => ref.read(liveViewProvider.notifier).restart(),
            ),
          ),
      ]),
    );
  }
}

class _ControlPanel extends ConsumerWidget {
  const _ControlPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final clips = ref.watch(viewerClipsProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Padding(padding: EdgeInsets.fromLTRB(12, 8, 12, 0), child: StatusLine()),
      const Padding(padding: EdgeInsets.all(12), child: SaveControls()),
      if (kIsWeb)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(l10n.viewerSessionOnlyNotice, style: Theme.of(context).textTheme.bodySmall),
        ),
      const Divider(),
      Expanded(
        child: clips.isEmpty
            ? Center(child: Text(l10n.viewerClipsEmpty, style: Theme.of(context).textTheme.bodyMedium))
            : ListView.builder(
                itemCount: clips.length,
                itemBuilder: (context, i) => ClipTile(clip: clips[i], number: clips.length - i),
              ),
      ),
    ]);
  }
}

/// Compact Camera status: recording, fps, buffer, outbox, temperature, battery.
class StatusLine extends ConsumerWidget {
  const StatusLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final link = ref.watch(linkStateProvider);
    final status = link?.status;
    final text = Theme.of(context).textTheme.bodyMedium;
    if (link == null || link.phase != LinkPhase.connected || status == null) {
      return Text(
        link?.phase == LinkPhase.reconnecting ? l10n.viewerLinkReconnecting : l10n.viewerLinkConnecting,
        style: text,
      );
    }
    final hot = status.thermalStatus >= 3;
    final parts = [
      l10n.viewerStatusFps(status.fps.round()),
      l10n.viewerStatusBuffer((status.bufferMs / 1000).round()),
      l10n.viewerStatusOutbox(status.outboxClips),
      if (status.batteryTempC case final t?) l10n.viewerStatusTemperature(t.toStringAsFixed(0)),
      if (status.batteryPercent case final p?) l10n.viewerStatusBattery(p, status.plugged == true ? '⚡' : ''),
    ];
    return Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
      Icon(Icons.fiber_manual_record, size: 14, color: status.recording ? Colors.red : scheme.outline),
      Text(status.recording ? l10n.viewerStatusRec : l10n.viewerStatusIdle,
          style: text?.copyWith(fontWeight: FontWeight.bold)),
      Text(parts.join(' · '), style: text?.copyWith(color: hot ? scheme.error : null)),
    ]);
  }
}

/// The big SAVE button (default preset) and quick chips that save at once with their duration (D11).
class SaveControls extends ConsumerWidget {
  const SaveControls({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final presets = ref.watch(savePresetsProvider);
    final connected = ref.watch(linkStateProvider.select((s) => s?.phase == LinkPhase.connected));
    final recording = ref.watch(linkStateProvider.select((s) => s?.status?.recording ?? true));
    final enabled = connected && recording;
    void save(int? seconds) => ref.read(viewerClipsProvider.notifier).save(seconds: seconds);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(
        height: 88,
        child: FilledButton.icon(
          key: const ValueKey('viewer-save'),
          onPressed: enabled ? () => save(null) : null,
          icon: const Icon(Icons.save_alt, size: 32),
          label: Text(
            l10n.viewerSave(presets.defaultSeconds),
            style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
          ),
        ),
      ),
      const SizedBox(height: 8),
      Row(children: [
        for (final s in presets.quickSeconds)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OutlinedButton(
                key: ValueKey('viewer-save-$s'),
                onPressed: enabled ? () => save(s) : null,
                child: Text(l10n.viewerSaveQuick(s)),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 4),
      Text(
        l10n.viewerSaveHint(presets.postSeconds),
        style: Theme.of(context).textTheme.bodySmall,
        textAlign: TextAlign.center,
      ),
    ]);
  }
}

class ClipTile extends ConsumerWidget {
  const ClipTile({super.key, required this.clip, required this.number});

  final SessionClip clip;
  final int number;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final seconds = clip.durationMs != null ? (clip.durationMs! / 1000).round() : clip.seconds.round();
    final time = TimeOfDay.fromDateTime(clip.requestedAt).format(context);
    final (subtitle, color) = switch (clip.phase) {
      SessionClipPhase.requesting => (l10n.viewerClipRequesting, null),
      SessionClipPhase.recording => (l10n.viewerClipRecording, null),
      SessionClipPhase.downloading => (
          clip.progress == null || clip.received == 0
              ? l10n.viewerClipDownloadingStarted
              : l10n.viewerClipDownloading((clip.progress! * 100).round()),
          null
        ),
      SessionClipPhase.ready => (l10n.viewerClipReady, scheme.primary),
      SessionClipPhase.failed => (
          switch (clip.failure) {
            ClipFailure.request || null => l10n.viewerClipFailedRequest,
            ClipFailure.download => l10n.viewerClipFailedDownload,
            ClipFailure.checksum => l10n.viewerClipFailedChecksum,
            ClipFailure.expired => l10n.viewerClipExpired,
          },
          scheme.error
        ),
    };
    final stored = clip.stored;
    final busy = clip.phase == SessionClipPhase.requesting ||
        clip.phase == SessionClipPhase.recording ||
        clip.phase == SessionClipPhase.downloading;
    return ListTile(
      leading: SizedBox.square(
        dimension: 32,
        child: busy
            ? CircularProgressIndicator(
                value: clip.phase == SessionClipPhase.downloading && clip.received > 0 ? clip.progress : null,
                strokeWidth: 3,
              )
            : Icon(
                clip.phase == SessionClipPhase.ready ? Icons.play_circle : Icons.error_outline,
                color: color,
                size: 32,
              ),
      ),
      title: Text(l10n.viewerClipTitle(number, seconds)),
      subtitle: Text('$time · $subtitle', style: TextStyle(color: color)),
      onTap: stored == null
          ? null
          : () => Navigator.of(context).push(MaterialPageRoute<void>(
                fullscreenDialog: true,
                builder: (_) => ReviewPage(clip: stored, title: l10n.viewerClipTitle(number, seconds)),
              )),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (clip.phase == SessionClipPhase.failed && clip.failure != ClipFailure.expired && clip.clipId != null)
          IconButton(
            tooltip: l10n.viewerClipRetry,
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(viewerClipsProvider.notifier).retry(clip.requestId),
          ),
        if (stored != null && stored.canDownload)
          IconButton(
            tooltip: l10n.viewerClipDownload,
            icon: const Icon(Icons.download),
            onPressed: () => stored.download(clipFileName(clip)),
          ),
      ]),
    );
  }
}

/// `instantreplay-20261029-153012.mp4`
String clipFileName(SessionClip clip) {
  final t = clip.requestedAt;
  String two(int v) => v.toString().padLeft(2, '0');
  return 'instantreplay-${t.year}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}${two(t.second)}.mp4';
}
