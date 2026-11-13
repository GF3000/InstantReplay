import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../youtube/youtube_account.dart';
import '../youtube/youtube_api.dart';
import 'youtube_share.dart';

/// What "Prepare the stream" returns. [key] null keeps the stored key. [goLive]: the user asked to
/// start streaming with these settings (only offered with `canGoLive`).
typedef BroadcastConfigResult = ({
  String server,
  String? key,
  int targetKbps,
  bool audio,
  bool replayScoreboard,
  bool goLive,
});

/// "Prepare the stream" (B2_Emision): a full-screen page with the destination (stream key or
/// YouTube account), picture and sound, and replays. On a tablet: tabs on the left, the
/// [checklist] and the main button on the right. On a phone: a stepper with a summary.
///
/// The stored key never comes back to the screen: an empty field keeps it. With a [youtube]
/// account available (the Android app) it also offers the account mode: the live is created on
/// the channel and its server and key come back as if typed.
///
/// [canGoLive] (the stream is off) makes the main button "Start streaming"; otherwise it saves.
Future<BroadcastConfigResult?> showBroadcastConfigDialog(
  BuildContext context,
  BroadcastInfo info, {
  YouTubeAccount? youtube,
  bool canGoLive = false,
  Widget? checklist,
}) =>
    Navigator.of(context).push<BroadcastConfigResult>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _StreamSetupPage(info: info, youtube: youtube, canGoLive: canGoLive, checklist: checklist),
    ));

/// The bitrate presets, in kbps.
const streamQualityPresets = [2500, 4500, 6000];

enum _StreamMode { key, account }

enum _Section { destination, image, replays, check }

class _StreamSetupPage extends StatefulWidget {
  const _StreamSetupPage({required this.info, this.youtube, required this.canGoLive, this.checklist});

  final BroadcastInfo info;
  final YouTubeAccount? youtube;
  final bool canGoLive;
  final Widget? checklist;

  @override
  State<_StreamSetupPage> createState() => _StreamSetupPageState();
}

class _StreamSetupPageState extends State<_StreamSetupPage> {
  late final _server = TextEditingController(text: widget.info.server);
  final _key = TextEditingController();
  late int _kbps = widget.info.targetKbps.clamp(BroadcastInfo.minKbps, BroadcastInfo.maxKbps);
  late bool _audio = widget.info.audio;
  late bool _replayScoreboard = widget.info.replayScoreboard;
  bool _showKey = false;
  var _section = _Section.destination;

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

  List<_Section> get _sections => [
        _Section.destination,
        _Section.image,
        _Section.replays,
        if (widget.checklist != null) _Section.check,
      ];

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

  BroadcastConfigResult _result({required String server, String? key, bool goLive = false}) => (
        server: server,
        key: key,
        targetKbps: _kbps,
        audio: _audio,
        replayScoreboard: _replayScoreboard,
        goLive: goLive,
      );

  bool get _canSave => !_busy && !(_mode == _StreamMode.account && widget.youtube?.email == null);

  void _save({bool goLive = false}) {
    if (_mode == _StreamMode.key) {
      final key = _key.text.trim();
      if (widget.youtube case final y?) unawaited(y.setActive(false));
      Navigator.of(context).pop(_result(
        server: _server.text.trim().isEmpty ? BroadcastInfo.defaultServer : _server.text.trim(),
        key: key.isEmpty ? null : key,
        goLive: goLive,
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
      if (mounted) Navigator.of(context).pop(_result(server: target.server, key: target.key, goLive: goLive));
    }));
  }

  /// Streams with what is stored, as last time.
  void _goLiveAsBefore() {
    final info = widget.info;
    Navigator.of(context).pop((
      server: info.server,
      key: null,
      targetKbps: info.targetKbps,
      audio: info.audio,
      replayScoreboard: info.replayScoreboard,
      goLive: true,
    ));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900 && box.maxHeight >= 520;
        return wide ? _wide(context) : _stepper(context, box);
      });

  // region Layouts

  Widget _wide(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final tabs = [
      (_Section.destination, l10n.camTabDestination, l10n.camTabDestinationSub),
      (_Section.image, l10n.camTabImage, l10n.camTabImageSub),
      (_Section.replays, l10n.camTabReplays, l10n.camTabReplaysSub),
    ];
    final section = _section == _Section.check ? _Section.destination : _section;
    return Scaffold(
      key: const ValueKey('broadcast-config-page'),
      appBar: AppBar(
        toolbarHeight: 60,
        leading: _backButton(l10n),
        title: Text(l10n.camPrepareStream),
        actions: [
          Center(child: Text(l10n.camSavedForNext, style: TextStyle(fontSize: 14, color: c.muted))),
          const SizedBox(width: 12),
          if (widget.canGoLive) ...[_saveButton(l10n, small: true), const SizedBox(width: 12)],
        ],
      ),
      body: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            width: 220,
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 16),
            decoration: BoxDecoration(border: Border(right: BorderSide(color: c.line))),
            child: Column(children: [
              for (final (s, label, sub) in tabs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: _TabButton(
                    key: ValueKey('broadcast-tab-${s.name}'),
                    label: label,
                    sub: sub,
                    selected: s == section,
                    onTap: () => setState(() => _section = s),
                  ),
                ),
            ]),
          ),
          Expanded(
            child: ListView(
              key: ValueKey('broadcast-section-${section.name}'),
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              children: _content(context, section, headings: true),
            ),
          ),
          Container(
            width: 320,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: c.surface, border: Border(left: BorderSide(color: c.line))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(l10n.checkTitle, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    if (widget.checklist case final list?) ...[
                      list,
                      const SizedBox(height: 8),
                      Text(l10n.camAmberHint, style: TextStyle(fontSize: 13, color: c.muted)),
                      const SizedBox(height: 16),
                    ],
                    _Summary(rows: _summaryRows(l10n)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              widget.canGoLive ? _goLiveButton(l10n, height: 72) : _saveButton(l10n),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _stepper(BuildContext context, BoxConstraints box) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final sections = _sections;
    final index = sections.indexOf(_section).clamp(0, sections.length - 1);
    final current = sections[index];
    final last = index == sections.length - 1;
    final side = box.maxWidth >= 600;
    String stepName(_Section s) => switch (s) {
          _Section.destination => l10n.camTabDestination,
          _Section.image => l10n.camStepImage,
          _Section.replays => l10n.camTabReplays,
          _Section.check => l10n.camStepCheck,
        };
    final roomy = box.maxWidth >= 760;
    final steps = Row(mainAxisSize: MainAxisSize.min, children: [
      for (final (i, s) in sections.indexed)
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: _StepChip(
            key: ValueKey('broadcast-step-${s.name}'),
            number: i + 1,
            done: i < index,
            label: roomy || i == index ? stepName(s) : null,
            selected: i == index,
            onTap: () => setState(() => _section = s),
          ),
        ),
    ]);

    final next = FilledButton(
      key: const ValueKey('broadcast-config-next'),
      style: FilledButton.styleFrom(minimumSize: const Size(64, 56), textStyle: const TextStyle(fontFamily: IrFonts.sans, fontSize: 18, fontWeight: FontWeight.w700)),
      onPressed: () => setState(() => _section = sections[index + 1]),
      child: Text(l10n.camNext),
    );
    final asBefore = widget.canGoLive && widget.info.configured && !last
        ? TextButton(
            key: const ValueKey('broadcast-config-golive-last'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48), foregroundColor: c.muted),
            onPressed: _busy ? null : _goLiveAsBefore,
            child: Text(l10n.camGoLiveLast, textAlign: TextAlign.center),
          )
        : null;
    final Widget primary = !last
        ? next
        : widget.canGoLive
            ? _goLiveButton(l10n, height: 64)
            : _saveButton(l10n, key: const ValueKey('broadcast-config-done'));

    final content = ListView(
      key: ValueKey('broadcast-section-${current.name}'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      children: _content(context, current, headings: false),
    );

    return Scaffold(
      key: const ValueKey('broadcast-config-stepper'),
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // One slim bar: back, title, the steps and Save.
          Container(
            height: 52,
            padding: const EdgeInsets.only(left: 4, right: 8),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              _backButton(l10n),
              Expanded(
                child: Text(l10n.camPrepareStream,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text)),
              ),
              if (side) steps,
              const SizedBox(width: 8),
              _saveButton(l10n, small: true),
            ]),
          ),
          if (!side)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
              child: steps,
            ),
          Expanded(
            child: side
                ? Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Expanded(child: content),
                    Container(
                      width: 220,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: c.surface, border: Border(left: BorderSide(color: c.line))),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Text(l10n.camSummary, style: irMono(12, weight: FontWeight.w600, color: c.muted)),
                        const SizedBox(height: 8),
                        Expanded(child: SingleChildScrollView(child: _Summary(rows: _summaryRows(l10n), dense: true))),
                        const SizedBox(height: 8),
                        primary,
                        ?asBefore,
                      ]),
                    ),
                  ])
                : content,
          ),
          if (!side)
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(color: c.surface, border: Border(top: BorderSide(color: c.line))),
              child: Row(children: [
                if (asBefore != null) Expanded(child: asBefore),
                if (asBefore != null) const SizedBox(width: 8),
                Expanded(child: primary),
              ]),
            ),
        ]),
      ),
    );
  }

  Widget _backButton(AppLocalizations l10n) => IconButton(
        key: const ValueKey('broadcast-config-back'),
        tooltip: l10n.broadcastCancel,
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      );

  /// Save without going live. A FilledButton so tests can read whether it is enabled.
  Widget _saveButton(AppLocalizations l10n, {bool small = false, Key key = const ValueKey('broadcast-config-save')}) {
    final button = FilledButton(
      key: key,
      style: FilledButton.styleFrom(
        minimumSize: Size(small ? 88 : 64, small ? 44 : 56),
        textStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: small ? 16 : 18, fontWeight: FontWeight.w700),
      ),
      onPressed: _canSave ? _save : null,
      child: Text(l10n.broadcastSave),
    );
    return small ? button : SizedBox(height: 56, child: button);
  }

  Widget _goLiveButton(AppLocalizations l10n, {required double height}) {
    final c = context.ir;
    return SizedBox(
      height: height,
      child: FilledButton(
        key: const ValueKey('broadcast-config-golive'),
        style: FilledButton.styleFrom(
          backgroundColor: c.live,
          foregroundColor: c.onLive,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          textStyle: TextStyle(fontFamily: IrFonts.sans, fontSize: height >= 72 ? 22 : 19, fontWeight: FontWeight.w700),
        ),
        onPressed: _canSave ? () => _save(goLive: true) : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IrLiveDot(color: c.onLive, size: 12, blink: false),
          const SizedBox(width: 10),
          Flexible(child: Text(l10n.camGoLiveNow, overflow: TextOverflow.ellipsis)),
        ]),
      ),
    );
  }

  List<(String, String)> _summaryRows(AppLocalizations l10n) => [
        (
          l10n.camTabDestination,
          _mode == _StreamMode.account ? l10n.camSumYouTube(youtubePrivacyLabel(l10n, _privacy)) : l10n.camSumKey,
        ),
        (l10n.camStepImage, '${_mbps(context, _kbps)} ${l10n.camMbps}'),
        (l10n.camSoundTitle, _audio ? l10n.camYes : l10n.camNo),
        (l10n.camSumReplay, _replayScoreboard ? l10n.camSumScoreboardOn : l10n.camSumScoreboardOff),
      ];

  // endregion

  // region Sections

  List<Widget> _content(BuildContext context, _Section section, {required bool headings}) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    Widget heading(String text) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(text, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: c.text)),
        );
    switch (section) {
      case _Section.destination:
        final youtube = widget.youtube;
        return [
          if (headings) heading(l10n.camWhereStream),
          if (youtube != null) ...[
            _ModeChoice(
              mode: _mode,
              enabled: !_busy,
              onChanged: (m) => setState(() => _mode = m),
            ),
            const SizedBox(height: 16),
          ],
          if (_mode == _StreamMode.key) ..._keyFields(l10n) else ..._accountFields(l10n, youtube!),
        ];
      case _Section.image:
        return [
          if (headings) heading(l10n.camQualityTitle),
          _QualityChoice(kbps: _kbps, onChanged: (v) => setState(() => _kbps = v)),
          const SizedBox(height: 8),
          Text(l10n.camQualityAuto, style: TextStyle(fontSize: 14, color: c.muted)),
          const SizedBox(height: 12),
          Text(l10n.camFineTune, style: _label(c)),
          Row(children: [
            Expanded(
              child: Slider(
                key: const ValueKey('broadcast-kbps'),
                value: _kbps.toDouble(),
                min: BroadcastInfo.minKbps.toDouble(),
                max: BroadcastInfo.maxKbps.toDouble(),
                divisions: (BroadcastInfo.maxKbps - BroadcastInfo.minKbps) ~/ 250,
                label: '$_kbps',
                onChanged: (v) => setState(() => _kbps = v.round()),
              ),
            ),
            Text('$_kbps kbps', style: irMono(14, weight: FontWeight.w600, color: c.muted)),
          ]),
          Divider(height: 32, color: c.line),
          if (headings) heading(l10n.camSoundTitle),
          _SwitchRow(
            key: const ValueKey('broadcast-audio'),
            title: l10n.camMicTitle,
            subtitle: l10n.camMicSub,
            value: _audio,
            onChanged: (v) => setState(() => _audio = v),
          ),
        ];
      case _Section.replays:
        return [
          if (headings) heading(l10n.camReplaysTitle),
          _SwitchRow(
            key: const ValueKey('broadcast-replay-scoreboard'),
            title: l10n.broadcastReplayScoreboard,
            subtitle: l10n.broadcastReplayScoreboardHint,
            value: _replayScoreboard,
            onChanged: (v) => setState(() => _replayScoreboard = v),
          ),
        ];
      case _Section.check:
        return [
          ?widget.checklist,
          const SizedBox(height: 8),
          Text(l10n.camAmberHint, style: TextStyle(fontSize: 13, color: c.muted)),
        ];
    }
  }

  static TextStyle _label(IrColors c) => TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);

  List<Widget> _keyFields(AppLocalizations l10n) {
    final c = context.ir;
    final hint = widget.info.keyHint;
    return [
      Text(l10n.broadcastKey, style: _label(c)),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: TextField(
            key: const ValueKey('broadcast-key'),
            controller: _key,
            obscureText: !_showKey,
            autocorrect: false,
            enableSuggestions: false,
            style: irMono(16, weight: FontWeight.w500, color: c.text),
            decoration: InputDecoration(
              hintText: hint == null ? null : '•••• $hint',
              helperText: hint == null ? l10n.broadcastKeyHelp : l10n.broadcastKeyKeep(hint),
              helperMaxLines: 2,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(height: 52, child: IrKey(
          key: const ValueKey('broadcast-key-paste'),
          minHeight: 52,
          semanticLabel: l10n.broadcastPaste,
          onPressed: _paste,
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.content_paste, size: 20, color: c.text),
            const SizedBox(width: 6),
            Text(l10n.broadcastPaste, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
          ])),
        )),
        const SizedBox(width: 8),
        SizedBox(
          width: 52,
          child: IrKey(
            key: const ValueKey('broadcast-key-show'),
            minHeight: 52,
            padding: EdgeInsets.zero,
            semanticLabel: _showKey ? l10n.broadcastKeyHide : l10n.broadcastKeyShow,
            onPressed: () => setState(() => _showKey = !_showKey),
            child: Center(child: Tooltip(
              message: _showKey ? l10n.broadcastKeyHide : l10n.broadcastKeyShow,
              child: Icon(_showKey ? Icons.visibility_off : Icons.visibility, color: c.text),
            )),
          ),
        ),
      ]),
      const SizedBox(height: 16),
      Text(l10n.broadcastServer, style: _label(c)),
      const SizedBox(height: 6),
      TextField(
        key: const ValueKey('broadcast-server'),
        controller: _server,
        autocorrect: false,
        keyboardType: TextInputType.url,
        style: irMono(14, weight: FontWeight.w500, color: c.muted),
      ),
    ];
  }

  List<Widget> _accountFields(AppLocalizations l10n, YouTubeAccount youtube) {
    final c = context.ir;
    final signedIn = youtube.email != null;
    final error = _error;
    final errorText = error == null
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(error, key: const ValueKey('youtube-error'), style: TextStyle(color: c.liveText)),
          );
    if (!signedIn) {
      return [
        Text(l10n.youtubeAccountHelp, style: TextStyle(fontSize: 14, color: c.muted)),
        const SizedBox(height: 12),
        SizedBox(height: 56, child: IrKey(
          key: const ValueKey('youtube-sign-in'),
          onPressed: _busy ? null : _signIn,
          child: Center(child: Row(mainAxisSize: MainAxisSize.min, children: [
            _busy
                ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.login, color: c.text),
            const SizedBox(width: 8),
            Text(l10n.youtubeSignIn, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
          ])),
        )),
        ?errorText,
      ];
    }
    final live = _live;
    final usable = live != null && live.lifeCycle.usable && !_fresh;
    return [
      IrPanel(
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        child: Row(children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: c.live,
            child: Text(youtube.email!.substring(0, 1).toUpperCase(),
                style: TextStyle(color: c.onLive, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(youtube.email!,
                key: const ValueKey('youtube-email'),
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
          ),
          OutlinedButton(
            key: const ValueKey('youtube-sign-out'),
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 44)),
            onPressed: _busy
                ? null
                : () => _youtubeAction((y) async {
                      await y.signOut();
                      if (mounted) setState(() => _live = null);
                    }),
            child: Text(l10n.youtubeSignOut),
          ),
        ]),
      ),
      const SizedBox(height: 10),
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
        Text(l10n.youtubeWillCreate,
            key: const ValueKey('youtube-will-create'), style: TextStyle(fontSize: 14, color: c.muted)),
      const SizedBox(height: 14),
      TextField(
        key: const ValueKey('youtube-title'),
        controller: _title,
        maxLength: 100,
        decoration: InputDecoration(labelText: l10n.youtubeTitle, hintText: youtubeDefaultTitle(l10n, DateTime.now())),
      ),
      const SizedBox(height: 8),
      TextField(
        key: const ValueKey('youtube-description'),
        controller: _description,
        minLines: 1,
        maxLines: 3,
        decoration: InputDecoration(labelText: l10n.youtubeDescription),
      ),
      const SizedBox(height: 14),
      Text(l10n.camWhoCanSee, style: _label(c)),
      const SizedBox(height: 6),
      _PrivacyChoice(
        privacy: _privacy,
        enabled: !_busy,
        onChanged: (p) => setState(() => _privacy = p),
      ),
      if (_busy) ...[
        const SizedBox(height: 12),
        const LinearProgressIndicator(),
      ],
      ?errorText,
    ];
  }

  // endregion
}

/// `4,5` for 4500 kbps, in the locale's format.
String _mbps(BuildContext context, int kbps) =>
    NumberFormat('0.#', Localizations.localeOf(context).toString()).format(kbps / 1000);

/// A left-column tab: label and a line under it; amber when selected.
class _TabButton extends StatelessWidget {
  const _TabButton({super.key, required this.label, required this.sub, required this.selected, required this.onTap});

  final String label;
  final String sub;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.signalSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(label, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A step in the phone's stepper: its number (a check once passed) and, when there is room, its
/// name.
class _StepChip extends StatelessWidget {
  const _StepChip({
    super.key,
    required this.number,
    required this.done,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final int number;
  final bool done;
  final String? label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    final fg = selected || done ? c.text : c.muted;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: Material(
        color: selected ? c.signalSoft : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(4),
          side: BorderSide(color: selected ? c.signal : c.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(4),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                done
                    ? Icon(Icons.check, size: 16, color: c.ok)
                    : Text('$number', style: irMono(13, weight: FontWeight.w600, color: fg)),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(label!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// YouTube account or stream key, as one segmented strip.
class _ModeChoice extends StatelessWidget {
  const _ModeChoice({required this.mode, required this.enabled, required this.onChanged});

  final _StreamMode mode;
  final bool enabled;
  final ValueChanged<_StreamMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    Widget segment(_StreamMode m, String label, IconData icon) {
      final selected = m == mode;
      final fg = selected ? c.onSignal : c.text;
      return Expanded(
        child: Semantics(
          selected: selected,
          button: true,
          child: Material(
            color: selected ? c.signal : c.surface,
            child: InkWell(
              key: ValueKey('broadcast-mode-${m.name}'),
              onTap: enabled ? () => onChanged(m) : null,
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(icon, size: 20, color: fg),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 520),
      child: Container(
        key: const ValueKey('broadcast-mode'),
        height: 50,
        decoration: BoxDecoration(border: Border.all(color: c.line), borderRadius: BorderRadius.circular(4)),
        clipBehavior: Clip.antiAlias,
        child: Row(children: [
          segment(_StreamMode.account, l10n.broadcastModeAccount, Icons.account_circle),
          VerticalDivider(width: 1, thickness: 1, color: c.line),
          segment(_StreamMode.key, l10n.broadcastModeKey, Icons.key),
        ]),
      ),
    );
  }
}

/// Public, unlisted or private as three choice tiles.
class _PrivacyChoice extends StatelessWidget {
  const _PrivacyChoice({required this.privacy, required this.enabled, required this.onChanged});

  final YouTubePrivacy privacy;
  final bool enabled;
  final ValueChanged<YouTubePrivacy> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(key: const ValueKey('youtube-privacy'), children: [
      for (final (i, p) in YouTubePrivacy.values.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: _ChoiceTile(
            key: ValueKey('youtube-privacy-${p.name}'),
            selected: p == privacy,
            onTap: enabled ? () => onChanged(p) : null,
            title: youtubePrivacyLabel(l10n, p),
            sub: youtubePrivacySub(l10n, p),
          ),
        ),
      ],
    ]);
  }
}

/// Ahorro 2,5 · Normal 4,5 · Alta 6 Mbps; another value from the fine slider selects none.
class _QualityChoice extends StatelessWidget {
  const _QualityChoice({required this.kbps, required this.onChanged});

  final int kbps;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final locale = Localizations.localeOf(context).toString();
    final presets = [
      (streamQualityPresets[0], l10n.camQualityLow, l10n.camQualityLowSub),
      (streamQualityPresets[1], l10n.camQualityNormal, l10n.camQualityNormalSub),
      (streamQualityPresets[2], l10n.camQualityHigh, l10n.camQualityHighSub),
    ];
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final (i, (value, label, sub)) in presets.indexed) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: _ChoiceTile(
            key: ValueKey('broadcast-kbps-$value'),
            selected: value == kbps,
            onTap: () => onChanged(value),
            title: label,
            number: Text.rich(
              TextSpan(children: [
                TextSpan(text: NumberFormat('0.0', locale).format(value / 1000)),
                TextSpan(text: ' ${l10n.camMbps}', style: irMono(13, color: value == kbps ? c.signal : c.text)),
              ]),
              style: irMono(24, color: value == kbps ? c.signal : c.text),
            ),
            sub: '${l10n.camQualityPerHour(NumberFormat('0.0', locale).format(value * 3600 / 8 / 1e6))} · $sub',
          ),
        ),
      ],
    ]);
  }
}

/// A selectable tile: title, an optional big number and a line under it. Amber border and a soft
/// amber fill when selected.
class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({super.key, required this.selected, required this.onTap, required this.title, this.number, this.sub});

  final bool selected;
  final VoidCallback? onTap;
  final String title;
  final Widget? number;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? c.signalSoft : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: selected ? c.signal : c.line, width: selected ? 2 : 1),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
                ?number,
                if (sub != null) Text(sub!, style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// A panel row with a title, a line under it and a switch; the whole row toggles it.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({super.key, required this.title, required this.subtitle, required this.value, required this.onChanged});

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4), side: BorderSide(color: c.line)),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: c.text)),
                Text(subtitle, style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
            Switch(value: value, onChanged: onChanged),
          ]),
        ),
      ),
    );
  }
}

/// Key–value lines: what will go on air.
class _Summary extends StatelessWidget {
  const _Summary({required this.rows, this.dense = false});

  final List<(String, String)> rows;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    return Column(key: const ValueKey('broadcast-config-summary'), crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final (k, v) in rows)
        Padding(
          padding: EdgeInsets.symmetric(vertical: dense ? 3 : 5),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(fontSize: 14, color: c.muted)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(v, textAlign: TextAlign.end, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.text)),
            ),
          ]),
        ),
    ]);
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
    final c = context.ir;
    final (ingestText, ingestColor, ingestIcon) = switch (ingest) {
      YouTubeIngest.good => (l10n.youtubeIngestGood, c.ok, Icons.check_circle),
      YouTubeIngest.bad => (l10n.youtubeIngestBad, c.warnText, Icons.warning_amber_rounded),
      YouTubeIngest.none => (l10n.youtubeIngestNone, c.muted, Icons.remove_circle_outline),
      null => (null, null, null),
    };
    final buttonStyle = TextButton.styleFrom(minimumSize: const Size(48, 48));
    return Container(
      key: const ValueKey('youtube-live'),
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 4),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: live.lifeCycle == YouTubeLifeCycle.live ? c.live : c.line),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(youtubeLifeCycleLabel(l10n, live.lifeCycle),
            key: const ValueKey('youtube-life'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text)),
        if (ingestText != null)
          Row(children: [
            Icon(ingestIcon, size: 16, color: ingestColor),
            const SizedBox(width: 6),
            Flexible(child: Text(ingestText, key: const ValueKey('youtube-ingest'), style: TextStyle(color: ingestColor))),
          ]),
        const SizedBox(height: 4),
        SelectableText(live.url, style: irMono(13, weight: FontWeight.w500, color: c.muted)),
        Wrap(children: [
          TextButton.icon(
            style: buttonStyle,
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
            style: buttonStyle,
            onPressed: () => showYouTubeLinkQr(context, live),
            icon: const Icon(Icons.qr_code_2),
            label: Text(l10n.youtubeQr),
          ),
          TextButton.icon(
            key: const ValueKey('youtube-refresh'),
            style: buttonStyle,
            onPressed: busy ? null : onRefresh,
            icon: const Icon(Icons.refresh),
            label: Text(l10n.youtubeRefresh),
          ),
          TextButton.icon(
            key: const ValueKey('youtube-new'),
            style: buttonStyle,
            onPressed: busy ? null : onNew,
            icon: const Icon(Icons.add),
            label: Text(l10n.youtubeNewLive),
          ),
        ]),
      ]),
    );
  }
}
