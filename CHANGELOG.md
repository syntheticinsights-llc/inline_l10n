# Changelog

## 0.1.4

- Extract inline localization entries from every package's `lib/` in a Dart workspace.

## 0.1.3

- Read the ARB directory and template file from `l10n.yaml`.
- Fix localization extraction with analyzer 13.

## 0.1.2

- Support analyzer 13's `Argument` and `NamedArgument` AST APIs.

## 0.1.1

- Clarify that inline_l10n builds on Flutter's official gen-l10n workflow.
- Document the flutter_localizations and intl prerequisites.

## 0.1.0

- First public release.
- Add the `String.inline` marker for Flutter localization accessors.
- Extract inline localization entries with the Dart analyzer AST.
- Generate `app_en.arb`, align existing locale ARB files, and run
  `flutter gen-l10n`.
