import 'dart:async';

import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../l10n/app_localizations.dart';
import '../recording/recording_widgets.dart' show formatRecordingClock;
import 'scoreboard_controller.dart' show periodLabel;
import 'youtube/youtube_account.dart';
import 'youtube/youtube_api.dart';

// Broadcast mode (SPEC §12) as both roles show it: the Camera for its own stream controls, every
// Viewer for the scoreboard and the stream from the status the Camera pushes.

// region Stream

String broadcastStateLabel(AppLocalizations l10n, BroadcastStreamState state) => switch (state) {
      BroadcastStreamState.idle => l10n.broadcastStateIdle,
      BroadcastStreamState.connecting => l10n.broadcastStateConnecting,
      BroadcastStreamState.live => l10n.broadcastStateLive,
      BroadcastStreamState.reconnecting => l10n.broadcastStateReconnecting,
      BroadcastStreamState.failed => l10n.broadcastStateFailed,
    };

Color broadcastStateColor(BroadcastStreamState state, {bool dim = false}) => switch (state) {
      BroadcastStreamState.live => dim ? const Color(0xFF8A2A2A) : const Color(0xFFE53935),
      BroadcastStreamState.connecting || BroadcastStreamState.reconnecting =>
        dim ? const Color(0xFF7A6020) : const Color(0xFFFFB300),
      BroadcastStreamState.failed => dim ? const Color(0xFF8A2A2A) : const Color(0xFFB71C1C),
      BroadcastStreamState.idle => const Color(0xFF7A7A7A),
    };

/// Why a broadcast command was refused, from the Camera's error code.
String broadcastErrorMessage(AppLocalizations l10n, String code, String? message) => switch (code) {
      'not_configured' => l10n.broadcastNotConfigured,
      'mic_permission' => l10n.broadcastMicDenied,
      'not_broadcast_mode' => l10n.broadcastNotBroadcastMode,
      'not_live' => l10n.replayNotLive,
      'replay_unavailable' => l10n.replayUnavailable,
      'replay_failed' => l10n.replayFailed(message ?? code),
      _ => l10n.broadcastFailed(message ?? code),
    };

/// The second line under the state: bitrate and time on air, the last error, or what is missing.
String broadcastDetail(AppLocalizations l10n, BroadcastInfo info) {
  final numbers = [
    if (info.bitrateKbps case final kbps?) l10n.broadcastBitrate((kbps / 1000).toStringAsFixed(1)),
    if (info.uptimeMs case final ms?) formatRecordingClock(ms),
  ].join(' · ');
  return switch (info.state) {
    BroadcastStreamState.live || BroadcastStreamState.connecting => numbers,
    BroadcastStreamState.reconnecting || BroadcastStreamState.failed =>
      [?info.message, if (numbers.isNotEmpty) numbers].join(' · '),
    BroadcastStreamState.idle => info.configured ? l10n.broadcastReady(info.targetKbps) : l10n.broadcastNotConfigured,
  };
}

/// One compact row: the stream state and numbers on the left, settings and Go live / Stop on the
/// right. Stop asks first.
class BroadcastBar extends StatelessWidget {
  const BroadcastBar({
    super.key,
    required this.info,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onConfigure,
    this.onShare,
    this.keyPrefix = 'broadcast',
    this.buttonSize = 48,
    this.dim = false,
  });

  final BroadcastInfo info;

  /// False while the Camera is not reachable or not capturing.
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onConfigure;

  /// Shows the live's link as a QR code; null without a YouTube account live.
  final VoidCallback? onShare;

  /// Prefix of the buttons' keys, e.g. `viewer-broadcast` → `viewer-broadcast-start`.
  final String keyPrefix;
  final double buttonSize;

  /// The Camera's black operating screen.
  final bool dim;

  static const _dim = Color(0xFF5A5A5A);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final color = broadcastStateColor(info.state, dim: dim);
    final detail = broadcastDetail(l10n, info);
    final size = buttonSize;
    final fg = dim ? _dim : null;
    final side = dim ? const BorderSide(color: _dim) : null;
    return Row(children: [
      Icon(info.state == BroadcastStreamState.live ? Icons.sensors : Icons.sensors_off, size: 20, color: color),
      const SizedBox(width: 6),
      Expanded(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            broadcastStateLabel(l10n, info.state),
            key: ValueKey('$keyPrefix-state'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: dim ? color : null, fontWeight: FontWeight.bold, fontSize: 15),
          ),
          if (detail.isNotEmpty)
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: dim ? _dim : theme.colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ]),
      ),
      if (!dim && onShare != null)
        IconButton(
          key: ValueKey('$keyPrefix-qr'),
          tooltip: l10n.youtubeQrTitle,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          onPressed: onShare,
          icon: const Icon(Icons.qr_code_2),
        ),
      if (!dim)
        IconButton(
          key: ValueKey('$keyPrefix-settings'),
          tooltip: l10n.broadcastSettings,
          constraints: BoxConstraints.tightFor(width: size, height: size),
          onPressed: enabled ? onConfigure : null,
          icon: const Icon(Icons.settings),
        ),
      const SizedBox(width: 4),
      if (info.active)
        OutlinedButton.icon(
          key: ValueKey('$keyPrefix-stop'),
          style: OutlinedButton.styleFrom(minimumSize: Size(size, size), foregroundColor: fg, side: side),
          onPressed: enabled ? () => _stop(context) : null,
          icon: const Icon(Icons.stop),
          label: Text(l10n.broadcastStop),
        )
      else
        FilledButton.icon(
          key: ValueKey('$keyPrefix-start'),
          style: FilledButton.styleFrom(
            minimumSize: Size(size, size),
            backgroundColor: dim ? Colors.transparent : const Color(0xFFC62828),
            foregroundColor: dim ? _dim : Colors.white,
            side: side,
          ),
          onPressed: enabled && info.configured ? onStart : (enabled ? onConfigure : null),
          icon: const Icon(Icons.sensors),
          label: Text(l10n.broadcastStart, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
    ]);
  }

  Future<void> _stop(BuildContext context) async {
    if (await confirmStopBroadcast(context)) onStop();
  }
}

/// The stream in a header: settings, then one button that says Go live (red) when idle and, on
/// air, shows the state with the bitrate and the time on air; tapping it then asks to stop.
class BroadcastHeaderControls extends StatelessWidget {
  const BroadcastHeaderControls({
    super.key,
    required this.info,
    required this.enabled,
    required this.onStart,
    required this.onStop,
    required this.onConfigure,
    this.onShare,
    this.keyPrefix = 'broadcast',
  });

  final BroadcastInfo info;
  final bool enabled;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onConfigure;

  /// Shows the live's link as a QR code; null without a YouTube account live.
  final VoidCallback? onShare;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    const red = Color(0xFFC62828);
    final Widget button;
    if (info.active) {
      final color = broadcastStateColor(info.state);
      final numbers = [
        if (info.bitrateKbps case final kbps?) l10n.broadcastBitrate((kbps / 1000).toStringAsFixed(1)),
        if (info.uptimeMs case final ms?) formatRecordingClock(ms),
      ].join(' · ');
      final label = info.state == BroadcastStreamState.live && numbers.isNotEmpty
          ? numbers
          : broadcastStateLabel(l10n, info.state);
      button = OutlinedButton.icon(
        key: ValueKey('$keyPrefix-stop'),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          foregroundColor: color,
          side: BorderSide(color: color, width: 2),
        ),
        onPressed: enabled ? () => _stop(context) : null,
        icon: Icon(info.state == BroadcastStreamState.live ? Icons.sensors : Icons.sync),
        label: Text(
          label,
          key: ValueKey('$keyPrefix-state'),
          style: const TextStyle(fontWeight: FontWeight.bold, fontFeatures: [FontFeature.tabularFigures()]),
        ),
      );
    } else {
      button = FilledButton.icon(
        key: ValueKey('$keyPrefix-start'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          backgroundColor: red,
          foregroundColor: Colors.white,
        ),
        onPressed: enabled && info.configured ? onStart : (enabled ? onConfigure : null),
        icon: const Icon(Icons.sensors),
        label: Text(l10n.broadcastStart, style: const TextStyle(fontWeight: FontWeight.bold)),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (onShare != null)
        IconButton(
          key: ValueKey('$keyPrefix-qr'),
          tooltip: l10n.youtubeQrTitle,
          constraints: const BoxConstraints.tightFor(width: 48, height: 48),
          onPressed: onShare,
          icon: const Icon(Icons.qr_code_2),
        ),
      IconButton(
        key: ValueKey('$keyPrefix-settings'),
        tooltip: l10n.broadcastSettings,
        constraints: const BoxConstraints.tightFor(width: 48, height: 48),
        onPressed: enabled ? onConfigure : null,
        icon: const Icon(Icons.settings),
      ),
      Tooltip(message: broadcastDetail(l10n, info), child: button),
    ]);
  }

  Future<void> _stop(BuildContext context) async {
    if (await confirmStopBroadcast(context)) onStop();
  }
}

/// True to end the stream.
Future<bool> confirmStopBroadcast(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final stop = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.broadcastStopTitle),
      content: Text(l10n.broadcastStopBody),
      actions: [
        TextButton(
          key: const ValueKey('broadcast-stop-keep'),
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.broadcastStopKeep),
        ),
        FilledButton(
          key: const ValueKey('broadcast-stop-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.broadcastStop),
        ),
      ],
    ),
  );
  return stop ?? false;
}

/// What the stream settings dialog returns. [key] null keeps the stored key.
typedef BroadcastConfigResult = ({String server, String? key, int targetKbps, bool audio, bool replayScoreboard});

/// Server, stream key (hidden, paste-friendly), bitrate and microphone. The stored key never
/// comes back to the screen: an empty field keeps it.
///
/// With a [youtube] account available (the Android app) it also offers the account mode: the
/// live is created on the channel and its server and key come back as if typed.
Future<BroadcastConfigResult?> showBroadcastConfigDialog(BuildContext context, BroadcastInfo info,
        {YouTubeAccount? youtube}) =>
    showDialog<BroadcastConfigResult>(
        context: context, builder: (_) => _BroadcastConfigDialog(info: info, youtube: youtube));

enum _StreamMode { key, account }

class _BroadcastConfigDialog extends StatefulWidget {
  const _BroadcastConfigDialog({required this.info, this.youtube});

  final BroadcastInfo info;
  final YouTubeAccount? youtube;

  @override
  State<_BroadcastConfigDialog> createState() => _BroadcastConfigDialogState();
}

class _BroadcastConfigDialogState extends State<_BroadcastConfigDialog> {
  late final _server = TextEditingController(text: widget.info.server);
  final _key = TextEditingController();
  late int _kbps = widget.info.targetKbps.clamp(BroadcastInfo.minKbps, BroadcastInfo.maxKbps);
  late bool _audio = widget.info.audio;
  late bool _replayScoreboard = widget.info.replayScoreboard;
  bool _showKey = false;

  // Account mode.
  late _StreamMode _mode =
      widget.youtube?.email != null && widget.youtube?.current != null ? _StreamMode.account : _StreamMode.key;
  late final _title = TextEditingController(text: widget.youtube?.current?.title);
  late final _description = TextEditingController(text: widget.youtube?.current?.description);
  late YouTubePrivacy _privacy = widget.youtube?.current?.privacy ?? YouTubePrivacy.unlisted;
  YouTubeBroadcast? _live;
  YouTubeIngest? _ingest;
  bool _fresh = false;
  bool _busy = false;
  String? _error;
  StreamSubscription<void>? _youtubeSub;

  @override
  void initState() {
    super.initState();
    final youtube = widget.youtube;
    if (youtube != null) {
      _youtubeSub = youtube.changes.listen((_) {
        if (mounted) setState(() {});
      });
      if (youtube.email != null) unawaited(_refreshLive());
    }
  }

  @override
  void dispose() {
    unawaited(_youtubeSub?.cancel());
    _server.dispose();
    _key.dispose();
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty && mounted) setState(() => _key.text = text);
  }

  Future<void> _youtubeAction(Future<void> Function(YouTubeAccount) action) async {
    final youtube = widget.youtube!;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(youtube);
    } on YouTubeAccountException catch (e) {
      if (mounted && e.code != 'canceled') {
        setState(() => _error = youtubeErrorMessage(AppLocalizations.of(context), e));
      }
    } catch (e) {
      if (mounted) {
        setState(() =>
            _error = youtubeErrorMessage(AppLocalizations.of(context), YouTubeAccountException('api', '$e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signIn() => _youtubeAction((y) async {
        await y.signIn();
        await _refreshLive();
      });

  Future<void> _refreshLive() async {
    final youtube = widget.youtube!;
    YouTubeBroadcast? live;
    try {
      live = await youtube.refresh();
    } catch (_) {
      live = youtube.current;
    }
    final ingest = await youtube.ingest();
    if (!mounted) return;
    setState(() {
      _live = live;
      _ingest = ingest;
      if (live != null && live.lifeCycle.usable) {
        _title.text = live.title;
        _description.text = live.description;
        _privacy = live.privacy;
      }
    });
  }

  BroadcastConfigResult _result({required String server, String? key}) => (
        server: server,
        key: key,
        targetKbps: _kbps,
        audio: _audio,
        replayScoreboard: _replayScoreboard,
      );

  void _save() {
    if (_mode == _StreamMode.key) {
      final key = _key.text.trim();
      if (widget.youtube case final y?) unawaited(y.setActive(false));
      Navigator.of(context).pop(_result(
        server: _server.text.trim().isEmpty ? BroadcastInfo.defaultServer : _server.text.trim(),
        key: key.isEmpty ? null : key,
      ));
      return;
    }
    final l10n = AppLocalizations.of(context);
    final title = _title.text.trim().isEmpty ? youtubeDefaultTitle(l10n, DateTime.now()) : _title.text.trim();
    unawaited(_youtubeAction((y) async {
      final target = await y.save(
        title: title,
        description: _description.text.trim(),
        privacy: _privacy,
        fresh: _fresh || !(_live?.lifeCycle.usable ?? false),
      );
      if (mounted) Navigator.of(context).pop(_result(server: target.server, key: target.key));
    }));
  }

  /// A phone on its side: too short for a dialog, so the settings take the whole screen.
  static bool fullScreen(Size size) => size.width > size.height && size.height < 500;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final youtube = widget.youtube;
    final signedIn = youtube?.email != null;
    final canSave = !_busy && !(_mode == _StreamMode.account && !signedIn);
    final destination = <Widget>[
      if (youtube != null) ...[
        SegmentedButton<_StreamMode>(
          key: const ValueKey('broadcast-mode'),
          segments: [
            ButtonSegment(
              value: _StreamMode.key,
              icon: const Icon(Icons.key),
              label: Text(l10n.broadcastModeKey, key: const ValueKey('broadcast-mode-key')),
            ),
            ButtonSegment(
              value: _StreamMode.account,
              icon: const Icon(Icons.account_circle),
              label: Text(l10n.broadcastModeAccount, key: const ValueKey('broadcast-mode-account')),
            ),
          ],
          selected: {_mode},
          onSelectionChanged: _busy ? null : (s) => setState(() => _mode = s.single),
        ),
        const SizedBox(height: 16),
      ],
      if (_mode == _StreamMode.key) ..._keyFields(l10n) else ..._accountFields(l10n, youtube!, signedIn),
    ];
    final quality = <Widget>[
      Text(l10n.broadcastBitrateLabel(_kbps)),
      Slider(
        key: const ValueKey('broadcast-kbps'),
        value: _kbps.toDouble(),
        min: BroadcastInfo.minKbps.toDouble(),
        max: BroadcastInfo.maxKbps.toDouble(),
        divisions: (BroadcastInfo.maxKbps - BroadcastInfo.minKbps) ~/ 250,
        label: '$_kbps',
        onChanged: (v) => setState(() => _kbps = v.round()),
      ),
      SwitchListTile(
        key: const ValueKey('broadcast-audio'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.broadcastAudio),
        value: _audio,
        onChanged: (v) => setState(() => _audio = v),
      ),
      SwitchListTile(
        key: const ValueKey('broadcast-replay-scoreboard'),
        contentPadding: EdgeInsets.zero,
        title: Text(l10n.broadcastReplayScoreboard),
        subtitle: Text(l10n.broadcastReplayScoreboardHint),
        value: _replayScoreboard,
        onChanged: (v) => setState(() => _replayScoreboard = v),
      ),
    ];
    final save = FilledButton(
      key: const ValueKey('broadcast-config-save'),
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      onPressed: canSave ? _save : null,
      child: Text(l10n.broadcastSave),
    );

    if (fullScreen(MediaQuery.sizeOf(context))) {
      // Bar with close and Save on top, destination | quality side by side below.
      Widget column(List<Widget> children) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          );
      return Dialog.fullscreen(
        key: const ValueKey('broadcast-config-fullscreen'),
        child: ScaffoldMessenger(
          child: Scaffold(
            appBar: AppBar(
              toolbarHeight: 52,
              leading: IconButton(
                tooltip: l10n.broadcastCancel,
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
              title: Text(l10n.broadcastSettings),
              actions: [save, const SizedBox(width: 12)],
            ),
            body: SafeArea(
              top: false,
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(flex: 3, child: column(destination)),
                const VerticalDivider(width: 1),
                Expanded(flex: 2, child: column(quality)),
              ]),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      title: Text(l10n.broadcastSettings),
      scrollable: true,
      content: SizedBox(
        width: 460,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...destination,
          const SizedBox(height: 16),
          ...quality,
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        save,
      ],
    );
  }

  List<Widget> _keyFields(AppLocalizations l10n) {
    final hint = widget.info.keyHint;
    return [
      TextField(
        key: const ValueKey('broadcast-key'),
        controller: _key,
        obscureText: !_showKey,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: l10n.broadcastKey,
          hintText: hint == null ? null : '•••• $hint',
          helperText: hint == null ? l10n.broadcastKeyHelp : l10n.broadcastKeyKeep(hint),
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
          suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(tooltip: l10n.broadcastPaste, icon: const Icon(Icons.content_paste), onPressed: _paste),
            IconButton(
              tooltip: _showKey ? l10n.broadcastKeyHide : l10n.broadcastKeyShow,
              icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showKey = !_showKey),
            ),
          ]),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        key: const ValueKey('broadcast-server'),
        controller: _server,
        autocorrect: false,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(labelText: l10n.broadcastServer, border: const OutlineInputBorder()),
      ),
    ];
  }

  List<Widget> _accountFields(AppLocalizations l10n, YouTubeAccount youtube, bool signedIn) {
    final theme = Theme.of(context);
    final error = _error;
    final errorText = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, key: const ValueKey('youtube-error'), style: TextStyle(color: theme.colorScheme.error)),
          );
    if (!signedIn) {
      return [
        Text(l10n.youtubeAccountHelp, style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        FilledButton.tonalIcon(
          key: const ValueKey('youtube-sign-in'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: _busy ? null : _signIn,
          icon: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.login),
          label: Text(l10n.youtubeSignIn),
        ),
        ?errorText,
      ];
    }
    final live = _live;
    final usable = live != null && live.lifeCycle.usable && !_fresh;
    return [
      Row(children: [
        const Icon(Icons.account_circle, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(youtube.email!, key: const ValueKey('youtube-email'), overflow: TextOverflow.ellipsis),
        ),
        TextButton(
          key: const ValueKey('youtube-sign-out'),
          onPressed: _busy
              ? null
              : () => _youtubeAction((y) async {
                    await y.signOut();
                    if (mounted) setState(() => _live = null);
                  }),
          child: Text(l10n.youtubeSignOut),
        ),
      ]),
      const SizedBox(height: 8),
      if (usable)
        _YouTubeLiveStatus(
          live: live,
          ingest: _ingest,
          busy: _busy,
          onRefresh: () => _youtubeAction((_) => _refreshLive()),
          onNew: () => setState(() {
            _fresh = true;
            _title.clear();
            _description.clear();
          }),
        )
      else
        Text(l10n.youtubeWillCreate, key: const ValueKey('youtube-will-create'), style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      TextField(
        key: const ValueKey('youtube-title'),
        controller: _title,
        maxLength: 100,
        decoration: InputDecoration(
          labelText: l10n.youtubeTitle,
          hintText: youtubeDefaultTitle(l10n, DateTime.now()),
          border: const OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('youtube-description'),
        controller: _description,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(labelText: l10n.youtubeDescription, border: const OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<YouTubePrivacy>(
        key: const ValueKey('youtube-privacy'),
        initialValue: _privacy,
        decoration: InputDecoration(labelText: l10n.youtubePrivacy, border: const OutlineInputBorder()),
        items: [
          for (final p in YouTubePrivacy.values)
            DropdownMenuItem(value: p, child: Text(youtubePrivacyLabel(l10n, p))),
        ],
        onChanged: _busy ? null : (p) => setState(() => _privacy = p ?? _privacy),
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      ?errorText,
    ];
  }
}

/// The live this device created: its state on YouTube, whether YouTube receives the stream, the
/// link, and a way to start a new one instead.
class _YouTubeLiveStatus extends StatelessWidget {
  const _YouTubeLiveStatus({
    required this.live,
    required this.ingest,
    required this.busy,
    required this.onRefresh,
    required this.onNew,
  });

  final YouTubeBroadcast live;
  final YouTubeIngest? ingest;
  final bool busy;
  final VoidCallback onRefresh;
  final VoidCallback onNew;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final (ingestText, ingestColor) = switch (ingest) {
      YouTubeIngest.good => (l10n.youtubeIngestGood, const Color(0xFF43A047)),
      YouTubeIngest.bad => (l10n.youtubeIngestBad, const Color(0xFFFFB300)),
      YouTubeIngest.none => (l10n.youtubeIngestNone, theme.colorScheme.onSurfaceVariant),
      null => (null, null),
    };
    return DecoratedBox(
      key: const ValueKey('youtube-live'),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(youtubeLifeCycleLabel(l10n, live.lifeCycle),
              key: const ValueKey('youtube-life'), style: const TextStyle(fontWeight: FontWeight.bold)),
          if (ingestText != null)
            Text(ingestText, key: const ValueKey('youtube-ingest'), style: TextStyle(color: ingestColor)),
          SelectableText(live.url, style: theme.textTheme.bodySmall),
          Wrap(children: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: live.url));
                if (context.mounted) {
                  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(l10n.youtubeLinkCopied)));
                }
              },
              icon: const Icon(Icons.link),
              label: Text(l10n.youtubeCopyLink),
            ),
            TextButton.icon(
              key: const ValueKey('youtube-qr'),
              onPressed: () => showYouTubeLinkQr(context, live),
              icon: const Icon(Icons.qr_code_2),
              label: Text(l10n.youtubeQr),
            ),
            TextButton.icon(
              key: const ValueKey('youtube-refresh'),
              onPressed: busy ? null : onRefresh,
              icon: const Icon(Icons.refresh),
              label: Text(l10n.youtubeRefresh),
            ),
            TextButton.icon(
              key: const ValueKey('youtube-new'),
              onPressed: busy ? null : onNew,
              icon: const Icon(Icons.add),
              label: Text(l10n.youtubeNewLive),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// The live's link as a big QR code, for people to open it on their phones.
Future<void> showYouTubeLinkQr(BuildContext context, YouTubeBroadcast live) => showDialog<void>(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final size = MediaQuery.sizeOf(context);
        final title = live.title.isEmpty ? l10n.youtubeQrTitle : live.title;
        // Fixed size: dialogs measure their content, which QrImageView can't answer.
        Widget code(double side) => SizedBox.square(
              dimension: side,
              child: QrImageView(
                key: const ValueKey('youtube-qr-code'),
                data: live.url,
                size: side,
                padding: const EdgeInsets.all(12),
                backgroundColor: Colors.white,
                semanticsLabel: live.url,
              ),
            );
        final close = FilledButton(
          key: const ValueKey('youtube-qr-close'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.youtubeQrClose),
        );
        // Copy and share the link: for the team chat, without scanning anything.
        final linkActions = Wrap(spacing: 8, runSpacing: 4, children: [
          _CopyLinkButton(url: live.url),
          OutlinedButton.icon(
            key: const ValueKey('youtube-qr-share'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => SharePlus.instance.share(ShareParams(text: '$title\n${live.url}', subject: title)),
            icon: const Icon(Icons.share),
            label: Text(l10n.youtubeShare),
          ),
        ]);

        if (size.width > size.height) {
          // On its side: the code as tall as the screen allows, the words beside it.
          final side = (size.height - 64).clamp(160.0, 480.0);
          return Dialog(
            key: const ValueKey('youtube-qr-dialog'),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                code(side),
                const SizedBox(width: 24),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: (size.width - side - 140).clamp(160.0, 360.0)),
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: theme.textTheme.headlineSmall, maxLines: 3, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 12),
                    SelectableText(live.url, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 16),
                    linkActions,
                    const SizedBox(height: 16),
                    close,
                  ]),
                ),
              ]),
            ),
          );
        }

        final side = (size.shortestSide - 96).clamp(160.0, 420.0);
        return AlertDialog(
          key: const ValueKey('youtube-qr-dialog'),
          scrollable: true,
          title: Text(title, textAlign: TextAlign.center),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            code(side),
            const SizedBox(height: 8),
            SelectableText(live.url, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            linkActions,
          ]),
          actionsAlignment: MainAxisAlignment.center,
          actions: [close],
        );
      },
    );

/// Copies the link and says so on the button for a moment (a snack bar would hide behind the
/// dialog).
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
    return FilledButton.tonalIcon(
      key: const ValueKey('youtube-qr-copy'),
      style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
      onPressed: () async {
        await Clipboard.setData(ClipboardData(text: widget.url));
        if (!mounted) return;
        setState(() => _copied = true);
        _reset?.cancel();
        _reset = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _copied = false);
        });
      },
      icon: Icon(_copied ? Icons.check : Icons.content_copy),
      label: Text(_copied ? l10n.youtubeLinkCopied : l10n.youtubeCopyLink),
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

/// The QR button: prepares the live if needed (so its link exists before going on air), then
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

// endregion

// region Scoreboard

/// Team colours to choose from: readable on air and distinct from each other.
const teamPalette = <int>[
  0xFF1E88E5, // blue
  0xFF0D2B6B, // navy
  0xFFE53935, // red
  0xFF8E1B1B, // maroon
  0xFF43A047, // green
  0xFFFDD835, // yellow
  0xFFFB8C00, // orange
  0xFF8E24AA, // purple
  0xFF212121, // black
  0xFFFAFAFA, // white
];

/// Black or white, whichever reads better on [background].
Color onColor(Color background) => background.computeLuminance() > 0.45 ? Colors.black : Colors.white;

/// Rebuilds [builder] with the clock value while a scoreboard clock runs, starting from [state]'s
/// value at the moment the state arrived (a new state object re-anchors it).
class ScoreboardClock extends StatefulWidget {
  const ScoreboardClock({super.key, required this.state, required this.builder});

  final ScoreboardState state;
  final Widget Function(BuildContext context, int clockMs) builder;

  @override
  State<ScoreboardClock> createState() => _ScoreboardClockState();
}

class _ScoreboardClockState extends State<ScoreboardClock> {
  final _since = Stopwatch()..start();
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ScoreboardClock old) {
    super.didUpdateWidget(old);
    if (!identical(old.state, widget.state)) {
      _since
        ..reset()
        ..start();
      _schedule();
    }
  }

  void _schedule() {
    _tick?.cancel();
    _tick = widget.state.clockRunning
        ? Timer.periodic(const Duration(milliseconds: 250), (_) {
            if (mounted) setState(() {});
          })
        : null;
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, widget.state.clockAt(_since.elapsedMilliseconds));
}

/// The scoreboard controls (SPEC §12.2), pressed under stress during a match: per team the name
/// in its colour, the score and big, spaced + and − buttons; in the middle the clock (tap to
/// set), start/stop, the period, and the overlay toggle, reset and settings.
class ScoreboardPanel extends StatelessWidget {
  const ScoreboardPanel({
    super.key,
    required this.state,
    required this.enabled,
    required this.onCommand,
    this.compact = false,
  });

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand command) onCommand;

  /// Short screens: smaller buttons and figures.
  final bool compact;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, c) {
        final home = _TeamControl(team: Team.home, state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final away = _TeamControl(team: Team.away, state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        final centre = _CentreControl(state: state, enabled: enabled, onCommand: onCommand, compact: compact);
        if (c.maxWidth >= 620) {
          return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(child: home),
            const SizedBox(width: 8),
            centre,
            const SizedBox(width: 8),
            Expanded(child: away),
          ]);
        }
        return Column(mainAxisSize: MainAxisSize.min, children: [
          Row(children: [Expanded(child: home), const SizedBox(width: 12), Expanded(child: away)]),
          const SizedBox(height: 4),
          centre,
        ]);
      });
}

class _TeamControl extends StatelessWidget {
  const _TeamControl({
    required this.team,
    required this.state,
    required this.enabled,
    required this.onCommand,
    required this.compact,
  });

  final Team team;
  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final t = state.team(team);
    final color = Color(t.color);
    final plus = compact ? 60.0 : 76.0;
    final minus = compact ? 44.0 : 52.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
        child: Text(
          t.name.toUpperCase(),
          key: ValueKey('score-${team.name}-name'),
          style: TextStyle(color: onColor(color), fontWeight: FontWeight.w900, fontSize: compact ? 16 : 18, letterSpacing: 1),
        ),
      ),
      const SizedBox(height: 4),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton.outlined(
          key: ValueKey('score-${team.name}-minus'),
          tooltip: l10n.scoreboardMinus(t.name),
          constraints: BoxConstraints.tightFor(width: minus, height: minus),
          onPressed: enabled && t.score > 0 ? () => onCommand(ScoreCommand(team: team, delta: -1)) : null,
          icon: const Icon(Icons.remove),
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: compact ? 56 : 72),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '${t.score}',
                key: ValueKey('score-${team.name}'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: compact ? 40 : 52,
                  fontWeight: FontWeight.w900,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: plus,
          height: plus,
          child: FilledButton(
            key: ValueKey('score-${team.name}-plus'),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: color,
              foregroundColor: onColor(color),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              side: color.computeLuminance() > 0.8 ? const BorderSide(color: Colors.black26) : null,
            ),
            onPressed: enabled ? () => onCommand(ScoreCommand(team: team, delta: 1)) : null,
            child: Icon(Icons.add, size: compact ? 36 : 44, semanticLabel: l10n.scoreboardPlus(t.name)),
          ),
        ),
      ]),
    ]);
  }
}

class _CentreControl extends StatelessWidget {
  const _CentreControl({required this.state, required this.enabled, required this.onCommand, required this.compact});

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final play = compact ? 52.0 : 60.0;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(mainAxisSize: MainAxisSize.min, children: [
        // A long press, so a stray tap during the match never opens the editor.
        InkWell(
          key: const ValueKey('score-clock'),
          borderRadius: BorderRadius.circular(8),
          onTap: enabled ? () => _holdHint(context) : null,
          onLongPress: enabled ? () => _setClock(context) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: ScoreboardClock(
              state: state,
              builder: (context, ms) => Text(
                formatClock(ms),
                semanticsLabel: l10n.scoreboardSetClock,
                style: TextStyle(
                  fontSize: compact ? 34 : 42,
                  fontWeight: FontWeight.w800,
                  fontFeatures: const [FontFeature.tabularFigures()],
                  color: state.clockRunning ? null : scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: play,
          height: play,
          child: FilledButton.tonal(
            key: const ValueKey('score-clock-toggle'),
            style: FilledButton.styleFrom(padding: EdgeInsets.zero, shape: const CircleBorder()),
            onPressed: enabled
                ? () => onCommand(state.clockRunning ? const ClockPauseCommand() : const ClockStartCommand())
                : null,
            child: Icon(
              state.clockRunning ? Icons.pause : Icons.play_arrow,
              size: compact ? 32 : 38,
              semanticLabel: state.clockRunning ? l10n.scoreboardPauseClock : l10n.scoreboardStartClock,
            ),
          ),
        ),
      ]),
      // Period changes, hiding, reset and settings happen a few times per match: one menu, out of
      // the way of the buttons used under pressure.
      _ScoreboardMenu(state: state, enabled: enabled, onCommand: onCommand),
    ]);
  }

  void _holdHint(BuildContext context) {
    final text = AppLocalizations.of(context).scoreboardHoldToSetClock;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _setClock(BuildContext context) async {
    unawaited(HapticFeedback.mediumImpact());
    final ms = await showClockSetDialog(context, state.clockAt(0));
    if (ms != null) onCommand(ClockSetCommand(ms: ms));
  }
}

enum _MenuAction { nextPeriod, prevPeriod, visible, reset, settings }

/// The period label plus a menu with the actions used a few times per match.
class _ScoreboardMenu extends StatelessWidget {
  const _ScoreboardMenu({required this.state, required this.enabled, required this.onCommand});

  final ScoreboardState state;
  final bool enabled;
  final void Function(ScoreboardCommand) onCommand;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    String label(int period) => periodLabel(l10n, period: period, periods: state.periods);
    final hasPeriods = state.periods > 1;
    return PopupMenuButton<_MenuAction>(
      key: const ValueKey('score-menu'),
      enabled: enabled,
      tooltip: l10n.scoreboardMore,
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        if (hasPeriods && state.period < state.periods)
          PopupMenuItem(
            key: const ValueKey('score-period-next'),
            value: _MenuAction.nextPeriod,
            child: ListTile(
              leading: const Icon(Icons.skip_next),
              title: Text(l10n.scoreboardGoToPeriod(label(state.period + 1))),
            ),
          ),
        if (hasPeriods && state.period > 1)
          PopupMenuItem(
            key: const ValueKey('score-period-prev'),
            value: _MenuAction.prevPeriod,
            child: ListTile(
              leading: const Icon(Icons.skip_previous),
              title: Text(l10n.scoreboardBackToPeriod(label(state.period - 1))),
            ),
          ),
        if (hasPeriods) const PopupMenuDivider(),
        CheckedPopupMenuItem(
          key: const ValueKey('score-visible'),
          value: _MenuAction.visible,
          checked: state.visible,
          child: Text(l10n.scoreboardVisible),
        ),
        PopupMenuItem(
          key: const ValueKey('score-reset'),
          value: _MenuAction.reset,
          child: ListTile(leading: const Icon(Icons.restart_alt), title: Text(l10n.scoreboardReset)),
        ),
        PopupMenuItem(
          key: const ValueKey('score-settings'),
          value: _MenuAction.settings,
          child: ListTile(leading: const Icon(Icons.tune), title: Text(l10n.scoreboardSettings)),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (hasPeriods) ...[
            Text(
              label(state.period),
              key: const ValueKey('score-period'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(width: 8),
          ],
          if (!state.visible) ...[
            Icon(Icons.visibility_off, size: 20, semanticLabel: l10n.scoreboardHidden),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.more_horiz),
        ]),
      ),
    );
  }

  Future<void> _onSelected(BuildContext context, _MenuAction action) async {
    switch (action) {
      case _MenuAction.nextPeriod:
      case _MenuAction.prevPeriod:
        final delta = action == _MenuAction.nextPeriod ? 1 : -1;
        if (await _confirmPeriod(context, state.period + delta)) onCommand(PeriodCommand(delta: delta));
      case _MenuAction.visible:
        onCommand(VisibleCommand(visible: !state.visible));
      case _MenuAction.reset:
        if (await confirmScoreboardReset(context)) onCommand(const ResetCommand());
      case _MenuAction.settings:
        final settings = await showScoreboardSettingsDialog(context, state.settings);
        if (settings != null) onCommand(SettingsCommand(settings));
    }
  }

  /// A period change stops and resets the clock, so it asks first.
  Future<bool> _confirmPeriod(BuildContext context, int period) async {
    final l10n = AppLocalizations.of(context);
    final label = periodLabel(l10n, period: period, periods: state.periods);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.scoreboardPeriodConfirmTitle(label)),
        content: Text(l10n.scoreboardPeriodConfirmBody(formatClock(state.periodStartMs))),
        actions: [
          TextButton(
            style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.broadcastCancel),
          ),
          FilledButton(
            key: const ValueKey('score-period-confirm'),
            style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.scoreboardPeriodConfirm),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

/// Asks for a clock value with minute and second wheels, like the Android alarm picker; null when
/// cancelled.
Future<int?> showClockSetDialog(BuildContext context, int currentMs) =>
    showDialog<int>(context: context, builder: (_) => _ClockSetDialog(initialMs: currentMs));

class _ClockSetDialog extends StatefulWidget {
  const _ClockSetDialog({required this.initialMs});

  final int initialMs;

  @override
  State<_ClockSetDialog> createState() => _ClockSetDialogState();
}

class _ClockSetDialogState extends State<_ClockSetDialog> {
  static const maxMinutes = 199;

  late final _minutes = FixedExtentScrollController(initialItem: (widget.initialMs ~/ 60000).clamp(0, maxMinutes));
  late final _seconds = FixedExtentScrollController(initialItem: widget.initialMs ~/ 1000 % 60);

  @override
  void dispose() {
    _minutes.dispose();
    _seconds.dispose();
    super.dispose();
  }

  void _submit() {
    // The seconds wheel loops, so its index can run past 59 or below 0.
    final ms = (_minutes.selectedItem * 60 + _seconds.selectedItem % 60) * 1000;
    Navigator.of(context).pop(ms);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(l10n.scoreboardSetClock),
      content: SizedBox(
        height: _Wheel.itemExtent * 5,
        child: Stack(alignment: Alignment.center, children: [
          // The selection band, as in the Android alarm picker.
          Container(
            height: _Wheel.itemExtent,
            decoration: BoxDecoration(color: scheme.secondaryContainer, borderRadius: BorderRadius.circular(12)),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            _Wheel(
              key: const ValueKey('score-clock-minutes'),
              controller: _minutes,
              count: maxMinutes + 1,
              looping: false,
              semanticLabel: l10n.scoreboardMinutes,
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Text(':', style: TextStyle(fontSize: _Wheel.fontSize, fontWeight: FontWeight.w700)),
            ),
            _Wheel(
              key: const ValueKey('score-clock-seconds'),
              controller: _seconds,
              count: 60,
              looping: true,
              semanticLabel: l10n.scoreboardSeconds,
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-clock-set'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: _submit,
          child: Text(l10n.scoreboardSet),
        ),
      ],
    );
  }
}

/// One two-digit wheel. Dragged with a finger, a mouse (web viewer) or the mouse wheel.
class _Wheel extends StatelessWidget {
  const _Wheel({
    super.key,
    required this.controller,
    required this.count,
    required this.looping,
    required this.semanticLabel,
  });

  static const itemExtent = 56.0;
  static const fontSize = 36.0;

  final FixedExtentScrollController controller;
  final int count;
  final bool looping;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    Widget item(int i) => Center(
          child: Text(
            (i % count).toString().padLeft(2, '0'),
            style: const TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        );
    return Semantics(
      label: semanticLabel,
      child: SizedBox(
        width: 84,
        child: ScrollConfiguration(
          // Flutter web doesn't drag scrollables with a mouse by default.
          behavior: ScrollConfiguration.of(context).copyWith(dragDevices: {...PointerDeviceKind.values}, scrollbars: false),
          child: ListWheelScrollView.useDelegate(
            controller: controller,
            itemExtent: itemExtent,
            diameterRatio: 1.6,
            overAndUnderCenterOpacity: 0.45,
            physics: const FixedExtentScrollPhysics(),
            onSelectedItemChanged: (_) => HapticFeedback.selectionClick(),
            childDelegate: looping
                ? ListWheelChildLoopingListDelegate(children: [for (var i = 0; i < count; i++) item(i)])
                : ListWheelChildBuilderDelegate(childCount: count, builder: (context, i) => item(i)),
          ),
        ),
      ),
    );
  }
}

/// True to reset scores, period and clock.
Future<bool> confirmScoreboardReset(BuildContext context) async {
  final l10n = AppLocalizations.of(context);
  final reset = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.scoreboardResetTitle),
      content: Text(l10n.scoreboardResetBody),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-reset-confirm'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(l10n.scoreboardReset),
        ),
      ],
    ),
  );
  return reset ?? false;
}

/// Team names and colours, periods, period length and clock direction; null when cancelled.
Future<ScoreboardSettings?> showScoreboardSettingsDialog(BuildContext context, ScoreboardSettings current) =>
    showDialog<ScoreboardSettings>(context: context, builder: (_) => _SettingsDialog(current: current));

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.current});

  final ScoreboardSettings current;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _homeName = TextEditingController(text: widget.current.homeName);
  late final _awayName = TextEditingController(text: widget.current.awayName);
  late final _minutes = TextEditingController(text: '${widget.current.periodMs ~/ 60000}');
  late int _homeColor = widget.current.homeColor;
  late int _awayColor = widget.current.awayColor;
  late int _periods = widget.current.periods.clamp(1, ScoreboardState.maxPeriods);
  late bool _countDown = widget.current.countDown;
  late int _scale = ScoreboardState.scales.contains(widget.current.scale)
      ? widget.current.scale
      : ScoreboardState.defaultScale;

  @override
  void dispose() {
    _homeName.dispose();
    _awayName.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;
    Widget team(String title, TextEditingController name, int color, ValueChanged<int> onColor, String key) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(title, style: text.titleSmall),
            const SizedBox(height: 8),
            TextField(
              key: ValueKey('score-settings-$key-name'),
              controller: name,
              maxLength: ScoreboardState.maxNameLength,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: l10n.scoreboardTeamName, border: const OutlineInputBorder()),
            ),
            _Palette(selected: color, onSelected: onColor, keyPrefix: 'score-settings-$key-color', label: title),
          ],
        );

    return AlertDialog(
      title: Text(l10n.scoreboardSettings),
      scrollable: true,
      content: SizedBox(
        width: 520,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          team(l10n.scoreboardHome, _homeName, _homeColor, (c) => setState(() => _homeColor = c), 'home'),
          const SizedBox(height: 16),
          team(l10n.scoreboardAway, _awayName, _awayColor, (c) => setState(() => _awayColor = c), 'away'),
          const SizedBox(height: 16),
          Text(l10n.scoreboardPeriods, style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const ValueKey('score-settings-periods'),
            showSelectedIcon: false,
            segments: [
              for (var p = 1; p <= ScoreboardState.maxPeriods; p++) ButtonSegment(value: p, label: Text('$p')),
            ],
            selected: {_periods},
            onSelectionChanged: (s) => setState(() => _periods = s.single),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('score-settings-minutes'),
            controller: _minutes,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
            decoration: InputDecoration(labelText: l10n.scoreboardPeriodMinutes, border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 16),
          Text(l10n.scoreboardClockDirection, style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            key: const ValueKey('score-settings-direction'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: false, icon: const Icon(Icons.arrow_upward), label: Text(l10n.scoreboardCountUp)),
              ButtonSegment(value: true, icon: const Icon(Icons.arrow_downward), label: Text(l10n.scoreboardCountDown)),
            ],
            selected: {_countDown},
            onSelectionChanged: (s) => setState(() => _countDown = s.single),
          ),
          const SizedBox(height: 16),
          Text(l10n.scoreboardSize, style: text.titleSmall),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            key: const ValueKey('score-settings-size'),
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ScoreboardState.scales[0], label: Text(l10n.scoreboardSizeSmall)),
              ButtonSegment(value: ScoreboardState.scales[1], label: Text(l10n.scoreboardSizeMedium)),
              ButtonSegment(value: ScoreboardState.scales[2], label: Text(l10n.scoreboardSizeLarge)),
            ],
            selected: {_scale},
            onSelectionChanged: (s) => setState(() => _scale = s.single),
          ),
        ]),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.broadcastCancel),
        ),
        FilledButton(
          key: const ValueKey('score-settings-save'),
          style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
          onPressed: () {
            final minutes = int.tryParse(_minutes.text) ?? widget.current.periodMs ~/ 60000;
            Navigator.of(context).pop(ScoreboardSettings(
              homeName: ScoreboardState.normalizeName(_homeName.text, widget.current.homeName),
              awayName: ScoreboardState.normalizeName(_awayName.text, widget.current.awayName),
              homeColor: _homeColor,
              awayColor: _awayColor,
              periods: _periods,
              periodMs: minutes.clamp(1, 120) * 60000,
              countDown: _countDown,
              scale: _scale,
            ));
          },
          child: Text(l10n.broadcastSave),
        ),
      ],
    );
  }
}

class _Palette extends StatelessWidget {
  const _Palette({required this.selected, required this.onSelected, required this.keyPrefix, required this.label});

  final int selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final String label;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final outline = Theme.of(context).colorScheme.outline;
    return Semantics(
      label: l10n.scoreboardTeamColor(label),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        for (final (i, c) in teamPalette.indexed)
          InkResponse(
            key: ValueKey('$keyPrefix-$i'),
            onTap: () => onSelected(c),
            radius: 24,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(color: c == selected ? onColor(Color(c)) : outline, width: c == selected ? 3 : 1),
                boxShadow: c == selected ? [BoxShadow(color: outline, spreadRadius: 2)] : null,
              ),
              child: c == selected ? Icon(Icons.check, color: onColor(Color(c)), size: 20) : null,
            ),
          ),
      ]),
    );
  }
}

// endregion

/// The stream's microphone, on or off with one tap (SPEC §12.7): on air at once while
/// streaming, and remembered for the next stream.
class BroadcastMicButton extends StatelessWidget {
  const BroadcastMicButton({super.key, required this.on, required this.enabled, required this.onChanged, this.keyPrefix = 'broadcast'});

  final bool on;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return IconButton(
      key: ValueKey('$keyPrefix-mic'),
      tooltip: on ? l10n.broadcastMicMute : l10n.broadcastMicUnmute,
      isSelected: on,
      constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
      onPressed: enabled ? () => onChanged(!on) : null,
      icon: Icon(Icons.mic_off, color: Theme.of(context).colorScheme.error),
      selectedIcon: const Icon(Icons.mic),
    );
  }
}

