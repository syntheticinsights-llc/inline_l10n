// ignore_for_file: prefer_immutable_collections
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:watcher/watcher.dart';
import 'package:yaml/yaml.dart';

// =============================================================================
// Configuration
// =============================================================================

class L10nConfig {
  const L10nConfig._();

  static const generatedFileSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gen.dart',
  ];
  static const defaultL10nDir = 'lib/resources/l10n';
  static const defaultTemplateFile = 'app_en.arb';
  static const sourceDir = 'lib';
  static const watchDebounce = Duration(milliseconds: 200);
}

// =============================================================================
// Data Models
// =============================================================================

class L10nException implements Exception {
  const L10nException(this.message);

  final String message;

  @override
  String toString() => message;
}

class L10nEntry {
  const L10nEntry({
    required this.text,
    required this.line,
    required this.filePath,
    this.placeholders,
  });

  final String filePath;
  final int line;
  final Map<String, dynamic>? placeholders;
  final String text;
}

class GenerationResult {
  const GenerationResult({
    required this.filesScanned,
    required this.filesWithEntries,
    required this.uniqueEntries,
    required this.totalEntries,
  });

  final int filesScanned;
  final int filesWithEntries;
  final int totalEntries;
  final int uniqueEntries;
}

class ExtractionResult {
  const ExtractionResult({
    required this.entries,
    required this.generationResult,
  });

  final Map<String, L10nEntry> entries;
  final GenerationResult generationResult;
}

class AlignmentResult {
  const AlignmentResult({
    required this.totalLocaleFiles,
    required this.updatedLocaleFiles,
  });

  final int totalLocaleFiles;
  final int updatedLocaleFiles;
}

class ArbWriteResult {
  const ArbWriteResult({
    required this.templateChanged,
    required this.alignment,
  });

  final AlignmentResult alignment;
  final bool templateChanged;

  bool get changed => templateChanged || alignment.updatedLocaleFiles > 0;
}

// =============================================================================
// L10n Sources
// =============================================================================

class L10nSources {
  L10nSources._(this.sourceBase, this.roots);

  factory L10nSources.resolve() {
    final workspace = _findWorkspace();
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
        if (root.existsSync()) Directory(_trimTrailingSeparator(root.path)),
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

  final _fileEntries = <String, Map<String, L10nEntry>>{};

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
    _fileEntries.clear();
    for (final file in collectDartFiles()) {
      refresh(file.path);
    }
  }

  void refresh(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      _fileEntries.remove(path);
      return;
    }

    try {
      _fileEntries[path] = _extractFileEntries(file, sourceBase);
    } on ArgumentError catch (error) {
      throw L10nException('Failed to parse $path\n${error.message}');
    } on FileSystemException catch (error) {
      if (!file.existsSync()) {
        _fileEntries.remove(path);
        return;
      }
      throw L10nException('Failed to read $path\n${error.message}');
    }
  }

  ExtractionResult merge() {
    final mergedEntries = <String, L10nEntry>{};
    final paths = _fileEntries.keys.toList()..sort();

    var filesWithEntries = 0;
    var totalEntries = 0;

    for (final path in paths) {
      final entries = _fileEntries[path]!;
      if (entries.isEmpty) {
        continue;
      }

      filesWithEntries++;
      totalEntries += entries.length;
      _mergeEntries(mergedEntries, entries);
    }

    return ExtractionResult(
      entries: mergedEntries,
      generationResult: GenerationResult(
        filesScanned: _fileEntries.length,
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

  static Map<String, L10nEntry> _extractFileEntries(
    File file,
    Directory sourceBase,
  ) {
    final content = file.readAsStringSync();
    final lineStarts = _buildLineStartOffsets(content);
    final parseResult = parseString(content: content);
    final relativePath = _relativePath(file, sourceBase);
    final visitor = L10nAutoVisitor(relativePath, lineStarts);
    parseResult.unit.accept(visitor);

    return visitor.entries;
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

  static ({Directory root, List<String> members})? _findWorkspace() {
    var directory = Directory.current.absolute;

    while (true) {
      final pubspec = File.fromUri(directory.uri.resolve('pubspec.yaml'));
      if (pubspec.existsSync()) {
        final document = loadYaml(pubspec.readAsStringSync());
        if (document is YamlMap && document.containsKey('workspace')) {
          final members = document['workspace'];
          if (members is! YamlList ||
              members.any((member) => member is! String)) {
            throw L10nException('Invalid workspace list in ${pubspec.path}');
          }
          return (root: directory, members: members.cast<String>().toList());
        }
      }

      final parent = directory.parent;
      if (parent.path == directory.path) {
        return null;
      }
      directory = parent;
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

String _trimTrailingSeparator(String path) =>
    path.length > 1 && path.endsWith(Platform.pathSeparator)
    ? path.substring(0, path.length - 1)
    : path;

// =============================================================================
// ARB Writer
// =============================================================================

class AppEnWriter {
  const AppEnWriter._();

  static bool write(
    Directory l10nRoot,
    Map<String, L10nEntry> entries, {
    String templateFileName = L10nConfig.defaultTemplateFile,
  }) {
    final appEnData = <String, dynamic>{'@@locale': 'en'};

    final keys = entries.keys.toList()..sort();

    for (final key in keys) {
      final entry = entries[key];
      if (entry == null) {
        continue;
      }

      appEnData[key] = entry.text;
      final metadata = <String, dynamic>{
        'description': 'Defined in ${entry.filePath}',
      };
      if (entry.placeholders != null) {
        metadata['placeholders'] = entry.placeholders;
      }
      appEnData['@$key'] = metadata;
    }

    final appEnFile = File(
      '${l10nRoot.path}${Platform.pathSeparator}$templateFileName',
    );
    const encoder = JsonEncoder.withIndent('  ');
    final encoded = '${encoder.convert(appEnData)}\n';
    if (appEnFile.existsSync() && appEnFile.readAsStringSync() == encoded) {
      return false;
    }

    appEnFile.writeAsStringSync(encoded);
    return true;
  }
}

// =============================================================================
// Locale ARB Aligner
// =============================================================================

class LocaleArbAligner {
  const LocaleArbAligner._();

  static AlignmentResult align(
    Directory l10nRoot, {
    String templateFileName = L10nConfig.defaultTemplateFile,
  }) {
    final sourceFile = File(
      '${l10nRoot.path}${Platform.pathSeparator}$templateFileName',
    );

    if (!sourceFile.existsSync()) {
      throw L10nException('Source ARB not found: ${sourceFile.path}');
    }

    final sourceData = _readJsonMap(sourceFile);
    final sourceKeys = sourceData.keys.toList(growable: false);

    final otherArbFiles =
        l10nRoot
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.arb') && file.path != sourceFile.path,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    var updatedCount = 0;

    for (final file in otherArbFiles) {
      final targetData = _readJsonMap(file);
      final cleaned = _buildCleanedMap(sourceKeys, targetData, file);
      final encoded = _encodeJson(cleaned);
      final current = file.readAsStringSync();

      if (encoded != current) {
        file.writeAsStringSync(encoded);
        updatedCount++;
      }
    }

    return AlignmentResult(
      totalLocaleFiles: otherArbFiles.length,
      updatedLocaleFiles: updatedCount,
    );
  }

  static Map<String, dynamic> _buildCleanedMap(
    List<String> sourceKeys,
    Map<String, dynamic> targetData,
    File targetFile,
  ) {
    final output = <String, dynamic>{};
    final locale = _readLocale(targetData, targetFile);
    if (locale != null) {
      output['@@locale'] = locale;
    }

    for (final key in sourceKeys) {
      if (key == '@@locale') {
        continue;
      }
      if (!targetData.containsKey(key)) {
        continue;
      }
      output[key] = targetData[key];
    }

    return output;
  }

  static String _encodeJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');

    return '${encoder.convert(data)}\n';
  }

  static Map<String, dynamic> _readJsonMap(File file) {
    try {
      final content = file.readAsStringSync();
      final decoded = jsonDecode(content);

      if (decoded is! Map<String, dynamic>) {
        throw L10nException(
          'Invalid ARB format (not a JSON object): ${file.path}',
        );
      }

      return decoded;
    } on FormatException catch (e) {
      throw L10nException('Failed to parse JSON: ${file.path}\n$e');
    }
  }

  static String? _readLocale(Map<String, dynamic> targetData, File targetFile) {
    final locale = targetData['@@locale'];
    if (locale is String && locale.isNotEmpty) {
      return locale;
    }

    final fileName = targetFile.uri.pathSegments.last;
    final match = RegExp(r'^app_(.+)\.arb$').firstMatch(fileName);

    return match?.group(1);
  }
}

// =============================================================================
// Flutter L10n Runner
// =============================================================================

class FlutterL10nRunner {
  const FlutterL10nRunner._();

  static Future<void> run() async {
    stdout.writeln('Running flutter gen-l10n...');
    final Process process;
    try {
      process = await Process.start(
        'flutter',
        const ['gen-l10n'],
        runInShell: Platform.isWindows,
      );
    } on ProcessException catch (error) {
      throw L10nException('Failed to run flutter gen-l10n: ${error.message}');
    }
    final outputFuture = Future.wait([
      process.stdout.forEach(stdout.add),
      process.stderr.forEach(stderr.add),
    ]);
    final exitCode = await process.exitCode;
    await outputFuture;

    if (exitCode != 0) {
      throw L10nException('flutter gen-l10n failed with exit code $exitCode');
    }

    stdout.writeln('flutter gen-l10n completed.');
  }
}

// =============================================================================
// Pipeline
// =============================================================================

class L10nPipeline {
  L10nPipeline._(this.sources, this.l10nRoot, this.templateFileName);

  factory L10nPipeline.resolve() {
    final l10nRoot = Directory(
      _trimTrailingSeparator(
        Directory.fromUri(Directory.current.uri.resolve(_resolveL10nDir())).path,
      ),
    );
    if (!l10nRoot.existsSync()) {
      throw L10nException('Localization directory not found: ${l10nRoot.path}');
    }

    return L10nPipeline._(
      L10nSources.resolve(),
      l10nRoot,
      _resolveTemplateArbFile(),
    );
  }

  final Directory l10nRoot;
  final L10nSources sources;
  final String templateFileName;

  bool isArbFile(String path) =>
      path.endsWith('.arb') &&
      path.startsWith('${l10nRoot.path}${Platform.pathSeparator}') &&
      !path
          .substring(l10nRoot.path.length + 1)
          .contains(Platform.pathSeparator);

  Map<String, String> readArbSnapshot() => {
    for (final file in l10nRoot.listSync().whereType<File>())
      if (file.path.endsWith('.arb')) file.path: file.readAsStringSync(),
  };

  ArbWriteResult writeArbs(ExtractionResult extraction) => ArbWriteResult(
    templateChanged: AppEnWriter.write(
      l10nRoot,
      extraction.entries,
      templateFileName: templateFileName,
    ),
    alignment: LocaleArbAligner.align(
      l10nRoot,
      templateFileName: templateFileName,
    ),
  );
}

// =============================================================================
// Watch Session
// =============================================================================

class L10nWatchSession {
  L10nWatchSession(this.pipeline);

  final L10nPipeline pipeline;

  final _brokenSources = <String>{};
  final _changedSources = <String>{};
  var _arbChanged = false;
  var _arbSnapshot = <String, String>{};
  Timer? _debounce;
  var _genL10nPending = false;
  var _lastCycleFailed = false;
  var _running = false;

  Future<void> start() async {
    final watchedDirectories = [
      ...pipeline.sources.roots,
      if (!pipeline.sources.roots.any(
        (root) => pipeline.l10nRoot.path.startsWith(
          '${root.path}${Platform.pathSeparator}',
        ),
      ))
        pipeline.l10nRoot,
    ];
    final watchers = [
      for (final directory in watchedDirectories)
        DirectoryWatcher(directory.path),
    ];
    final subscriptions = [
      for (final watcher in watchers)
        watcher.events.listen(
          _onEvent,
          onError: (Object error) => stderr.writeln('Watcher error: $error'),
        ),
    ];
    await Future.wait(watchers.map((watcher) => watcher.ready));

    _running = true;
    try {
      for (final file in pipeline.sources.collectDartFiles()) {
        _refreshSource(file.path);
      }
      await _runCycle(forceGenL10n: true);
    } finally {
      _running = false;
    }

    stdout.writeln(
      'Watching ${watchedDirectories.length} director'
      '${watchedDirectories.length == 1 ? 'y' : 'ies'} for changes. '
      'Press Ctrl+C to stop.',
    );
    _scheduleIfPending();

    await ProcessSignal.sigint.watch().first;
    _debounce?.cancel();
    await Future.wait(subscriptions.map((subscription) => subscription.cancel()));
    stdout.writeln('\nStopped watching.');
  }

  void _onEvent(WatchEvent event) {
    final path = event.path;
    if (pipeline.sources.tracks(path)) {
      _changedSources.add(path);
    } else if (pipeline.isArbFile(path) &&
        _readOrNull(path) != _arbSnapshot[path]) {
      _arbChanged = true;
    } else {
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(L10nConfig.watchDebounce, _flush);
  }

  Future<void> _flush() async {
    if (_running) {
      return;
    }

    _running = true;
    try {
      final changedSources = _changedSources.toList()..sort();
      _changedSources.clear();
      final arbChanged = _arbChanged;
      _arbChanged = false;

      changedSources.forEach(_refreshSource);
      await _runCycle(forceGenL10n: arbChanged);
    } finally {
      _running = false;
      _scheduleIfPending();
    }
  }

  void _refreshSource(String path) {
    try {
      pipeline.sources.refresh(path);
      _brokenSources.remove(path);
    } on L10nException catch (error) {
      _brokenSources.add(path);
      stderr.writeln('[${_timestamp()}] $error');
    }
  }

  Future<void> _runCycle({required bool forceGenL10n}) async {
    _genL10nPending |= forceGenL10n;
    if (_brokenSources.isNotEmpty) {
      stderr.writeln(
        '[${_timestamp()}] Skipped ARB update until '
        '${_brokenSources.length} source file(s) can be parsed.',
      );
      _lastCycleFailed = true;
      return;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final extraction = pipeline.sources.merge();
      final writeResult = pipeline.writeArbs(extraction);
      _refreshArbSnapshot();
      _genL10nPending |= writeResult.changed;
      if (!_genL10nPending) {
        if (_lastCycleFailed) {
          stdout.writeln(
            '[${_timestamp()}] Recovered, no localization changes.',
          );
        }
        _lastCycleFailed = false;
        return;
      }

      await FlutterL10nRunner.run();
      _genL10nPending = false;
      _lastCycleFailed = false;
      stdout.writeln(
        '[${_timestamp()}] ${extraction.generationResult.uniqueEntries} '
        'entries, ${pipeline.templateFileName} '
        '${writeResult.templateChanged ? 'updated' : 'unchanged'}, '
        'aligned ${writeResult.alignment.updatedLocaleFiles} of '
        '${writeResult.alignment.totalLocaleFiles} locale ARB file(s) '
        '(${stopwatch.elapsedMilliseconds}ms).',
      );
    } on L10nException catch (error) {
      _reportCycleFailure(error);
    } on FileSystemException catch (error) {
      _reportCycleFailure(error);
    }
  }

  void _reportCycleFailure(Object error) {
    stderr.writeln('[${_timestamp()}] $error');
    _lastCycleFailed = true;
    _refreshArbSnapshot();
  }

  void _refreshArbSnapshot() {
    try {
      _arbSnapshot = pipeline.readArbSnapshot();
    } on FileSystemException catch (error) {
      stderr.writeln('[${_timestamp()}] $error');
    }
  }

  void _scheduleIfPending() {
    if (_changedSources.isNotEmpty || _arbChanged) {
      _debounce?.cancel();
      _debounce = Timer(L10nConfig.watchDebounce, _flush);
    }
  }

  static String? _readOrNull(String path) {
    final file = File(path);
    return file.existsSync() ? file.readAsStringSync() : null;
  }

  static String _timestamp() {
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${twoDigits(now.hour)}:${twoDigits(now.minute)}:'
        '${twoDigits(now.second)}';
  }
}

// =============================================================================
// AST Visitor
// =============================================================================

class L10nAutoVisitor extends RecursiveAstVisitor<void> {
  L10nAutoVisitor(this.filePath, this.lineStarts);

  final entries = <String, L10nEntry>{};

  final String filePath;
  final List<int> lineStarts;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'inline') {
      _processInlineCall(node);
    }
    super.visitMethodInvocation(node);
  }

  String? _extractKey(Expression? target) {
    if (target is PrefixedIdentifier) {
      // Pattern: l10n.key
      if (target.prefix.name == 'l10n') {
        return target.identifier.name;
      }
    } else if (target is PropertyAccess) {
      // Patterns: l10n.something.key, AppLocalizations.of(context).key
      if (_isL10nAccess(target.target)) {
        return target.propertyName.name;
      }
    } else if (target is MethodInvocation) {
      // Pattern: l10n.method(...).inline(...)
      if (_isL10nAccess(target.target)) {
        return target.methodName.name;
      }
    }

    return null;
  }

  static Map<String, dynamic>? _extractMapLiteral(Expression expr) {
    if (expr is! SetOrMapLiteral) {
      return null;
    }

    final result = <String, dynamic>{};

    for (final element in expr.elements) {
      if (element is MapLiteralEntry) {
        final keyExpr = element.key;
        final valueExpr = element.value;

        if (keyExpr is! SimpleStringLiteral) {
          continue;
        }

        final key = keyExpr.value;

        Object? value;

        if (valueExpr is SimpleStringLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is SetOrMapLiteral) {
          value = _extractMapLiteral(valueExpr);
        } else if (valueExpr is IntegerLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is BooleanLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is PrefixedIdentifier ||
            valueExpr is SimpleIdentifier) {
          value = valueExpr.toSource();
        }

        if (value != null) {
          result[key] = value;
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  Map<String, dynamic>? _extractPlaceholders(NodeList<Argument> args) {
    for (final arg in args) {
      if (arg is NamedArgument && arg.name.lexeme == 'placeholders') {
        return _extractMapLiteral(arg.argumentExpression);
      }
    }

    return null;
  }

  String? _extractStringValue(Expression expr) {
    if (expr is SimpleStringLiteral) {
      return expr.value;
    } else if (expr is AdjacentStrings) {
      final buffer = StringBuffer();

      for (final string in expr.strings) {
        if (string is SimpleStringLiteral) {
          buffer.write(string.value);
        }
      }

      return buffer.toString();
    }

    return null;
  }

  static bool _isL10nAccess(Expression? expr) {
    if (expr == null) {
      return false;
    }

    // Pattern 1: l10n variable
    if (expr is SimpleIdentifier && expr.name == 'l10n') {
      return true;
    }

    // Pattern 2: AppLocalizations.of(context)
    if (expr is MethodInvocation) {
      final target = expr.target;

      if (target is SimpleIdentifier &&
          target.name == 'AppLocalizations' &&
          expr.methodName.name == 'of') {
        return true;
      }
    }

    // Pattern 3: Nested property access
    if (expr is PropertyAccess) {
      return _isL10nAccess(expr.target);
    }

    return false;
  }

  static int _lineNumberAt(int offset, List<int> lineStarts) {
    var low = 0;
    var high = lineStarts.length - 1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final start = lineStarts[mid];

      if (start <= offset) {
        if (mid == lineStarts.length - 1 || lineStarts[mid + 1] > offset) {
          return mid + 1;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return 1;
  }

  void _processInlineCall(MethodInvocation node) {
    final key = _extractKey(node.target);
    if (key == null) {
      return;
    }

    final args = node.argumentList.arguments;
    if (args.isEmpty) {
      return;
    }

    final stringValue = _extractStringValue(args.first.argumentExpression);
    if (stringValue == null) {
      return;
    }

    final line = _lineNumberAt(node.offset, lineStarts);
    final placeholders = _extractPlaceholders(args);

    final existing = entries[key];

    if (existing != null && existing.text != stringValue) {
      throw L10nException(
        '''Duplicate l10n key "$key" with different content.\n  First defined at: ${existing.filePath}:${existing.line}\n  Conflict at: $filePath:$line''',
      );
    }

    entries[key] = L10nEntry(
      text: stringValue,
      line: line,
      filePath: filePath,
      placeholders: placeholders,
    );
  }
}

// =============================================================================
// Main Entry Point
// =============================================================================

String _resolveL10nDir() {
  final l10nConfigFile = File('l10n.yaml');
  if (l10nConfigFile.existsSync()) {
    for (final rawLine in l10nConfigFile.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.startsWith('arb-dir:')) {
        final value = line.substring('arb-dir:'.length).trim();
        final unquoted = value
            .replaceAll(RegExp(r"""^['"]|['"]$"""), '')
            .trim();
        if (unquoted.isNotEmpty) {
          return unquoted;
        }
      }
    }
  }

  return L10nConfig.defaultL10nDir;
}

String _resolveTemplateArbFile() {
  final l10nConfigFile = File('l10n.yaml');
  if (l10nConfigFile.existsSync()) {
    for (final rawLine in l10nConfigFile.readAsLinesSync()) {
      final line = rawLine.trim();
      if (line.startsWith('template-arb-file:')) {
        final value = line.substring('template-arb-file:'.length).trim();
        final unquoted = value
            .replaceAll(RegExp(r"""^['"]|['"]$"""), '')
            .trim();
        if (unquoted.isNotEmpty) {
          return unquoted;
        }
      }
    }
  }

  return L10nConfig.defaultTemplateFile;
}

Future<void> main(List<String> arguments) async {
  final unknownArguments = arguments.where(
    (argument) => argument != '--watch' && argument != '-w',
  );
  if (unknownArguments.isNotEmpty) {
    stderr
      ..writeln('Unknown argument(s): ${unknownArguments.join(' ')}')
      ..writeln('Usage: dart run inline_l10n:gen_l10n [--watch | -w]');
    exit(64);
  }

  try {
    final pipeline = L10nPipeline.resolve();
    if (arguments.isNotEmpty) {
      await L10nWatchSession(pipeline).start();
      exit(0);
    }
    await _generateOnce(pipeline);
  } on L10nException catch (error) {
    stderr.writeln(error);
    exit(1);
  }
}

Future<void> _generateOnce(L10nPipeline pipeline) async {
  final mainStopwatch = Stopwatch()..start();

  // Step 1: Extract inline l10n entries from Dart files.
  final extractStopwatch = Stopwatch()..start();
  pipeline.sources.scanAll();
  final extractionResult = pipeline.sources.merge();
  extractStopwatch.stop();

  // Step 2: Write app_en.arb and align locale ARB files to it.
  final writeStopwatch = Stopwatch()..start();
  final writeResult = pipeline.writeArbs(extractionResult);
  writeStopwatch.stop();

  // Step 3: Run flutter gen-l10n
  final flutterStopwatch = Stopwatch()..start();
  await FlutterL10nRunner.run();
  flutterStopwatch.stop();

  mainStopwatch.stop();

  _printResults(
    extractionResult.generationResult,
    writeResult,
    pipeline.templateFileName,
  );

  _printTimingSummary(
    extractStopwatch,
    writeStopwatch,
    flutterStopwatch,
    mainStopwatch,
    pipeline.templateFileName,
  );
}

void _printResults(
  GenerationResult result,
  ArbWriteResult writeResult,
  String templateFileName,
) {
  stdout.writeln('Scanned ${result.filesScanned} Dart file(s).');

  if (result.filesWithEntries > 0) {
    final totalWord = result.totalEntries == 1 ? 'entry' : 'entries';
    final uniqueWord = result.uniqueEntries == 1 ? 'entry' : 'entries';
    stdout.writeln(
      '''Found ${result.totalEntries} $totalWord across ${result.filesWithEntries} file(s), ${result.uniqueEntries} unique $uniqueWord.''',
    );
  } else {
    stdout.writeln('No inline l10n entries found.');
  }

  final entryWord = result.uniqueEntries == 1 ? 'entry' : 'entries';
  final alignment = writeResult.alignment;

  stdout
    ..writeln(
      writeResult.templateChanged
          ? 'Wrote ${result.uniqueEntries} $entryWord to $templateFileName.'
          : '$templateFileName is up to date.',
    )
    ..writeln(
      '''Aligned ${alignment.updatedLocaleFiles} of ${alignment.totalLocaleFiles} locale ARB file(s).''',
    );
}

void _printTimingSummary(
  Stopwatch extractStopwatch,
  Stopwatch writeStopwatch,
  Stopwatch flutterStopwatch,
  Stopwatch mainStopwatch,
  String templateFileName,
) {
  stdout
    ..writeln('\n⏱️  Timing Summary:')
    ..writeln(
      '''   AST parsing & extraction: ${extractStopwatch.elapsedMilliseconds}ms''',
    )
    ..writeln(
      '   $templateFileName write & locale ARB align: '
      '${writeStopwatch.elapsedMilliseconds}ms',
    )
    ..writeln('   flutter gen-l10n: ${flutterStopwatch.elapsedMilliseconds}ms')
    ..writeln('   Total: ${mainStopwatch.elapsedMilliseconds}ms');
}
