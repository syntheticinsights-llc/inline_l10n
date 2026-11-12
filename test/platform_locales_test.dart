import 'dart:io';

import 'package:inline_l10n/src/generator/platform_locales.dart';
import 'package:test/test.dart';

const _plist = '''
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
<dict>
\t<key>CFBundleLocalizations</key>
\t<array>
\t\t<string>en</string>
\t\t<string>fr</string>
\t</array>
\t<key>CFBundleName</key>
\t<string>App</string>
</dict>
</plist>
''';

const _manifest = '''
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <application android:localeConfig="@xml/locales">
    </application>
</manifest>
''';

const _localeConfig = '''
<?xml version="1.0" encoding="utf-8"?>
<locale-config xmlns:android="http://schemas.android.com/apk/res/android">
    <locale android:name="en" />
</locale-config>
''';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('inline_l10n_'));
  tearDown(() => root.deleteSync(recursive: true));

  File write(String path, String content) =>
      File('${root.path}/$path')
        ..createSync(recursive: true)
        ..writeAsStringSync(content);

  test('replaces only the CFBundleLocalizations entries, sorted', () {
    final plist = write('ios/Runner/Info.plist', _plist);

    final changed = PlatformLocales.sync([
      'zh_Hant',
      'en',
      'de',
    ], projectRoot: root);

    expect(changed, [plist.path]);
    expect(
      plist.readAsStringSync(),
      _plist.replaceFirst(
        '\t\t<string>en</string>\n\t\t<string>fr</string>\n',
        '\t\t<string>de</string>\n\t\t<string>en</string>\n'
            '\t\t<string>zh-Hant</string>\n',
      ),
    );
  });

  test('adds CFBundleLocalizations to a plist without it', () {
    final plist = write(
      'macos/Runner/Info.plist',
      '<plist version="1.0">\n<dict>\n\t<key>CFBundleName</key>\n</dict>\n'
          '</plist>\n',
    );

    PlatformLocales.sync(['en', 'tr'], projectRoot: root);

    expect(
      plist.readAsStringSync(),
      '<plist version="1.0">\n<dict>\n'
      '\t<key>CFBundleLocalizations</key>\n\t<array>\n'
      '\t\t<string>en</string>\n\t\t<string>tr</string>\n\t</array>\n'
      '\t<key>CFBundleName</key>\n</dict>\n</plist>\n',
    );
  });

  test('rewrites the locale config the Android manifest names', () {
    write('android/app/src/main/AndroidManifest.xml', _manifest);
    final config = write(
      'android/app/src/main/res/xml/locales.xml',
      _localeConfig,
    );

    PlatformLocales.sync(['en', 'id'], projectRoot: root);

    expect(
      config.readAsStringSync(),
      _localeConfig.replaceFirst(
        '    <locale android:name="en" />\n',
        '    <locale android:name="en" />\n    <locale android:name="id" />\n',
      ),
    );
  });

  test('skips missing shells and reports nothing when up to date', () {
    write('ios/Runner/Info.plist', _plist);

    expect(PlatformLocales.sync(['fr', 'en'], projectRoot: root), isEmpty);
  });
}
