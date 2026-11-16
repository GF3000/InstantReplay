import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:replay_protocol/replay_protocol.dart';

import '../../../core/ui/ir_colors.dart';
import '../../../core/ui/ir_widgets.dart';
import '../../../l10n/app_localizations.dart';
import '../scoreboard_controller.dart' show periodLabel;
import 'scoreboard_panel.dart' show onColor, teamPalette;

/// The scoreboard's settings (B2_Marcador): whether the board goes on air and whether this screen
/// shows its controls (both apply at once), style (Classic bar, Plate or Banner, each card drawing
/// the board with the names as typed), position on the picture, team names and colours, size on
/// screen, periods, whether the period shows on air, minutes and clock direction. Null when
/// cancelled. [state] feeds the cards with the current scores and clock.
///
/// [onAirChanged] (with [onAir], the board's current visibility) and [onControlsChanged] (with
/// [controlsShown]) add their switch only when given.
Future<ScoreboardSettings?> showScoreboardSettingsDialog(
  BuildContext context,
  ScoreboardSettings current, {
  ScoreboardState? state,
  bool? onAir,
  ValueChanged<bool>? onAirChanged,
  bool? controlsShown,
  ValueChanged<bool>? onControlsChanged,
}) => Navigator.of(context).push<ScoreboardSettings>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _ScoreboardSettingsPage(
      current: current,
      state: state,
      onAir: onAir ?? state?.visible ?? true,
      onAirChanged: onAirChanged,
      controlsShown: controlsShown ?? true,
      onControlsChanged: onControlsChanged,
    ),
  ),
);

class _ScoreboardSettingsPage extends StatefulWidget {
  const _ScoreboardSettingsPage({
    required this.current,
    this.state,
    required this.onAir,
    this.onAirChanged,
    required this.controlsShown,
    this.onControlsChanged,
  });

  final ScoreboardSettings current;
  final ScoreboardState? state;
  final bool onAir;
  final ValueChanged<bool>? onAirChanged;
  final bool controlsShown;
  final ValueChanged<bool>? onControlsChanged;

  @override
  State<_ScoreboardSettingsPage> createState() => _ScoreboardSettingsPageState();
}

class _ScoreboardSettingsPageState extends State<_ScoreboardSettingsPage> {
  late final _homeName = TextEditingController(text: widget.current.homeName);
  late final _awayName = TextEditingController(text: widget.current.awayName);
  late final _minutes = TextEditingController(text: '${widget.current.periodMs ~/ 60000}');
  late int _homeColor = widget.current.homeColor;
  late int _awayColor = widget.current.awayColor;
  late int _periods = widget.current.periods.clamp(1, ScoreboardState.maxPeriods);
  late bool _countDown = widget.current.countDown;
  late bool _showPeriod = widget.current.showPeriod ?? widget.state?.showPeriod ?? true;
  late ScoreboardStyle _style = widget.current.style ?? widget.state?.style ?? ScoreboardStyle.classic;
  late ScoreboardPosition _position =
      widget.current.position ?? widget.state?.position ?? ScoreboardPosition.defaultPosition;
  late bool _onAir = widget.onAir;
  late bool _controls = widget.controlsShown;
  late int _scale = ScoreboardState.scales.contains(widget.current.scale)
      ? widget.current.scale
      : ScoreboardState.defaultScale;

  @override
  void initState() {
    super.initState();
    for (final c in [_homeName, _awayName, _minutes]) {
      c.addListener(_changed);
    }
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _homeName.dispose();
    _awayName.dispose();
    _minutes.dispose();
    super.dispose();
  }

  void _save() {
    final minutes = int.tryParse(_minutes.text) ?? widget.current.periodMs ~/ 60000;
    Navigator.of(context).pop(
      ScoreboardSettings(
        homeName: ScoreboardState.normalizeName(_homeName.text, widget.current.homeName),
        awayName: ScoreboardState.normalizeName(_awayName.text, widget.current.awayName),
        homeColor: _homeColor,
        awayColor: _awayColor,
        periods: _periods,
        periodMs: minutes.clamp(1, 120) * 60000,
        countDown: _countDown,
        scale: _scale,
        style: _style,
        position: _position,
        showPeriod: _showPeriod,
      ),
    );
  }

  /// What the preview draws: the names as typed, the scores and clock of the match.
  ScoreboardPreviewData _preview(AppLocalizations l10n) {
    final s = widget.state;
    final minutes = (int.tryParse(_minutes.text) ?? widget.current.periodMs ~/ 60000).clamp(1, 120);
    final period = (s?.period ?? 1).clamp(1, _periods);
    String name(TextEditingController c, String fallback) => ScoreboardState.normalizeName(c.text, fallback);
    return ScoreboardPreviewData(
      homeName: name(_homeName, widget.current.homeName),
      awayName: name(_awayName, widget.current.awayName),
      homeColor: _homeColor,
      awayColor: _awayColor,
      homeScore: s?.home.score ?? 0,
      awayScore: s?.away.score ?? 0,
      clock: formatClock(s?.clockAt(0) ?? (_countDown ? minutes * 60000 : 0)),
      period: periodLabel(l10n, period: period, periods: _periods, shown: _showPeriod),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final data = _preview(l10n);
    final save = Padding(
      padding: const EdgeInsets.only(right: 12),
      child: FilledButton(
        key: const ValueKey('score-settings-save'),
        style: FilledButton.styleFrom(minimumSize: const Size(96, 48)),
        onPressed: _save,
        child: Text(l10n.broadcastSave),
      ),
    );
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: l10n.broadcastCancel,
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(l10n.sbPageTitle),
        actions: [save],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 900;
            final styleCards = _StyleCards(data: data, style: _style, onChanged: (s) => setState(() => _style = s));
            // No big preview: each style card already draws the board with the names as typed.
            final styleBlock = <Widget>[
              ..._visibility(l10n, c),
              Text(l10n.sbStyle, style: _label(c)),
              const SizedBox(height: 8),
              styleCards,
              const SizedBox(height: 18),
              Text(l10n.sbPosition, style: _label(c)),
              const SizedBox(height: 8),
              _PositionPicker(
                data: data,
                style: _style,
                scale: _scale,
                position: _position,
                onChanged: (p) => setState(() => _position = p),
              ),
            ];
            final fields = _fields(l10n, c, foldColours: !wide);
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    flex: 11,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: styleBlock),
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.line),
                  Expanded(
                    flex: 8,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 20),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
                    ),
                  ),
                ],
              );
            }
            if (box.maxWidth > box.maxHeight && box.maxWidth >= 600) {
              // A phone on its side: visibility and style on the left, the fields beside them.
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: styleBlock),
                    ),
                  ),
                  VerticalDivider(width: 1, color: c.line),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: fields),
                    ),
                  ),
                ],
              );
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [...styleBlock, const SizedBox(height: 20), ...fields],
              ),
            );
          },
        ),
      ),
    );
  }

  static TextStyle _label(IrColors c) => TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);

  /// The two switches that act at once: the board on air, and its controls on this screen.
  List<Widget> _visibility(AppLocalizations l10n, IrColors c) {
    final onAirChanged = widget.onAirChanged;
    final onControlsChanged = widget.onControlsChanged;
    if (onAirChanged == null && onControlsChanged == null) return const [];
    return [
      Text(l10n.sbVisibility, style: _label(c)),
      const SizedBox(height: 8),
      IrPanel(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            if (onAirChanged != null)
              _SwitchRow(
                key: const ValueKey('score-settings-on-air'),
                title: l10n.sbOnAir,
                subtitle: l10n.sbOnAirSub,
                value: _onAir,
                onChanged: (v) {
                  setState(() => _onAir = v);
                  onAirChanged(v);
                },
              ),
            if (onAirChanged != null && onControlsChanged != null) Divider(height: 1, color: c.line),
            if (onControlsChanged != null)
              _SwitchRow(
                key: const ValueKey('score-settings-controls'),
                title: l10n.sbControls,
                subtitle: l10n.sbControlsSub,
                value: _controls,
                onChanged: (v) {
                  setState(() => _controls = v);
                  onControlsChanged(v);
                },
              ),
          ],
        ),
      ),
      const SizedBox(height: 18),
    ];
  }

  List<Widget> _fields(AppLocalizations l10n, IrColors c, {required bool foldColours}) {
    // Classic and Banner draw only the first letters of a name; the Plate draws it whole.
    final shown = _style.cutsNames ? _style.nameLength : null;
    final cutWarning = switch (_style) {
      ScoreboardStyle.classic => l10n.sbClassicCut,
      ScoreboardStyle.banner => l10n.sbBannerCut,
      ScoreboardStyle.plate => null,
    };
    Widget team(String title, TextEditingController name, int color, ValueChanged<int> onColor, String key) {
      final length = name.text.trim().length;
      final cut = shown != null && length > shown;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: _label(c)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: ValueKey('score-settings-$key-name'),
                  controller: name,
                  maxLength: ScoreboardState.maxNameLength,
                  maxLengthEnforcement: MaxLengthEnforcement.enforced,
                  buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
                  textCapitalization: TextCapitalization.characters,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, letterSpacing: 1, color: c.text),
                  decoration: InputDecoration(labelText: l10n.sbTeamName),
                ),
              ),
              SizedBox(
                width: 64,
                child: Text(
                  '$length / ${shown ?? ScoreboardState.maxNameLength}',
                  key: ValueKey('score-settings-$key-count'),
                  textAlign: TextAlign.end,
                  style: irMono(13, weight: FontWeight.w500, color: cut ? c.warnText : c.muted),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _Palette(
            selected: color,
            onSelected: onColor,
            keyPrefix: 'score-settings-$key-color',
            label: title,
            foldable: foldColours,
          ),
        ],
      );
    }

    return [
      team(l10n.sbHomeTeam, _homeName, _homeColor, (v) => setState(() => _homeColor = v), 'home'),
      const SizedBox(height: 18),
      team(l10n.sbAwayTeam, _awayName, _awayColor, (v) => setState(() => _awayColor = v), 'away'),
      if (cutWarning != null) ...[
        const SizedBox(height: 14),
        Container(
          key: ValueKey('score-settings-${_style.name}-cut'),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.signalSoft,
            border: Border.all(color: c.warn.withValues(alpha: 0.5)),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(cutWarning, style: TextStyle(fontSize: 14, color: c.warnText)),
        ),
      ],
      const SizedBox(height: 18),
      Text(l10n.sbSizeOnScreen, style: _label(c)),
      const SizedBox(height: 8),
      IrSegmented<int>(
        key: const ValueKey('score-settings-size'),
        values: ScoreboardState.scales,
        selected: _scale,
        labelOf: (v) => switch (ScoreboardState.scales.indexOf(v)) {
          0 => l10n.scoreboardSizeSmall,
          1 => l10n.scoreboardSizeMedium,
          _ => l10n.scoreboardSizeLarge,
        },
        onChanged: (v) => setState(() => _scale = v),
      ),
      const SizedBox(height: 18),
      Text(l10n.scoreboardPeriods, style: _label(c)),
      const SizedBox(height: 8),
      IrSegmented<int>(
        key: const ValueKey('score-settings-periods'),
        values: [for (var p = 1; p <= ScoreboardState.maxPeriods; p++) p],
        selected: _periods,
        labelOf: (p) => '$p',
        mono: true,
        onChanged: (p) => setState(() => _periods = p),
      ),
      const SizedBox(height: 10),
      IrPanel(
        padding: EdgeInsets.zero,
        child: _SwitchRow(
          key: const ValueKey('score-settings-show-period'),
          title: l10n.sbShowPeriod,
          subtitle: l10n.sbShowPeriodSub,
          value: _showPeriod,
          onChanged: (v) => setState(() => _showPeriod = v),
        ),
      ),
      const SizedBox(height: 18),
      TextField(
        key: const ValueKey('score-settings-minutes'),
        controller: _minutes,
        keyboardType: TextInputType.number,
        style: irMono(18, weight: FontWeight.w600, color: c.text),
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
        decoration: InputDecoration(labelText: l10n.scoreboardPeriodMinutes),
      ),
      const SizedBox(height: 18),
      Text(l10n.scoreboardClockDirection, style: _label(c)),
      const SizedBox(height: 8),
      IrSegmented<bool>(
        key: const ValueKey('score-settings-direction'),
        values: const [false, true],
        selected: _countDown,
        labelOf: (down) => down ? l10n.scoreboardCountDown : l10n.scoreboardCountUp,
        onChanged: (v) => setState(() => _countDown = v),
      ),
    ];
  }
}

/// Classic, Plate and Banner as choice cards, each with a small drawing of the style.
class _StyleCards extends StatelessWidget {
  const _StyleCards({required this.data, required this.style, required this.onChanged});

  final ScoreboardPreviewData data;
  final ScoreboardStyle style;
  final ValueChanged<ScoreboardStyle> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    Widget card(ScoreboardStyle s, String title, String sub, {String? tag}) {
      final selected = s == style;
      return Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? c.signalSoft : c.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: BorderSide(color: selected ? c.signal : c.line, width: 2),
          ),
          child: InkWell(
            key: ValueKey('score-settings-style-${s.name}'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => onChanged(s),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.text),
                        ),
                      ),
                      if (tag != null)
                        Text(
                          tag,
                          style: irMono(11, weight: FontWeight.w600, color: c.muted),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: ScoreboardPreview(data: data, style: s, barHeight: 24),
                  ),
                  const SizedBox(height: 10),
                  Text(sub, style: TextStyle(fontSize: 14, color: c.muted)),
                ],
              ),
            ),
          ),
        ),
      );
    }

    final classic = card(ScoreboardStyle.classic, l10n.sbClassic, l10n.sbClassicSub, tag: l10n.sbDefault);
    final plate = card(ScoreboardStyle.plate, l10n.sbPlate, l10n.sbPlateSub);
    final banner = card(ScoreboardStyle.banner, l10n.sbBanner, l10n.sbBannerSub);
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [classic, const SizedBox(height: 10), plate, const SizedBox(height: 10), banner],
          );
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: classic),
              const SizedBox(width: 12),
              Expanded(child: plate),
              const SizedBox(width: 12),
              Expanded(child: banner),
            ],
          ),
        );
      },
    );
  }
}

/// The picture as a 16:9 frame with the six places the board can go; the chosen one shows the
/// board in its style and at its [scale], the others a dot to tap.
class _PositionPicker extends StatelessWidget {
  const _PositionPicker({
    required this.data,
    required this.style,
    required this.scale,
    required this.position,
    required this.onChanged,
  });

  final ScoreboardPreviewData data;
  final ScoreboardStyle style;

  /// Board size in percent of the base bar.
  final int scale;
  final ScoreboardPosition position;
  final ValueChanged<ScoreboardPosition> onChanged;

  static String label(AppLocalizations l10n, ScoreboardPosition p) => switch (p) {
    ScoreboardPosition.topLeft => l10n.sbPositionTopLeft,
    ScoreboardPosition.topCenter => l10n.sbPositionTopCenter,
    ScoreboardPosition.topRight => l10n.sbPositionTopRight,
    ScoreboardPosition.bottomLeft => l10n.sbPositionBottomLeft,
    ScoreboardPosition.bottomCenter => l10n.sbPositionBottomCenter,
    ScoreboardPosition.bottomRight => l10n.sbPositionBottomRight,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    // Aligned so the width cap holds inside the stretched settings column.
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          // A Material, so the spots' ink shows on the picture.
          child: Material(
            color: const Color(0xFF2E3B2A),
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
              side: BorderSide(color: c.line),
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                // The board at its share of the frame, as on air.
                final bar = box.maxHeight * ScoreboardState.baseBarFraction * scale / 100;
                return Stack(
                  children: [
                    for (final p in ScoreboardPosition.values)
                      Align(
                        alignment: Alignment(p.column - 1.0, p.top ? -1 : 1),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                            box.maxWidth * 0.03,
                            box.maxHeight * 0.03,
                            box.maxWidth * 0.03,
                            box.maxHeight * 0.06,
                          ),
                          child: Semantics(
                            button: true,
                            selected: p == position,
                            label: label(l10n, p),
                            child: InkWell(
                              key: ValueKey('score-settings-position-${p.name}'),
                              borderRadius: BorderRadius.circular(4),
                              onTap: () => onChanged(p),
                              child: p == position
                                  ? ConstrainedBox(
                                      constraints: BoxConstraints(maxWidth: box.maxWidth * 0.45),
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: ScoreboardPreview(data: data, style: style, barHeight: bar),
                                      ),
                                    )
                                  : SizedBox.square(
                                      dimension: 48,
                                      child: Center(
                                        child: Container(
                                          width: 18,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: Colors.white.withValues(alpha: 0.25),
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.8), width: 2),
                                          ),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// What [ScoreboardPreview] draws.
class ScoreboardPreviewData {
  const ScoreboardPreviewData({
    required this.homeName,
    required this.awayName,
    required this.homeColor,
    required this.awayColor,
    required this.homeScore,
    required this.awayScore,
    required this.clock,
    required this.period,
  });

  final String homeName;
  final String awayName;
  final int homeColor;
  final int awayColor;
  final int homeScore;
  final int awayScore;
  final String clock;
  final String period;
}

/// A drawing of the burned-in board in [style], [barHeight] tall per row of the Classic bar. The
/// greys mirror the native overlay's, which sits on the video and not on the app's theme.
class ScoreboardPreview extends StatelessWidget {
  const ScoreboardPreview({super.key, required this.data, required this.style, required this.barHeight});

  final ScoreboardPreviewData data;
  final ScoreboardStyle style;
  final double barHeight;

  static const _barBg = Color(0xD9101418);
  static const _plateBg = Color(0xED0F1012);
  static const _cell = Color(0x40FFFFFF);
  static const _dark = Color(0x66000000);
  static const _plateLine = Color(0x24FFFFFF);
  static const _plateCell = Color(0x0DFFFFFF);
  static const _amber = Color(0xFFFFC107);
  static const _grey = Color(0xFF9AA0A8);
  static const _navy = Color(0xF20B1240);
  static const _tab = Color(0xF2F2C744);
  static const _tabText = Color(0xFF0B1240);

  @override
  Widget build(BuildContext context) => switch (style) {
    ScoreboardStyle.classic => _classic(),
    ScoreboardStyle.plate => _plate(),
    ScoreboardStyle.banner => _banner(context),
  };

  /// Mirrors the native banner (`Scoreboard.bannerLayout`): navy bar with team-coloured edges,
  /// both names centred in equal columns and scores reserving two digits, so the dash sits in the
  /// middle; the period + clock tab hangs below.
  Widget _banner(BuildContext context) {
    final h = barHeight * 1.15;
    final r = Radius.circular(h * 0.06);
    final base = DefaultTextStyle.of(context).style;
    final name = base.merge(
      TextStyle(
        color: Colors.white,
        fontSize: h * 0.46,
        fontWeight: FontWeight.w600,
        letterSpacing: h * 0.03,
        height: 1,
      ),
    );
    final score = base.merge(irMono(h * 0.62, color: Colors.white, height: 1));
    final tab = base.merge(irMono(h * 0.34, color: _tabText, height: 1));
    double width(String text, TextStyle style) => (TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout()).width;
    String zeros(String s) => s.replaceAll(RegExp('[0-9]'), '0');
    final home = ScoreboardState.displayName(data.homeName, ScoreboardStyle.banner);
    final away = ScoreboardState.displayName(data.awayName, ScoreboardStyle.banner);
    final names = math.max(width(home, name), width(away, name));
    final scores = [
      width(zeros('${data.homeScore}'), score),
      width(zeros('${data.awayScore}'), score),
      width('00', score),
    ].reduce(math.max);
    Widget cell(String text, TextStyle style, double w, TextAlign align) => SizedBox(
      width: w,
      child: Text(text, style: style, textAlign: align, maxLines: 1, softWrap: false, textScaler: TextScaler.noScaling),
    );
    Widget edge(int color) => Container(width: h * 0.09, height: h, color: Color(color));
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.all(r),
          child: Container(
            height: h,
            color: _navy,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                edge(data.homeColor),
                SizedBox(width: h * 0.4),
                cell(home, name, names, TextAlign.center),
                SizedBox(width: h * 0.45),
                cell('${data.homeScore}', score, scores, TextAlign.right),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: h * 0.12),
                  child: Text('-', style: score, textScaler: TextScaler.noScaling),
                ),
                cell('${data.awayScore}', score, scores, TextAlign.left),
                SizedBox(width: h * 0.45),
                cell(away, name, names, TextAlign.center),
                SizedBox(width: h * 0.4),
                edge(data.awayColor),
              ],
            ),
          ),
        ),
        Container(
          height: h * 0.52,
          padding: EdgeInsets.symmetric(horizontal: h * 0.28),
          decoration: BoxDecoration(
            color: _tab,
            borderRadius: BorderRadius.only(bottomLeft: r, bottomRight: r),
          ),
          // No alignment here: it would stretch the tab to the whole width.
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (data.period.isNotEmpty) ...[
                Text(
                  data.period,
                  style: tab.copyWith(color: _tabText.withValues(alpha: 0.7)),
                  textScaler: TextScaler.noScaling,
                ),
                SizedBox(width: h * 0.22),
              ],
              cell(data.clock, tab, width(zeros(data.clock), tab), TextAlign.center),
            ],
          ),
        ),
      ],
    );
  }

  Widget _classic() {
    final h = barHeight;
    final font = TextStyle(color: Colors.white, fontSize: h * 0.6, fontWeight: FontWeight.w700, height: 1);
    final mono = irMono(h * 0.6, color: Colors.white, height: 1);
    Widget cell(String text, {Color? bg, bool number = false}) => Container(
      height: h,
      color: bg,
      constraints: BoxConstraints(minWidth: number ? h * 0.9 : 0),
      padding: EdgeInsets.symmetric(horizontal: h * 0.25),
      alignment: Alignment.center,
      child: Text(text, style: number ? mono : font),
    );
    Widget bar(int color) => Container(width: h * 0.13, height: h, color: Color(color));
    return Container(
      color: _barBg,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          bar(data.homeColor),
          cell(ScoreboardState.displayName(data.homeName, ScoreboardStyle.classic)),
          cell('${data.homeScore}', bg: _cell, number: true),
          cell('${data.awayScore}', bg: _cell, number: true),
          cell(ScoreboardState.displayName(data.awayName, ScoreboardStyle.classic)),
          bar(data.awayColor),
          cell(data.clock, bg: _dark, number: true),
          if (data.period.isNotEmpty) cell(data.period, bg: _dark),
        ],
      ),
    );
  }

  Widget _plate() {
    final f = barHeight * 0.5;
    final pad = EdgeInsets.symmetric(horizontal: f * 0.7, vertical: f * 0.35);
    final name = TextStyle(
      color: Colors.white,
      fontSize: f,
      fontWeight: FontWeight.w600,
      letterSpacing: f * 0.1,
      height: 1.1,
    );
    final number = irMono(f, color: Colors.white, height: 1.1);
    TableRow row(String team, int color, int score, {required bool first}) {
      final border = first ? const Border(bottom: BorderSide(color: _plateLine)) : null;
      return TableRow(
        children: [
          Container(
            decoration: BoxDecoration(border: border),
            padding: pad,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(width: f * 0.22, height: f * 1.05, color: Color(color)),
                SizedBox(width: f * 0.45),
                Text(ScoreboardState.displayName(team, ScoreboardStyle.plate), style: name),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(color: _plateCell, border: border),
            padding: pad,
            alignment: Alignment.centerRight,
            child: Text('$score', style: number),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: _plateBg,
        border: Border.all(color: _plateLine),
        borderRadius: BorderRadius.circular(4),
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              children: [
                row(data.homeName, data.homeColor, data.homeScore, first: true),
                row(data.awayName, data.awayColor, data.awayScore, first: false),
              ],
            ),
            Container(
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: _plateLine)),
              ),
              padding: EdgeInsets.symmetric(horizontal: f * 0.75),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(data.clock, style: irMono(f, color: _amber, height: 1.1)),
                  if (data.period.isNotEmpty)
                    Text(
                      data.period,
                      style: TextStyle(color: _grey, fontSize: f * 0.55, fontWeight: FontWeight.w600),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Team colour swatches: squares, the chosen one ringed in amber. [foldable] (small screens): only
/// the chosen colour shows, with a "change" key; tapping it opens the others, and picking one
/// folds them again.
class _Palette extends StatefulWidget {
  const _Palette({
    required this.selected,
    required this.onSelected,
    required this.keyPrefix,
    required this.label,
    this.foldable = false,
  });

  final int selected;
  final ValueChanged<int> onSelected;
  final String keyPrefix;
  final String label;
  final bool foldable;

  @override
  State<_Palette> createState() => _PaletteState();
}

class _PaletteState extends State<_Palette> {
  bool _open = false;

  Widget _swatch(IrColors c, int color, {required bool selected, required VoidCallback onTap, Key? key}) => InkResponse(
    key: key,
    onTap: onTap,
    radius: 24,
    child: SizedBox.square(
      dimension: 48,
      child: Center(
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Color(color),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: selected ? c.signal : c.line, width: selected ? 3 : 1),
          ),
          child: selected ? Icon(Icons.check, color: onColor(Color(color)), size: 20) : null,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.ir;
    final folded = widget.foldable && !_open;
    if (folded) {
      return Semantics(
        label: l10n.scoreboardTeamColor(widget.label),
        child: Row(
          children: [
            _swatch(c, widget.selected, selected: true, onTap: () => setState(() => _open = true)),
            const SizedBox(width: 4),
            TextButton.icon(
              key: ValueKey('${widget.keyPrefix}-open'),
              onPressed: () => setState(() => _open = true),
              icon: const Icon(Icons.palette_outlined, size: 20),
              label: Text(l10n.sbChangeColour, style: const TextStyle(fontFamily: IrFonts.sans, fontSize: 15)),
            ),
          ],
        ),
      );
    }
    return Semantics(
      label: l10n.scoreboardTeamColor(widget.label),
      child: Wrap(
        spacing: 2,
        runSpacing: 2,
        children: [
          for (final (i, color) in teamPalette.indexed)
            _swatch(
              c,
              color,
              key: ValueKey('${widget.keyPrefix}-$i'),
              selected: color == widget.selected,
              onTap: () {
                widget.onSelected(color);
                if (widget.foldable) setState(() => _open = false);
              },
            ),
        ],
      ),
    );
  }
}

/// A title, a line under it and a switch; the whole row toggles.
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.ir;
    // Transparent Material: the ink shows over the panel's opaque colour.
    return MergeSemantics(
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: () => onChanged(!value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: c.text),
                        ),
                        const SizedBox(height: 2),
                        Text(subtitle, style: TextStyle(fontSize: 13, color: c.muted)),
                      ],
                    ),
                  ),
                  Switch(value: value, onChanged: onChanged),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
