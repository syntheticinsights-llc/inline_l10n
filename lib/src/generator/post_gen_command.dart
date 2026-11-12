import 'dart:io';

import 'models.dart';

/// A shell command (`--post-gen`) to run after every generation, for the
/// project's own steps that derive from the ARB files, such as native string
/// resources or checks of store listings.
///
/// It runs once `flutter gen-l10n` has finished: after a single run, and in
/// watch mode after every cycle that ran `flutter gen-l10n`, so the project's
/// files follow the ARB files without anyone remembering to run them. It runs
/// in the working directory of the generator, and its output goes straight to
/// the terminal.
///
/// A failing command fails a single run, so a check in CI stops the build,
/// but in watch mode it is only reported: the ARB files and the generated code
/// are up to date either way.
class PostGenCommand {
  const PostGenCommand(this.command);

  final String command;

  /// Runs [command] and returns its exit code.
  Future<int> run() async {
    stdout.writeln('Running $command...');
    final Process process;
    try {
      process = await Process.start(
        Platform.isWindows ? 'cmd' : 'sh',
        [if (Platform.isWindows) '/c' else '-c', command],
      );
    } on ProcessException catch (error) {
      throw L10nException('Failed to run $command: ${error.message}');
    }
    final outputFuture = Future.wait([
      process.stdout.forEach(stdout.add),
      process.stderr.forEach(stderr.add),
    ]);
    final exitCode = await process.exitCode;
    await outputFuture;

    return exitCode;
  }

  /// Runs [command] and throws when it fails.
  Future<void> runOrThrow() async {
    final exitCode = await run();
    if (exitCode != 0) {
      throw L10nException('$command failed with exit code $exitCode');
    }
  }
}
