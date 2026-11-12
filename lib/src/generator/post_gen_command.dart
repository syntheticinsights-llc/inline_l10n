import 'dart:io';

import 'models.dart';
import 'process_runner.dart';

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

  /// How long the command may run before it is killed, for the same reason as
  /// `FlutterL10nRunner.timeout`: a command that never ends must not hold the
  /// watch session's cycle open.
  static const timeout = Duration(minutes: 2);

  final String command;

  /// Runs [command] and returns its exit code.
  Future<int> run() async {
    stdout.writeln('Running $command...');

    return runProcess(
      Platform.isWindows ? 'cmd' : 'sh',
      [if (Platform.isWindows) '/c' else '-c', command],
      description: command,
      timeout: timeout,
    );
  }

  /// Runs [command] and throws when it fails.
  Future<void> runOrThrow() async {
    final exitCode = await run();
    if (exitCode != 0) {
      throw L10nException('$command failed with exit code $exitCode');
    }
  }
}
