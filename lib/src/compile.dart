// Copyright 2018 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// DO NOT EDIT. This file was generated from async_compile.dart.
// See tool/grind/synchronize.dart for details.
//
// Checksum: d305a0f75e329a29f5aff734ac31ce145fd3b8d5
//
// ignore_for_file: unused_import

export 'async_compile.dart';

import 'dart:convert';

import 'package:cli_pkg/js.dart';
import 'package:path/path.dart' as p;

import 'ast/sass.dart';
import 'import_cache.dart';
import 'callable.dart';
import 'compile_result.dart';
import 'deprecation.dart';
import 'importer.dart';
import 'importer/legacy_node.dart';
import 'importer/no_op.dart';
import 'io.dart';
import 'logger.dart';
import 'logger/deprecation_processing.dart';
import 'syntax.dart';
import 'utils.dart';
import 'visitor/evaluate.dart';
import 'visitor/serialize.dart';

/// Like [compile] in `lib/sass.dart`, but provides more options to support
/// the node-sass compatible API and the executable.
///
/// If both `importCache` and `nodeImporter` are provided, the importers in
/// `importCache` will be evaluated before `nodeImporter`.
CompileResult compile(
  String path, {
  Syntax? syntax,
  Logger? logger,
  ImportCache? importCache,
  NodeImporter? nodeImporter,
  Iterable<Callable>? functions,
  OutputStyle? style,
  bool useSpaces = true,
  int? indentWidth,
  LineFeed? lineFeed,
  bool quietDeps = false,
  bool verbose = false,
  bool sourceMap = false,
  bool charset = true,
  Iterable<Deprecation>? silenceDeprecations,
  Iterable<Deprecation>? fatalDeprecations,
  Iterable<Deprecation>? futureDeprecations,
}) {
  DeprecationProcessingLogger deprecationLogger =
      logger = DeprecationProcessingLogger(
    logger ?? Logger.stderr(),
    silenceDeprecations: {...?silenceDeprecations},
    fatalDeprecations: {...?fatalDeprecations},
    futureDeprecations: {...?futureDeprecations},
    limitRepetition: !verbose,
  )..validate();

  // If the syntax is different than the importer would default to, we have to
  // parse the file manually and we can't store it in the cache.
  Stylesheet? stylesheet;
  if (nodeImporter == null &&
      (syntax == null || syntax == Syntax.forPath(path))) {
    importCache ??= ImportCache.none();
    stylesheet = importCache.importCanonical(
      FilesystemImporter.cwd,
      p.toUri(canonicalize(path)),
      originalUrl: p.toUri(path),
    )!;
  } else {
    stylesheet = Stylesheet.parse(
      readFile(path),
      syntax ?? Syntax.forPath(path),
      url: p.toUri(path),
    );
  }

  var result = _compileStylesheet(
    stylesheet,
    logger,
    importCache,
    nodeImporter,
    FilesystemImporter.cwd,
    functions,
    style,
    useSpaces,
    indentWidth,
    lineFeed,
    quietDeps,
    sourceMap,
    charset,
  );

  deprecationLogger.summarize(js: nodeImporter != null);
  return result;
}

/// Like [compileString] in `lib/sass.dart`, but provides more options to
/// support the node-sass compatible API.
///
/// At most one of `importCache` and `nodeImporter` may be provided at once.
CompileResult compileString(
  String source, {
  Syntax? syntax,
  Logger? logger,
  ImportCache? importCache,
  NodeImporter? nodeImporter,
  Iterable<Importer>? importers,
  Iterable<String>? loadPaths,
  Importer? importer,
  Iterable<Callable>? functions,
  OutputStyle? style,
  bool useSpaces = true,
  int? indentWidth,
  LineFeed? lineFeed,
  Object? url,
  bool quietDeps = false,
  bool verbose = false,
  bool sourceMap = false,
  bool charset = true,
  Iterable<Deprecation>? silenceDeprecations,
  Iterable<Deprecation>? fatalDeprecations,
  Iterable<Deprecation>? futureDeprecations,
}) {
  DeprecationProcessingLogger deprecationLogger =
      logger = DeprecationProcessingLogger(
    logger ?? Logger.stderr(),
    silenceDeprecations: {...?silenceDeprecations},
    fatalDeprecations: {...?fatalDeprecations},
    futureDeprecations: {...?futureDeprecations},
    limitRepetition: !verbose,
  )..validate();

  var stylesheet = Stylesheet.parse(source, syntax ?? Syntax.scss, url: url);

  if (stylesheet.span.sourceUrl case Uri(scheme: '')
      when nodeImporter == null) {
    deprecationLogger.warnForDeprecation(
      Deprecation.compileStringRelativeUrl,
      'Passing a relative `url` argument (${stylesheet.span.sourceUrl}) to '
      'compileString() or related functions is deprecated and will be an error '
      'in Dart Sass 2.0.0.',
    );
  }

  var result = _compileStylesheet(
    stylesheet,
    logger,
    importCache,
    nodeImporter,
    importer ?? (isBrowser ? NoOpImporter() : FilesystemImporter.cwd),
    functions,
    style,
    useSpaces,
    indentWidth,
    lineFeed,
    quietDeps,
    sourceMap,
    charset,
  );

  deprecationLogger.summarize(js: nodeImporter != null);
  return result;
}

/// Compiles [stylesheet] and returns its result.
///
/// Arguments are handled as for [compileString].
CompileResult _compileStylesheet(
  Stylesheet stylesheet,
  Logger? logger,
  ImportCache? importCache,
  NodeImporter? nodeImporter,
  Importer importer,
  Iterable<Callable>? functions,
  OutputStyle? style,
  bool useSpaces,
  int? indentWidth,
  LineFeed? lineFeed,
  bool quietDeps,
  bool sourceMap,
  bool charset,
) {
  if (nodeImporter != null) {
    logger?.warnForDeprecation(
      Deprecation.legacyJsApi,
      'The legacy JS API is deprecated and will be removed in '
      'Dart Sass 2.0.0.\n\n'
      'More info: https://sass-lang.com/d/legacy-js-api',
    );
  }
  var evaluateResult = evaluate(
    stylesheet,
    importCache: importCache,
    nodeImporter: nodeImporter,
    importer: importer,
    functions: functions,
    logger: logger,
    quietDeps: quietDeps,
    sourceMap: sourceMap,
  );

  var serializeResult = serialize(
    evaluateResult.stylesheet,
    style: style,
    useSpaces: useSpaces,
    indentWidth: indentWidth,
    lineFeed: lineFeed,
    logger: logger,
    sourceMap: sourceMap,
    charset: charset,
  );

  var resultSourceMap = serializeResult.sourceMap;
  if (resultSourceMap != null && importCache != null) {
    mapInPlace(
      resultSourceMap.urls,
      (url) => url == ''
          ? Uri.dataFromString(
              stylesheet.span.file.getText(0),
              encoding: utf8,
            ).toString()
          : importCache.sourceMapUrl(Uri.parse(url)).toString(),
    );
  }

  return CompileResult(evaluateResult, serializeResult);
}
