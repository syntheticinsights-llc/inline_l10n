import 'dart:io';

import 'package:inline_l10n/src/generator/flutter_l10n_runner.dart';
import 'package:inline_l10n/src/generator/l10n_pipeline.dart';
import 'package:inline_l10n/src/generator/models.dart';
import 'package:inline_l10n/src/generator/watch_session.dart';

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
