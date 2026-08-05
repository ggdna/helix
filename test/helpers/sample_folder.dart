// @license
// Copyright (c) 2019 - 2026 Dr. Gabriel Gatzsche. All Rights Reserved.
//
// Use of this source code is governed by terms that can be
// found in the LICENSE file in the root of this package.

import 'dart:io';

import 'package:path/path.dart' as p;

/// Absolute path to the checked-in `test/sample_folder` fixtures.
///
/// Tests never mutate the fixtures directly. Relies on `Directory.current`
/// being the repo root: the cwd is process-wide and shared by all parallel
/// suites, so tests must never mutate it.
String sampleRoot() => p.join(Directory.current.path, 'test', 'sample_folder');
