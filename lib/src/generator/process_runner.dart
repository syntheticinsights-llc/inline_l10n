import 'dart:io';

import 'models.dart';

/// Exit code [runProcess] reports when it gave up waiting.
const _killed = -1;

/// How long a killed process gets to close its output pipes before the run
/// gives up on draining them: its own children may still hold them open.
const _drainTimeout = Duration(seconds: 5);

/// Starts [executable], forwards its output to this process's, and returns its
/// exit code.
///
/// A child that outlives [timeout] is killed and reported as a [L10nException].
/// Waiting for it instead is what leaves a watch session alive but silent: one
/// stuck command holds the cycle open and every later change is dropped without
/// a word.
///
/// The kill walks the child's own children first (`pkill -P`): `flutter` and
/// `sh -c` each start a child that inherits the output pipes, so killing only
/// the process we hold would leave those pipes open and draining them would
/// wait for a process nobody is waiting for. The drain keeps its own bound
/// ([_drainTimeout]) for the children `pkill` cannot reach.
Future<int> runProcess(
  String executable,
  List<String> arguments, {
  required String description,
  required Duration timeout,
}) async {
  final Process process;
  try {
    process = await Process.start(
      executable,
      arguments,
      runInShell: Platform.isWindows,
    );
  } on ProcessException catch (error) {
    throw L10nException('Failed to run $description: ${error.message}');
  }

  final output = Future.wait([
    process.stdout.forEach(stdout.add),
    process.stderr.forEach(stderr.add),
  ]);

  final exitCode = await process.exitCode.timeout(
    timeout,
    onTimeout: () {
      _killWithChildren(process);
      return _killed;
    },
  );
  await output.timeout(_drainTimeout, onTimeout: () => const <void>[]);

  if (exitCode == _killed) {
    throw L10nException('$description timed out after ${timeout.inSeconds}s.');
  }

  return exitCode;
}

void _killWithChildren(Process process) {
  if (!Platform.isWindows) {
    Process.runSync('pkill', ['-TERM', '-P', '${process.pid}']);
  }
  process.kill(ProcessSignal.sigkill);
}
