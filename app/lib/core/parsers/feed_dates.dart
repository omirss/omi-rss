/// Shared feed date parsing used by every parser so RSS (RFC 822),
/// Atom (RFC 3339), and JSON Feed timestamps are handled uniformly.
/// Results are normalized to UTC.
library;

const Map<String, int> _months = {
  'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6,
  'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12,
};

const Map<String, int> _namedZones = {
  'GMT': 0, 'UT': 0, 'UTC': 0, 'Z': 0,
  'EST': -300, 'EDT': -240,
  'CST': -360, 'CDT': -300,
  'MST': -420, 'MDT': -360,
  'PST': -480, 'PDT': -420,
};

final RegExp _rfc822 = RegExp(
  r'^(?:[A-Za-z]+,\s*)?(\d{1,2})\s+([A-Za-z]{3})[A-Za-z]*\s+(\d{2,4})\s+'
  r'(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s+([+-]\d{4}|[A-Za-z]{1,5}))?$',
);

int? _zoneOffsetMinutes(String zone) {
  final z = zone.toUpperCase();
  if (_namedZones.containsKey(z)) return _namedZones[z];

  final m = RegExp(r'^([+-])(\d{2})(\d{2})$').firstMatch(zone);
  if (m == null) return null;

  final hours = int.parse(m.group(2)!);
  final minutes = int.parse(m.group(3)!);
  if (hours > 23 || minutes > 59) return null;

  final sign = m.group(1) == '-' ? -1 : 1;
  return sign * (hours * 60 + minutes);
}

/// Parses RFC 3339 and RFC 822/1123 timestamps, returning a UTC DateTime.
/// Returns null when the value cannot be interpreted.
DateTime? parseFeedDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final trimmed = raw.trim();
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) return iso.toUtc();

  final m = _rfc822.firstMatch(trimmed);
  if (m == null) return null;
  final month = _months[m.group(2)!.toLowerCase()];
  if (month == null) return null;
  var year = int.parse(m.group(3)!);
  if (year < 100) year += year < 50 ? 2000 : 1900;
  final day = int.parse(m.group(1)!);
  final hour = int.parse(m.group(4)!);
  final minute = int.parse(m.group(5)!);
  final second = m.group(6) == null ? 0 : int.parse(m.group(6)!);
  if (day < 1 || day > 31 || hour > 23 || minute > 59 || second > 59) {
    return null;
  }
  final offset = _zoneOffsetMinutes(m.group(7) ?? 'GMT');
  if (offset == null) return null;
  final local = DateTime.utc(year, month, day, hour, minute, second);
  if (local.year != year || local.month != month || local.day != day ||
      local.hour != hour || local.minute != minute || local.second != second) {
    return null;
  }
  return local.subtract(Duration(minutes: offset));
}
