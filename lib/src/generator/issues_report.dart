import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// Reports `.inline(...)` calls that were not extracted, without failing the
/// generation.
///
/// Such calls compile and run, since `inline()` returns its receiver, so
/// without a report they silently miss their translations. They are warnings
/// rather than errors: one stray call should not stop the ARB files from
/// updating for everything else.
///
/// The optional [file] (`--issues-file`) holds the current list as JSON, in
/// the spirit of gen-l10n's `untranslated-messages-file`, so tools and
/// reviewers can see it without reading the generator output. It always
/// exists after a run and holds `[]` when there are no issues.
class IssuesReport {
  IssuesReport({this.file});

  final File? file;

  /// The message last returned by [update]; the empty string stands for no
  /// issues, so a clean first run prints nothing.
  var _lastMessage = '';

  /// Writes [issues] to [file] and returns the warning to print, or `null`
  /// when it is the same as last time, so watch mode does not repeat it on
  /// every change.
  String? update(List<L10nIssue> issues) {
    _writeFile(issues);

    final message = _messageFor(issues);
    if (message == _lastMessage) {
      return null;
    }

    final resolved = message.isEmpty;
    _lastMessage = message;
    return resolved ? 'All inline calls are extracted again.' : message;
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

  void _writeFile(List<L10nIssue> issues) {
    final file = this.file;
    if (file == null) {
      return;
    }

    const encoder = JsonEncoder.withIndent('  ');
    final encoded =
        '${encoder.convert([for (final issue in issues) issue.toJson()])}\n';
    if (file.existsSync() && file.readAsStringSync() == encoded) {
      return;
    }

    file.parent.createSync(recursive: true);
    file.writeAsStringSync(encoded);
  }
}
