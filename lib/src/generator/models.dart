class L10nException implements Exception {
  const L10nException(this.message);

  final String message;

  @override
  String toString() => message;
}

class L10nEntry {
  const L10nEntry({
    required this.text,
    required this.line,
    required this.filePath,
    this.placeholders,
  });

  final String filePath;
  final int line;
  final Map<String, dynamic>? placeholders;
  final String text;
}

/// Why an `.inline(...)` call that looks like a localization marker was not
/// extracted.
enum L10nIssueKind {
  /// The receiver is not a recognized localization key, e.g.
  /// `'Settings'.inline('Settings')` or `loc.settings.inline('Settings')`.
  unrecognizedReceiver(
    'unrecognized-receiver',
    'The receiver is not a recognized localization key. '
        'Use l10n.key.inline(...) or '
        'AppLocalizations.of(context).key.inline(...).',
  ),

  /// The English text is not a string literal, so it cannot be read without
  /// running the code.
  nonLiteralText(
    'non-literal-text',
    'The English text must be a string literal or adjacent string literals, '
        'without interpolation.',
  );

  const L10nIssueKind(this.id, this.message);

  /// Stable identifier written to the issues file.
  final String id;
  final String message;
}

/// An `.inline(...)` call that looks like a localization marker but was not
/// extracted.
///
/// A call counts as a marker when its receiver is a localization key or its
/// first argument is a string literal. Calls with neither are left alone: the
/// generator only sees syntax, and another API may also define an `inline`
/// method.
class L10nIssue {
  const L10nIssue({
    required this.filePath,
    required this.line,
    required this.kind,
    required this.code,
  });

  final String code;
  final String filePath;
  final L10nIssueKind kind;
  final int line;

  Map<String, Object> toJson() => {
    'file': filePath,
    'line': line,
    'issue': kind.id,
    'code': code,
  };

  @override
  String toString() => '$filePath:$line: ${kind.message}\n    $code';
}

class GenerationResult {
  const GenerationResult({
    required this.filesScanned,
    required this.filesWithEntries,
    required this.uniqueEntries,
    required this.totalEntries,
  });

  final int filesScanned;
  final int filesWithEntries;
  final int totalEntries;
  final int uniqueEntries;
}

class ExtractionResult {
  const ExtractionResult({
    required this.entries,
    required this.issues,
    required this.generationResult,
  });

  final Map<String, L10nEntry> entries;
  final GenerationResult generationResult;
  final List<L10nIssue> issues;
}

class AlignmentResult {
  const AlignmentResult({
    required this.totalLocaleFiles,
    required this.updatedLocaleFiles,
  });

  final int totalLocaleFiles;
  final int updatedLocaleFiles;
}

class ArbWriteResult {
  const ArbWriteResult({
    required this.templateChanged,
    required this.alignment,
  });

  final AlignmentResult alignment;
  final bool templateChanged;

  bool get changed => templateChanged || alignment.updatedLocaleFiles > 0;
}
