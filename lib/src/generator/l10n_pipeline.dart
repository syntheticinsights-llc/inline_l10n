import 'dart:io';

import 'app_en_writer.dart';
import 'l10n_config.dart';
import 'l10n_sources.dart';
import 'locale_arb_aligner.dart';
import 'models.dart';
import 'workspace.dart';

class L10nPipeline {
  L10nPipeline._(this.sources, this.l10nRoot, this.templateFileName);

  factory L10nPipeline.resolve() {
    final arbDirUri = Directory.current.uri.resolve(L10nConfig.resolveArbDir());
    final l10nRoot = Directory(
      trimTrailingSeparator(Directory.fromUri(arbDirUri).path),
    );
    if (!l10nRoot.existsSync()) {
      throw L10nException('Localization directory not found: ${l10nRoot.path}');
    }

    return L10nPipeline._(
      L10nSources.resolve(),
      l10nRoot,
      L10nConfig.resolveTemplateArbFile(),
    );
  }

  final Directory l10nRoot;
  final L10nSources sources;
  final String templateFileName;

  bool isArbFile(String path) =>
      path.endsWith('.arb') &&
      path.startsWith('${l10nRoot.path}${Platform.pathSeparator}') &&
      !path
          .substring(l10nRoot.path.length + 1)
          .contains(Platform.pathSeparator);

  Map<String, String> readArbSnapshot() => {
    for (final file in l10nRoot.listSync().whereType<File>())
      if (file.path.endsWith('.arb')) file.path: file.readAsStringSync(),
  };

  ArbWriteResult writeArbs(ExtractionResult extraction) => ArbWriteResult(
    templateChanged: AppEnWriter.write(
      l10nRoot,
      extraction.entries,
      templateFileName: templateFileName,
    ),
    alignment: LocaleArbAligner.align(
      l10nRoot,
      templateFileName: templateFileName,
    ),
  );
}
