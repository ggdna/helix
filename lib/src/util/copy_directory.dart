// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

// .............................................................................
/// Recursively copies [source] into [target] with overlay semantics:
/// colliding files are overwritten, extra files in [target] are kept.
/// [skip] receives each relative posix path and may exclude entries.
void copyDirectory(
  Directory source,
  Directory target, {
  bool Function(String relPosixPath)? skip,
}) {
  target.createSync(recursive: true);
  for (final entity in source.listSync(recursive: true, followLinks: false)) {
    final relative = p.relative(entity.path, from: source.path);
    if (skip != null && skip(relative.replaceAll('\\', '/'))) continue;
    final targetPath = p.join(target.path, relative);
    if (entity is Directory) {
      Directory(targetPath).createSync(recursive: true);
    } else if (entity is File) {
      Directory(p.dirname(targetPath)).createSync(recursive: true);
      entity.copySync(targetPath);
    }
  }
}
