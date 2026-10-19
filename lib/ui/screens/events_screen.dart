// Events: the design's "05 Events". The logbook keeps a file per day; this
// shows the last week, with a summary of the picked day and a CSV export.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/cloud_source.dart' show describeError;
import '../../models/ups.dart';
import '../../state/controllers.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

const _week = 7;

/// The filter chips and the event kinds each one shows. Kinds PowerPilot adds
/// later land under Device.
const _filters = <String, Set<String>?>{
  'All': null,
  'Power': {'utility_lost', 'utility_restored', 'on_battery', 'shutdown', 'overload'},
  'Battery': {'battery_charging', 'low_battery', 'self_test'},
  'Alarms': {'alarm', 'alarm_muted', 'alarm_unmuted'},
  'Device': {},
};

bool _matches(String filter, UpsEvent e) {
  final kinds = _filters[filter];
  if (kinds == null) return true;
  if (filter == 'Device') return !_filters.values.any((k) => k != null && k.isNotEmpty && k.contains(e.kind));
  return kinds.contains(e.kind);
}

class EventsScreen extends StatefulWidget {
  const EventsScreen({super.key});

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  late DateTime _selected = _today();
  String _filter = 'All';
  final _events = <String, List<UpsEvent>>{};
  final _readings = <String, List<Reading>>{};
  UpsController? _ups;
  bool _exporting = false;

  static DateTime _today() {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  List<DateTime> get _strip {
    final t = _today();
    return [for (var i = _week - 1; i >= 0; i--) DateTime(t.year, t.month, t.day - i)];
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ups = UpsScope.of(context);
    if (ups != _ups) {
      _ups = ups;
      _events.clear();
      _readings.clear();
      _loadWeek();
    }
  }

  Future<void> _loadWeek() async {
    final source = _ups!.source;
    try {
      final dates = _strip.map(ymd).toList();
      final lists = await Future.wait(dates.map(source.logEvents));
      if (!mounted) return;
      setState(() {
        for (var i = 0; i < dates.length; i++) {
          _events[dates[i]] = lists[i];
        }
      });
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    }
    await _loadReadings(_selected);
  }

  Future<void> _loadReadings(DateTime day) async {
    final d = ymd(day);
    if (_readings.containsKey(d) && d != ymd(_today())) return;
    try {
      final r = await _ups!.source.logReadings(d);
      if (mounted) setState(() => _readings[d] = r);
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    }
  }

  /// A day's events, newest first. Today's include what arrived on the stream
  /// since the logbook was read.
  List<UpsEvent> _dayEvents(DateTime day, UpsController ups) {
    final d = ymd(day);
    final logged = _events[d] ?? const <UpsEvent>[];
    final live = d == ymd(_today()) ? ups.events.where((e) => sameDay(e.time, day)) : const <UpsEvent>[];
    final seen = <String>{};
    return [
      for (final e in [...logged, ...live])
        if (seen.add(e.key)) e,
    ]..sort((a, b) => b.time.compareTo(a.time));
  }

  Future<void> _export(BuildContext button) async {
    final ups = _ups!;
    final from = ymd(_strip.first), to = ymd(_strip.last);
    final box = button.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    setState(() => _exporting = true);
    try {
      final csv = await ups.source.exportCsv('events', from, to);
      final dir = await Directory.systemTemp.createTemp('powerpilot');
      final file = File('${dir.path}/PowerPilot-${ups.source.label.toLowerCase()}-events-$from-to-$to.csv');
      await file.writeAsString(csv);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'text/csv')],
          subject: 'PowerPilot events, ${date(_strip.first)} to ${date(_strip.last)}',
          sharePositionOrigin: origin,
        ),
      );
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ups = UpsScope.of(context);
    final today = _today();
    // The picked day first, then the earlier days of the week that had any.
    final days = [
      for (final d in _strip.reversed)
        if (!d.isAfter(_selected)) d,
    ];

    return TabPage(
      onRefresh: _loadWeek,
      children: [
        ScreenHeader(
          'Events',
          subtitle: '${monthYear(_selected)} · Kept for ${number(ups.settings.logRetentionDays)} days',
          trailing: Builder(
            builder: (button) => _CsvButton(busy: _exporting, onTap: () => _export(button)),
          ),
        ),
        Row(
          children: [
            for (final d in _strip) ...[
              if (d != _strip.first) const SizedBox(width: 6),
              Expanded(
                child: _DayCell(
                  day: d,
                  selected: sameDay(d, _selected),
                  dot: _dot(_dayEvents(d, ups)),
                  onTap: () {
                    setState(() => _selected = d);
                    _loadReadings(d);
                  },
                ),
              ),
            ],
          ],
        ),
        _Summary(events: _dayEvents(_selected, ups), readings: _readings[ymd(_selected)]),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final f in _filters.keys) ...[
                if (f != 'All') const SizedBox(width: 8),
                _FilterChip(f, selected: f == _filter, onTap: () => setState(() => _filter = f)),
              ],
            ],
          ),
        ),
        for (final d in days)
          if (_dayEvents(d, ups).where((e) => _matches(_filter, e)).toList() case final list when list.isNotEmpty || d == _selected)
            _DaySection(
              heading:
                  '${sameDay(d, today)
                      ? 'Today'
                      : sameDay(d, today.subtract(const Duration(days: 1)))
                      ? 'Yesterday'
                      : weekday(d)} · ${date(d)}',
              events: list,
              loading: !_events.containsKey(ymd(d)),
            ),
      ],
    );
  }

  /// A day's dot: amber after an alert or warning, green for a quiet day with
  /// events, none without.
  Color? _dot(List<UpsEvent> events) {
    if (events.isEmpty) return null;
    return events.any((e) => e.level == 'alert' || e.level == 'warn') ? AppColors.warning : AppColors.good;
  }
}

class _CsvButton extends StatelessWidget {
  const _CsvButton({required this.busy, required this.onTap});

  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.card,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: const BorderSide(color: AppColors.border),
    ),
    child: InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(LucideIcons.download, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              'CSV',
              style: text(13, weight: FontWeight.w600, color: AppColors.primary),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DayCell extends StatelessWidget {
  const _DayCell({required this.day, required this.selected, required this.dot, required this.onTap});

  final DateTime day;
  final bool selected;
  final Color? dot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    label: '${weekday(day)} ${date(day)}',
    excludeSemantics: true,
    child: GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.ink : AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? AppColors.ink : AppColors.border),
        ),
        child: Column(
          children: [
            Text(
              weekday(day),
              style: text(11, weight: FontWeight.w500, color: selected ? const Color(0xB3FFFFFF) : AppColors.ink3),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: text(17, weight: FontWeight.w700, color: selected ? Colors.white : AppColors.ink),
            ),
            const SizedBox(height: 4),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(color: dot ?? Colors.transparent, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Outages, time on battery, the lowest charge and the peak load of a day.
class _Summary extends StatelessWidget {
  const _Summary({required this.events, required this.readings});

  final List<UpsEvent> events;
  final List<Reading>? readings;

  @override
  Widget build(BuildContext context) {
    final outages = events.where((e) => e.kind == 'utility_lost').length;
    final r = readings;
    final charges = [for (final x in r ?? const <Reading>[]) ?x.charge];
    final battery = r?.where((x) => x.mode == 'battery').length;
    final cells = [
      (number(outages), outages == 1 ? 'Outage' : 'Outages'),
      (
        battery == null
            ? '—'
            : battery == 0
            ? '0 min'
            : elapsed(Duration(minutes: battery)),
        'On battery',
      ),
      (charges.isEmpty ? '—' : pct(charges.reduce(math.min)), 'Low charge'),
      (r == null || r.isEmpty ? '—' : pct(r.map((x) => x.loadMax).reduce(math.max)), 'Peak load'),
    ];
    return AppCard(
      child: IntrinsicHeight(
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                child: Container(
                  padding: EdgeInsets.only(left: i == 0 ? 0 : 12),
                  decoration: i == 0
                      ? null
                      : const BoxDecoration(
                          border: Border(left: BorderSide(color: AppColors.hairline)),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(cells[i].$1, style: text(17, weight: FontWeight.w700)),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        cells[i].$2,
                        style: text(11, color: AppColors.ink3),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip(this.label, {required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: selected,
    child: GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.card,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: text(12, weight: FontWeight.w600, color: selected ? Colors.white : AppColors.ink2),
        ),
      ),
    ),
  );
}

class _DaySection extends StatelessWidget {
  const _DaySection({required this.heading, required this.events, required this.loading});

  final String heading;
  final List<UpsEvent> events;
  final bool loading;

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
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: cardDecoration,
        child: events.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(loading ? 'Loading…' : 'No events on this day.', style: text(14, color: AppColors.ink3)),
              )
            : Column(children: [for (var i = 0; i < events.length; i++) _EventRow(events[i], last: i == events.length - 1)]),
      ),
    ],
  );
}

class _EventRow extends StatelessWidget {
  const _EventRow(this.e, {required this.last});

  final UpsEvent e;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final parts = e.parts;
    final colors = eventColors(e);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: last
          ? null
          : const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppColors.hairline)),
            ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBox(eventIcon(e.kind), wash: colors.wash, color: colors.icon, size: 32, iconSize: 16, round: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(parts.title, style: text(14, weight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Text(clock(e.time), style: text(12, color: AppColors.ink3)),
                  ],
                ),
                if (parts.detail != null) ...[
                  const SizedBox(height: 3),
                  Text(parts.detail!, style: text(12, color: AppColors.ink2, height: 1.4)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
