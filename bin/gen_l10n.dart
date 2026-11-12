import 'dart:io';

import 'package:args/args.dart';
import 'package:inline_l10n/src/generator/flutter_l10n_runner.dart';
import 'package:inline_l10n/src/generator/issues_report.dart';
import 'package:inline_l10n/src/generator/l10n_pipeline.dart';
import 'package:inline_l10n/src/generator/models.dart';
import 'package:inline_l10n/src/generator/post_gen_command.dart';
import 'package:inline_l10n/src/generator/watch_session.dart';

Future<void> main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'watch',
      abbr: 'w',
      negatable: false,
      help: 'Keep watching sources and ARB files after the first generation.',
    )
    ..addOption(
      'issues-file',
      valueHelp: 'path',
      help:
          'Also write .inline(...) calls that were not extracted to this '
          'JSON file.',
    )
    ..addOption(
      'post-gen',
      valueHelp: 'command',
      help:
          'Run this shell command after every generation, such as a script '
          'that derives native resources from the ARB files.',
    );

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr
      ..writeln(error.message)
      ..writeln('Usage: dart run inline_l10n:gen_l10n [options]')
      ..writeln(parser.usage);
    exit(64);
  }

  final issuesPath = options.option('issues-file');
  final issuesReport = IssuesReport(
    file: issuesPath == null ? null : File(issuesPath),
  );

  final postGenCommand = options.option('post-gen');
  final postGen = postGenCommand == null
      ? null
      : PostGenCommand(postGenCommand);

  try {
    final pipeline = L10nPipeline.resolve();
    if (options.flag('watch')) {
      await L10nWatchSession(pipeline, issuesReport, postGen).start();
      exit(0);
    }
    await _generateOnce(pipeline, issuesReport);
    await postGen?.runOrThrow();
    issuesReport.recordRun(RunStatus.ok);
  } on L10nException catch (error) {
    _fail(issuesReport, error);
  } on FileSystemException catch (error) {
    _fail(issuesReport, L10nException(error.toString()));
  }
}

Never _fail(IssuesReport issuesReport, L10nException error) {
  stderr.writeln(error);
  issuesReport.recordRun(RunStatus.failed, [error]);
  exit(1);
}

Future<void> _generateOnce(
  L10nPipeline pipeline,
  IssuesReport issuesReport,
) async {
  final mainStopwatch = Stopwatch()..start();

  // Step 1: Extract inline l10n entries from Dart files.
  final extractStopwatch = Stopwatch()..start();
  pipeline.sources.scanAll();
  final extractionResult = pipeline.sources.merge();
  extractStopwatch.stop();
  final issuesWarning = issuesReport.updateWarnings(extractionResult.issues);
  if (issuesWarning != null) {
    stderr.writeln('$issuesWarning\n');
  }

  // Step 2: Write app_en.arb and align locale ARB files to it.
  final writeStopwatch = Stopwatch()..start();
  final writeResult = pipeline.writeArbs(extractionResult);
  final platformChanges = pipeline.syncPlatformLocales();
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
  for (final path in platformChanges) {
    stdout.writeln('Updated the declared locales in $path.');
  }

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
