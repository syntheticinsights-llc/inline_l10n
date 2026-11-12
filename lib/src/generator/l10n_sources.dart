import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';

import 'inline_call_visitor.dart';
import 'l10n_config.dart';
import 'models.dart';
import 'workspace.dart';

typedef _FileScan = ({Map<String, L10nEntry> entries, List<L10nIssue> issues});

class L10nSources {
  L10nSources._(this.sourceBase, this.roots);

  factory L10nSources.resolve() {
    final workspace = findWorkspace();
    final sourceBase = workspace?.root ?? Directory(L10nConfig.sourceDir);
    final sourceRoots = workspace == null
        ? [Directory(L10nConfig.sourceDir).absolute]
        : [
            Directory.fromUri(workspace.root.uri.resolve('lib/')),
            for (final member in workspace.members)
              Directory.fromUri(workspace.root.uri.resolve('$member/lib/')),
          ];
    final existingRoots = [
      for (final root in sourceRoots)
        if (root.existsSync()) Directory(trimTrailingSeparator(root.path)),
    ];
    if (existingRoots.isEmpty) {
      throw const L10nException(
        'No lib directories found for localization extraction.',
      );
    }

    return L10nSources._(sourceBase, existingRoots);
  }

  final Directory sourceBase;
  final List<Directory> roots;

  final _files = <String, _FileScan>{};

  List<File> collectDartFiles() => [
    for (final root in roots) ..._collectDartFiles(root),
  ]..sort((a, b) => a.path.compareTo(b.path));

  bool tracks(String path) =>
      path.endsWith('.dart') &&
      !_isGeneratedDartFile(path) &&
      roots.any(
        (root) => path.startsWith('${root.path}${Platform.pathSeparator}'),
      );

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
      throw L10nException('Failed to parse $path\n${error.message}');
    } on FileSystemException catch (error) {
      if (!file.existsSync()) {
        _files.remove(path);
        return;
      }
      throw L10nException('Failed to read $path\n${error.message}');
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

  static List<File> _collectDartFiles(Directory sourceRoot) => sourceRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (file) =>
            file.path.endsWith('.dart') && !_isGeneratedDartFile(file.path),
      )
      .toList();

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

  static bool _isGeneratedDartFile(String path) =>
      L10nConfig.generatedFileSuffixes.any(path.endsWith);

  static void _mergeEntries(
    Map<String, L10nEntry> mergedEntries,
    Map<String, L10nEntry> fileEntries,
  ) {
    for (final MapEntry(:key, :value) in fileEntries.entries) {
      final existing = mergedEntries[key];

      if (existing != null && existing.text != value.text) {
        throw L10nException(
          '''Duplicate l10n key "$key" with different content.\n  First defined at: ${existing.filePath}:${existing.line}\n  Conflict at: ${value.filePath}:${value.line}''',
        );
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
