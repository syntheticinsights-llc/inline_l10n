import 'dart:io';

import 'models.dart';

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
