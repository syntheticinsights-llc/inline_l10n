import 'dart:async';
import 'dart:io';

import 'package:watcher/watcher.dart';

import 'flutter_l10n_runner.dart';
import 'issues_report.dart';
import 'l10n_config.dart';
import 'l10n_pipeline.dart';
import 'models.dart';
import 'post_gen_command.dart';

/// Regenerates on every change until the user presses Ctrl+C.
///
/// Changes come from [PollingDirectoryWatcher] rather than from native change
/// notifications: a native watcher that drops an event is never re-subscribed,
/// and the session cannot notice that it went deaf — the process stays alive and
/// idle and every later edit is ignored in silence. Polling makes the file
/// system the source of truth once per interval instead, and reports deletions
/// the same way.
///
/// The same interval re-reads the workspace members (see
/// [L10nSources.reconcileRoots]), so a package added while the session runs is
/// watched and scanned, and a removed one stops counting.
class L10nWatchSession {
  L10nWatchSession(this.pipeline, this.issuesReport, [this.postGen]);

  final IssuesReport issuesReport;
  final L10nPipeline pipeline;
  final PostGenCommand? postGen;

  final _brokenSources = <String, L10nException>{};
  final _changedSources = <String>{};
  final _rootSubscriptions = <String, StreamSubscription<WatchEvent>>{};
  var _arbChanged = false;
  var _arbSnapshot = <String, String>{};
  Timer? _debounce;
  var _genL10nPending = false;
  var _lastCycleFailed = false;
  var _reconcilingRoots = false;
  var _rootsChanged = false;
  var _running = false;

  Future<void> start() async {
    final roots = pipeline.sources.roots;
    for (final root in roots) {
      _rootSubscriptions[root.path] = await _watch(root);
    }
    final l10nSubscription =
        roots.any(
          (root) => pipeline.l10nRoot.path.startsWith(
            '${root.path}${Platform.pathSeparator}',
          ),
        )
        ? null
        : await _watch(pipeline.l10nRoot);
    final rootPoll = Timer.periodic(
      L10nConfig.watchPollInterval,
      (_) => _reconcileRoots(),
    );

    _running = true;
    try {
      for (final file in pipeline.sources.collectDartFiles()) {
        _refreshSource(file.path);
      }
      await _runCycle(forceGenL10n: true);
    } finally {
      _running = false;
    }

    final watchedCount =
        _rootSubscriptions.length + (l10nSubscription == null ? 0 : 1);
    stdout.writeln(
      'Watching $watchedCount director'
      '${watchedCount == 1 ? 'y' : 'ies'} for changes. '
      'Press Ctrl+C to stop.',
    );
    _scheduleIfPending();

    await ProcessSignal.sigint.watch().first;
    rootPoll.cancel();
    _debounce?.cancel();
    await Future.wait([
      for (final subscription in _rootSubscriptions.values)
        subscription.cancel(),
      ?l10nSubscription?.cancel(),
    ]);
    stdout.writeln('\nStopped watching.');
  }

  Future<StreamSubscription<WatchEvent>> _watch(Directory directory) async {
    // Built directly: the DirectoryWatcher factory ignores pollingDelay where
    // native watching is supported, which is every platform we run on.
    final watcher = PollingDirectoryWatcher(
      directory.path,
      pollingDelay: L10nConfig.watchPollInterval,
    );
    final subscription = watcher.events.listen(
      _onEvent,
      onError: (Object error) => stderr.writeln('Watcher error: $error'),
    );
    await watcher.ready;
    return subscription;
  }

  Future<void> _reconcileRoots() async {
    if (_reconcilingRoots) {
      return;
    }

    _reconcilingRoots = true;
    try {
      final (:added, :removed) = pipeline.sources.reconcileRoots();
      if (added.isEmpty && removed.isEmpty) {
        return;
      }

      for (final root in removed) {
        await _rootSubscriptions.remove(root.path)?.cancel();
      }
      for (final root in added) {
        _rootSubscriptions[root.path] = await _watch(root);
        _changedSources.addAll([
          for (final file in pipeline.sources.collectDartFilesIn(root))
            file.path,
        ]);
      }
      stdout.writeln(
        '[${_timestamp()}] Workspace changed: watching ${added.length} more '
        'and ${removed.length} fewer package source director'
        '${added.length + removed.length == 1 ? 'y' : 'ies'}.',
      );
      _rootsChanged = true;
      _scheduleIfPending();
    } on Exception catch (error) {
      // A pubspec.yaml saved half edited cannot be read; the next poll retries.
      stderr.writeln('[${_timestamp()}] Could not re-read the workspace: $error');
    } finally {
      _reconcilingRoots = false;
    }
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
      _rootsChanged = false;

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
      _brokenSources[path] = error;
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
      issuesReport.recordRun(RunStatus.waiting, [..._brokenSources.values]);
      return;
    }

    final stopwatch = Stopwatch()..start();
    try {
      final extraction = pipeline.sources.merge();
      _reportIssues(extraction.issues);
      final writeResult = pipeline.writeArbs(extraction);
      for (final path in pipeline.syncPlatformLocales()) {
        stdout.writeln(
          '[${_timestamp()}] Updated the declared locales in $path.',
        );
      }
      _refreshArbSnapshot();
      _genL10nPending |= writeResult.changed;
      if (!_genL10nPending) {
        if (_lastCycleFailed) {
          stdout.writeln(
            '[${_timestamp()}] Recovered, no localization changes.',
          );
        }
        _lastCycleFailed = false;
        issuesReport.recordRun(RunStatus.ok);
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
      final postGenError = await _runPostGen();
      if (postGenError == null) {
        issuesReport.recordRun(RunStatus.ok);
      } else {
        issuesReport.recordRun(RunStatus.failed, [postGenError]);
      }
    } on L10nException catch (error) {
      _reportCycleFailure(error);
    } on FileSystemException catch (error) {
      _reportCycleFailure(L10nException(error.toString()));
    }
  }

  /// Runs [postGen] and returns its failure without failing the cycle: the
  /// ARB files and the generated code are already up to date.
  Future<L10nException?> _runPostGen() async {
    final postGen = this.postGen;
    if (postGen == null) {
      return null;
    }
    final exitCode = await postGen.run();
    if (exitCode == 0) {
      return null;
    }
    final error = L10nException(
      '${postGen.command} failed with exit code $exitCode.',
    );
    stderr.writeln('[${_timestamp()}] $error');
    return error;
  }

  void _reportIssues(List<L10nIssue> issues) {
    final warning = issuesReport.updateWarnings(issues);
    if (warning != null) {
      stderr.writeln('[${_timestamp()}] $warning');
    }
  }

  void _reportCycleFailure(L10nException error) {
    stderr.writeln('[${_timestamp()}] $error');
    _lastCycleFailed = true;
    issuesReport.recordRun(RunStatus.failed, [error]);
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
    if (_changedSources.isNotEmpty || _arbChanged || _rootsChanged) {
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
