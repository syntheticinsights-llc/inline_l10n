import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:inline_l10n/src/generator/inline_call_visitor.dart';
import 'package:inline_l10n/src/generator/models.dart';
import 'package:test/test.dart';

L10nAutoVisitor _scan(String body) {
  final content = 'void f() {\n$body\n}\n';
  final lineStarts = [
    0,
    for (var i = 0; i < content.length; i++)
      if (content.codeUnitAt(i) == 10) i + 1,
  ];
  final visitor = L10nAutoVisitor('lib/a.dart', lineStarts);
  parseString(content: content).unit.accept(visitor);
  return visitor;
}

void main() {
  group('recognized markers', () {
    for (final code in [
      "l10n.title.inline('Title');",
      "l10n.greeting(name).inline('Hello {name}');",
      "AppLocalizations.of(context).title.inline('Title');",
      "AppLocalizations.of(context).title.inline('Ti' 'tle');",
    ]) {
      test(code, () {
        final visitor = _scan(code);

        expect(visitor.entries, hasLength(1));
        expect(visitor.issues, isEmpty);
      });
    }
  });

  group('reports a call whose receiver is not a key', () {
    for (final code in [
      "'Title'.inline('Title');",
      "loc.title.inline('Title');",
      "title.inline('Title');",
    ]) {
      test(code, () {
        final visitor = _scan(code);

        expect(visitor.entries, isEmpty);
        expect(visitor.issues.single.kind, L10nIssueKind.unrecognizedReceiver);
      });
    }
  });

  group('reports a key whose English text is not a literal', () {
    for (final code in [
      'l10n.title.inline(text);',
      r"l10n.title.inline('Hello $name');",
    ]) {
      test(code, () {
        final visitor = _scan(code);

        expect(visitor.entries, isEmpty);
        expect(visitor.issues.single.kind, L10nIssueKind.nonLiteralText);
      });
    }
  });

  group('ignores calls that are not localization markers', () {
    for (final code in ['style.inline(span);', 'widget.inline();']) {
      test(code, () {
        final visitor = _scan(code);

        expect(visitor.entries, isEmpty);
        expect(visitor.issues, isEmpty);
      });
    }
  });

  test('records where the issue is', () {
    final issue = _scan("\n'Title'.inline('Title');").issues.single;

    expect(issue.filePath, 'lib/a.dart');
    expect(issue.line, 3);
    expect(issue.code, "'Title'.inline('Title')");
  });
}
