import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:lumina/domain/models/light.dart';
import 'package:lumina/domain/models/preset.dart';
import 'package:lumina/ui/core/theme.dart';

/// A labeled slider with a gradient track.
class GradientSlider extends StatelessWidget {
  final String label;
  final String valueText;
  final double value, min, max;
  final int? divisions;
  final Gradient gradient;
  final ValueChanged<double> onChanged;
  const GradientSlider({
    super.key,
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.gradient,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                valueText,
                style: TextStyle(
                  color: p.muted,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 6,
            trackShape: _GradientTrack(gradient, p.line),
            thumbColor: p.surface,
            thumbShape: _Thumb(p.text),
            overlayColor: p.text.withValues(alpha: 0.08),
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            label: valueText,
            semanticFormatterCallback: (_) => valueText,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _GradientTrack extends SliderTrackShape with BaseSliderTrackShape {
  final Gradient gradient;
  final Color border;
  const _GradientTrack(this.gradient, this.border);

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(parentBox: parentBox, offset: offset, sliderTheme: sliderTheme);
    final r = RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2));
    context.canvas
      ..drawRRect(r, Paint()..shader = gradient.createShader(rect))
      ..drawRRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = border,
      );
  }
}

class _Thumb extends SliderComponentShape {
  final Color ring;
  const _Thumb(this.ring);
  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(22, 22);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final c = context.canvas;
    c.drawCircle(
      center + const Offset(0, 1),
      11,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    c.drawCircle(center, 11, Paint()..color = sliderTheme.thumbColor!);
    c.drawCircle(
      center,
      10,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = ring,
    );
  }
}

const warmGradient = LinearGradient(
  colors: [Color(0xFFFFB46B), Color(0xFFFFE4CE), Color(0xFFF3F2FF)],
);

LinearGradient brightGradient(BuildContext context, Color glow) =>
    LinearGradient(colors: [Palette.of(context).off, glow]);

String kelvinLabel(int k) => '$k K';

/// Brightness and warmth sliders.
class LightSliders extends StatelessWidget {
  final int level, kelvin;
  final bool showWarmth;
  final ValueChanged<int> onLevel;
  final ValueChanged<int>? onKelvin;

  /// The brightness track's color when the light shows a color.
  final Color? color;
  const LightSliders({
    super.key,
    required this.level,
    required this.kelvin,
    required this.onLevel,
    this.onKelvin,
    this.showWarmth = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GradientSlider(
          label: 'Brightness',
          valueText: '$level%',
          value: level.toDouble(),
          min: 1,
          max: 100,
          gradient: brightGradient(context, color ?? kelvinColor(kelvin)),
          onChanged: (v) => onLevel(v.round()),
        ),
        if (showWarmth && onKelvin != null)
          GradientSlider(
            label: 'Warm to cool',
            valueText: kelvinLabel(kelvin),
            value: kelvin.toDouble(),
            min: minKelvin.toDouble(),
            max: maxKelvin.toDouble(),
            divisions: (maxKelvin - minKelvin) ~/ 100,
            gradient: warmGradient,
            onChanged: (v) => onKelvin!((v / 100).round() * 100),
          ),
      ],
    );
  }
}

/// Asks before doing [action]. Returns true if the user confirmed.
Future<bool> confirm(
  BuildContext context,
  String title,
  String body, {
  required String action,
  bool danger = false,
}) async {
  final p = Palette.of(context);
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title, style: display(20)),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action, style: TextStyle(color: danger ? p.danger : null)),
        ),
      ],
    ),
  );
  return r == true;
}

/// A section title, with an optional action on the right.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 24, 0, 8),
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Palette.of(context).muted,
                  ),
                ),
              ),
            ),
            ?trailing,
          ],
        ),
      ),
    );
  }
}

/// A light, or all lights, as a tile: tap to switch it, drag sideways to
/// dim it, and the tune button (or a long press) for everything else.
///
/// The tinted part of the tile shows how bright the light is.
class LightTile extends StatefulWidget {
  final String name;
  final String status;
  final bool on;

  /// 1–100 %.
  final int level;
  final Color color;
  final IconData icon;

  /// The light needs the user: [status] shows in red, and [action] says what
  /// a tap does.
  final bool attention;
  final String? action;
  final VoidCallback? onTap;
  final ValueChanged<int>? onLevel;
  final VoidCallback? onOpen;
  const LightTile({
    super.key,
    required this.name,
    required this.status,
    required this.on,
    required this.level,
    required this.color,
    this.icon = Icons.lightbulb_outline_rounded,
    this.attention = false,
    this.action,
    this.onTap,
    this.onLevel,
    this.onOpen,
  });

  @override
  State<LightTile> createState() => _LightTileState();
}

class _LightTileState extends State<LightTile> {
  /// The level under the finger while dragging.
  double? _drag;

  void _dragStart(DragStartDetails _) {
    setState(() => _drag = widget.on ? widget.level.toDouble() : 1);
  }

  void _dragUpdate(DragUpdateDetails d) {
    final from = _drag;
    if (from == null) return;
    final width = context.size?.width ?? 1;
    final next = (from + d.delta.dx / width * 100).clamp(1.0, 100.0);
    setState(() => _drag = next);
    if (next.round() != from.round()) widget.onLevel?.call(next.round());
  }

  void _dragEnd([DragEndDetails? _]) => setState(() => _drag = null);

  void _step(int by) => widget.onLevel?.call((widget.level + by).clamp(1, 100));

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final w = widget;
    final drag = _drag;
    final lit = !w.attention && (w.on || drag != null);
    final level = (drag ?? w.level.toDouble()) / 100;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final canDim = w.onLevel != null;
    return Semantics(
      container: true,
      label: w.name,
      value: w.status,
      toggled: w.attention ? null : w.on,
      increasedValue: canDim ? '${(w.level + 10).clamp(1, 100)}%' : null,
      decreasedValue: canDim ? '${(w.level - 10).clamp(1, 100)}%' : null,
      onIncrease: canDim ? () => _step(10) : null,
      onDecrease: canDim ? () => _step(-10) : null,
      child: GestureDetector(
        onHorizontalDragStart: canDim ? _dragStart : null,
        onHorizontalDragUpdate: canDim ? _dragUpdate : null,
        onHorizontalDragEnd: canDim ? _dragEnd : null,
        onHorizontalDragCancel: canDim ? _dragEnd : null,
        child: Material(
          // A light that's on takes a soft tint of its own white.
          color: lit
              ? Color.alphaBlend(w.color.withValues(alpha: dark ? 0.1 : 0.18), p.surface)
              : p.surface,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMedium),
            side: BorderSide(color: p.line),
          ),
          child: InkWell(
            onTap: w.onTap == null
                ? null
                : () {
                    unawaited(HapticFeedback.selectionClick());
                    w.onTap?.call();
                  },
            onLongPress: w.onOpen,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Brightness, as a thin bar along the bottom.
                if (lit)
                  PositionedDirectional(
                    start: 14,
                    end: 14,
                    bottom: 10,
                    height: 3,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: ColoredBox(
                        color: p.line,
                        child: Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: AnimatedFractionallySizedBox(
                            duration: drag != null
                                ? Duration.zero
                                : const Duration(milliseconds: 250),
                            curve: Curves.easeOut,
                            widthFactor: level,
                            heightFactor: 1,
                            child: ColoredBox(color: p.text),
                          ),
                        ),
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 250),
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: w.attention
                                  ? p.danger.withValues(alpha: 0.14)
                                  : lit
                                  ? w.color
                                  : p.off,
                            ),
                            child: Icon(
                              w.attention ? Icons.priority_high_rounded : w.icon,
                              size: 20,
                              color: w.attention
                                  ? p.danger
                                  : lit
                                  ? const Color(0xFF181715)
                                  : p.muted,
                            ),
                          ),
                          const Spacer(),
                          if (w.onOpen case final open?)
                            IconButton(
                              tooltip: 'More for ${w.name}',
                              visualDensity: VisualDensity.compact,
                              onPressed: open,
                              icon: Icon(Icons.tune_rounded, size: 20, color: p.muted),
                            ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        w.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        drag != null ? '${drag.round()}%' : w.status,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: w.attention ? p.danger : p.muted,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (w.action case final a?)
                        Text(
                          a,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A scene in the scene row: a swatch over a name. With [onDelete] it shows
/// a remove button instead of recalling.
class SceneCard extends StatelessWidget {
  final String label;
  final Widget swatch;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  const SceneCard({
    super.key,
    required this.label,
    required this.swatch,
    required this.onTap,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final delete = onDelete;
    return SizedBox(
      width: 112,
      child: Material(
        color: p.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMedium),
          side: BorderSide(color: p.line),
        ),
        child: InkWell(
          onTap: delete ?? onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    swatch,
                    const Spacer(),
                    if (delete != null)
                      Icon(Icons.remove_circle_rounded, size: 20, color: p.danger),
                  ],
                ),
                const Spacer(),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A preset's swatch: its color, as bright as its level.
class PresetSwatch extends StatelessWidget {
  final Preset preset;
  const PresetSwatch(this.preset, {super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: kelvinColor(preset.kelvin).withValues(alpha: 0.3 + preset.level / 100 * 0.7),
        border: Border.all(color: Palette.of(context).line),
      ),
    );
  }
}

/// The whites the bulbs can make, from warm to daylight.
const whiteTones = [
  (name: 'Warm', kelvin: 2700),
  (name: 'Soft', kelvin: 3000),
  (name: 'Neutral', kelvin: 4000),
  (name: 'Cool', kelvin: 5000),
  (name: 'Daylight', kelvin: 6500),
];

/// A row of white tones to pick from; the one nearest [kelvin] is marked.
class WhiteToneSwatches extends StatelessWidget {
  final int kelvin;
  final ValueChanged<int> onPick;
  const WhiteToneSwatches({super.key, required this.kelvin, required this.onPick});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final nearest = whiteTones.reduce(
      (a, b) => (a.kelvin - kelvin).abs() <= (b.kelvin - kelvin).abs() ? a : b,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final t in whiteTones)
          Semantics(
            button: true,
            selected: t == nearest,
            label: '${t.name}, ${t.kelvin} K',
            excludeSemantics: true,
            child: InkWell(
              onTap: () => onPick(t.kelvin),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: kelvinColor(t.kelvin),
                        border: Border.all(
                          color: t == nearest ? p.text : p.line,
                          width: t == nearest ? 2.5 : 1,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      t.name,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: t == nearest ? p.text : p.muted,
                        fontWeight: t == nearest ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Colors to pick from, by hue in degrees.
const colorTones = [
  (name: 'Red', hue: 0),
  (name: 'Orange', hue: 30),
  (name: 'Yellow', hue: 55),
  (name: 'Green', hue: 120),
  (name: 'Cyan', hue: 185),
  (name: 'Blue', hue: 225),
  (name: 'Purple', hue: 275),
  (name: 'Pink', hue: 320),
];

/// Hue and saturation sliders, with a row of colors to pick from.
class ColorControls extends StatelessWidget {
  final int hue, saturation;
  final ValueChanged<int> onHue, onSaturation;
  const ColorControls({
    super.key,
    required this.hue,
    required this.saturation,
    required this.onHue,
    required this.onSaturation,
  });

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final full = lookColor(kelvin: 0, hue: hue);
    final nearest = colorTones.reduce((a, b) => _gap(a.hue) <= _gap(b.hue) ? a : b);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GradientSlider(
          label: 'Color',
          valueText: '$hue°',
          value: hue.toDouble(),
          min: 0,
          max: 359,
          gradient: LinearGradient(
            colors: [for (var h = 0; h <= 360; h += 60) lookColor(kelvin: 0, hue: h)],
          ),
          onChanged: (v) => onHue(v.round()),
        ),
        GradientSlider(
          label: 'Saturation',
          valueText: '$saturation%',
          value: saturation.toDouble(),
          min: 0,
          max: 100,
          gradient: LinearGradient(colors: [Colors.white, full]),
          onChanged: (v) => onSaturation(v.round()),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final t in colorTones)
              Semantics(
                button: true,
                selected: t == nearest && saturation >= 50,
                label: t.name,
                excludeSemantics: true,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () {
                    onHue(t.hue);
                    if (saturation < 50) onSaturation(100);
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: lookColor(kelvin: 0, hue: t.hue),
                      border: Border.all(
                        color: t == nearest && saturation >= 50 ? p.text : p.line,
                        width: t == nearest && saturation >= 50 ? 2.5 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  int _gap(int h) {
    final d = (h - hue).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}
