import 'package:flutter_test/flutter_test.dart';
import 'package:rss_glassmorphism_reader/core/models/feed.dart';
import 'package:rss_glassmorphism_reader/core/models/folder.dart';
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

  test('B17: export nests feeds by folder membership, not categoryId',
      () async {
    final folder = Folder(id: 'folder-1', name: 'Tech');
    final feeds = [
      Feed(
        id: 'feed-member',
        url: 'https://member.example/feed.xml',
        title: 'Member',
        // categoryId null: membership still comes from the join table.
        categoryId: null,
      ),
      Feed(
        id: 'feed-loose',
        url: 'https://loose.example/feed.xml',
        title: 'Loose',
        // categoryId pointing at a folder id must NOT imply membership.
        categoryId: 'folder-1',
      ),
    ];

    final opml = await OPMLService().exportOPML(
      feeds: feeds,
      folders: [folder],
      folderFeedIds: {'folder-1': ['feed-member']},
    );

    expect(opml, contains('xmlUrl="https://member.example/feed.xml"'));
    final folderStart = opml.indexOf('text="Tech"');
    final memberPos = opml.indexOf('https://member.example/feed.xml');
    final loosePos = opml.indexOf('https://loose.example/feed.xml');
    final folderEnd = opml.indexOf('</outline>', folderStart);
    expect(folderStart, greaterThanOrEqualTo(0));
    // The member feed is nested inside the folder outline...
    expect(memberPos, greaterThan(folderStart));
    expect(memberPos, lessThan(folderEnd),
        reason: 'join-table member must be nested under its folder');
    // ...while the loose feed is emitted at the body level.
    expect(loosePos, lessThan(folderStart),
        reason: 'categoryId must not be treated as folder membership');
  });

  test('B18: exporting corrupted duplicate-id folder data terminates',
      () async {
    // Two folders sharing one id where the duplicate is its own parent:
    // without an ancestry guard the builder would recurse forever.
    final root = Folder(id: 'x', name: 'Root');
    final evil = Folder(id: 'x', name: 'Evil', parentId: 'x');

    final opml = await OPMLService().exportOPML(
      feeds: const [],
      folders: [root, evil],
      folderFeedIds: const {},
    );

    expect(opml, contains('text="Root"'));
    // The cyclic duplicate is skipped instead of recursing.
    expect(opml, isNot(contains('text="Evil"')));
  });
}
