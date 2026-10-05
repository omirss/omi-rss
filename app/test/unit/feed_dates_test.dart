import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/parsers/feed_dates.dart';

void main() {
  test('parses RFC 822 date with numeric timezone offset', () {
    final result = parseFeedDate('Sun, 04 Oct 2026 16:00:00 -0700');
    expect(result, DateTime.utc(2026, 10, 4, 23, 0, 0));
  });

  test('parses RFC 822 date with GMT zone', () {
    final result = parseFeedDate('04 Oct 2026 23:00:00 GMT');
    expect(result, DateTime.utc(2026, 10, 4, 23, 0, 0));
  });

  test('parses RFC 822 date with named US zone', () {
    final result = parseFeedDate('Mon, 05 Oct 2026 01:00:00 PST');
    expect(result, DateTime.utc(2026, 10, 5, 9, 0, 0));
  });

  test('parses RFC 822 date with positive offset', () {
    final result = parseFeedDate('Tue, 3 Nov 2026 08:15:30 +0530');
    expect(result, DateTime.utc(2026, 11, 3, 2, 45, 30));
  });

  test('parses RFC 3339 timestamps', () {
    expect(
      parseFeedDate('2026-10-04T16:00:00-07:00'),
      DateTime.utc(2026, 10, 4, 23, 0, 0),
    );
    expect(
      parseFeedDate('2026-10-04T23:00:00Z'),
      DateTime.utc(2026, 10, 4, 23, 0, 0),
    );
  });

  test('malformed values return null', () {
    expect(parseFeedDate('not a date at all'), isNull);
    expect(parseFeedDate(''), isNull);
    expect(parseFeedDate(null), isNull);
    expect(parseFeedDate('99 Zzz 2026 25:99'), isNull);
  });

  test('B02: unknown timezone names are rejected, not treated as UTC', () {
    expect(parseFeedDate('04 Oct 2026 12:00:00 XYZ'), isNull);
    expect(parseFeedDate('Sun, 04 Oct 2026 12:00:00 NOTAZONE'), isNull);
  });

  test('B02: out-of-range numeric offsets are rejected', () {
    expect(parseFeedDate('04 Oct 2026 12:00:00 +2460'), isNull);
    expect(parseFeedDate('04 Oct 2026 12:00:00 -1261'), isNull);
    // Valid boundary offsets still parse.
    expect(parseFeedDate('04 Oct 2026 12:00:00 -1200'),
        DateTime.utc(2026, 10, 5, 0, 0, 0));
  });

  test('B03: trailing garbage is rejected', () {
    expect(parseFeedDate('04 Oct 2026 12:00 GMT garbage'), isNull);
    expect(parseFeedDate('Sun, 04 Oct 2026 12:00:00 GMT extra words'), isNull);
    // Leading/trailing whitespace alone remains acceptable.
    expect(parseFeedDate('  04 Oct 2026 12:00:00 GMT  '),
        DateTime.utc(2026, 10, 4, 12, 0, 0));
  });

  test('B04: impossible dates are rejected, not normalized', () {
    expect(parseFeedDate('31 Feb 2026 12:00:00 GMT'), isNull);
    expect(parseFeedDate('04 Oct 2026 25:00:00 GMT'), isNull);
    expect(parseFeedDate('04 Oct 2026 12:99:00 GMT'), isNull);
    expect(parseFeedDate('04 Oct 2026 12:00:99 GMT'), isNull);
    expect(parseFeedDate('00 Oct 2026 12:00:00 GMT'), isNull);
    // A real leap day still parses.
    expect(parseFeedDate('29 Feb 2024 12:00:00 GMT'),
        DateTime.utc(2024, 2, 29, 12, 0, 0));
  });
}
