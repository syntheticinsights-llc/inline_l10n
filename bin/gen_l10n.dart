// ignore_for_file: prefer_immutable_collections
import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
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
}

// =============================================================================
// Data Models
// =============================================================================

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

// =============================================================================
// L10n Extractor
// =============================================================================

class L10nExtractor {
  const L10nExtractor._();

  static ExtractionResult extract() {
    final workspace = _findWorkspace();
    final sourceBase = workspace?.root ?? Directory(L10nConfig.sourceDir);
    final sourceRoots = workspace == null
        ? [sourceBase]
        : [
            Directory.fromUri(workspace.root.uri.resolve('lib/')),
            for (final member in workspace.members)
              Directory.fromUri(workspace.root.uri.resolve('$member/lib/')),
          ];
    final existingRoots = sourceRoots.where((root) => root.existsSync()).toList();
    if (existingRoots.isEmpty) {
      throw StateError('No lib directories found for localization extraction.');
    }

    final dartFiles = [
      for (final root in existingRoots) ..._collectDartFiles(root),
    ]..sort((a, b) => a.path.compareTo(b.path));
    final mergedEntries = <String, L10nEntry>{};

    var filesWithEntries = 0;
    var totalEntries = 0;

    for (final file in dartFiles) {
      final entries = _extractFileEntries(file, sourceBase);
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
        filesScanned: dartFiles.length,
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

  static List<File> _collectDartFiles(Directory sourceRoot) =>
      sourceRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.dart') && !_isGeneratedDartFile(file.path),
          )
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

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
        throw StateError(
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
          if (members is! YamlList || members.any((member) => member is! String)) {
            throw FormatException('Invalid workspace list in ${pubspec.path}');
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
      throw StateError('Source file outside localization root: $path');
    }
    return path.substring(prefix.length).replaceAll(Platform.pathSeparator, '/');
  }
}

// =============================================================================
// ARB Writer
// =============================================================================

class AppEnWriter {
  const AppEnWriter._();

  static int write(
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
    appEnFile.writeAsStringSync('${encoder.convert(appEnData)}\n');

    return entries.length;
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
      stderr.writeln('Source ARB not found: ${sourceFile.path}');
      exit(1);
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
        stderr.writeln('Invalid ARB format (not a JSON object): ${file.path}');
        exit(1);
      }

      return decoded;
    } on FormatException catch (e) {
      stderr.writeln('Failed to parse JSON: ${file.path}\n$e');
      exit(1);
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
    final process = await Process.start('flutter', const ['gen-l10n']);
    final stdoutFuture = stdout.addStream(process.stdout);
    final stderrFuture = stderr.addStream(process.stderr);
    final exitCode = await process.exitCode;
    await stdoutFuture;
    await stderrFuture;

    if (exitCode != 0) {
      stderr.writeln('flutter gen-l10n failed with exit code $exitCode');
      exit(exitCode);
    }

    stdout.writeln('flutter gen-l10n completed.');
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
      throw StateError(
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

Future<void> main() async {
  final mainStopwatch = Stopwatch()..start();

  // Step 1: Extract inline l10n entries from Dart files.
  final extractStopwatch = Stopwatch()..start();
  final extractionResult = L10nExtractor.extract();
  extractStopwatch.stop();

  // Step 2: Write app_en.arb directly from extracted entries.
  final l10nDir = _resolveL10nDir();
  final templateFileName = _resolveTemplateArbFile();
  final l10nRoot = Directory(l10nDir);

  if (!l10nRoot.existsSync()) {
    stderr.writeln('Localization directory not found: ${l10nRoot.path}');
    exit(1);
  }

  final writeStopwatch = Stopwatch()..start();
  final writtenCount = AppEnWriter.write(
    l10nRoot,
    extractionResult.entries,
    templateFileName: templateFileName,
  );
  writeStopwatch.stop();

  // Step 3: Align locale ARB files to app_en.arb.
  final alignStopwatch = Stopwatch()..start();
  final alignmentResult = LocaleArbAligner.align(
    l10nRoot,
    templateFileName: templateFileName,
  );
  alignStopwatch.stop();

  // Step 4: Run flutter gen-l10n
  final flutterStopwatch = Stopwatch()..start();
  await FlutterL10nRunner.run();
  flutterStopwatch.stop();

  mainStopwatch.stop();

  // Print results
  _printResults(
    extractionResult.generationResult,
    writtenCount,
    alignmentResult,
    templateFileName,
  );

  _printTimingSummary(
    extractStopwatch,
    writeStopwatch,
    alignStopwatch,
    flutterStopwatch,
    mainStopwatch,
    templateFileName,
  );
}

void _printResults(
  GenerationResult result,
  int writtenCount,
  AlignmentResult alignmentResult,
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

  final entryWord = writtenCount == 1 ? 'entry' : 'entries';

  stdout
    ..writeln('Wrote $writtenCount $entryWord to $templateFileName.')
    ..writeln(
      '''Aligned ${alignmentResult.updatedLocaleFiles} of ${alignmentResult.totalLocaleFiles} locale ARB file(s).''',
    );
}

void _printTimingSummary(
  Stopwatch extractStopwatch,
  Stopwatch writeStopwatch,
  Stopwatch alignStopwatch,
  Stopwatch flutterStopwatch,
  Stopwatch mainStopwatch,
  String templateFileName,
) {
  stdout
    ..writeln('\n⏱️  Timing Summary:')
    ..writeln(
      '''   AST parsing & extraction: ${extractStopwatch.elapsedMilliseconds}ms''',
    )
    ..writeln('   $templateFileName write: ${writeStopwatch.elapsedMilliseconds}ms')
    ..writeln('   locale ARB align: ${alignStopwatch.elapsedMilliseconds}ms')
    ..writeln('   flutter gen-l10n: ${flutterStopwatch.elapsedMilliseconds}ms')
    ..writeln('   Total: ${mainStopwatch.elapsedMilliseconds}ms');
}
