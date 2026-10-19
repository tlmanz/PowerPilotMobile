// Formatting, as PowerPilot's dashboard does it (js/ui/core.js): MM/DD/YY
// dates, thousands separators and one-decimal percentages.

String number(num v, [int decimals = 0]) {
  final fixed = v.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final frac = dot < 0 ? '' : fixed.substring(dot);
  final out = StringBuffer();
  for (var i = 0; i < whole.length; i++) {
    if (i > 0 && (whole.length - i) % 3 == 0) out.write(',');
    out.write(whole[i]);
  }
  // -0.0 rounds to "0.0": no sign then.
  final negative = v < 0 && double.parse(fixed) != 0;
  return '${negative ? '-' : ''}$out$frac';
}

String pct(num v) => '${number(v, 1)}%';

String _pad(int n) => n.toString().padLeft(2, '0');

String date(DateTime d) => '${_pad(d.month)}/${_pad(d.day)}/${_pad(d.year % 100)}';

String clock(DateTime d, {bool seconds = false}) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final s = seconds ? ':${_pad(d.second)}' : '';
  return '$h:${_pad(d.minute)}$s ${d.hour >= 12 ? 'PM' : 'AM'}';
}

String dateTime(DateTime d, {bool seconds = false}) => '${date(d)} ${clock(d, seconds: seconds)}';

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Today's events show the time; older ones the date.
String shortTime(DateTime d, [DateTime? now]) => sameDay(d, now ?? DateTime.now()) ? clock(d) : date(d);

/// Runtime estimates: the dashboard caps them at 8 hours.
String duration(double? minutes) {
  if (minutes == null) return '—';
  if (minutes >= 480) return 'Over 8 h';
  final m = minutes.round().clamp(0, 480);
  return m < 60 ? '$m min' : '${m ~/ 60} h ${m % 60} min';
}

/// How long something lasted, as PowerPilot's monitor.Duration words it.
String elapsed(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'under a minute';
  if (m < 60) return '$m min';
  if (m % 60 == 0) return '${number(m ~/ 60)} h';
  return '${number(m ~/ 60)} h ${m % 60} min';
}

/// A log date, as the server's API takes it: 2026-10-19.
String ymd(DateTime d) => '${d.year}-${_pad(d.month)}-${_pad(d.day)}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

String weekday(DateTime d) => _weekdays[d.weekday - 1];
String monthYear(DateTime d) => '${_months[d.month - 1]} ${d.year}';
