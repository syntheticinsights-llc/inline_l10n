import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'models.dart';

class L10nAutoVisitor extends RecursiveAstVisitor<void> {
  L10nAutoVisitor(this.filePath, this.lineStarts);

  final entries = <String, L10nEntry>{};
  final issues = <L10nIssue>[];

  final String filePath;
  final List<int> lineStarts;

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (node.methodName.name == 'inline') {
      _processInlineCall(node);
    }
    super.visitMethodInvocation(node);
  }

  String? _extractKey(Expression? target) {
    if (target is PrefixedIdentifier) {
      // Pattern: l10n.key
      if (target.prefix.name == 'l10n') {
        return target.identifier.name;
      }
    } else if (target is PropertyAccess) {
      // Patterns: l10n.something.key, AppLocalizations.of(context).key
      if (_isL10nAccess(target.target)) {
        return target.propertyName.name;
      }
    } else if (target is MethodInvocation) {
      // Pattern: l10n.method(...).inline(...)
      if (_isL10nAccess(target.target)) {
        return target.methodName.name;
      }
    }

    return null;
  }

  static Map<String, dynamic>? _extractMapLiteral(Expression expr) {
    if (expr is! SetOrMapLiteral) {
      return null;
    }

    final result = <String, dynamic>{};

    for (final element in expr.elements) {
      if (element is MapLiteralEntry) {
        final keyExpr = element.key;
        final valueExpr = element.value;

        if (keyExpr is! SimpleStringLiteral) {
          continue;
        }

        final key = keyExpr.value;

        Object? value;

        if (valueExpr is SimpleStringLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is SetOrMapLiteral) {
          value = _extractMapLiteral(valueExpr);
        } else if (valueExpr is IntegerLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is BooleanLiteral) {
          value = valueExpr.value;
        } else if (valueExpr is PrefixedIdentifier ||
            valueExpr is SimpleIdentifier) {
          value = valueExpr.toSource();
        }

        if (value != null) {
          result[key] = value;
        }
      }
    }

    return result.isEmpty ? null : result;
  }

  Map<String, dynamic>? _extractPlaceholders(NodeList<Argument> args) {
    for (final arg in args) {
      if (arg is NamedArgument && arg.name.lexeme == 'placeholders') {
        return _extractMapLiteral(arg.argumentExpression);
      }
    }

    return null;
  }

  String? _extractStringValue(Expression expr) {
    if (expr is SimpleStringLiteral) {
      return expr.value;
    } else if (expr is AdjacentStrings) {
      final buffer = StringBuffer();

      for (final string in expr.strings) {
        if (string is SimpleStringLiteral) {
          buffer.write(string.value);
        }
      }

      return buffer.toString();
    }

    return null;
  }

  static bool _isL10nAccess(Expression? expr) {
    if (expr == null) {
      return false;
    }

    // Pattern 1: l10n variable
    if (expr is SimpleIdentifier && expr.name == 'l10n') {
      return true;
    }

    // Pattern 2: AppLocalizations.of(context)
    if (expr is MethodInvocation) {
      final target = expr.target;

      if (target is SimpleIdentifier &&
          target.name == 'AppLocalizations' &&
          expr.methodName.name == 'of') {
        return true;
      }
    }

    // Pattern 3: Nested property access
    if (expr is PropertyAccess) {
      return _isL10nAccess(expr.target);
    }

    return false;
  }

  static int _lineNumberAt(int offset, List<int> lineStarts) {
    var low = 0;
    var high = lineStarts.length - 1;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final start = lineStarts[mid];

      if (start <= offset) {
        if (mid == lineStarts.length - 1 || lineStarts[mid + 1] > offset) {
          return mid + 1;
        }
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    return 1;
  }

  /// Records the call as an entry when both its key and English text can be
  /// read, as an [L10nIssue] when only one of them can, and ignores it when
  /// neither can, since then it is not a localization marker.
  void _processInlineCall(MethodInvocation node) {
    final args = node.argumentList.arguments;
    if (args.isEmpty) {
      return;
    }

    final key = _extractKey(node.target);
    final text = _extractStringValue(args.first.argumentExpression);

    switch ((key, text)) {
      case (final key?, final text?):
        _addEntry(node, key, text);
      case (null, _?):
        _addIssue(node, L10nIssueKind.unrecognizedReceiver);
      case (_?, null):
        _addIssue(node, L10nIssueKind.nonLiteralText);
      case (null, null):
        return;
    }
  }

  void _addIssue(MethodInvocation node, L10nIssueKind kind) {
    issues.add(
      L10nIssue(
        filePath: filePath,
        line: _lineNumberAt(node.offset, lineStarts),
        kind: kind,
        code: node.toSource(),
      ),
    );
  }

  void _addEntry(MethodInvocation node, String key, String stringValue) {
    final line = _lineNumberAt(node.offset, lineStarts);
    final placeholders = _extractPlaceholders(node.argumentList.arguments);

    final entry = L10nEntry(
      text: stringValue,
      line: line,
      filePath: filePath,
      placeholders: placeholders,
    );

    final existing = entries[key];
    if (existing != null && existing.text != entry.text) {
      throw L10nException.duplicateKey(key, existing, entry);
    }

    entries[key] = entry;
  }
}
