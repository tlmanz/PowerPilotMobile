// Controls: the design's "03 Controls", with PowerPilot's rules from
// js/ui/controls.js. Dangerous actions (shutdown, restart) always end in an
// explicit confirmation.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/cloud_source.dart' show describeError;
import '../../models/ups_view.dart';
import '../../state/controllers.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';
import 'settings_screen.dart';

/// The shutdown delays the UPS takes: .2–.9 or 1–10 minutes.
const _delays = [(0.2, '12 seconds'), (0.5, '30 seconds'), (1.0, '1 minute'), (2.0, '2 minutes'), (5.0, '5 minutes'), (10.0, '10 minutes')];

class ControlsScreen extends StatefulWidget {
  const ControlsScreen({super.key});

  @override
  State<ControlsScreen> createState() => _ControlsScreenState();
}

class _ControlsScreenState extends State<ControlsScreen> {
  /// Commands waiting for the device; the server waits up to 90 s for it.
  final _busy = <String>{};

  /// The alarm switch shows the choice until the UPS confirms it.
  bool? _beeper;

  Future<bool> _run(UpsController ups, String id, String done, {double minutes = 0, int restoreAfter = 0}) async {
    final group = id.split('.').first;
    setState(() => _busy.add(group));
    try {
      await ups.command(id, minutes: minutes, restoreAfter: restoreAfter);
      if (mounted) toast(context, done);
      return true;
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
      return false;
    } finally {
      if (mounted) setState(() => _busy.remove(group));
    }
  }

  @override
  Widget build(BuildContext context) {
    final ups = UpsScope.of(context);
    final v = ups.view;
    final on = v.connected && ups.online && ups.linkUp;
    final s = ups.settings;

    final beeper = _beeper ?? v.alarm.enabled;
    final canMute = on && (v.alarm.muted || (v.alarm.active && v.alarm.enabled));
    final canTest = on && (v.testRunning || v.mode == UpsMode.ac);

    return TabPage(
      gap: 22,
      children: [
        ScreenHeader(
          'Controls',
          subtitle: '${v.device.name} · ${ups.source.isDemo ? 'Demo data: nothing is sent' : 'Commands go through the server'}',
        ),
        Section(
          'Alarm',
          children: [
            ControlRow(
              icon: LucideIcons.bell,
              wash: AppColors.primaryWash,
              iconColor: AppColors.primary,
              title: 'UPS alarm',
              subtitle: !on
                  ? 'UPS not connected'
                  : v.alarm.muted
                  ? 'On, muted for the current alarm'
                  : beeper
                  ? 'Beeps on power events'
                  : 'Off: the UPS stays silent',
              trailing: AppToggle(
                value: beeper,
                label: 'UPS alarm',
                onChanged: !on || _busy.contains('beeper')
                    ? null
                    : (want) async {
                        setState(() => _beeper = want);
                        await _run(ups, want ? 'beeper.on' : 'beeper.off', want ? 'UPS alarm turned on' : 'UPS alarm turned off');
                        if (mounted) setState(() => _beeper = null);
                      },
              ),
            ),
            ControlRow(
              icon: LucideIcons.bellOff,
              title: 'Mute alarm',
              subtitle: !on
                  ? 'UPS not connected'
                  : v.alarm.muted
                  ? 'Muted until the condition clears'
                  : v.alarm.active
                  ? 'Silence it until the condition clears'
                  : 'No alarm sounding',
              trailing: SoftButton(
                v.alarm.muted ? 'Unmute' : 'Mute',
                busy: _busy.contains('alarm'),
                onPressed: canMute
                    ? () => _run(
                        ups,
                        v.alarm.muted ? 'alarm.unmute' : 'alarm.mute',
                        v.alarm.muted ? 'Alarm unmuted' : 'Alarm muted until the condition clears',
                      )
                    : null,
              ),
            ),
            ControlRow(
              icon: LucideIcons.batteryLow,
              wash: AppColors.warnWash,
              iconColor: AppColors.warnInk,
              title: 'Low battery alarm',
              subtitle: 'Alert when charge falls below',
              trailing: ValueChevron('${s.lowBatteryPercent}%'),
              onTap: () => editLowBattery(context, ups),
            ),
          ],
        ),
        Section(
          'Diagnostics',
          children: [
            ControlRow(
              icon: LucideIcons.activity,
              wash: AppColors.goodWash,
              iconColor: AppColors.good,
              title: 'Self-test',
              subtitle: v.testRunning
                  ? 'Test in progress'
                  : v.mode == UpsMode.ac
                  ? 'Runs on battery for 10 seconds'
                  : 'Available on mains power only',
              trailing: SoftButton(
                v.testRunning ? 'Cancel test' : 'Start test',
                busy: _busy.contains('test'),
                onPressed: !canTest
                    ? null
                    : () async {
                        if (v.testRunning) {
                          await _run(ups, 'test.cancel', 'Self-test cancelled');
                          return;
                        }
                        final yes = await confirm(
                          context,
                          title: 'Run a battery self-test?',
                          body:
                              'The UPS runs on battery for 10 seconds, then returns to mains. Mains stays connected, so your '
                              'equipment keeps power if the battery struggles.',
                          ok: 'Start test',
                        );
                        if (yes && context.mounted) await _run(ups, 'test.quick', 'Self-test started');
                      },
              ),
            ),
          ],
        ),
        Section(
          'Power',
          children: [
            _shutdownRow(ups, v, on),
            ControlRow(
              icon: LucideIcons.rotateCw,
              wash: AppColors.primaryWash,
              iconColor: AppColors.primary,
              title: 'Restart UPS',
              subtitle: 'Turn the outlets off and back on',
              trailing: SoftButton(
                'Restart',
                busy: _busy.contains('shutdown'),
                onPressed: !on || v.shutdownPending ? null : () => _schedule(ups, restart: true),
              ),
            ),
            ControlRow(
              icon: LucideIcons.settings2,
              title: 'Shutdown configuration',
              subtitle: s.shutdownMac
                  ? 'On · Shut down the paired Mac after ${s.shutdownAfterMinutes} min on battery'
                  : 'Off · Shut down the paired Mac on outage',
              trailing: const ValueChevron(null),
              onTap: () => openSettings(context),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              const Icon(LucideIcons.info, size: 16, color: AppColors.ink3),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_testNote(v), style: text(12, color: AppColors.ink2, height: 1.4)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _testNote(UpsView v) {
    final t = v.lastTest;
    final last = t == null ? 'No self-test recorded.' : 'Last self-test ${dateTime(t.started)}: ${t.result}.';
    return '$last Self-test is available on mains power only.';
  }

  Widget _shutdownRow(UpsController ups, UpsView v, bool on) {
    final busy = _busy.contains('shutdown');
    if (on && v.shutdownPending) {
      return ControlRow(
        icon: LucideIcons.power,
        wash: AppColors.badWash,
        iconColor: AppColors.critical,
        title: 'Graceful shutdown',
        subtitle: 'Shutdown is counting down',
        trailing: SoftButton('Cancel', busy: busy, onPressed: () => _run(ups, 'shutdown.cancel', 'Shutdown cancelled')),
      );
    }
    if (on && v.mode == UpsMode.standby) {
      return ControlRow(
        icon: LucideIcons.power,
        wash: AppColors.goodWash,
        iconColor: AppColors.good,
        title: 'Outlets are off',
        subtitle: 'Turn them back on to power your equipment',
        trailing: SoftButton(
          'Turn on',
          tone: Tone.good,
          busy: busy,
          onPressed: () async {
            final yes = await confirm(
              context,
              title: 'Turn the outlets on?',
              body: 'Power is restored to everything plugged into the UPS.',
              ok: 'Turn on',
            );
            if (yes && mounted) await _run(ups, 'shutdown.cancel', 'Outlets turning on');
          },
        ),
      );
    }
    return ControlRow(
      icon: LucideIcons.power,
      wash: AppColors.badWash,
      iconColor: AppColors.critical,
      title: 'Graceful shutdown',
      subtitle: 'Turn off connected equipment after a delay',
      trailing: SoftButton('Shutdown', tone: Tone.bad, busy: busy, onPressed: on ? () => _schedule(ups, restart: false) : null),
    );
  }

  /// Graceful shutdown and restart share one sheet, then a confirmation.
  Future<void> _schedule(UpsController ups, {required bool restart}) async {
    final plan = await showModalBottomSheet<(double, String, int)>(
      context: context,
      isScrollControlled: true,
      builder: (context) => _PowerSheet(restart: restart),
    );
    if (plan == null || !mounted) return;
    final (minutes, delay, after) = plan;
    final what = restart
        ? 'turn off in $delay, then back on after ${number(after)} min'
        : 'turn off in $delay and stay off until you turn them on';
    final yes = await confirm(
      context,
      title: restart ? 'Restart the UPS outlets?' : 'Shut down the UPS outlets?',
      body: 'The outlets will $what. Everything plugged into them loses power.',
      ok: restart ? 'Yes, restart' : 'Yes, shut down',
      danger: true,
    );
    if (yes && mounted) {
      await _run(ups, 'shutdown', restart ? 'Restart scheduled' : 'Shutdown scheduled', minutes: minutes, restoreAfter: after);
    }
  }
}

class _PowerSheet extends StatefulWidget {
  const _PowerSheet({required this.restart});

  final bool restart;

  @override
  State<_PowerSheet> createState() => _PowerSheetState();
}

class _PowerSheetState extends State<_PowerSheet> {
  double _minutes = 1;
  final _after = TextEditingController(text: '1');
  String? _error;

  @override
  void dispose() {
    _after.dispose();
    super.dispose();
  }

  void _continue() {
    final after = widget.restart ? int.tryParse(_after.text.trim()) : 0;
    if (after == null || (widget.restart && (after < 1 || after > 9999))) {
      setState(() => _error = 'Restart delay must be a whole number from 1 to 9,999 minutes.');
      return;
    }
    final label = _delays.firstWhere((d) => d.$1 == _minutes).$2;
    Navigator.pop(context, (_minutes, label, after));
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.restart ? 'Restart UPS outlets' : 'Graceful shutdown', style: text(18, weight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(
            widget.restart
                ? 'The outlets turn off when the delay ends, then back on after the restart delay, once mains is present.'
                : 'Connected equipment keeps power until the delay ends, giving it time to shut down.',
            style: text(13, color: AppColors.ink2, height: 1.45),
          ),
          const SizedBox(height: 16),
          Text(
            'TURN OFF IN',
            style: text(12, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.6),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (m, label) in _delays)
                ChoiceChip(
                  label: Text(label),
                  selected: _minutes == m,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _minutes = m),
                  labelStyle: text(13, weight: FontWeight.w600, color: _minutes == m ? Colors.white : AppColors.ink2),
                  selectedColor: AppColors.primary,
                  backgroundColor: AppColors.card,
                  side: BorderSide(color: _minutes == m ? AppColors.primary : AppColors.border),
                  shape: const StadiumBorder(),
                ),
            ],
          ),
          if (widget.restart) ...[
            const SizedBox(height: 16),
            Text(
              'TURN BACK ON AFTER',
              style: text(12, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.6),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _after,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
              decoration: const InputDecoration(suffixText: 'min'),
              style: text(15),
              onSubmitted: (_) => _continue(),
            ),
          ],
          if (_error != null) ...[const SizedBox(height: 8), Text(_error!, style: text(12, color: AppColors.badInk))],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: widget.restart ? AppColors.primary : AppColors.critical,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _continue,
              child: Text(
                'Continue',
                style: text(15, weight: FontWeight.w600, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
