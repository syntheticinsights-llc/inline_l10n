import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// How the last generation run ended, as written to the issues file.
enum RunStatus {
  /// The ARB files and the generated code are up to date.
  ok,

  /// The run stopped on an error, so the ARB files may be out of date.
  failed,

  /// Some source files cannot be parsed, so the ARB files are left alone
  /// until they can; otherwise their entries would be dropped.
  waiting,
}

/// Reports the outcome of every generation run: the errors that stopped it
/// and the `.inline(...)` calls that were not extracted.
///
/// Unextracted calls compile and run, since `inline()` returns its receiver,
/// so without a report they silently miss their translations. They are
/// warnings rather than errors: one stray call should not stop the ARB files
/// from updating for everything else.
///
/// The optional [file] (`--issues-file`) holds the state of the last run as
/// JSON, in the spirit of gen-l10n's `untranslated-messages-file`, so tools,
/// coding agents, and reviewers can see it without reading the generator
/// output, which in watch mode often runs in a terminal nobody looks at:
///
/// ```json
/// {
///   "lastRun": "2026-11-12T06:22:37.000Z",
///   "status": "failed",
///   "errors": [
///     {
///       "message": "Duplicate l10n key \"title\" with different content. ...",
///       "locations": ["lib/a.dart:3", "lib/b.dart:7"]
///     }
///   ],
///   "warnings": [
///     {"file": "lib/a.dart", "line": 3, "issue": "...", "code": "..."}
///   ]
/// }
/// ```
///
/// `lastRun` (UTC) changes on every run, so a reader can tell whether the
/// generator has processed an edit yet, and a generator that is not running
/// at all from one that ran and found nothing wrong. `locations` is left out
/// for errors that do not come from the sources, such as a failing
/// `flutter gen-l10n`. The warnings survive a run that fails before
/// extraction: they are the ones from the last extraction.
class IssuesReport {
  IssuesReport({this.file});

  final File? file;

  /// The message last returned by [updateWarnings]; the empty string stands
  /// for no issues, so a clean first run prints nothing.
  var _lastMessage = '';

  var _warnings = const <L10nIssue>[];

  /// Remembers [issues] for the next [recordRun] and returns the warning to
  /// print, or `null` when it is the same as last time, so watch mode does
  /// not repeat it on every change.
  String? updateWarnings(List<L10nIssue> issues) {
    _warnings = issues;

    final message = _messageFor(issues);
    if (message == _lastMessage) {
      return null;
    }

    final resolved = message.isEmpty;
    _lastMessage = message;
    return resolved ? 'All inline calls are extracted again.' : message;
  }

  /// Writes the outcome of the run that just ended to [file].
  void recordRun(RunStatus status, [List<L10nException> errors = const []]) {
    final file = this.file;
    if (file == null) {
      return;
    }

    const encoder = JsonEncoder.withIndent('  ');
    final report = {
      'lastRun': DateTime.now().toUtc().toIso8601String(),
      'status': status.name,
      'errors': [for (final error in errors) error.toJson()],
      'warnings': [for (final issue in _warnings) issue.toJson()],
    };
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${encoder.convert(report)}\n');
  }

  static String _messageFor(List<L10nIssue> issues) {
    if (issues.isEmpty) {
      return '';
    }

    final callWord = issues.length == 1 ? 'call was' : 'calls were';
    return [
      'Warning: ${issues.length} .inline(...) $callWord not extracted:',
      for (final issue in issues) '  $issue',
    ].join('\n');
  }
}
