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
    required this.generationResult,
  });

  final Map<String, L10nEntry> entries;
  final GenerationResult generationResult;
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
