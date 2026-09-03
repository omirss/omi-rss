import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor openAppConnection() {
  return WebDatabase('rss_reader');
}
