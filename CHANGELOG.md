# Changelog

## 0.5.2

- Watch mode follows the workspace: every poll also re-reads the workspace
  members, so a package added after the session started is watched and
  scanned, and a removed one stops counting. Before, the members were read
  once at startup, so the `.inline(...)` calls of a newer package were never
  seen, and a key moved into it read as deleted, which dropped its
  translations from every locale ARB file.

## 0.5.1

- Watch mode finds changes by polling instead of by native change
  notifications: it re-lists the watched directories and stats every file every
  5 seconds (`L10nConfig.watchPollInterval`). A native watcher that stops
  delivering events leaves the process alive and idle, quietly ignoring every
  later edit, and nothing lets the session notice that it went deaf. Polling
  removes that state instead of detecting it, and reports removed files the same
  way. Measured cost on a project with about 1900 Dart files is 12ms per poll.
- `flutter gen-l10n` and `--post-gen` are killed after two minutes instead of
  waiting forever. A command that never ends used to hold the watch session's
  cycle open, and every later change was dropped without a word.

## 0.5.0

- **Breaking:** the `--issues-file` JSON is now the status of the last run
  instead of a list of warnings: `lastRun` (UTC), `status` (`ok`, `failed`,
  or `waiting`), `errors` with their source `locations`, and the former list
  as `warnings`. Errors that stop a run, such as duplicate keys, unparsable
  sources, or a failing `flutter gen-l10n` or `--post-gen` command, were only
  printed to the terminal, so a tool watching the file could not tell a
  failed run from one that had not happened yet.

## 0.4.0

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
