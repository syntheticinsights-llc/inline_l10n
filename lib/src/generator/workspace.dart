import 'dart:io';

import 'package:yaml/yaml.dart';

import 'models.dart';

({Directory root, List<String> members})? findWorkspace() {
  var directory = Directory.current.absolute;

  while (true) {
    final pubspec = File.fromUri(directory.uri.resolve('pubspec.yaml'));
    if (pubspec.existsSync()) {
      final document = loadYaml(pubspec.readAsStringSync());
      if (document is YamlMap && document.containsKey('workspace')) {
        final members = document['workspace'];
        if (members is! YamlList ||
            members.any((member) => member is! String)) {
          throw L10nException('Invalid workspace list in ${pubspec.path}');
        }
        return (root: directory, members: members.cast<String>().toList());
      }
    }

    final parent = directory.parent;
    if (parent.path == directory.path) {
      return null;
    }
    directory = parent;
  }
}

String trimTrailingSeparator(String path) =>
    path.length > 1 && path.endsWith(Platform.pathSeparator)
    ? path.substring(0, path.length - 1)
    : path;
