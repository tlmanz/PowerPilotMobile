// Trends: the design's "04 Trends". The last hour comes from the live samples;
// longer ranges from the logbook's per-minute readings, a day at a time.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/cloud_source.dart' show describeError;
import '../../models/ups.dart';
import '../../state/controllers.dart';
import '../format.dart';
import '../shell.dart';
import '../theme.dart';
import '../widgets.dart';

const _bars = 36;

enum _Range {
  hour('1 hour', Duration(hours: 1)),
  day('24 hours', Duration(hours: 24)),
  week('7 days', Duration(days: 7)),
  month('30 days', Duration(days: 30));

  const _Range(this.label, this.span);
  final String label;
  final Duration span;
}

/// One reading, from a live sample or a logbook minute.
class _Point {
  const _Point(
    this.t, {
    required this.input,
    required this.output,
    required this.load,
    this.charge,
    this.temperature,
    required this.onBattery,
  });

  factory _Point.sample(Sample s) =>
      // Samples carry no mode; no input voltage means the battery.
      _Point(s.t, input: s.input, output: s.output, load: s.load, charge: s.charge, onBattery: s.input < 20);

  factory _Point.reading(Reading r) =>
      _Point(r.t, input: r.input, output: r.output, load: r.load, charge: r.charge, onBattery: r.mode == 'battery');

  final DateTime t;
  final double input, output, load;
  final double? charge, temperature;
  final bool onBattery;
}

enum _Kind { volts, percent, battery, temperature }

class _Series {
  const _Series(this.title, this.icon, this.unit, this.kind, this.value);

  final String title, unit;
  final IconData icon;
  final _Kind kind;
  final double? Function(_Point) value;
}

final _series = [
  _Series('Input voltage', LucideIcons.plugZap, 'V', _Kind.volts, (p) => p.input),
  _Series('Load', LucideIcons.chartColumn, '%', _Kind.percent, (p) => p.load),
  _Series('Battery', LucideIcons.batteryMedium, '%', _Kind.battery, (p) => p.charge),
  _Series('Temperature', LucideIcons.thermometer, '°C', _Kind.temperature, (p) => p.temperature),
  _Series('Output voltage', LucideIcons.monitor, 'V', _Kind.volts, (p) => p.output),
];

/// Averages the points into equal time buckets; a bucket with any point on
/// battery counts as on battery. Voltages leave out 0 V readings, so a bucket
/// that spans a power cut isn't drawn half-height: it shows as failed (0)
/// when most of its readings are 0 V.
List<({double? value, bool onBattery})> _bucket(List<_Point> points, _Series s, DateTime start, DateTime end) {
  final span = end.difference(start).inMilliseconds / _bars;
  final sums = List.filled(_bars, 0.0), counts = List.filled(_bars, 0), zeros = List.filled(_bars, 0);
  final battery = List.filled(_bars, false);
  for (final p in points) {
    final v = s.value(p);
    if (v == null) continue;
    final i = ((p.t.difference(start).inMilliseconds) / span).floor();
    if (i < 0 || i >= _bars) continue;
    battery[i] = battery[i] || p.onBattery;
    if (s.kind == _Kind.volts && v < 1) {
      zeros[i]++;
      continue;
    }
    sums[i] += v;
    counts[i]++;
  }
  double? value(int i) => zeros[i] > 0 && zeros[i] >= counts[i]
      ? 0
      : counts[i] == 0
      ? null
      : sums[i] / counts[i];
  return [for (var i = 0; i < _bars; i++) (value: value(i), onBattery: battery[i])];
}

class TrendsScreen extends StatefulWidget {
  const TrendsScreen({super.key});

  @override
  State<TrendsScreen> createState() => _TrendsScreenState();
}

class _TrendsScreenState extends State<TrendsScreen> {
  _Range _range = _Range.hour;
  final _days = <String, List<Reading>>{};
  final _fetchedAt = <String, DateTime>{};
  bool _loading = false;

  UpsController get _ups => UpsScope.of(context);

  List<DateTime> _dates(_Range r) {
    final now = DateTime.now();
    final n = switch (r) {
      _Range.hour => 0,
      _Range.day => 2,
      _Range.week => 7,
      _Range.month => 30,
    };
    return [for (var i = n - 1; i >= 0; i--) DateTime(now.year, now.month, now.day - i)];
  }

  /// Fetches the days a range needs. Past days never change; today is fetched
  /// again after a couple of minutes.
  Future<void> _load(_Range r) async {
    final today = ymd(DateTime.now());
    final stale = [
      for (final d in _dates(r).map(ymd))
        if (!_days.containsKey(d) || (d == today && DateTime.now().difference(_fetchedAt[d]!) > const Duration(minutes: 2))) d,
    ];
    if (stale.isEmpty) return;
    setState(() => _loading = true);
    try {
      final source = _ups.source;
      final got = await Future.wait(stale.map(source.logReadings));
      for (var i = 0; i < stale.length; i++) {
        _days[stale[i]] = got[i];
        _fetchedAt[stale[i]] = DateTime.now();
      }
    } catch (e) {
      if (mounted) toast(context, describeError(e), bad: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _pick(_Range r) {
    setState(() => _range = r);
    _load(r);
  }

  List<_Point> _points(DateTime start) {
    if (_range == _Range.hour) return [for (final s in _ups.history) _Point.sample(s)];
    return [
      for (final d in _dates(_range).map(ymd))
        for (final r in _days[d] ?? const <Reading>[])
          if (!r.t.isBefore(start)) _Point.reading(r),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ups = UpsScope.of(context);
    final now = DateTime.now();
    final start = now.subtract(_range.span);
    final points = _points(start);
    // The live temperature, when the UPS reports one, joins the last hour.
    final temp = ups.view.temperature;
    final pts = temp != null && _range == _Range.hour && points.isNotEmpty
        ? [
            ...points.take(points.length - 1),
            _Point(
              points.last.t,
              input: points.last.input,
              output: points.last.output,
              load: points.last.load,
              charge: points.last.charge,
              temperature: temp,
              onBattery: points.last.onBattery,
            ),
          ]
        : points;
    final shown = [
      for (final s in _series)
        if (s.kind != _Kind.temperature || pts.any((p) => p.temperature != null)) s,
    ];

    return TabPage(
      children: [
        ScreenHeader(
          'Trends',
          subtitle: _range == _Range.hour ? '${date(now)} · Live, the last hour' : '${date(start)} to ${date(now)} · Averaged per minute',
          trailing: SquareButton(
            LucideIcons.table2,
            label: 'Show as a table',
            onTap: pts.isEmpty ? null : () => _showTable(pts, start, now),
          ),
        ),
        _RangePicker(current: _range, onPick: _pick),
        for (final s in shown) _TrendCard(series: s, points: pts, start: start, end: now, range: _range, loading: _loading),
      ],
    );
  }

  void _showTable(List<_Point> pts, DateTime start, DateTime end) {
    final cols = [_series[0], _series[4], _series[1], _series[2]];
    final buckets = [for (final s in cols) _bucket(pts, s, start, end)];
    final span = end.difference(start) ~/ _bars;
    String cell(double? v, _Series s) => v == null
        ? '—'
        : s.kind == _Kind.volts
        ? number(v, 1)
        : number(v, 1);
    final head = text(11, weight: FontWeight.w600, color: AppColors.ink3);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  children: [
                    Expanded(flex: 4, child: Text('TIME', style: head)),
                    for (final c in ['IN V', 'OUT V', 'LOAD %', 'BATT %'])
                      Expanded(
                        flex: 3,
                        child: Text(c, style: head, textAlign: TextAlign.right),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _bars,
                  itemBuilder: (context, k) {
                    final i = _bars - 1 - k;
                    final t = start.add(span * i);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.hairline)),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 4,
                            child: Text(
                              _range.span > const Duration(days: 1) ? dateTime(t) : clock(t),
                              style: text(12, color: AppColors.ink2),
                            ),
                          ),
                          for (var c = 0; c < cols.length; c++)
                            Expanded(
                              flex: 3,
                              child: Text(
                                cell(buckets[c][i].value, cols[c]),
                                style: text(12, weight: FontWeight.w600),
                                textAlign: TextAlign.right,
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RangePicker extends StatelessWidget {
  const _RangePicker({required this.current, required this.onPick});

  final _Range current;
  final ValueChanged<_Range> onPick;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(color: AppColors.hairline, borderRadius: BorderRadius.circular(14)),
    child: Row(
      children: [
        for (final r in _Range.values) ...[
          if (r.index > 0) const SizedBox(width: 4),
          Expanded(
            child: Semantics(
              selected: r == current,
              button: true,
              child: GestureDetector(
                onTap: () => onPick(r),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: r == current ? AppColors.card : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    r.label,
                    style: text(
                      13,
                      weight: r == current ? FontWeight.w600 : FontWeight.w500,
                      color: r == current ? AppColors.ink : AppColors.ink2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ],
    ),
  );
}

class _TrendCard extends StatelessWidget {
  const _TrendCard({
    required this.series,
    required this.points,
    required this.start,
    required this.end,
    required this.range,
    required this.loading,
  });

  final _Series series;
  final List<_Point> points;
  final DateTime start, end;
  final _Range range;
  final bool loading;

  String _fmt(double v) => switch (series.kind) {
    _Kind.volts => '${number(v, 1)} V',
    _Kind.temperature => '${number(v, 1)} °C',
    _ => pct(v),
  };

  @override
  Widget build(BuildContext context) {
    final values = [for (final p in points) ?series.value(p)];
    final latest = points.isEmpty ? null : series.value(points.last);
    final failed = series.kind == _Kind.volts && latest != null && latest < 1;

    final buckets = _bucket(points, series, start, end);
    final live = [for (final b in buckets) ?b.value];
    final nonZero = series.kind == _Kind.volts ? live.where((v) => v >= 1).toList() : live;
    final lo = nonZero.isEmpty ? 0.0 : nonZero.reduce(math.min), hi = nonZero.isEmpty ? 1.0 : nonZero.reduce(math.max);
    final (double y0, double y1) = switch (series.kind) {
      _Kind.volts => (lo - math.max(2, (hi - lo) * 0.8), hi + math.max(0.5, (hi - lo) * 0.2)),
      _Kind.percent => (0, math.max(10, hi * 1.3)),
      _Kind.battery => (0, 100),
      _Kind.temperature => (lo - 1, hi + 1),
    };
    final lastIndex = buckets.lastIndexWhere((b) => b.value != null);
    final bars = [
      for (var i = 0; i < buckets.length; i++)
        if (buckets[i].value == null)
          null
        else
          () {
            final v = buckets[i].value!;
            final last = i == lastIndex;
            if (series.kind == _Kind.volts && v < 1) return const Bar(0, AppColors.critical, failed: true);
            final color = series.kind == _Kind.battery
                ? (buckets[i].onBattery
                      ? AppColors.warning
                      : last
                      ? AppColors.good
                      : AppColors.goodBar)
                : last
                ? AppColors.series
                : AppColors.seriesBar;
            return Bar((v - y0) / (y1 - y0 == 0 ? 1 : y1 - y0), color);
          }(),
    ];

    final ticks = [
      for (final k in [0.0, 1 / 3, 2 / 3]) start.add(end.difference(start) * k),
    ];
    String tick(DateTime t) => range.span > const Duration(days: 1) ? date(t) : clock(t);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(series.icon, size: 15, color: AppColors.ink3),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            series.title,
                            style: text(13, weight: FontWeight.w500, color: AppColors.ink2),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          latest == null ? '—' : number(latest, series.kind == _Kind.volts ? 0 : 1),
                          style: text(24, weight: FontWeight.w700, spacing: -0.4, color: failed ? AppColors.badInk : AppColors.ink),
                        ),
                        const SizedBox(width: 3),
                        if (latest != null)
                          Text(
                            series.unit,
                            style: text(13, weight: FontWeight.w500, color: AppColors.ink3),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (values.isNotEmpty)
                Text(
                  'Min ${_fmt(values.reduce(math.min))}\nMax ${_fmt(values.reduce(math.max))}',
                  textAlign: TextAlign.right,
                  style: text(11, color: AppColors.ink3, height: 1.35),
                ),
            ],
          ),
          const SizedBox(height: 12),
          BarChart(bars, empty: loading ? 'Loading…' : 'No readings in this range'),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final t in ticks) ...[Text(tick(t), style: text(10, color: AppColors.ink3)), const Spacer()],
              Text('Now', style: text(10, color: AppColors.ink3)),
            ],
          ),
        ],
      ),
    );
  }
}
