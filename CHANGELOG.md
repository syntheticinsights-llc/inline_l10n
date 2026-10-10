# Changelog

## 0.2.0

- Add `--watch` (`-w`) mode: after a full generation, it watches every scanned
  `lib/` directory and the ARB directory, re-parses only changed Dart files, and
  runs `flutter gen-l10n` only when an ARB file changed.
- Watch mode reports duplicate keys, Dart syntax errors, and invalid ARB JSON
  without stopping, and skips ARB updates while any source file fails to parse
  so existing translations are never dropped.
- Only rewrite `app_en.arb` when its content changes.
- Report generator errors as a single message with exit code 1 instead of a
  stack trace; unknown arguments exit with code 64.
- Run `flutter gen-l10n` through the shell on Windows so `flutter.bat` is found.
- Parse `l10n.yaml` with a YAML parser instead of line matching.

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
