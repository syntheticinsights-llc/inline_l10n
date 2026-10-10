import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'models.dart';

class L10nAutoVisitor extends RecursiveAstVisitor<void> {
  L10nAutoVisitor(this.filePath, this.lineStarts);

  final entries = <String, L10nEntry>{};

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

  void _processInlineCall(MethodInvocation node) {
    final key = _extractKey(node.target);
    if (key == null) {
      return;
    }

    final args = node.argumentList.arguments;
    if (args.isEmpty) {
      return;
    }

    final stringValue = _extractStringValue(args.first.argumentExpression);
    if (stringValue == null) {
      return;
    }

    final line = _lineNumberAt(node.offset, lineStarts);
    final placeholders = _extractPlaceholders(args);

    final existing = entries[key];

    if (existing != null && existing.text != stringValue) {
      throw L10nException(
        '''Duplicate l10n key "$key" with different content.\n  First defined at: ${existing.filePath}:${existing.line}\n  Conflict at: $filePath:$line''',
      );
    }

    entries[key] = L10nEntry(
      text: stringValue,
      line: line,
      filePath: filePath,
      placeholders: placeholders,
    );
  }
}
