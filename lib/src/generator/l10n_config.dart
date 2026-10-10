import 'dart:io';

import 'package:yaml/yaml.dart';

import 'models.dart';

class L10nConfig {
  const L10nConfig._();

  static const generatedFileSuffixes = [
    '.g.dart',
    '.freezed.dart',
    '.gen.dart',
  ];
  static const defaultL10nDir = 'lib/resources/l10n';
  static const defaultTemplateFile = 'app_en.arb';
  static const sourceDir = 'lib';
  static const watchDebounce = Duration(milliseconds: 200);

  static String resolveArbDir() =>
      _readL10nYamlOption('arb-dir') ?? defaultL10nDir;

  static String resolveTemplateArbFile() =>
      _readL10nYamlOption('template-arb-file') ?? defaultTemplateFile;

  static String? _readL10nYamlOption(String key) {
    final file = File('l10n.yaml');
    if (!file.existsSync()) {
      return null;
    }

    final Object? document;
    try {
      document = loadYaml(file.readAsStringSync());
    } on YamlException catch (error) {
      throw L10nException('Failed to parse ${file.path}\n$error');
    }

    final value = document is YamlMap ? document[key] : null;
    return value is String && value.trim().isNotEmpty ? value.trim() : null;
  }
}
