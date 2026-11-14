import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';

import 'inline_call_visitor.dart';
import 'l10n_config.dart';
import 'models.dart';
import 'workspace.dart';

typedef _FileScan = ({Map<String, L10nEntry> entries, List<L10nIssue> issues});

/// The Dart sources that `.inline(...)` calls are extracted from: the `lib/`
/// directory of the workspace root and of every workspace member, or of the
/// current package outside a workspace.
///
/// The roots follow the workspace: [reconcileRoots] re-reads its members, so a
/// long watch session picks up a package added after it started. Without that,
/// the calls in such a package are never seen, and every key that moved into it
/// reads as deleted, which drops the key's translations from every locale.
class L10nSources {
  L10nSources._(this.sourceBase, this._roots);

  factory L10nSources.resolve() {
    final workspace = findWorkspace();
    final roots = _resolveRoots(workspace);
    if (roots.isEmpty) {
      throw const L10nException(
        'No lib directories found for localization extraction.',
      );
    }

    return L10nSources._(
      workspace?.root ?? Directory(L10nConfig.sourceDir),
      roots,
    );
  }

  final Directory sourceBase;
  List<Directory> _roots;

  final _files = <String, _FileScan>{};

  List<Directory> get roots => List.unmodifiable(_roots);

  List<File> collectDartFiles() => [
    for (final root in _roots) ...collectDartFilesIn(root),
  ]..sort((a, b) => a.path.compareTo(b.path));

  List<File> collectDartFilesIn(Directory root) => root
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') && !_isGeneratedDartFile(file.path),
      )
      .toList();

  bool tracks(String path) =>
      path.endsWith('.dart') &&
      !_isGeneratedDartFile(path) &&
      _roots.any((root) => _isUnder(path, root));

  /// Re-reads the workspace members and returns the roots that appeared and
  /// the ones that went away; the scans of a removed root's files are dropped.
  /// An added root is only listed: its files are scanned by whoever refreshes
  /// them, as with any other change.
  ///
  /// A workspace that resolves to no roots at all, as while its `pubspec.yaml`
  /// is half edited, changes nothing.
  ({List<Directory> added, List<Directory> removed}) reconcileRoots() {
    final resolved = _resolveRoots(findWorkspace());
    if (resolved.isEmpty) {
      return (added: const [], removed: const []);
    }

    final resolvedPaths = {for (final root in resolved) root.path};
    final currentPaths = {for (final root in _roots) root.path};
    final added = [
      for (final root in resolved)
        if (!currentPaths.contains(root.path)) root,
    ];
    final removed = [
      for (final root in _roots)
        if (!resolvedPaths.contains(root.path)) root,
    ];

    for (final root in removed) {
      _files.removeWhere((path, _) => _isUnder(path, root));
    }
    _roots = resolved;

    return (added: added, removed: removed);
  }

  void scanAll() {
    _files.clear();
    for (final file in collectDartFiles()) {
      refresh(file.path);
    }
  }

  void refresh(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      _files.remove(path);
      return;
    }

    try {
      _files[path] = _scanFile(file, sourceBase);
    } on ArgumentError catch (error) {
      throw L10nException(
        'Failed to parse $path\n${error.message}',
        locations: [_relativePath(file, sourceBase)],
      );
    } on FileSystemException catch (error) {
      if (!file.existsSync()) {
        _files.remove(path);
        return;
      }
      throw L10nException(
        'Failed to read $path\n${error.message}',
        locations: [_relativePath(file, sourceBase)],
      );
    }
  }

  ExtractionResult merge() {
    final mergedEntries = <String, L10nEntry>{};
    final issues = <L10nIssue>[];
    final paths = _files.keys.toList()..sort();

    var filesWithEntries = 0;
    var totalEntries = 0;

    for (final path in paths) {
      final file = _files[path]!;
      issues.addAll(file.issues);
      final entries = file.entries;
      if (entries.isEmpty) {
        continue;
      }

      filesWithEntries++;
      totalEntries += entries.length;
      _mergeEntries(mergedEntries, entries);
    }

    return ExtractionResult(
      entries: mergedEntries,
      issues: issues,
      generationResult: GenerationResult(
        filesScanned: _files.length,
        filesWithEntries: filesWithEntries,
        uniqueEntries: mergedEntries.length,
        totalEntries: totalEntries,
      ),
    );
  }

  static List<int> _buildLineStartOffsets(String content) {
    final starts = <int>[0];

    for (var i = 0; i < content.length; i++) {
      if (content.codeUnitAt(i) == 10) {
        starts.add(i + 1);
      }
    }

    return starts;
  }

  static _FileScan _scanFile(
    File file,
    Directory sourceBase,
  ) {
    final content = file.readAsStringSync();
    final lineStarts = _buildLineStartOffsets(content);
    final parseResult = parseString(content: content);
    final relativePath = _relativePath(file, sourceBase);
    final visitor = L10nAutoVisitor(relativePath, lineStarts);
    parseResult.unit.accept(visitor);

    return (entries: visitor.entries, issues: visitor.issues);
  }

  static List<Directory> _resolveRoots(
    ({Directory root, List<String> members})? workspace,
  ) {
    final candidates = workspace == null
        ? [Directory(L10nConfig.sourceDir).absolute]
        : [
            Directory.fromUri(workspace.root.uri.resolve('lib/')),
            for (final member in workspace.members)
              Directory.fromUri(workspace.root.uri.resolve('$member/lib/')),
          ];

    return [
      for (final root in candidates)
        if (root.existsSync()) Directory(trimTrailingSeparator(root.path)),
    ];
  }

  static bool _isUnder(String path, Directory root) =>
      path.startsWith('${root.path}${Platform.pathSeparator}');

  static bool _isGeneratedDartFile(String path) =>
      L10nConfig.generatedFileSuffixes.any(path.endsWith);

  static void _mergeEntries(
    Map<String, L10nEntry> mergedEntries,
    Map<String, L10nEntry> fileEntries,
  ) {
    for (final MapEntry(:key, :value) in fileEntries.entries) {
      final existing = mergedEntries[key];

      if (existing != null && existing.text != value.text) {
        throw L10nException.duplicateKey(key, existing, value);
      }

      // Keep the latest metadata when text is identical.
      mergedEntries[key] = value;
    }
  }

  static String _relativePath(File file, Directory sourceBase) {
    final path = file.absolute.path;
    final prefix = '${sourceBase.absolute.path}${Platform.pathSeparator}';
    if (!path.startsWith(prefix)) {
      throw L10nException('Source file outside localization root: $path');
    }
    return path
        .substring(prefix.length)
        .replaceAll(Platform.pathSeparator, '/');
  }
}
