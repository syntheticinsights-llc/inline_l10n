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

    expect(report.update([]), isNull);
    expect(report.update([_issue]), contains('lib/a.dart:3'));
    expect(report.update([_issue]), isNull);
    expect(report.update([]), 'All inline calls are extracted again.');
    expect(report.update([]), isNull);
  });

  test('writes the current issues to the file, creating its directory', () {
    final file = File('${temp.path}/nested/issues.json');
    final report = IssuesReport(file: file)..update([_issue]);

    expect(jsonDecode(file.readAsStringSync()), [
      {
        'file': 'lib/a.dart',
        'line': 3,
        'issue': 'unrecognized-receiver',
        'code': "'Title'.inline('Title')",
      },
    ]);

    report.update([]);

    expect(jsonDecode(file.readAsStringSync()), isEmpty);
  });
}
