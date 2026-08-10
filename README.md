# inline_l10n

Generate Flutter ARB localization entries from English text kept next to the
typed localization key that uses it.

Flutter's `gen-l10n` generates typed localization accessors from ARB files.
`inline_l10n` reverses the authoring flow: write the English source text at its
use site, generate `app_en.arb`, then let Flutter generate the accessors.

```dart
Text(l10n.settings.inline('Settings'))
```

At runtime, `inline()` returns the localized value from `l10n.settings`. Its
English argument is used only by the generator.

## What it does

- Extracts `.inline(...)` calls from Dart source with the Dart analyzer AST.
- Writes `lib/resources/l10n/app_en.arb` from the extracted English strings.
- Adds descriptions pointing to the defining source file.
- Keeps every non-English ARB file aligned with the generated English keys.
- Runs `flutter gen-l10n` after updating the ARB files.
- Fails when the same localization key has conflicting English source text.

This package is for Flutter apps that use the standard `flutter gen-l10n`
workflow. It does not translate strings.

## Install

Add the package to the Flutter app's `pubspec.yaml`:

```yaml
dependencies:
  inline_l10n: ^0.1.0
```

Then run:

```sh
flutter pub get
```

The app must already have Flutter localization generation enabled:

```yaml
# pubspec.yaml
flutter:
  generate: true
```

The generator requires this ARB layout:

```yaml
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

## Usage

Import the runtime marker where localized text is used:

```dart
import 'package:inline_l10n/inline_l10n.dart';
```

Write the English source text alongside a generated `AppLocalizations` key:

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

Run the generator from the Flutter app root:

```sh
dart run inline_l10n:gen_l10n
```

It creates or replaces `app_en.arb`, removes obsolete keys from every other
`app_*.arb` file, and invokes `flutter gen-l10n`. Commit the generated ARB and
Flutter localization output after reviewing the changes.

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

## Important behavior

`app_en.arb` is the generated source of truth and is overwritten on each run.
Other locale files retain only keys that still exist in `app_en.arb`; missing
translations are not created. Keep ARB files under version control and review
generator output before committing.

## License

This project is licensed under the [MIT License](LICENSE).
