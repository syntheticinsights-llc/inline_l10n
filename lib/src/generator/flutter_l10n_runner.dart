import 'dart:io';

import 'models.dart';
import 'process_runner.dart';

class FlutterL10nRunner {
  const FlutterL10nRunner._();

  /// How long `flutter gen-l10n` may run before it is killed. Without it a
  /// generation that never ends holds the watch session's cycle open forever.
  static const timeout = Duration(minutes: 2);

  static Future<void> run() async {
    stdout.writeln('Running flutter gen-l10n...');
    final exitCode = await runProcess(
      'flutter',
      const ['gen-l10n'],
      description: 'flutter gen-l10n',
      timeout: timeout,
    );
    if (exitCode != 0) {
      throw L10nException('flutter gen-l10n failed with exit code $exitCode');
    }

    stdout.writeln('flutter gen-l10n completed.');
  }
}
