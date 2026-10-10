import 'dart:convert';
import 'dart:io';

import 'l10n_config.dart';
import 'models.dart';

class LocaleArbAligner {
  const LocaleArbAligner._();

  static AlignmentResult align(
    Directory l10nRoot, {
    String templateFileName = L10nConfig.defaultTemplateFile,
  }) {
    final sourceFile = File(
      '${l10nRoot.path}${Platform.pathSeparator}$templateFileName',
    );

    if (!sourceFile.existsSync()) {
      throw L10nException('Source ARB not found: ${sourceFile.path}');
    }

    final sourceData = _readJsonMap(sourceFile);
    final sourceKeys = sourceData.keys.toList(growable: false);

    final otherArbFiles =
        l10nRoot
            .listSync()
            .whereType<File>()
            .where(
              (file) =>
                  file.path.endsWith('.arb') && file.path != sourceFile.path,
            )
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));

    var updatedCount = 0;

    for (final file in otherArbFiles) {
      final targetData = _readJsonMap(file);
      final cleaned = _buildCleanedMap(sourceKeys, targetData, file);
      final encoded = _encodeJson(cleaned);
      final current = file.readAsStringSync();

      if (encoded != current) {
        file.writeAsStringSync(encoded);
        updatedCount++;
      }
    }

    return AlignmentResult(
      totalLocaleFiles: otherArbFiles.length,
      updatedLocaleFiles: updatedCount,
    );
  }

  static Map<String, dynamic> _buildCleanedMap(
    List<String> sourceKeys,
    Map<String, dynamic> targetData,
    File targetFile,
  ) {
    final output = <String, dynamic>{};
    final locale = _readLocale(targetData, targetFile);
    if (locale != null) {
      output['@@locale'] = locale;
    }

    for (final key in sourceKeys) {
      if (key == '@@locale') {
        continue;
      }
      if (!targetData.containsKey(key)) {
        continue;
      }
      output[key] = targetData[key];
    }

    return output;
  }

  static String _encodeJson(Map<String, dynamic> data) {
    const encoder = JsonEncoder.withIndent('  ');

    return '${encoder.convert(data)}\n';
  }

  static Map<String, dynamic> _readJsonMap(File file) {
    try {
      final content = file.readAsStringSync();
      final decoded = jsonDecode(content);

      if (decoded is! Map<String, dynamic>) {
        throw L10nException(
          'Invalid ARB format (not a JSON object): ${file.path}',
        );
      }

      return decoded;
    } on FormatException catch (e) {
      throw L10nException('Failed to parse JSON: ${file.path}\n$e');
    }
  }

  static String? _readLocale(Map<String, dynamic> targetData, File targetFile) {
    final locale = targetData['@@locale'];
    if (locale is String && locale.isNotEmpty) {
      return locale;
    }

    final fileName = targetFile.uri.pathSegments.last;
    final match = RegExp(r'^app_(.+)\.arb$').firstMatch(fileName);

    return match?.group(1);
  }
}
