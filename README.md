# inline_l10n

An authoring tool for Flutter's official `gen-l10n` localization workflow.
Keep English ARB source text next to the typed `AppLocalizations` key that uses
it.

`inline_l10n` is not a standalone localization framework. It depends on
Flutter's `flutter_localizations`, `intl`, ARB files, and `flutter gen-l10n`
for runtime localization and generated `AppLocalizations` accessors.

Flutter's `gen-l10n` normally generates typed localization accessors from ARB
files. `inline_l10n` reverses the authoring flow: write English source text at
its use site, generate `app_en.arb`, then let Flutter generate the accessors.

```dart
Text(l10n.settings.inline('Settings'))
```

At runtime, `inline()` returns the localized value from `l10n.settings`. Its
English argument is used only by the generator.

## What it does

- Extracts `.inline(...)` calls from the current package's `lib/`, or every package's `lib/` in a Dart workspace, with the Dart analyzer AST.
- Writes the English ARB file specified by `l10n.yaml` from the extracted strings.
- Adds descriptions pointing to the defining source file.
- Keeps every non-English ARB file aligned with the generated English keys.
- Runs `flutter gen-l10n` after updating the ARB files.
- Keeps the languages the native app shells declare equal to the ARB files: `CFBundleLocalizations` in `ios/Runner/Info.plist` and `macos/Runner/Info.plist`, and the Android locale config named by `android:localeConfig` in `AndroidManifest.xml`. Without these, iOS and macOS may not use a language the app ships, and the system per-app language settings do not offer it. Only the locale entries are rewritten; missing shells are skipped.
- Fails when the same localization key has conflicting English source text.
- Warns about `.inline(...)` calls it cannot extract, and can list them in a JSON file.

This package only changes how you author Flutter localization entries. Flutter
still loads translations and formats messages at runtime. It does not translate
strings.

## Prerequisites

Set up Flutter's official localization system first. Your app needs
`flutter_localizations`, `intl`, and localization generation enabled:

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter
  intl: any
  inline_l10n: ^0.4.0

flutter:
  generate: true
```

The generator reads the ARB directory and template filename from `l10n.yaml`:

```yaml
# l10n.yaml
arb-dir: lib/resources/l10n
template-arb-file: app_en.arb
```

For example, a compatible `l10n.yaml` can be:

```yaml
arb-dir: lib/resources/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
nullable-getter: false
```

Register the generated `AppLocalizations` delegates in your `MaterialApp` as
described by Flutter's localization documentation.

## Install

Run:

```sh
flutter pub get
```

`inline_l10n` is a regular dependency because its `String.inline` extension is
compiled into your app.

## Usage

Import the runtime marker where localized text is used:

```dart
import 'package:inline_l10n/inline_l10n.dart';
```

Write the English source text alongside a Flutter-generated
`AppLocalizations` key:

```dart
final l10n = AppLocalizations.of(context);

Text(l10n.settings.inline('Settings'));
```

For arguments, use ICU placeholders in the English source and supply ARB
placeholder metadata:

```dart
Text(
  l10n.greeting(name).inline(
    'Hello {name}',
    placeholders: {
      'name': {'type': 'String'},
    },
  ),
);
```

Run the generator from the Flutter app root. In a Dart workspace, it finds the workspace root and scans each member package's `lib/`:

```sh
dart run inline_l10n:gen_l10n
```

It creates or replaces `app_en.arb`, removes obsolete keys from every other
`app_*.arb` file, and invokes `flutter gen-l10n`. Commit the generated ARB and
Flutter localization output after reviewing the changes.

### Watch mode

```sh
dart run inline_l10n:gen_l10n --watch
```

Watch mode runs a full generation, then keeps watching every scanned `lib/`
directory and the ARB directory. When a Dart file changes, only that file is
parsed again. `app_en.arb` and the locale ARB files are rewritten only when
their content changes, and `flutter gen-l10n` runs only when an ARB file
changed. Errors such as duplicate keys, Dart syntax errors, or invalid ARB JSON
are reported without stopping the watcher. Restart it after changing
`l10n.yaml` or the workspace members. Press Ctrl+C to stop.

## Recognized markers

The generator recognizes these forms:

```dart
l10n.key.inline('English text');
l10n.key(argument).inline('English {argument}');
AppLocalizations.of(context).key.inline('English text');
```

For local variables, the localization object must be named `l10n`. The source
argument must be a string literal or adjacent string literals. String
interpolation is not extracted; use ICU placeholders instead.

## Calls that are not extracted

`inline()` returns its receiver, so a call the generator cannot read still
compiles and runs, and silently shows untranslated text. The generator warns
about these calls instead of skipping them:

- `unrecognized-receiver`: the English text is a string literal, but the
  receiver is not one of the recognized markers, e.g.
  `'Settings'.inline('Settings')` or `loc.settings.inline('Settings')`.
- `non-literal-text`: the receiver is a recognized key, but the English text
  is not a string literal, e.g. `l10n.settings.inline(text)`.

Calls with neither a recognized receiver nor a string literal are not
localization markers and are left alone.

The warning does not fail the run: every other entry is still written, and the
exit code is unchanged. Watch mode prints it only when the list changes.

## Status file

Pass `--issues-file` to also keep the outcome of the last run in a JSON file,
so tools and coding agents can read it instead of the terminal, which in watch
mode often runs where nobody looks:

```sh
dart run inline_l10n:gen_l10n --watch --issues-file=inline_issues.json
```

The file is rewritten on every run:

```json
{
  "lastRun": "2026-11-12T06:22:37.000Z",
  "status": "failed",
  "errors": [
    {
      "message": "Duplicate l10n key \"title\" with different content.\n  First defined at: lib/a.dart:3\n  Conflict at: lib/b.dart:7",
      "locations": ["lib/a.dart:3", "lib/b.dart:7"]
    }
  ],
  "warnings": [
    {
      "file": "lib/attachments.dart",
      "line": 42,
      "issue": "unrecognized-receiver",
      "code": "'Dropping folders is not supported'.inline('Dropping folders is not supported')"
    }
  ]
}
```

- `lastRun`: when the run ended, in UTC. If it is older than an edit, the
  generator has not processed that edit yet, or is not running.
- `status`: `ok` when the ARB files and the generated code are up to date;
  `failed` when an error stopped the run, or the `--post-gen` command failed;
  `waiting` when watch mode leaves the ARB files alone until every source file
  can be parsed.
- `errors`: what stopped the run. `locations` lists the `file:line` places in
  the sources, and is left out for errors such as a failing
  `flutter gen-l10n`.
- `warnings`: the calls that were not extracted, from the last extraction.

## Native declarations and other derived files

Every run also rewrites the languages the native app shells declare from the
ARB files: `CFBundleLocalizations` in `ios/Runner/Info.plist` and
`macos/Runner/Info.plist`, and the Android locale config that
`android:localeConfig` names in `AndroidManifest.xml`. Only the locale entries
change; a shell that does not exist is skipped.

For files only your project derives from the ARB files, such as native string
resources of home screen widgets, pass a command to run after every
generation:

```sh
dart run inline_l10n:gen_l10n --watch --post-gen="dart run tool/sync_native.dart"
```

The command runs in a shell, in the generator's working directory, once
`flutter gen-l10n` has finished: after a single run, and in watch mode after
every cycle that ran `flutter gen-l10n`. When it fails, a single run exits with
code 1, and watch mode reports it and keeps watching.

## Important behavior

`app_en.arb` is the generated source of truth and is overwritten on each run.
Other locale files retain only keys that still exist in `app_en.arb`; missing
translations are not created. Keep ARB files under version control and review
generator output before committing.

## License

This project is licensed under the [MIT License](LICENSE).
