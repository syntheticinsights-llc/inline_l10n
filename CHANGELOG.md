# Changelog
## 0.1.1

- Clarify that inline_l10n builds on Flutter's official gen-l10n workflow.
- Document the flutter_localizations and intl prerequisites.

## 0.1.0

- First public release.
- Add the `String.inline` marker for Flutter localization accessors.
- Extract inline localization entries with the Dart analyzer AST.
- Generate `app_en.arb`, align existing locale ARB files, and run
  `flutter gen-l10n`.
