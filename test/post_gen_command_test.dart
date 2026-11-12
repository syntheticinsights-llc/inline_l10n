// The commands below are POSIX shell syntax.
@TestOn('!windows')
library;

import 'dart:io';

import 'package:inline_l10n/src/generator/models.dart';
import 'package:inline_l10n/src/generator/post_gen_command.dart';
import 'package:test/test.dart';

void main() {
  test('runs the command in a shell and returns its exit code', () async {
    expect(await const PostGenCommand('true && exit 3').run(), 3);
  });

  test('runOrThrow fails only when the command fails', () async {
    await const PostGenCommand('exit 0').runOrThrow();

    await expectLater(
      const PostGenCommand('exit 2').runOrThrow(),
      throwsA(
        isA<L10nException>().having(
          (error) => error.message,
          'message',
          contains('exit code 2'),
        ),
      ),
    );
  });

  test('runs in the working directory of the generator', () async {
    final temp = Directory.systemTemp.createTempSync('inline_l10n_');
    addTearDown(() => temp.deleteSync(recursive: true));
    final previous = Directory.current;
    addTearDown(() => Directory.current = previous);
    Directory.current = temp;

    await const PostGenCommand('echo done > marker').runOrThrow();

    expect(File('${temp.path}/marker').readAsStringSync().trim(), 'done');
  });
}
