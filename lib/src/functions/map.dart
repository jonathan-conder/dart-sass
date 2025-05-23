// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

import 'package:collection/collection.dart';

import '../callable.dart';
import '../exception.dart';
import '../module/built_in.dart';
import '../util/iterable.dart';
import '../util/map.dart';
import '../value.dart';

/// The global definitions of Sass map functions.
final global = UnmodifiableListView([
  _get.withDeprecationWarning('map').withName("map-get"),
  _merge.withDeprecationWarning('map').withName("map-merge"),
  _remove.withDeprecationWarning('map').withName("map-remove"),
  _keys.withDeprecationWarning('map').withName("map-keys"),
  _values.withDeprecationWarning('map').withName("map-values"),
  _hasKey.withDeprecationWarning('map').withName("map-has-key"),
]);

/// The Sass map module.
final module = BuiltInModule(
  "map",
  functions: <Callable>[
    _get,
    _set,
    _merge,
    _remove,
    _keys,
    _values,
    _hasKey,
    _deepMerge,
    _deepRemove,
  ],
);

final _get = _function("get", r"$map, $key, $keys...", (arguments) {
  var map = arguments[0].assertMap("map");
  var keys = [arguments[1], ...arguments[2].asList];
  for (var key in keys.exceptLast) {
    var value = map.contents[key];
    if (value is! SassMap) return sassNull;
    map = value;
  }
  return map.contents[keys.last] ?? sassNull;
});

final _set = BuiltInCallable.overloadedFunction("set", {
  r"$map, $key, $value": (arguments) {
    var map = arguments[0].assertMap("map");
    return _modify(map, [arguments[1]], (_) => arguments[2]);
  },
  r"$map, $args...": (arguments) {
    var map = arguments[0].assertMap("map");
    switch (arguments[1].asList) {
      case []:
        throw SassScriptException("Expected \$args to contain a key.");
      case [_]:
        throw SassScriptException("Expected \$args to contain a value.");
      case [...var keys, var value]:
        return _modify(map, keys, (_) => value);
      default: // ignore: unreachable_switch_default
        // This code is unreachable, and the compiler knows it (hence the
        // `unreachable_switch_default` warning being ignored above). However,
        // due to architectural limitations in the Dart front end, the compiler
        // doesn't understand that the code is unreachable until late in the
        // compilation process (after flow analysis). So this `default` clause
        // must be kept around to avoid flow analysis incorrectly concluding
        // that the function fails to return. See
        // https://github.com/dart-lang/language/issues/2977 for details.
        throw '[BUG] Unreachable code';
    }
  },
});

final _merge = BuiltInCallable.overloadedFunction("merge", {
  r"$map1, $map2": (arguments) {
    var map1 = arguments[0].assertMap("map1");
    var map2 = arguments[1].assertMap("map2");
    return SassMap({...map1.contents, ...map2.contents});
  },
  r"$map1, $args...": (arguments) {
    var map1 = arguments[0].assertMap("map1");
    switch (arguments[1].asList) {
      case []:
        throw SassScriptException("Expected \$args to contain a key.");
      case [_]:
        throw SassScriptException("Expected \$args to contain a map.");
      case [...var keys, var last]:
        var map2 = last.assertMap("map2");
        return _modify(map1, keys, (oldValue) {
          var nestedMap = oldValue.tryMap();
          if (nestedMap == null) return map2;
          return SassMap({...nestedMap.contents, ...map2.contents});
        });
      default: // ignore: unreachable_switch_default
        // This code is unreachable, and the compiler knows it (hence the
        // `unreachable_switch_default` warning being ignored above). However,
        // due to architectural limitations in the Dart front end, the compiler
        // doesn't understand that the code is unreachable until late in the
        // compilation process (after flow analysis). So this `default` clause
        // must be kept around to avoid flow analysis incorrectly concluding
        // that the function fails to return. See
        // https://github.com/dart-lang/language/issues/2977 for details.
        throw '[BUG] Unreachable code';
    }
  },
});

final _deepMerge = _function("deep-merge", r"$map1, $map2", (arguments) {
  var map1 = arguments[0].assertMap("map1");
  var map2 = arguments[1].assertMap("map2");
  return _deepMergeImpl(map1, map2);
});

final _deepRemove = _function("deep-remove", r"$map, $key, $keys...", (
  arguments,
) {
  var map = arguments[0].assertMap("map");
  var keys = [arguments[1], ...arguments[2].asList];
  return _modify(map, keys.exceptLast, (value) {
    if (value.tryMap() case var nestedMap?
        when nestedMap.contents.containsKey(keys.last)) {
      return SassMap(Map.of(nestedMap.contents)..remove(keys.last));
    }
    return value;
  }, addNesting: false);
});

final _remove = BuiltInCallable.overloadedFunction("remove", {
  // Because the signature below has an explicit `$key` argument, it doesn't
  // allow zero keys to be passed. We want to allow that case, so we add an
  // explicit overload for it.
  r"$map": (arguments) => arguments[0].assertMap("map"),

  // The first argument has special handling so that the $key parameter can be
  // passed by name.
  r"$map, $key, $keys...": (arguments) {
    var map = arguments[0].assertMap("map");
    var keys = [arguments[1], ...arguments[2].asList];
    var mutableMap = Map.of(map.contents);
    for (var key in keys) {
      mutableMap.remove(key);
    }
    return SassMap(mutableMap);
  },
});

final _keys = _function(
  "keys",
  r"$map",
  (arguments) => SassList(
    arguments[0].assertMap("map").contents.keys,
    ListSeparator.comma,
  ),
);

final _values = _function(
  "values",
  r"$map",
  (arguments) => SassList(
    arguments[0].assertMap("map").contents.values,
    ListSeparator.comma,
  ),
);

final _hasKey = _function("has-key", r"$map, $key, $keys...", (arguments) {
  var map = arguments[0].assertMap("map");
  var keys = [arguments[1], ...arguments[2].asList];
  for (var key in keys.exceptLast) {
    var value = map.contents[key];
    if (value is! SassMap) return sassFalse;
    map = value;
  }
  return SassBoolean(map.contents.containsKey(keys.last));
});

/// Updates the specified value in [map] by applying the [modify] callback to
/// it, then returns the resulting map.
///
/// If more than one key is provided, this means the map targeted for update is
/// nested within [map]. The multiple [keys] form a path of nested maps that
/// leads to the targeted value, which is passed to [modify].
///
/// If any value along the path (other than the last one) is not a map and
/// [addNesting] is `true`, this creates nested maps to match [keys] and passes
/// [sassNull] to [modify]. Otherwise, this fails and returns [map] with no
/// changes.
///
/// If no keys are provided, this passes [map] directly to modify and returns
/// the result.
Value _modify(
  SassMap map,
  Iterable<Value> keys,
  Value modify(Value old), {
  bool addNesting = true,
}) {
  var keyIterator = keys.iterator;
  SassMap modifyNestedMap(SassMap map) {
    var mutableMap = Map.of(map.contents);
    var key = keyIterator.current;

    if (!keyIterator.moveNext()) {
      mutableMap[key] = modify(mutableMap[key] ?? sassNull);
      return SassMap(mutableMap);
    }

    var nestedMap = mutableMap[key]?.tryMap();
    if (nestedMap == null && !addNesting) return SassMap(mutableMap);

    mutableMap[key] = modifyNestedMap(nestedMap ?? const SassMap.empty());
    return SassMap(mutableMap);
  }

  return keyIterator.moveNext() ? modifyNestedMap(map) : modify(map);
}

/// Merges [map1] and [map2], with values in [map2] taking precedence.
///
/// If both [map1] and [map2] have a map value associated with the same key,
/// this recursively merges those maps as well.
SassMap _deepMergeImpl(SassMap map1, SassMap map2) {
  if (map1.contents.isEmpty) return map2;
  if (map2.contents.isEmpty) return map1;

  var result = Map.of(map1.contents);
  for (var (key, value) in map2.contents.pairs) {
    if ((result[key]?.tryMap(), value.tryMap())
        case (
          var resultMap?,
          var valueMap?,
        )) {
      var merged = _deepMergeImpl(resultMap, valueMap);
      if (identical(merged, resultMap)) continue;
      result[key] = merged;
    } else {
      result[key] = value;
    }
  }

  return SassMap(result);
}

/// Like [BuiltInCallable.function], but always sets the URL to `sass:map`.
BuiltInCallable _function(
  String name,
  String arguments,
  Value callback(List<Value> arguments),
) =>
    BuiltInCallable.function(name, arguments, callback, url: "sass:map");
