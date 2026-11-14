import 'dart:io';

import 'package:inline_l10n/src/generator/l10n_sources.dart';
import 'package:test/test.dart';

void main() {
  late Directory workspace;
  late Directory previousCurrent;

  setUp(() {
    previousCurrent = Directory.current;
    // Resolved, because the sources see the real path of a symlinked temp dir.
    workspace = Directory(
      Directory.systemTemp
          .createTempSync('inline_l10n_sources_')
          .resolveSymbolicLinksSync(),
    );
    Directory.current = workspace;
  });

  tearDown(() {
    Directory.current = previousCurrent;
    workspace.deleteSync(recursive: true);
  });

  void writeWorkspace(List<String> members) => File(
    '${workspace.path}/pubspec.yaml',
  ).writeAsStringSync(
    'name: root\nworkspace:\n${[for (final m in members) '  - $m'].join('\n')}\n',
  );

  File writeSource(String member) =>
      File('${workspace.path}/$member/lib/$member.dart')
        ..createSync(recursive: true)
        ..writeAsStringSync('final $member = 1;\n');

  String rootOf(String member) =>
      Directory('${workspace.path}/$member/lib').absolute.path;

  test('picks up a member added to the workspace after resolving', () {
    writeWorkspace(['a']);
    writeSource('a');
    final sources = L10nSources.resolve();
    final added = writeSource('b');

    expect(sources.tracks(added.absolute.path), isFalse);

    writeWorkspace(['a', 'b']);
    final changes = sources.reconcileRoots();

    expect([for (final root in changes.added) root.path], [rootOf('b')]);
    expect(changes.removed, isEmpty);
    expect(sources.tracks(added.absolute.path), isTrue);
  });

  test('picks up a member whose lib directory appears later', () {
    writeWorkspace(['a', 'b']);
    writeSource('a');
    final sources = L10nSources.resolve();

    expect(sources.reconcileRoots().added, isEmpty);

    writeSource('b');

    expect(
      [for (final root in sources.reconcileRoots().added) root.path],
      [rootOf('b')],
    );
  });

  test('drops a removed member and the scans of its files', () {
    writeWorkspace(['a', 'b']);
    writeSource('a');
    final removed = writeSource('b');
    final sources = L10nSources.resolve()..scanAll();

    expect(sources.merge().generationResult.filesScanned, 2);

    writeWorkspace(['a']);
    final changes = sources.reconcileRoots();

    expect([for (final root in changes.removed) root.path], [rootOf('b')]);
    expect(sources.tracks(removed.absolute.path), isFalse);
    expect(sources.merge().generationResult.filesScanned, 1);
  });

  test('keeps its roots while the workspace resolves to none', () {
    writeWorkspace(['a']);
    writeSource('a');
    final sources = L10nSources.resolve();
    writeWorkspace(['missing']);

    final changes = sources.reconcileRoots();

    expect(changes.added, isEmpty);
    expect(changes.removed, isEmpty);
    expect([for (final root in sources.roots) root.path], [rootOf('a')]);
  });
}
