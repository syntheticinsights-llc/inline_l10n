import 'dart:io';

/// Keeps the locales the native app shells declare equal to the ARB files.
///
/// Flutter loads translations on its own, but the platforms only offer the
/// languages an app declares: Android 13+ lists the `localeConfig` ones in
/// the per-app language settings, and iOS and macOS pick the app language,
/// and list it in the per-app language settings, from
/// `CFBundleLocalizations`. A language missing there is easy to overlook,
/// because the app still shows it whenever it is the system language.
///
/// Since both lists derive from the ARB files, they are rewritten rather than
/// checked. Only the locale entries are replaced, keeping the rest of each
/// file and its indentation. A shell that is missing is skipped, so a project
/// that targets only some platforms needs nothing extra.
///
/// Locales are written as BCP 47 tags (`zh_Hant` → `zh-Hant`), which both
/// platforms accept.
class PlatformLocales {
  const PlatformLocales._();

  static const _androidManifestPath =
      'android/app/src/main/AndroidManifest.xml';
  static const _androidResourcePath = 'android/app/src/main/res';
  static const _applePlistPaths = [
    'ios/Runner/Info.plist',
    'macos/Runner/Info.plist',
  ];

  /// Rewrites the declarations under [projectRoot] to list [locales], and
  /// returns the paths of the files that changed.
  static List<String> sync(Iterable<String> locales, {Directory? projectRoot}) {
    final root = projectRoot ?? Directory.current;
    final tags = {for (final locale in locales) locale.replaceAll('_', '-')}
        .toList()
      ..sort();

    final changed = <String>[];
    void update(File? file, String Function(String content) rewrite) {
      if (file == null || !file.existsSync()) {
        return;
      }
      final content = file.readAsStringSync();
      final rewritten = rewrite(content);
      if (rewritten != content) {
        file.writeAsStringSync(rewritten);
        changed.add(file.path);
      }
    }

    update(
      _androidLocaleConfig(root),
      (content) => _rewriteAndroidLocaleConfig(content, tags),
    );
    for (final path in _applePlistPaths) {
      update(
        File('${root.path}/$path'),
        (content) => _rewriteApplePlist(content, tags),
      );
    }

    return changed;
  }

  /// The resource file the manifest names in `android:localeConfig`, or null
  /// when the app declares none.
  static File? _androidLocaleConfig(Directory root) {
    final manifest = File('${root.path}/$_androidManifestPath');
    if (!manifest.existsSync()) {
      return null;
    }
    final match = RegExp(
      r'android:localeConfig="@xml/([^"]+)"',
    ).firstMatch(manifest.readAsStringSync());

    return match == null
        ? null
        : File('${root.path}/$_androidResourcePath/xml/${match.group(1)}.xml');
  }

  static String _rewriteAndroidLocaleConfig(String content, List<String> tags) {
    final entries = RegExp(
      r'^([ \t]*)<locale\s+android:name="[^"]*"\s*/>[ \t]*\r?\n',
      multiLine: true,
    ).allMatches(content).toList();
    if (entries.isNotEmpty) {
      return _replaceEntries(
        content,
        start: entries.first.start,
        end: entries.last.end,
        indent: entries.first.group(1)!,
        tags: tags,
        render: (tag) => '<locale android:name="$tag" />',
      );
    }

    final close = RegExp(r'^([ \t]*)</locale-config>', multiLine: true)
        .firstMatch(content);
    if (close == null) {
      return content;
    }

    return _replaceEntries(
      content,
      start: close.start,
      end: close.start,
      indent: '${close.group(1)!}    ',
      tags: tags,
      render: (tag) => '<locale android:name="$tag" />',
    );
  }

  static String _rewriteApplePlist(String content, List<String> tags) {
    final declaration = RegExp(
      r'^([ \t]*)<key>CFBundleLocalizations</key>\s*<array>[ \t]*\r?\n'
      r'(?:[ \t]*<string>[^<]*</string>[ \t]*\r?\n)*'
      r'([ \t]*)</array>',
      multiLine: true,
    ).firstMatch(content);
    if (declaration != null) {
      final arrayStart = content.indexOf('<array>', declaration.start);
      final entriesStart = content.indexOf('\n', arrayStart) + 1;
      final closeIndent = declaration.group(2)!;

      return _replaceEntries(
        content,
        start: entriesStart,
        end: declaration.end - '</array>'.length - closeIndent.length,
        indent: '$closeIndent${_indentUnit(closeIndent)}',
        tags: tags,
        render: (tag) => '<string>$tag</string>',
      );
    }

    final dict = RegExp(r'^([ \t]*)<dict>[ \t]*\r?\n', multiLine: true)
        .firstMatch(content);
    if (dict == null) {
      return content;
    }
    final keyIndent = '${dict.group(1)!}${_indentUnit(dict.group(1)!)}';
    final itemIndent = '$keyIndent${_indentUnit(keyIndent)}';
    final items = tags
        .map((tag) => '$itemIndent<string>$tag</string>\n')
        .join();

    return content.replaceRange(
      dict.end,
      dict.end,
      '$keyIndent<key>CFBundleLocalizations</key>\n'
      '$keyIndent<array>\n'
      '$items'
      '$keyIndent</array>\n',
    );
  }

  static String _replaceEntries(
    String content, {
    required int start,
    required int end,
    required String indent,
    required List<String> tags,
    required String Function(String tag) render,
  }) => content.replaceRange(
    start,
    end,
    tags.map((tag) => '$indent${render(tag)}\n').join(),
  );

  /// Plists are indented with tabs unless the file already uses spaces.
  static String _indentUnit(String indent) =>
      indent.contains(' ') ? '  ' : '\t';
}
