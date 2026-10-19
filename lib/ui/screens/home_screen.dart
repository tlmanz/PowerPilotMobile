// Home: the design's "01 Dashboard" and, during an outage, "02 On Battery".
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/cloud_source.dart' show describeError;
import '../../models/ups.dart';
import '../../models/ups_view.dart';
import '../../state/controllers.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// The battery's color everywhere: red when low, amber on battery or under
/// half, green otherwise.
Color batteryColor(UpsView v) {
  if (v.batteryState == 'low') return AppColors.critical;
  if (v.mode == UpsMode.battery || (v.batteryPercent ?? 100) < 50) return AppColors.warning;
  return AppColors.good;
}

Color loadColor(double? load) => (load ?? 0) >= 100
    ? AppColors.critical
    : (load ?? 0) >= 80
    ? AppColors.warning
    : AppColors.series;

/// The name the header shows after "Connected": the device ID as a word.
String deviceLabel(UpsController ups) {
  if (ups.source.isDemo) return 'Demo data';
  final id = ups.source.label.replaceAll('-', ' ');
  return id.isEmpty ? id : id[0].toUpperCase() + id.substring(1);
}

String healthText(BatteryHealth h) => switch (h) {
  BatteryHealth.good => 'Good',
  BatteryHealth.replace => 'Replace soon',
  BatteryHealth.testing => 'Testing…',
  BatteryHealth.unknown => 'Not tested',
};

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ups = UpsScope.of(context);
    final v = ups.view;
    final banner = _Banner.of(ups);
    return TabPage(
      onRefresh: () async {
        try {
          await ups.refresh();
        } catch (e) {
          if (context.mounted) toast(context, describeError(e), bad: true);
        }
      },
      children: [
        _Header(ups),
        ?banner,
        _Hero(v),
        _PowerFlow(v),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: _LoadCard(v)),
              const SizedBox(width: 12),
              Expanded(child: _BatteryCard(v)),
            ],
          ),
        ),
        _RecentEvents(ups.events),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.ups);

  final UpsController ups;

  @override
  Widget build(BuildContext context) {
    final v = ups.view;
    final (Color dot, Color ink, String line) = switch (ups) {
      UpsController(loaded: false, linkUp: false, linkError: '') => (AppColors.ink3, AppColors.ink3, 'Connecting…'),
      UpsController(linkUp: false) => (AppColors.critical, AppColors.badInk, "Can't reach the server"),
      UpsController(online: false) => (
        AppColors.warning,
        AppColors.warnInk,
        'Device offline${ups.lastSeen == null ? '' : ' · seen ${shortTime(ups.lastSeen!)}'}',
      ),
      _ when !v.connected => (AppColors.critical, AppColors.badInk, 'UPS not connected'),
      _ => (AppColors.good, AppColors.goodInk, 'Connected · ${deviceLabel(ups)}'),
    };
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Image.asset('images/logo.png', width: 40, height: 40, fit: BoxFit.contain),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                ups.loaded ? v.device.name : 'PowerPilot',
                style: text(17, weight: FontWeight.w700, spacing: -0.2),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      line,
                      style: text(12, weight: FontWeight.w500, color: ink),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        _RefreshButton(ups),
      ],
    );
  }
}

class _RefreshButton extends StatefulWidget {
  const _RefreshButton(this.ups);

  final UpsController ups;

  @override
  State<_RefreshButton> createState() => _RefreshButtonState();
}

class _RefreshButtonState extends State<_RefreshButton> with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    _spin.forward(from: 0);
    try {
      await widget.ups.refresh();
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    }
  }

  @override
  Widget build(BuildContext context) => RotationTransition(
    turns: CurvedAnimation(parent: _spin, curve: Curves.easeInOut),
    child: SquareButton(LucideIcons.refreshCw, onTap: _refresh, label: 'Refresh'),
  );
}

/// The banner over the hero: alarms, and anything stopping the readings.
class _Banner extends StatefulWidget {
  const _Banner({required this.tone, required this.icon, required this.title, required this.detail, this.ups, this.muted});

  final Tone tone;
  final IconData icon;
  final String title, detail;

  /// With a mute button, for an alarm the beeper is (or was) sounding.
  final UpsController? ups;
  final bool? muted;

  static Widget? of(UpsController ups) {
    final v = ups.view;
    if (!ups.loaded && ups.linkError.isEmpty) return null;
    if (!ups.linkUp) {
      return _Banner(tone: Tone.bad, icon: LucideIcons.cloudOff, title: "Can't reach the server", detail: '${ups.linkError}. Retrying…');
    }
    if (!ups.online) {
      return _Banner(
        tone: Tone.warn,
        icon: LucideIcons.wifiOff,
        title: 'The UPS device is offline',
        detail: 'Showing its last reading${ups.lastSeen == null ? '' : ', from ${dateTime(ups.lastSeen!)}'}.',
      );
    }
    if (!v.connected) {
      return _Banner(
        tone: Tone.bad,
        icon: LucideIcons.unplug,
        title: 'UPS not connected',
        detail: v.error.isNotEmpty ? v.error : "The device can't reach the UPS. Check its USB cable.",
      );
    }
    if (!v.alarm.active) return null;
    final beeper = v.alarm.muted
        ? 'Alarm muted'
        : v.alarm.enabled
        ? 'Alarm sounding'
        : 'Alarm off';
    final detail = v.mode == UpsMode.battery && v.onBatterySec != null
        ? 'Power lost at ${clock(DateTime.now().subtract(Duration(seconds: v.onBatterySec!.round())))} · $beeper'
        : '${v.batteryPercent == null ? '' : 'Battery ${pct(v.batteryPercent!)} · '}$beeper';
    return _Banner(
      tone: v.alarm.level == AlarmLevel.critical ? Tone.bad : Tone.warn,
      icon: LucideIcons.bellRing,
      title: v.alarm.message,
      detail: detail,
      ups: v.alarm.enabled ? ups : null,
      muted: v.alarm.muted,
    );
  }

  @override
  State<_Banner> createState() => _BannerState();
}

class _BannerState extends State<_Banner> {
  bool _busy = false;

  Future<void> _toggleMute() async {
    final muted = widget.muted ?? false;
    setState(() => _busy = true);
    try {
      await widget.ups!.command(muted ? 'alarm.unmute' : 'alarm.mute');
      if (mounted) toast(context, muted ? 'Alarm unmuted' : 'Alarm muted until the condition clears');
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bad = widget.tone == Tone.bad;
    final (fill, stroke, circle, ink) = bad
        ? (const Color(0xFFFBEAEA), const Color(0xFFF2BDBD), AppColors.critical, AppColors.badInk)
        : (const Color(0xFFFDF1D8), const Color(0xFFF5D28A), AppColors.warning, AppColors.warnInk);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: stroke),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: circle, shape: BoxShape.circle),
            child: Icon(widget.icon, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: text(14, weight: FontWeight.w700, color: ink),
                ),
                const SizedBox(height: 2),
                Text(widget.detail, style: text(12, color: ink)),
              ],
            ),
          ),
          if (widget.ups != null) ...[
            const SizedBox(width: 12),
            Material(
              color: ink,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: _busy ? null : _toggleMute,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(widget.muted! ? LucideIcons.bell : LucideIcons.bellOff, size: 14, color: Colors.white),
                      const SizedBox(width: 6),
                      Text(
                        widget.muted! ? 'Unmute' : 'Mute',
                        style: text(13, weight: FontWeight.w600, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The hero: the charge, and the UPS with its display showing the readings.
class _Hero extends StatelessWidget {
  const _Hero(this.v);

  final UpsView v;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, String chip, Tone tone) = switch (v.mode) {
      UpsMode.ac => (LucideIcons.zap, v.avr ? 'Online · Regulating' : 'Online · AC mode', Tone.good),
      UpsMode.battery => (LucideIcons.battery, 'On battery', Tone.warn),
      UpsMode.bypass => (LucideIcons.arrowLeftRight, 'Bypass', Tone.warn),
      UpsMode.fault => (LucideIcons.triangleAlert, 'Fault', Tone.bad),
      UpsMode.standby => (LucideIcons.power, 'Outlets off', Tone.neutral),
      UpsMode.test => (LucideIcons.activity, 'Self-test', Tone.info),
      UpsMode.offline => (LucideIcons.unplug, 'Disconnected', Tone.neutral),
    };
    final state = switch (v.batteryState) {
      'charging' => 'Charging',
      'discharging' => 'Discharging',
      'full' => 'Fully charged',
      'low' => 'Low',
      _ => '',
    };
    final caption = !v.connected
        ? 'No data from the UPS'
        : v.mode == UpsMode.battery
        ? 'Remaining · $state'
        : ['Battery remaining', if (state.isNotEmpty) state].join(' · ');
    final percent = v.connected ? v.batteryPercent : null;

    return Container(
      height: 220,
      decoration: cardDecoration,
      child: LayoutBuilder(
        builder: (context, c) {
          // Never negative: Android's first frame can be zero wide, and a
          // negative width there breaks the whole tree for good.
          final textWidth = math.max(0.0, math.min(200.0, c.maxWidth - 172));
          return Stack(
            children: [
              Positioned(right: 2, top: 14, width: 150, height: 204, child: _UpsPicture(v)),
              Positioned(
                left: 20,
                top: 20,
                width: textWidth,
                height: 180,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusChip(icon, chip, tone),
                        const SizedBox(height: 6),
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  percent == null ? '—' : number(percent, 1),
                                  style: text(52, weight: FontWeight.w700, spacing: -1.5, height: 1),
                                ),
                                const SizedBox(width: 2),
                                if (percent != null)
                                  Text(
                                    '%',
                                    style: text(24, weight: FontWeight.w600, color: AppColors.ink2),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          caption,
                          style: text(13, color: AppColors.ink3),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                    SizedBox(
                      width: math.min(170, textWidth),
                      child: Column(
                        children: [
                          _Progress(value: (percent ?? 0) / 100, color: batteryColor(v)),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Runtime (est.)',
                                  style: text(12, color: AppColors.ink3),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(v.connected ? duration(v.runtimeMinutes) : '—', style: text(12, weight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.value, required this.color});

  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    height: 8,
    decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(4)),
    alignment: Alignment.centerLeft,
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: value.clamp(0, 1).toDouble()),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutCubic,
      builder: (context, f, _) => FractionallySizedBox(
        widthFactor: f,
        child: Container(
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(4)),
        ),
      ),
    ),
  );
}

/// The UPS picture with its display drawn over the glass, as the dashboard
/// does (the image never contains readings).
class _UpsPicture extends StatelessWidget {
  const _UpsPicture(this.v);

  final UpsView v;

  @override
  Widget build(BuildContext context) {
    final on = v.connected;
    final (String mode, Color modeColor) = switch (on ? v.mode : UpsMode.offline) {
      UpsMode.ac => ('AC MODE', const Color(0xFF5FD3FF)),
      UpsMode.battery => ('BATTERY', AppColors.warning),
      UpsMode.bypass => ('BYPASS', AppColors.warning),
      UpsMode.fault => ('FAULT', const Color(0xFFFF6B6B)),
      UpsMode.standby => ('OUTLETS OFF', const Color(0xFF9AA6BC)),
      UpsMode.test => ('SELF-TEST', const Color(0xFF5FD3FF)),
      UpsMode.offline => ('NO SIGNAL', const Color(0xFF9AA6BC)),
    };
    String volts(double? x) => on && x != null ? '${number(x)}V' : '---';
    String percent(double? x) => on && x != null ? '${number(x, 1)}%' : '--';
    Widget field(String k, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          k,
          style: text(4.5, weight: FontWeight.w600, color: const Color(0xFF7FB8FF), spacing: 0.4, height: 1.2),
        ),
        const SizedBox(height: 1),
        Text(
          value,
          style: text(10, weight: FontWeight.w700, color: const Color(0xFFE8F2FF), height: 1.2),
        ),
      ],
    );
    return Semantics(
      label: 'UPS display: $mode',
      child: Stack(
        children: [
          Positioned.fill(child: Image.asset('images/ups-front.png', fit: BoxFit.contain)),
          Positioned(
            left: 50,
            top: 26,
            width: 50,
            height: 148,
            // Painted on the picture: it keeps its size whatever the text size.
            child: ExcludeSemantics(
              child: MediaQuery.withNoTextScaling(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        field('INPUT', volts(v.inputVoltage)),
                        const SizedBox(height: 9),
                        field('OUTPUT', volts(v.outputVoltage)),
                        const SizedBox(height: 9),
                        field('BATTERY', percent(v.batteryPercent)),
                        const SizedBox(height: 9),
                        field('LOAD', percent(v.loadPercent)),
                        const SizedBox(height: 9),
                        Text(
                          mode,
                          style: text(5, weight: FontWeight.w700, color: modeColor, spacing: 0.5),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PowerFlow extends StatelessWidget {
  const _PowerFlow(this.v);

  final UpsView v;

  @override
  Widget build(BuildContext context) {
    final on = v.connected;
    final m = on ? v.mode : UpsMode.offline;
    final mainsLost = m == UpsMode.battery;
    final mains = on && !mainsLost && (v.inputVoltage ?? 0) > 0;
    final outOff = !on || m == UpsMode.standby || m == UpsMode.fault;

    final input = _Node(
      badge: IconBox(
        mainsLost ? LucideIcons.unplug : LucideIcons.plugZap,
        wash: !on
            ? AppColors.surface2
            : mainsLost
            ? AppColors.badWash
            : AppColors.goodWash,
        color: !on
            ? AppColors.ink3
            : mainsLost
            ? AppColors.critical
            : AppColors.good,
        size: 48,
        iconSize: 22,
        round: true,
      ),
      label: 'Input',
      value: on && v.inputVoltage != null ? '${number(v.inputVoltage!)} V' : '—',
      state: !on
          ? '—'
          : mainsLost
          ? 'Failed'
          : v.avr
          ? 'Regulating'
          : v.inputFrequency != null
          ? '${number(v.inputFrequency!, 1)} Hz'
          : 'Normal',
      stateColor: !on
          ? AppColors.ink3
          : mainsLost
          ? AppColors.badInk
          : v.avr
          ? AppColors.primary
          : AppColors.goodInk,
    );

    final (String upsValue, String upsState, Color upsColor) = switch (m) {
      UpsMode.ac => ('Online', 'AC mode', AppColors.goodInk),
      UpsMode.battery => ('On battery', '${duration(v.runtimeMinutes)} left', AppColors.warnInk),
      UpsMode.bypass => ('Bypass', 'Mains straight through', AppColors.warnInk),
      UpsMode.fault => ('Fault', 'Check the UPS', AppColors.badInk),
      UpsMode.standby => ('Standby', 'Outlets off', AppColors.ink3),
      UpsMode.test => ('Self-test', 'On battery briefly', AppColors.primary),
      UpsMode.offline => ('Offline', '—', AppColors.ink3),
    };
    final ups = _Node(
      badge: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: mainsLost ? AppColors.warnWash : AppColors.surface2,
          shape: BoxShape.circle,
          border: mainsLost ? Border.all(color: AppColors.warning, width: 2) : null,
        ),
        child: Image.asset('images/ups-flow.png', width: 30, height: 34, fit: BoxFit.contain),
      ),
      label: 'UPS',
      value: upsValue,
      state: upsState,
      stateColor: upsColor,
    );

    final output = _Node(
      badge: IconBox(
        LucideIcons.monitor,
        wash: outOff ? AppColors.surface2 : AppColors.primaryWash,
        color: outOff ? AppColors.ink3 : AppColors.primary,
        size: 48,
        iconSize: 22,
        round: true,
      ),
      label: 'Output',
      value: on && v.outputVoltage != null ? '${number(v.outputVoltage!)} V' : '—',
      state: !on
          ? '—'
          : outOff
          ? 'Off'
          : 'Normal',
      stateColor: outOff ? AppColors.ink3 : AppColors.goodInk,
    );

    _Mode mode(String label, IconData icon, Tone tone, bool active, String value) =>
        _Mode(label: label, icon: icon, tone: tone, active: on && active, value: on ? value : '—');

    return AppCard(
      child: Column(
        children: [
          const CardTitle(LucideIcons.workflow, 'Power Flow'),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              input,
              Expanded(
                child: _Wire(color: mains ? AppColors.good : AppColors.border, flowing: mains),
              ),
              ups,
              Expanded(
                child: _Wire(
                  color: outOff
                      ? AppColors.border
                      : mainsLost
                      ? AppColors.warning
                      : AppColors.series,
                  flowing: !outOff,
                ),
              ),
              output,
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: mode(
                    'AC mode',
                    LucideIcons.zap,
                    Tone.good,
                    m == UpsMode.ac || m == UpsMode.standby,
                    m == UpsMode.ac
                        ? 'Normal'
                        : m == UpsMode.standby
                        ? 'Outlets off'
                        : 'Not active',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: mode(
                    'Bypass',
                    LucideIcons.arrowLeftRight,
                    Tone.warn,
                    m == UpsMode.bypass,
                    m == UpsMode.bypass ? 'Active' : 'Not active',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: mode(
                    'Battery',
                    LucideIcons.battery,
                    Tone.warn,
                    m == UpsMode.battery || m == UpsMode.test,
                    m == UpsMode.battery
                        ? 'Active'
                        : m == UpsMode.test
                        ? 'Self-test'
                        : 'Not active',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Node extends StatelessWidget {
  const _Node({required this.badge, required this.label, required this.value, required this.state, required this.stateColor});

  final Widget badge;
  final String label, value, state;
  final Color stateColor;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      badge,
      const SizedBox(height: 4),
      Text(label, style: text(11, color: AppColors.ink3)),
      const SizedBox(height: 4),
      Text(value, style: text(17, weight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(
        state,
        style: text(11, weight: FontWeight.w600, color: stateColor),
      ),
    ],
  );
}

/// The line between two nodes, with a dot running along it while power flows.
class _Wire extends StatefulWidget {
  const _Wire({required this.color, required this.flowing});

  final Color color;
  final bool flowing;

  @override
  State<_Wire> createState() => _WireState();
}

class _WireState extends State<_Wire> with SingleTickerProviderStateMixin {
  late final _run = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Wire old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final animate = widget.flowing && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_run.isAnimating) {
      _run.repeat();
    } else if (!animate) {
      _run.stop();
      _run.value = 0.35;
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 48,
    child: AnimatedBuilder(
      animation: _run,
      builder: (context, _) => LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            Positioned(left: 0, right: 0, top: 23, height: 2, child: ColoredBox(color: widget.color)),
            Positioned(
              left: math.max(0.0, c.maxWidth - 8) * _run.value,
              top: 20,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Mode extends StatelessWidget {
  const _Mode({required this.label, required this.icon, required this.tone, required this.active, required this.value});

  final String label, value;
  final IconData icon;
  final Tone tone;
  final bool active;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      IconBox(
        icon,
        wash: active ? tone.wash : AppColors.surface2,
        color: active ? (tone == Tone.good ? AppColors.good : tone.icon) : AppColors.ink3,
        size: 28,
        iconSize: 14,
        round: true,
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: text(11, color: AppColors.ink3),
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              value,
              style: text(12, weight: FontWeight.w600, color: active ? AppColors.ink : AppColors.ink3),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    ],
  );
}

class _GaugeCard extends StatelessWidget {
  const _GaugeCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.caption,
    required this.facts,
  });

  final IconData icon;
  final String title, caption;
  final double? value;
  final Color color;
  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) => AppCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CardTitle(icon, title, iconSize: 16, size: 14),
        const SizedBox(height: 12),
        Center(
          child: Ring(
            value: value == null ? null : value! / 100,
            color: color,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value == null ? '—' : pct(value!), style: text(18, weight: FontWeight.w700)),
                Text(caption, style: text(10, color: AppColors.ink3)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < facts.length; i++) ...[if (i > 0) const SizedBox(height: 6), KeyValue(facts[i].$1, facts[i].$2)],
      ],
    ),
  );
}

class _LoadCard extends StatelessWidget {
  const _LoadCard(this.v);

  final UpsView v;

  @override
  Widget build(BuildContext context) {
    final on = v.connected;
    return _GaugeCard(
      icon: LucideIcons.chartColumn,
      title: 'Load',
      value: on ? v.loadPercent : null,
      color: loadColor(v.loadPercent),
      caption: 'of capacity',
      facts: [
        ('Real power', on && v.watts != null ? '≈ ${number(v.watts!)} W' : '—'),
        ('Apparent', on && v.va != null ? '≈ ${number(v.va!)} VA' : '—'),
      ],
    );
  }
}

class _BatteryCard extends StatelessWidget {
  const _BatteryCard(this.v);

  final UpsView v;

  @override
  Widget build(BuildContext context) {
    final on = v.connected;
    return _GaugeCard(
      icon: LucideIcons.batteryMedium,
      title: 'Battery',
      value: on ? v.batteryPercent : null,
      color: batteryColor(v),
      caption: 'remaining',
      facts: [('Voltage', on && v.batteryVoltage != null ? '${number(v.batteryVoltage!, 1)} V' : '—'), ('Health', healthText(v.health))],
    );
  }
}

class _RecentEvents extends StatelessWidget {
  const _RecentEvents(this.events);

  final List<UpsEvent> events;

  @override
  Widget build(BuildContext context) {
    final recent = events.reversed.take(3).toList();
    final now = DateTime.now();
    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: CardTitle(
              LucideIcons.list,
              'Recent Events',
              trailing: GestureDetector(
                onTap: () => ShellScope.of(context).go(AppTab.events),
                child: Text(
                  'View all',
                  style: text(13, weight: FontWeight.w500, color: AppColors.primary),
                ),
              ),
            ),
          ),
          if (recent.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No events yet', style: text(14, color: AppColors.ink3)),
            ),
          for (var i = 0; i < recent.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: i < recent.length - 1
                  ? const BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.hairline)),
                    )
                  : null,
              child: Row(
                children: [
                  IconBox(
                    eventIcon(recent[i].kind),
                    wash: eventColors(recent[i]).wash,
                    color: eventColors(recent[i]).icon,
                    size: 30,
                    iconSize: 15,
                    round: true,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(recent[i].parts.title, style: text(14), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 8),
                  Text(shortTime(recent[i].time, now), style: text(12, color: AppColors.ink3)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
