import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/services/opml_service.dart';

void main() {
  test('A17: type="rss" outline without xmlUrl is skipped, not fatal',
      () async {
    const opml = '''
<opml version="2.0"><body>
<outline type="rss" text="Valid One" xmlUrl="https://one.example/feed.xml"/>
<outline type="rss" text="Broken (no url)"/>
<outline type="rss" text="Valid Two" xmlUrl="https://two.example/feed.xml"/>
</body></opml>
''';

    final result = await OPMLService().importOPML(opml);

    expect(result.feeds, hasLength(2));
    expect(
      result.feeds.map((f) => f.xmlUrl),
      ['https://one.example/feed.xml', 'https://two.example/feed.xml'],
    );
    expect(result.errors, hasLength(1));
    expect(result.errors.first, contains('Broken (no url)'));
  });

  test('A18: rapidly created folders get unique ids', () async {
    final outlines = List.generate(
      100,
      (i) => '<outline text="Folder $i"><outline type="rss" '
          'text="Feed $i" xmlUrl="https://f$i.example/feed.xml"/></outline>',
    ).join();
    final opml = '<opml version="2.0"><body>$outlines</body></opml>';

    final result = await OPMLService().importOPML(opml);

    expect(result.folders, hasLength(100));
    final ids = result.folders.map((f) => f.id).toSet();
    expect(ids, hasLength(100), reason: 'folder ids must be unique');
  });

  test('nested folder structure is preserved', () async {
    const opml = '''
<opml version="2.0"><body>
<outline text="Root">
<outline text="Child">
<outline type="rss" text="Deep" xmlUrl="https://deep.example/feed.xml"/>
</outline>
</outline>
</body></opml>
''';

    final result = await OPMLService().importOPML(opml);

    expect(result.folders, hasLength(2));
    final child = result.folders.firstWhere((f) => f.name == 'Child');
    final root = result.folders.firstWhere((f) => f.name == 'Root');
    expect(child.parentId, root.id);
    expect(result.feeds.single.folderId, child.id);
  });
}
