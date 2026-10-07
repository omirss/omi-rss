import 'package:drift/drift.dart';
// The frozen client retains the legacy WebDatabase backend.
// ignore: experimental_member_use
import 'package:drift/web.dart';

QueryExecutor openAppConnection() {
  return WebDatabase('rss_reader');
}
