import 'dart:convert';
import 'dart:io';

import 'l10n_config.dart';
import 'models.dart';

class AppEnWriter {
  const AppEnWriter._();

  static bool write(
    Directory l10nRoot,
    Map<String, L10nEntry> entries, {
    String templateFileName = L10nConfig.defaultTemplateFile,
  }) {
    final appEnData = <String, dynamic>{'@@locale': 'en'};

    final keys = entries.keys.toList()..sort();

    for (final key in keys) {
      final entry = entries[key];
      if (entry == null) {
        continue;
      }

      appEnData[key] = entry.text;
      final metadata = <String, dynamic>{
        'description': 'Defined in ${entry.filePath}',
      };
      if (entry.placeholders != null) {
        metadata['placeholders'] = entry.placeholders;
      }
      appEnData['@$key'] = metadata;
    }

    final appEnFile = File(
      '${l10nRoot.path}${Platform.pathSeparator}$templateFileName',
    );
    const encoder = JsonEncoder.withIndent('  ');
    final encoded = '${encoder.convert(appEnData)}\n';
    if (appEnFile.existsSync() && appEnFile.readAsStringSync() == encoded) {
      return false;
    }

    appEnFile.writeAsStringSync(encoded);
    return true;
  }
}
