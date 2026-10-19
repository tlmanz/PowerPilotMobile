// Building blocks from the design's components: cards, the Control Row,
// section lists, buttons, the toggle, the ring gauge and the bar chart.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../models/ups.dart';
import 'theme.dart';

final cardDecoration = BoxDecoration(
  color: AppColors.card,
  borderRadius: BorderRadius.circular(radius),
  border: Border.all(color: AppColors.border),
);

class AppCard extends StatelessWidget {
  const AppCard({super.key, this.padding = const EdgeInsets.all(16), required this.child});

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(padding: padding, decoration: cardDecoration, child: child);
}

/// A card's title row: icon, title, and something on the right.
class CardTitle extends StatelessWidget {
  const CardTitle(this.icon, this.title, {super.key, this.iconSize = 18, this.size = 15, this.trailing});

  final IconData icon;
  final String title;
  final double iconSize, size;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: iconSize, color: AppColors.ink2),
      const SizedBox(width: 8),
      Expanded(
        child: Text(title, style: text(size, weight: FontWeight.w600)),
      ),
      ?trailing,
    ],
  );
}

/// A tab's big title, with a line under it and an optional button.
class ScreenHeader extends StatelessWidget {
  const ScreenHeader(this.title, {super.key, this.subtitle, this.trailing});

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.end,
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: text(30, weight: FontWeight.w700, spacing: -0.6)),
            if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle!, style: text(13, color: AppColors.ink3))],
          ],
        ),
      ),
      ?trailing,
    ],
  );
}

/// The 40×40 outlined icon button (refresh, table view).
class SquareButton extends StatelessWidget {
  const SquareButton(this.icon, {super.key, required this.onTap, required this.label});

  final IconData icon;
  final VoidCallback? onTap;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: label,
    child: Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox.square(dimension: 40, child: Icon(icon, size: 18, color: AppColors.ink2)),
      ),
    ),
  );
}

/// A section heading over a card of rows divided by hairlines.
class Section extends StatelessWidget {
  const Section(this.heading, {super.key, required this.children, this.footnote});

  final String heading;
  final List<Widget> children;
  final String? footnote;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        heading.toUpperCase(),
        style: text(12, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.6),
      ),
      const SizedBox(height: 8),
      Container(
        clipBehavior: Clip.antiAlias,
        decoration: cardDecoration,
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.hairline),
              children[i],
            ],
          ],
        ),
      ),
      if (footnote != null) ...[const SizedBox(height: 8), Text(footnote!, style: text(12, color: AppColors.ink3, height: 1.4))],
    ],
  );
}

class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, required this.wash, required this.color, this.size = 36, this.iconSize = 18, this.round = false});

  IconBox.tone(this.icon, Tone tone, {super.key, this.size = 36, this.iconSize = 18, this.round = false})
    : wash = tone.wash,
      color = tone.icon;

  final IconData icon;
  final Color wash, color;
  final double size, iconSize;
  final bool round;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: wash, borderRadius: BorderRadius.circular(round ? size / 2 : 10)),
    child: Icon(icon, size: iconSize, color: color),
  );
}

/// The design's Control Row: icon box, title and subtitle, and a trailing
/// control or value.
class ControlRow extends StatelessWidget {
  const ControlRow({
    super.key,
    required this.icon,
    this.wash = AppColors.surface2,
    this.iconColor = AppColors.ink2,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.titleColor = AppColors.ink,
  });

  final IconData icon;
  final Color wash, iconColor, titleColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            IconBox(icon, wash: wash, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: text(15, weight: FontWeight.w600, color: titleColor),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: text(12, color: AppColors.ink3, height: 1.35)),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          ],
        ),
      ),
    ),
  );
}

/// A row's value with a chevron: "20% >".
class ValueChevron extends StatelessWidget {
  const ValueChevron(this.value, {super.key});

  final String? value;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (value != null)
        Text(
          value!,
          style: text(14, weight: FontWeight.w600, color: AppColors.ink2),
        ),
      const SizedBox(width: 4),
      const Icon(LucideIcons.chevronRight, size: 18, color: AppColors.ink3),
    ],
  );
}

/// The small filled button on a row: "Start test", "Shutdown", "Mute".
class SoftButton extends StatelessWidget {
  const SoftButton(this.label, {super.key, this.tone = Tone.info, required this.onPressed, this.busy = false});

  final String label;
  final Tone tone;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null && !busy;
    return Material(
      color: on ? tone.wash : AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: on ? onPressed : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: busy
              ? SizedBox(height: 17, width: 17, child: CircularProgressIndicator(strokeWidth: 2, color: tone.ink))
              : Text(
                  label,
                  style: text(13, weight: FontWeight.w600, color: on ? tone.ink : AppColors.ink3),
                ),
        ),
      ),
    );
  }
}

/// The design's 50×30 toggle.
class AppToggle extends StatelessWidget {
  const AppToggle({super.key, required this.value, required this.onChanged, required this.label});

  final bool value;
  final ValueChanged<bool>? onChanged;
  final String label;

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return Semantics(
      toggled: value,
      enabled: enabled,
      label: label,
      child: GestureDetector(
        onTap: enabled ? () => onChanged!(!value) : null,
        child: Opacity(
          opacity: enabled ? 1 : 0.5,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 50,
            height: 30,
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: value ? AppColors.primary : AppColors.border, borderRadius: BorderRadius.circular(15)),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                width: 26,
                height: 26,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x330F1B3D), offset: Offset(0, 1), blurRadius: 3)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A pill with an icon: "Online · AC mode".
class StatusChip extends StatelessWidget {
  const StatusChip(this.icon, this.label, this.tone, {super.key});

  final IconData icon;
  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: tone.wash, borderRadius: BorderRadius.circular(999)),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: tone.ink),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            style: text(12, weight: FontWeight.w600, color: tone.ink),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    ),
  );
}

/// A label and its value across a row: "Real power ≈ 0 W".
class KeyValue extends StatelessWidget {
  const KeyValue(this.label, this.value, {super.key, this.valueColor = AppColors.ink});

  final String label, value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label, style: text(12, color: AppColors.ink3)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: text(12, weight: FontWeight.w600, color: valueColor),
        ),
      ),
    ],
  );
}

/// The ring gauge on the Load and Battery cards: an arc from the top,
/// clockwise, over a hairline track.
class Ring extends StatelessWidget {
  const Ring({super.key, required this.value, required this.color, this.size = 96, required this.child});

  /// 0 to 1; null draws only the track.
  final double? value;
  final Color color;
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: (value ?? 0).clamp(0, 1).toDouble()),
    duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 450),
    curve: Curves.easeOutCubic,
    builder: (context, v, child) => CustomPaint(
      painter: _RingPainter(v, color, size * 0.08),
      child: SizedBox.square(
        dimension: size,
        child: Center(child: child),
      ),
    ),
    child: child,
  );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.value, this.color, this.thickness);

  final double value, thickness;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(thickness / 2);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness;
    canvas.drawArc(rect, 0, 2 * math.pi, false, paint..color = AppColors.hairline);
    if (value > 0) canvas.drawArc(rect, -math.pi / 2, 2 * math.pi * value, false, paint..color = color);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.value != value || old.color != color;
}

class Bar {
  const Bar(this.fraction, this.color, {this.failed = false});

  /// 0 to 1 of the chart's height.
  final double fraction;
  final Color color;

  /// Drawn as a thin red line: no input, a failed mains.
  final bool failed;
}

/// The Trends bar chart: equal bars on a hairline baseline. With [onSelect], a
/// tap picks the bar under it (or nothing, tapping it again), and the picked
/// bar is drawn in ink.
class BarChart extends StatelessWidget {
  const BarChart(this.bars, {super.key, this.height = 72, this.empty = 'Waiting for data…', this.selected, this.onSelect});

  final List<Bar?> bars;
  final double height;
  final String empty;
  final int? selected;
  final ValueChanged<int?>? onSelect;

  @override
  Widget build(BuildContext context) {
    final chart = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < bars.length; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: bars[i] == null
                ? const SizedBox()
                : Container(
                    height: bars[i]!.failed ? 2 : math.max(3, bars[i]!.fraction.clamp(0, 1) * (height - 1)),
                    decoration: BoxDecoration(
                      color: i == selected
                          ? AppColors.ink
                          : bars[i]!.failed
                          ? AppColors.critical
                          : bars[i]!.color,
                      borderRadius: bars[i]!.failed ? null : const BorderRadius.vertical(top: Radius.circular(2)),
                    ),
                  ),
          ),
        ],
      ],
    );
    return Container(
      height: height,
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.hairline)),
      ),
      child: bars.every((b) => b == null)
          ? Center(
              child: Text(empty, style: text(12, color: AppColors.ink3)),
            )
          : onSelect == null
          ? chart
          : LayoutBuilder(
              builder: (context, c) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  final i = (d.localPosition.dx / c.maxWidth * bars.length).floor().clamp(0, bars.length - 1);
                  onSelect!(bars[i] == null || i == selected ? null : i);
                },
                child: chart,
              ),
            ),
    );
  }
}

// Events: an icon per kind, as PowerPilot's js/ui/events.js picks them, and a
// tone from the level. Self-tests are blue unless they failed; alarm changes
// are neutral.

IconData eventIcon(String kind) => switch (kind) {
  'utility_restored' => LucideIcons.plugZap,
  'utility_lost' => LucideIcons.unplug,
  'on_battery' => LucideIcons.batteryMedium,
  'battery_charging' => LucideIcons.batteryCharging,
  'low_battery' => LucideIcons.batteryLow,
  'overload' => LucideIcons.gauge,
  'self_test' => LucideIcons.activity,
  'fault' => LucideIcons.triangleAlert,
  'alarm' || 'alarm_unmuted' => LucideIcons.bell,
  'alarm_muted' => LucideIcons.bellOff,
  'connection' => LucideIcons.link,
  'shutdown' => LucideIcons.power,
  _ => LucideIcons.info,
};

({Color wash, Color icon}) eventColors(UpsEvent e) {
  if (e.kind.startsWith('alarm') && e.level == 'info') return (wash: AppColors.surface2, icon: AppColors.ink2);
  final tone = switch (e.level) {
    'good' when e.kind == 'self_test' => Tone.info,
    'good' => Tone.good,
    'warn' => Tone.warn,
    'alert' => Tone.bad,
    _ => Tone.info,
  };
  return (wash: tone.wash, icon: tone.icon);
}

// Dialogs and messages.

void toast(BuildContext context, String message, {bool bad = false}) {
  final m = ScaffoldMessenger.of(context);
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: bad ? AppColors.badInk : AppColors.ink,
      duration: Duration(milliseconds: bad ? 6000 : 3500),
    ),
  );
}

/// Dangerous actions always end here, as on the desktop.
Future<bool> confirm(BuildContext context, {required String title, required String body, required String ok, bool danger = false}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(
            'Cancel',
            style: text(15, weight: FontWeight.w600, color: AppColors.ink2),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: danger ? AppColors.critical : AppColors.primary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(
            ok,
            style: text(15, weight: FontWeight.w600, color: Colors.white),
          ),
        ),
      ],
    ),
  );
  return yes ?? false;
}

/// A bottom sheet of choices; returns the one picked.
Future<T?> pickOption<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<(T, String)> options,
  T? selected,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text(18, weight: FontWeight.w700)),
                if (subtitle != null) ...[const SizedBox(height: 4), Text(subtitle, style: text(13, color: AppColors.ink3, height: 1.4))],
              ],
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 12),
              children: [
                for (final (value, label) in options)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    title: Text(label, style: text(15, weight: value == selected ? FontWeight.w600 : FontWeight.w400)),
                    trailing: value == selected ? const Icon(LucideIcons.check, color: AppColors.primary, size: 20) : null,
                    onTap: () => Navigator.pop(context, value),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  ),
);
