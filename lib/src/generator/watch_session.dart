import 'dart:async';
import 'dart:io';

import 'package:watcher/watcher.dart';

import 'flutter_l10n_runner.dart';
import 'l10n_config.dart';
import 'l10n_pipeline.dart';
import 'models.dart';

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
