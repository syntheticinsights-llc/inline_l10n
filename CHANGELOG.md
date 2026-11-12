# Changelog

## Unreleased

- Keep the declared app languages in step with the ARB files on every run:
  `CFBundleLocalizations` in the iOS and macOS `Info.plist`, and the Android
  locale config named by `android:localeConfig`. Only the locale entries are
  rewritten, the key is added to a plist that lacks it, and missing shells are
  skipped.
- Add `--post-gen <command>` to run a shell command after every generation,
  for files a project derives from the ARB files itself. A failing command
  fails a single run; watch mode reports it and keeps watching.

## 0.3.0

- Warn about `.inline(...)` calls that cannot be extracted instead of skipping
  them silently: a string-literal text on a receiver that is not a recognized
  key (`unrecognized-receiver`), or a recognized key whose text is not a
  string literal (`non-literal-text`). The run still succeeds, and watch mode
  prints the warning only when the list changes.
- Add `--issues-file <path>` to keep the current list of these calls in a JSON
  file.
- Parse command-line options with `package:args`; unknown options print the
  list of supported options.

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
