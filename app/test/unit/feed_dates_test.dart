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
}
