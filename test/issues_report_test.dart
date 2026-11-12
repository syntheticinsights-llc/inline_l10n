import 'dart:convert';
import 'dart:io';

import 'package:inline_l10n/src/generator/issues_report.dart';
import 'package:inline_l10n/src/generator/models.dart';
import 'package:test/test.dart';

const _issue = L10nIssue(
  filePath: 'lib/a.dart',
  line: 3,
  kind: L10nIssueKind.unrecognizedReceiver,
  code: "'Title'.inline('Title')",
);

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('inline_l10n_'));
  tearDown(() => temp.deleteSync(recursive: true));

  test('warns once per change and when the issues are resolved', () {
    final report = IssuesReport();

    expect(report.updateWarnings([]), isNull);
    expect(report.updateWarnings([_issue]), contains('lib/a.dart:3'));
    expect(report.updateWarnings([_issue]), isNull);
    expect(report.updateWarnings([]), 'All inline calls are extracted again.');
    expect(report.updateWarnings([]), isNull);
  });

  test('writes the status, errors, and warnings, creating the directory', () {
    final file = File('${temp.path}/nested/issues.json');
    final report = IssuesReport(file: file)
      ..updateWarnings([_issue])
      ..recordRun(RunStatus.failed, [
        const L10nException('Duplicate', locations: ['lib/a.dart:3']),
        const L10nException('flutter gen-l10n failed'),
      ]);

    final failed = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(DateTime.parse(failed['lastRun']! as String).isUtc, isTrue);
    expect(failed, containsPair('status', 'failed'));
    expect(failed['errors'], [
      {
        'message': 'Duplicate',
        'locations': ['lib/a.dart:3'],
      },
      {'message': 'flutter gen-l10n failed'},
    ]);
    expect(failed['warnings'], [
      {
        'file': 'lib/a.dart',
        'line': 3,
        'issue': 'unrecognized-receiver',
        'code': "'Title'.inline('Title')",
      },
    ]);

    report
      ..updateWarnings([])
      ..recordRun(RunStatus.ok);

    final ok = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(ok, containsPair('status', 'ok'));
    expect(ok['errors'], isEmpty);
    expect(ok['warnings'], isEmpty);
  });
}
