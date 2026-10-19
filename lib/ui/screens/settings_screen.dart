// Settings: the design's "06 Settings". Settings live on the server, per UPS,
// with PowerPilot's ranges; the device gets battery_ah and low_battery_percent.
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/cloud_source.dart' show CloudSource, describeError;
import '../../data/pairing.dart';
import '../../models/ups.dart';
import '../../state/controllers.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

/// `make build-aab` passes the pubspec version; other builds say "dev".
const appVersion = String.fromEnvironment('APP_VERSION', defaultValue: 'dev');

/// Picks a value from [choices] (plus the current one) and saves it.
Future<void> _edit(
  BuildContext context,
  UpsController ups, {
  required String title,
  String? subtitle,
  required int current,
  required List<int> choices,
  required String Function(int) label,
  required UpsSettings Function(int) apply,
  required String Function(int) saved,
}) async {
  final values = {...choices, current}.toList()..sort();
  final picked = await pickOption<int>(
    context,
    title: title,
    subtitle: subtitle,
    options: [for (final v in values) (v, label(v))],
    selected: current,
  );
  if (picked == null || picked == current || !context.mounted) return;
  try {
    await ups.saveSettings(apply(picked));
    if (context.mounted) toast(context, saved(picked));
  } catch (e) {
    if (context.mounted) toast(context, describeError(e), bad: true);
  }
}

Future<void> editLowBattery(BuildContext context, UpsController ups) => _edit(
  context,
  ups,
  title: 'Low battery alarm',
  subtitle: 'Alert when the charge falls below this while on battery.',
  current: ups.settings.lowBatteryPercent,
  choices: const [10, 15, 20, 25, 30, 40, 50],
  label: (v) => '$v%',
  apply: (v) => ups.settings.copyWith(lowBatteryPercent: v),
  saved: (v) => 'Low battery alarm set to $v%',
);

String _pushSubtitle(PushController p) {
  if (p.demo) return 'Pair a PowerPilot server to get them';
  if (!p.supported) return Platform.isAndroid ? 'This build has no Firebase project' : 'On Android for now';
  if (p.blocked) return 'Blocked: allow them for PowerPilot in Android settings';
  return 'Power events, each with a summary of the reading';
}

Future<void> _pushAction(BuildContext context, Future<String> Function() action) async {
  try {
    final message = await action();
    if (context.mounted) toast(context, message);
  } catch (e) {
    if (context.mounted) toast(context, describeError(e), bad: true);
  }
}

String _connection(UpsController ups) {
  if (ups.source.isDemo) return 'Simulated';
  return switch (ups.device.connection) {
    '' => 'Via server',
    'esp32' => 'ESP32 bridge via server',
    final c => '$c via server',
  };
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ups = UpsScope.of(context);
    final app = AppScope.of(context);
    final s = ups.settings;
    final demo = ups.source.isDemo;
    final keychain = Platform.isIOS ? 'Keychain' : 'Android Keystore';

    return TabPage(
      gap: 22,
      children: [
        const ScreenHeader('Settings'),
        _DeviceCard(ups),
        Section(
          'Alerts',
          children: [
            ListenableBuilder(
              listenable: app.push,
              builder: (context, _) {
                final p = app.push;
                return ControlRow(
                  icon: LucideIcons.bell,
                  wash: AppColors.badWash,
                  iconColor: AppColors.critical,
                  title: 'Push notifications',
                  subtitle: _pushSubtitle(p),
                  trailing: AppToggle(
                    value: p.enabled && p.available,
                    label: 'Push notifications',
                    onChanged: p.available && !p.busy ? (on) => _pushAction(context, () => p.setEnabled(on)) : null,
                  ),
                );
              },
            ),
            ListenableBuilder(
              listenable: app.push,
              builder: (context, _) {
                final p = app.push;
                final on = p.available && p.enabled;
                return ControlRow(
                  icon: LucideIcons.timer,
                  wash: AppColors.warnWash,
                  iconColor: AppColors.warnInk,
                  title: 'Outage updates',
                  subtitle: on ? 'Every 5 minutes on battery' : 'Every 5 minutes on battery, with notifications on',
                  trailing: AppToggle(
                    value: on && p.outageUpdates,
                    label: 'Outage updates',
                    onChanged: on && !p.busy ? (v) => _pushAction(context, () => p.setOutageUpdates(v)) : null,
                  ),
                );
              },
            ),
            ControlRow(
              icon: LucideIcons.batteryLow,
              wash: AppColors.warnWash,
              iconColor: AppColors.warnInk,
              title: 'Low battery alarm',
              subtitle: 'Alert when the charge falls below',
              trailing: ValueChevron('${s.lowBatteryPercent}%'),
              onTap: () => editLowBattery(context, ups),
            ),
          ],
        ),
        Section(
          'Power outage',
          children: [
            ControlRow(
              icon: LucideIcons.laptop,
              title: 'Shut down the paired Mac',
              subtitle: 'Saves work before the battery runs out',
              trailing: AppToggle(
                value: s.shutdownMac,
                label: 'Shut down the paired Mac',
                onChanged: (on) async {
                  try {
                    await ups.saveSettings(s.copyWith(shutdownMac: on));
                  } catch (e) {
                    if (context.mounted) toast(context, describeError(e), bad: true);
                  }
                },
              ),
            ),
            ControlRow(
              icon: LucideIcons.circleHelp,
              title: 'After',
              subtitle: 'On battery, or sooner if the battery is low',
              trailing: ValueChevron('${s.shutdownAfterMinutes} min'),
              onTap: () => _edit(
                context,
                ups,
                title: 'Shut down the Mac after',
                subtitle: 'Minutes on battery before PowerPilot shuts the paired Mac down.',
                current: s.shutdownAfterMinutes,
                choices: const [1, 2, 3, 5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 240],
                label: (v) => '${number(v)} min',
                apply: (v) => s.copyWith(shutdownAfterMinutes: v),
                saved: (v) => 'Shuts down after ${number(v)} min on battery',
              ),
            ),
          ],
        ),
        Section(
          'Battery and events',
          children: [
            ControlRow(
              icon: LucideIcons.batteryFull,
              wash: AppColors.goodWash,
              iconColor: AppColors.good,
              title: 'Battery capacity',
              subtitle: 'Per 12 V battery, for the runtime estimate',
              trailing: ValueChevron('${s.batteryAh} Ah'),
              onTap: () => _edit(
                context,
                ups,
                title: 'Battery capacity',
                subtitle: "Amp-hours per 12 V battery, from the battery's label.",
                current: s.batteryAh,
                choices: const [5, 7, 9, 12, 18, 26, 40, 50, 65, 100, 200],
                label: (v) => '$v Ah',
                apply: (v) => s.copyWith(batteryAh: v),
                saved: (v) => 'Battery capacity set to $v Ah',
              ),
            ),
            ControlRow(
              icon: LucideIcons.calendar,
              wash: AppColors.primaryWash,
              iconColor: AppColors.primary,
              title: 'Keep events for',
              subtitle: 'Events and readings, a file per day',
              trailing: ValueChevron('${number(s.logRetentionDays)} days'),
              onTap: () => _edit(
                context,
                ups,
                title: 'Keep events for',
                subtitle: 'Older days are deleted from the server.',
                current: s.logRetentionDays,
                choices: const [7, 14, 30, 60, 90, 180, 365, 730, 1825, 3650],
                label: (v) => '${number(v)} days',
                apply: (v) => s.copyWith(logRetentionDays: v),
                saved: (v) => 'Events kept for ${number(v)} days',
              ),
            ),
          ],
        ),
        Section(
          'PowerPilot server',
          footnote: demo
              ? 'PowerPilot v$appVersion · The demo makes up its readings; nothing leaves this phone.'
              : 'PowerPilot v$appVersion · The token is stored in the $keychain and never shown again.',
          children: [
            ControlRow(
              icon: demo ? LucideIcons.play : LucideIcons.cloud,
              wash: demo ? AppColors.goodWash : AppColors.primaryWash,
              iconColor: demo ? AppColors.goodInk : AppColors.primary,
              title: demo ? 'Demo data' : app.pairing?.server?.host ?? 'Server',
              subtitle: demo
                  ? 'A simulated UPS · Pair a server instead'
                  : ups.lastSeen == null
                  ? 'Paired'
                  : 'Paired · Last seen ${dateTime(ups.lastSeen!)}',
              trailing: const ValueChevron(null),
              onTap: demo ? () => app.unpair() : () => _showServer(context, app, ups),
            ),
            ControlRow(
              icon: LucideIcons.unlink,
              wash: AppColors.badWash,
              iconColor: AppColors.critical,
              title: demo ? 'Leave the demo' : 'Unpair this phone',
              titleColor: AppColors.badInk,
              onTap: () async {
                if (demo) {
                  await app.unpair();
                  return;
                }
                final yes = await confirm(
                  context,
                  title: 'Unpair this phone?',
                  body: 'PowerPilot forgets the server address and token. To pair again, create a new phone token on the admin page.',
                  ok: 'Unpair',
                  danger: true,
                );
                if (yes) await app.unpair();
              },
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _showServer(BuildContext context, AppController app, UpsController ups) async {
    final p = app.pairing;
    if (p == null || p.server == null) return;
    // Lists the server's UPSes, so the token is checked too.
    List<DeviceSummary>? devices;
    String? problem;
    try {
      devices = await CloudSource.devices(p.server!, p.token!);
    } catch (e) {
      problem = describeError(e);
    }
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PowerPilot server', style: text(18, weight: FontWeight.w700)),
              const SizedBox(height: 12),
              KeyValue('Address', p.server.toString(), valueColor: AppColors.ink2),
              const SizedBox(height: 7),
              KeyValue('Connection', ups.linkUp ? 'Connected' : ups.linkError, valueColor: AppColors.ink2),
              const SizedBox(height: 16),
              Text(
                'UPS',
                style: text(12, weight: FontWeight.w600, color: AppColors.ink3, spacing: 0.6),
              ),
              const SizedBox(height: 4),
              if (problem != null) Text(problem, style: text(13, color: AppColors.badInk)),
              for (final d in devices ?? const <DeviceSummary>[])
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(d.device.name, style: text(15, weight: FontWeight.w600)),
                  subtitle: Text('${d.id} · ${d.online ? 'Online' : 'Offline'}', style: text(12, color: AppColors.ink3)),
                  trailing: d.id == p.device ? const Icon(LucideIcons.check, color: AppColors.primary, size: 20) : null,
                  onTap: () => Navigator.pop(context, d.id),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && picked != p.device) await app.pair(Pairing.cloud(server: p.server!, token: p.token!, device: picked));
  }
}

class _DeviceCard extends StatelessWidget {
  const _DeviceCard(this.ups);

  final UpsController ups;

  @override
  Widget build(BuildContext context) {
    final v = ups.view;
    final d = v.device;
    final battery = v.batteryNominalVoltage;
    final nominal = v.nominalVoltage == null
        ? '—'
        : [
            '${number(v.nominalVoltage!)} V',
            if (v.nominalFrequency != null) '${number(v.nominalFrequency!)} Hz',
            if (battery != null && battery > 0) '${number(battery)} V battery',
          ].join(' · ');
    final kind = v.type.isEmpty ? 'UPS' : v.type;
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.surface2, borderRadius: BorderRadius.circular(14)),
                child: Image.asset('images/ups-front.png', width: 40, height: 48, fit: BoxFit.contain),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, style: text(16, weight: FontWeight.w700)),
                    const SizedBox(height: 3),
                    Text(
                      ups.source.isDemo ? '$kind · Demo data' : '$kind · Device ID “${ups.source.label}”',
                      style: text(12, color: AppColors.ink3),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.only(top: 12),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.hairline)),
            ),
            child: Column(
              children: [
                KeyValue('Rating', d.ratedVA > 0 ? '${number(d.ratedVA)} VA / ${number(d.ratedW)} W' : '—', valueColor: AppColors.ink2),
                const SizedBox(height: 7),
                KeyValue('Nominal', nominal, valueColor: AppColors.ink2),
                const SizedBox(height: 7),
                KeyValue('Connection', _connection(ups), valueColor: AppColors.ink2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens Settings from another tab ("Shutdown configuration" on Controls).
void openSettings(BuildContext context) => ShellScope.of(context).go(AppTab.settings);
